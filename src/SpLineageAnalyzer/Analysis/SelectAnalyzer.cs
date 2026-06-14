using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal sealed class SelectAnalyzer(string sql)
{
    public IReadOnlyList<ColumnOccurrence> Analyze(SelectStatement statement)
    {
        var query = FindQuerySpecification(statement.QueryExpression);
        if (query is null)
        {
            return Array.Empty<ColumnOccurrence>();
        }

        var cteScope = BuildCteScope(statement);
        return AnalyzeQuerySpecification(query, $"select@line:{statement.StartLine}", cteScope);
    }

    private IReadOnlyList<ColumnOccurrence> AnalyzeQuerySpecification(
        QuerySpecification query,
        string branch,
        IReadOnlyDictionary<string, TableSource> outerScope)
    {
        var scope = BuildScope(query, outerScope);
        var results = new List<ColumnOccurrence>();
        var ordinal = 1;

        foreach (var element in query.SelectElements)
        {
            if (element is not SelectScalarExpression scalar)
            {
                continue;
            }

            var name = InferColumnName(scalar, ordinal);
            var expression = scalar.Expression;
            var formula = FragmentSql.GetText(expression, sql);
            var sources = SourceCollector.Collect(expression, scope);
            var operations = OperationCollector.Collect(expression);

            results.Add(new ColumnOccurrence(
                name,
                branch,
                scalar.StartLine,
                formula,
                sources,
                operations));
            ordinal++;
        }

        return results;
    }

    private Dictionary<string, TableSource> BuildScope(
        QuerySpecification query,
        IReadOnlyDictionary<string, TableSource> outerScope)
    {
        var scope = new Dictionary<string, TableSource>(outerScope, StringComparer.OrdinalIgnoreCase);
        if (query.FromClause is null)
        {
            return scope;
        }

        foreach (var tableReference in query.FromClause.TableReferences)
        {
            AddTableReference(tableReference, scope);
        }

        return scope;
    }

    private void AddTableReference(TableReference reference, Dictionary<string, TableSource> scope)
    {
        switch (reference)
        {
            case NamedTableReference named:
                AddNamedTable(named, scope);
                break;
            case QueryDerivedTable derived:
                AddDerivedTable(derived, scope);
                break;
            case QualifiedJoin qualifiedJoin:
                AddTableReference(qualifiedJoin.FirstTableReference, scope);
                AddTableReference(qualifiedJoin.SecondTableReference, scope);
                break;
            case UnqualifiedJoin unqualifiedJoin:
                AddTableReference(unqualifiedJoin.FirstTableReference, scope);
                AddTableReference(unqualifiedJoin.SecondTableReference, scope);
                break;
            case JoinParenthesisTableReference parenthesizedJoin:
                AddTableReference(parenthesizedJoin.Join, scope);
                break;
            default:
                var visitor = new FallbackTableReferenceVisitor(sql);
                reference.Accept(visitor);
                foreach (var source in visitor.Sources)
                {
                    scope[source.Key] = source.Value;
                }
                break;
        }
    }

    private Dictionary<string, TableSource> BuildCteScope(SelectStatement statement)
    {
        var scope = new Dictionary<string, TableSource>(StringComparer.OrdinalIgnoreCase);
        var commonTableExpressions = statement.WithCtesAndXmlNamespaces?.CommonTableExpressions;
        if (commonTableExpressions is null)
        {
            return scope;
        }

        foreach (var cte in commonTableExpressions)
        {
            var name = cte.ExpressionName?.Value;
            if (string.IsNullOrWhiteSpace(name))
            {
                continue;
            }

            var columns = BuildDerivedColumns(cte.QueryExpression, scope, cte.Columns.Select(column => column.Value).ToArray());
            scope[name] = new TableSource(name, $"CTE: {name}", columns, "CTE");
        }

        return scope;
    }

    private void AddNamedTable(NamedTableReference named, Dictionary<string, TableSource> scope)
    {
        var tableName = SqlName.Format(named.SchemaObject);
        var alias = named.Alias?.Value;
        if (string.IsNullOrWhiteSpace(alias))
        {
            alias = named.SchemaObject?.BaseIdentifier?.Value ?? tableName;
        }

        if (!string.IsNullOrWhiteSpace(alias))
        {
            if (!string.IsNullOrWhiteSpace(tableName) &&
                scope.TryGetValue(tableName, out var scopedSource) &&
                scopedSource.SourceKind is "CTE")
            {
                scope[alias] = scopedSource with { Alias = alias };
                return;
            }

            scope[alias] = new TableSource(alias, tableName, new Dictionary<string, DerivedColumn>(StringComparer.OrdinalIgnoreCase));
        }
    }

    private void AddDerivedTable(QueryDerivedTable derived, Dictionary<string, TableSource> scope)
    {
        var alias = derived.Alias?.Value;
        if (string.IsNullOrWhiteSpace(alias))
        {
            return;
        }

        var columns = BuildDerivedColumns(derived.QueryExpression, scope);
        scope[alias] = new TableSource(alias, $"Derived: {alias}", columns, "Derived");
    }

    private IReadOnlyDictionary<string, DerivedColumn> BuildDerivedColumns(
        QueryExpression? expression,
        IReadOnlyDictionary<string, TableSource> outerScope,
        IReadOnlyList<string>? explicitColumnNames = null)
    {
        var branches = new List<IReadOnlyList<DerivedColumn>>();
        CollectDerivedColumnBranches(expression, outerScope, branches);

        var merged = new Dictionary<string, DerivedColumn>(StringComparer.OrdinalIgnoreCase);
        for (var branchIndex = 0; branchIndex < branches.Count; branchIndex++)
        {
            var branch = branches[branchIndex];
            for (var i = 0; i < branch.Count; i++)
            {
                var column = branch[i];
                var name = explicitColumnNames is not null && i < explicitColumnNames.Count && !string.IsNullOrWhiteSpace(explicitColumnNames[i])
                    ? explicitColumnNames[i]
                    : column.Name;

                if (!merged.TryGetValue(name, out var existing))
                {
                    merged[name] = column with { Name = name };
                    continue;
                }

                merged[name] = new DerivedColumn(
                    name,
                    MergeText(existing.Formula, column.Formula),
                    MergeSources(existing.Sources.Concat(column.Sources)),
                    MergeTextValues(existing.Operations.Concat(column.Operations)));
            }
        }

        return merged;
    }

    private void CollectDerivedColumnBranches(
        QueryExpression? expression,
        IReadOnlyDictionary<string, TableSource> outerScope,
        List<IReadOnlyList<DerivedColumn>> branches)
    {
        switch (expression)
        {
            case QuerySpecification query:
                branches.Add(BuildDerivedColumnsFromQuery(query, outerScope));
                break;
            case BinaryQueryExpression binary:
                CollectDerivedColumnBranches(binary.FirstQueryExpression, outerScope, branches);
                CollectDerivedColumnBranches(binary.SecondQueryExpression, outerScope, branches);
                break;
            case QueryParenthesisExpression parenthesis:
                CollectDerivedColumnBranches(parenthesis.QueryExpression, outerScope, branches);
                break;
        }
    }

    private IReadOnlyList<DerivedColumn> BuildDerivedColumnsFromQuery(
        QuerySpecification query,
        IReadOnlyDictionary<string, TableSource> outerScope)
    {
        var derivedScope = BuildScope(query, outerScope);
        var columns = new List<DerivedColumn>();
        var ordinal = 1;
        foreach (var element in query.SelectElements)
        {
            if (element is not SelectScalarExpression scalar)
            {
                continue;
            }

            var name = InferColumnName(scalar, ordinal);
            columns.Add(new DerivedColumn(
                name,
                FragmentSql.GetText(scalar.Expression, sql),
                SourceCollector.Collect(scalar.Expression, derivedScope),
                OperationCollector.Collect(scalar.Expression)));
            ordinal++;
        }

        return columns;
    }

    private static string MergeText(string left, string right)
    {
        if (string.Equals(left, right, StringComparison.OrdinalIgnoreCase))
        {
            return left;
        }

        return $"{left} UNION/OR {right}";
    }

    private static IReadOnlyList<string> MergeTextValues(IEnumerable<string> values) =>
        values
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static IReadOnlyList<SourceReference> MergeSources(IEnumerable<SourceReference> sources) =>
        sources
            .GroupBy(source => $"{source.Alias}|{source.Table}|{source.Column}|{source.Formula}", StringComparer.OrdinalIgnoreCase)
            .Select(group =>
            {
                var first = group.First();
                return first with { DerivedSources = MergeSources(group.SelectMany(item => item.DerivedSources)) };
            })
            .OrderBy(source => source.Alias, StringComparer.OrdinalIgnoreCase)
            .ThenBy(source => source.Column, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static QuerySpecification? FindQuerySpecification(QueryExpression? expression)
    {
        return expression switch
        {
            QuerySpecification query => query,
            BinaryQueryExpression binary => FindQuerySpecification(binary.FirstQueryExpression),
            QueryParenthesisExpression parenthesis => FindQuerySpecification(parenthesis.QueryExpression),
            _ => null
        };
    }

    private static string InferColumnName(SelectScalarExpression scalar, int ordinal)
    {
        if (scalar.ColumnName is not null)
        {
            return scalar.ColumnName.Value;
        }

        if (scalar.Expression is ColumnReferenceExpression column && column.MultiPartIdentifier.Identifiers.Count > 0)
        {
            return column.MultiPartIdentifier.Identifiers[^1].Value;
        }

        return $"Expression{ordinal}";
    }

    private sealed class FallbackTableReferenceVisitor(string sqlText) : TSqlFragmentVisitor
    {
        private readonly Dictionary<string, TableSource> _sources = new(StringComparer.OrdinalIgnoreCase);

        public IReadOnlyDictionary<string, TableSource> Sources => _sources;

        public override void ExplicitVisit(NamedTableReference node)
        {
            var analyzer = new SelectAnalyzer(sqlText);
            analyzer.AddNamedTable(node, _sources);
        }

        public override void ExplicitVisit(QueryDerivedTable node)
        {
            var analyzer = new SelectAnalyzer(sqlText);
            analyzer.AddDerivedTable(node, _sources);
        }
    }
}
