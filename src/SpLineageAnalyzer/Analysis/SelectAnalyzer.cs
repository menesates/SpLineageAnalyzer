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

        return AnalyzeQuerySpecification(query, $"select@line:{statement.StartLine}", new Dictionary<string, TableSource>(StringComparer.OrdinalIgnoreCase));
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

    private static void AddNamedTable(NamedTableReference named, Dictionary<string, TableSource> scope)
    {
        var tableName = SqlName.Format(named.SchemaObject);
        var alias = named.Alias?.Value;
        if (string.IsNullOrWhiteSpace(alias))
        {
            alias = named.SchemaObject.BaseIdentifier?.Value ?? tableName;
        }

        if (!string.IsNullOrWhiteSpace(alias))
        {
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

        var query = FindQuerySpecification(derived.QueryExpression);
        if (query is null)
        {
            scope[alias] = new TableSource(alias, null, new Dictionary<string, DerivedColumn>(StringComparer.OrdinalIgnoreCase));
            return;
        }

        var derivedScope = BuildScope(query, scope);
        var columns = new Dictionary<string, DerivedColumn>(StringComparer.OrdinalIgnoreCase);
        var ordinal = 1;
        foreach (var element in query.SelectElements)
        {
            if (element is not SelectScalarExpression scalar)
            {
                continue;
            }

            var name = InferColumnName(scalar, ordinal);
            columns[name] = new DerivedColumn(
                name,
                FragmentSql.GetText(scalar.Expression, sql),
                SourceCollector.Collect(scalar.Expression, derivedScope),
                OperationCollector.Collect(scalar.Expression));
            ordinal++;
        }

        scope[alias] = new TableSource(alias, null, columns);
    }

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
            AddNamedTable(node, _sources);
        }

        public override void ExplicitVisit(QueryDerivedTable node)
        {
            var analyzer = new SelectAnalyzer(sqlText);
            analyzer.AddDerivedTable(node, _sources);
        }
    }
}
