using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

public sealed class StoredProcedureAnalyzer
{
    public SqlFileAnalysis Analyze(string file, string sql, string defaultServer = "vkdb")
    {
        var diagnostics = new List<AnalysisDiagnostic>();
        var normalizedSql = SqlTextNormalizer.Normalize(sql);
        var parser = new TSql160Parser(initialQuotedIdentifiers: false);

        TSqlFragment fragment;
        using (var reader = new StringReader(normalizedSql))
        {
            fragment = parser.Parse(reader, out var parseErrors);
            diagnostics.AddRange(parseErrors.Select(error =>
                new AnalysisDiagnostic("Error", error.Message, error.Line, error.Column)));
        }

        var visitor = new ProcedureVisitor(normalizedSql, defaultServer);
        fragment.Accept(visitor);

        diagnostics.AddRange(visitor.Diagnostics);
        return new SqlFileAnalysis(Path.GetFullPath(file), visitor.Procedures, diagnostics);
    }

    private sealed class ProcedureVisitor(string sql, string defaultServer) : TSqlFragmentVisitor
    {
        private readonly List<ProcedureAnalysis> _procedures = [];
        private readonly List<AnalysisDiagnostic> _diagnostics = [];

        public IReadOnlyList<ProcedureAnalysis> Procedures => _procedures;
        public IReadOnlyList<AnalysisDiagnostic> Diagnostics => _diagnostics;

        public override void ExplicitVisit(CreateProcedureStatement node) => AnalyzeProcedure(node, node.ProcedureReference?.Name);

        public override void ExplicitVisit(AlterProcedureStatement node) => AnalyzeProcedure(node, node.ProcedureReference?.Name);

        private void AnalyzeProcedure(ProcedureStatementBodyBase node, SchemaObjectName? name)
        {
            var occurrences = new List<ColumnOccurrence>();
            var selectAnalyzer = new SelectAnalyzer(sql, defaultServer);
            var processor = new ProcedureStatementProcessor(selectAnalyzer, _diagnostics);
            processor.Process(node.StatementList);
            occurrences.AddRange(processor.OutputOccurrences);

            var columns = MergeColumns(occurrences);

            _procedures.Add(new ProcedureAnalysis(
                SqlName.Format(name) ?? "<anonymous-procedure>",
                columns,
                Array.Empty<AnalysisDiagnostic>()));
        }

        private static IReadOnlyList<OutputColumnAnalysis> MergeColumns(IReadOnlyList<ColumnOccurrence> occurrences)
        {
            var grouped = new Dictionary<string, List<ColumnOccurrence>>(StringComparer.OrdinalIgnoreCase);
            var order = new List<string>();

            foreach (var occurrence in occurrences)
            {
                if (!grouped.TryGetValue(occurrence.Name, out var group))
                {
                    group = [];
                    grouped[occurrence.Name] = group;
                    order.Add(occurrence.Name);
                }

                group.Add(occurrence);
            }

            return order
                .Select(name =>
                {
                    var group = grouped[name];
                    return new OutputColumnAnalysis(
                        name,
                        Distinct(group.Select(item => item.Formula)),
                        MergeSources(group.SelectMany(item => item.Sources)),
                        Distinct(group.SelectMany(item => item.Operations)),
                        group.Select(item => new BranchColumnAnalysis(
                                item.Branch,
                                item.Line,
                                item.Formula,
                                item.Sources,
                                item.Operations))
                            .ToArray());
                })
                .ToArray();
        }

        private static IReadOnlyList<string> Distinct(IEnumerable<string> values) =>
            values
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
                .ToArray();

        private static IReadOnlyList<SourceReference> MergeSources(IEnumerable<SourceReference> sources) =>
            sources
                .GroupBy(source => $"{source.Alias}|{source.ObjectName}|{source.Column}|{source.Formula}", StringComparer.OrdinalIgnoreCase)
                .Select(group =>
                {
                    var first = group.First();
                    return first with
                    {
                        DerivedSources = MergeSources(group.SelectMany(item => item.DerivedSources))
                    };
                })
                .OrderBy(source => source.Alias, StringComparer.OrdinalIgnoreCase)
                .ThenBy(source => source.Column, StringComparer.OrdinalIgnoreCase)
                .ToArray();
    }

    private sealed class ProcedureStatementProcessor(
        SelectAnalyzer selectAnalyzer,
        List<AnalysisDiagnostic> diagnostics)
    {
        private readonly Dictionary<string, TableSource> _tempSources = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, IReadOnlyList<string>> _tempColumns = new(StringComparer.OrdinalIgnoreCase);
        private readonly List<ColumnOccurrence> _outputOccurrences = [];

        public IReadOnlyList<ColumnOccurrence> OutputOccurrences => _outputOccurrences;

        public void Process(StatementList? statementList)
        {
            if (statementList is null)
            {
                return;
            }

            foreach (var statement in statementList.Statements)
            {
                Process(statement);
            }
        }

        private void Process(TSqlStatement? statement)
        {
            switch (statement)
            {
                case null:
                    return;
                case BeginEndBlockStatement block:
                    Process(block.StatementList);
                    return;
                case IfStatement ifStatement:
                    Process(ifStatement.ThenStatement);
                    Process(ifStatement.ElseStatement);
                    return;
                case WhileStatement whileStatement:
                    Process(whileStatement.Statement);
                    return;
                case TryCatchStatement tryCatch:
                    Process(tryCatch.TryStatements);
                    Process(tryCatch.CatchStatements);
                    return;
                case CreateTableStatement createTable:
                    CaptureTempTableSchema(createTable);
                    return;
                case InsertStatement insertStatement:
                    CaptureTempInsert(insertStatement);
                    return;
                case UpdateStatement updateStatement:
                    CaptureTempUpdate(updateStatement);
                    return;
                case SelectStatement selectStatement:
                    CaptureSelect(selectStatement);
                    return;
            }
        }

        private void CaptureSelect(SelectStatement statement)
        {
            try
            {
                if (statement.Into is not null)
                {
                    var source = selectAnalyzer.BuildTempSourceFromSelectInto(statement, _tempSources);
                    AddTempSource(source);
                    return;
                }

                _outputOccurrences.AddRange(selectAnalyzer.Analyze(statement, _tempSources));
            }
            catch (Exception ex)
            {
                diagnostics.Add(new AnalysisDiagnostic(
                    "Warning",
                    $"Could not analyze SELECT at line {statement.StartLine}: {ex.Message}",
                    statement.StartLine,
                    statement.StartColumn));
            }
        }

        private void CaptureTempInsert(InsertStatement statement)
        {
            var insert = statement.InsertSpecification;
            if (insert.InsertSource is not SelectInsertSource { Select: { } select })
            {
                return;
            }

            try
            {
                var targetName = TryGetTargetName(insert.Target);
                var source = selectAnalyzer.BuildTempSourceFromInsert(
                    insert,
                    select,
                    _tempSources,
                    targetName is not null && _tempColumns.TryGetValue(targetName, out var columns) ? columns : null);

                AddTempSource(source);
            }
            catch (Exception ex)
            {
                diagnostics.Add(new AnalysisDiagnostic(
                    "Warning",
                    $"Could not analyze INSERT SELECT at line {statement.StartLine}: {ex.Message}",
                    statement.StartLine,
                    statement.StartColumn));
            }
        }

        private void CaptureTempUpdate(UpdateStatement statement)
        {
            try
            {
                var source = selectAnalyzer.BuildTempSourceFromUpdate(statement.UpdateSpecification, _tempSources);
                AddTempSource(source);
            }
            catch (Exception ex)
            {
                diagnostics.Add(new AnalysisDiagnostic(
                    "Warning",
                    $"Could not analyze UPDATE at line {statement.StartLine}: {ex.Message}",
                    statement.StartLine,
                    statement.StartColumn));
            }
        }

        private void CaptureTempTableSchema(CreateTableStatement statement)
        {
            var name = SqlName.Format(statement.SchemaObjectName);
            if (string.IsNullOrWhiteSpace(name) || !IsTempName(name))
            {
                return;
            }

            var columns = statement.Definition?.ColumnDefinitions
                .Select(column => column.ColumnIdentifier?.Value)
                .Where(column => !string.IsNullOrWhiteSpace(column))
                .Cast<string>()
                .ToArray();

            if (columns is { Length: > 0 })
            {
                _tempColumns[name] = columns;
            }
        }

        private void AddTempSource(TableSource? source)
        {
            if (source is null || string.IsNullOrWhiteSpace(source.ObjectName.Table))
            {
                return;
            }

            _tempSources[source.ObjectName.Table] = source;
            _tempSources[source.Alias] = source;
            _tempColumns[source.ObjectName.Table] = source.DerivedColumns.Keys.ToArray();
        }

        private static string? TryGetTargetName(TableReference? target)
        {
            if (target is NamedTableReference named)
            {
                return SqlName.Format(named.SchemaObject);
            }

            return null;
        }

        private static bool IsTempName(string name)
        {
            var lastPart = name.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault();
            return lastPart?.StartsWith('#') == true;
        }
    }
}
