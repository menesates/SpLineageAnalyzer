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
            var collector = new StatementSelectCollector();
            node.StatementList?.Accept(collector);

            var occurrences = new List<ColumnOccurrence>();
            var selectAnalyzer = new SelectAnalyzer(sql, defaultServer);
            foreach (var selectStatement in collector.SelectStatements)
            {
                try
                {
                    occurrences.AddRange(selectAnalyzer.Analyze(selectStatement));
                }
                catch (Exception ex)
                {
                    _diagnostics.Add(new AnalysisDiagnostic(
                        "Warning",
                        $"Could not analyze SELECT at line {selectStatement.StartLine}: {ex.Message}",
                        selectStatement.StartLine,
                        selectStatement.StartColumn));
                }
            }

            var columns = occurrences
                .GroupBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
                .Select(group => new OutputColumnAnalysis(
                    group.Key,
                    Distinct(group.Select(item => item.Formula)),
                    MergeSources(group.SelectMany(item => item.Sources)),
                    Distinct(group.SelectMany(item => item.Operations)),
                    group.Select(item => new BranchColumnAnalysis(
                            item.Branch,
                            item.Line,
                            item.Formula,
                            item.Sources,
                            item.Operations))
                        .ToArray()))
                .OrderBy(column => column.Name, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            _procedures.Add(new ProcedureAnalysis(
                SqlName.Format(name) ?? "<anonymous-procedure>",
                columns,
                Array.Empty<AnalysisDiagnostic>()));
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

    private sealed class StatementSelectCollector : TSqlFragmentVisitor
    {
        private readonly List<SelectStatement> _selectStatements = [];

        public IReadOnlyList<SelectStatement> SelectStatements => _selectStatements;

        public override void ExplicitVisit(SelectStatement node)
        {
            _selectStatements.Add(node);
        }
    }
}
