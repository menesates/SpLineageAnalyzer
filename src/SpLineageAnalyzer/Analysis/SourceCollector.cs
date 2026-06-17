using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal sealed class SourceCollector(IReadOnlyDictionary<string, TableSource> scope, string defaultServer) : TSqlFragmentVisitor
{
    private readonly List<SourceReference> _sources = [];
    private readonly Stack<IReadOnlyDictionary<string, TableSource>> _scopes = new(new[] { scope });
    private readonly Stack<TableSource?> _singleLocalSources = new(new TableSource?[] { null });

    public static IReadOnlyList<SourceReference> Collect(
        ScalarExpression expression,
        IReadOnlyDictionary<string, TableSource> scope,
        string defaultServer)
    {
        var visitor = new SourceCollector(scope, defaultServer);
        expression.Accept(visitor);
        return visitor._sources
            .GroupBy(source => $"{source.Alias}|{source.ObjectName}|{source.Column}|{source.Formula}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderBy(source => source.Alias, StringComparer.OrdinalIgnoreCase)
            .ThenBy(source => source.Column, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public override void ExplicitVisit(QuerySpecification node)
    {
        var localScope = new Dictionary<string, TableSource>(CurrentScope, StringComparer.OrdinalIgnoreCase);
        var localSources = AddFromSources(node.FromClause, localScope);
        _scopes.Push(localScope);
        _singleLocalSources.Push(localSources.Count == 1 ? localSources[0] : null);

        foreach (var selectElement in node.SelectElements)
        {
            selectElement.Accept(this);
        }

        node.FromClause?.Accept(this);
        node.WhereClause?.Accept(this);
        node.GroupByClause?.Accept(this);
        node.HavingClause?.Accept(this);
        node.OrderByClause?.Accept(this);

        _singleLocalSources.Pop();
        _scopes.Pop();
    }

    public override void ExplicitVisit(ColumnReferenceExpression node)
    {
        if (node.MultiPartIdentifier?.Identifiers is null)
        {
            return;
        }

        var parts = node.MultiPartIdentifier.Identifiers.Select(identifier => identifier.Value).ToArray();
        if (parts.Length == 0)
        {
            return;
        }

        if (parts.Length == 1)
        {
            if (IsDatePart(parts[0]))
            {
                return;
            }

            if (SingleLocalSource is { } singleSource)
            {
                var singleColumn = parts[0];
                if (singleSource.DerivedColumns.TryGetValue(singleColumn, out var singleDerivedColumn))
                {
                    _sources.Add(CreateReference(singleSource.Alias, singleSource.ObjectName, singleSource.SourceKind, singleColumn, false, singleDerivedColumn.Formula, singleDerivedColumn.Sources));
                    return;
                }

                _sources.Add(CreateReference(singleSource.Alias, singleSource.ObjectName, singleSource.SourceKind, singleColumn, false, null, Array.Empty<SourceReference>()));
                return;
            }

            _sources.Add(CreateReference("", SqlObjectName.Unknown, "Unknown", parts[0], true, null, Array.Empty<SourceReference>()));
            return;
        }

        var alias = parts[^2];
        var column = parts[^1];
        if (!CurrentScope.TryGetValue(alias, out var tableSource))
        {
            _sources.Add(CreateReference(alias, SqlObjectName.Unknown, "Unknown", column, true, null, Array.Empty<SourceReference>()));
            return;
        }

        if (tableSource.DerivedColumns.TryGetValue(column, out var derivedColumn))
        {
            _sources.Add(CreateReference(alias, tableSource.ObjectName, tableSource.SourceKind, column, false, derivedColumn.Formula, derivedColumn.Sources));
            return;
        }

        _sources.Add(CreateReference(alias, tableSource.ObjectName, tableSource.SourceKind, column, false, null, Array.Empty<SourceReference>()));
    }

    private static SourceReference CreateReference(
        string alias,
        SqlObjectName objectName,
        string sourceKind,
        string column,
        bool unresolved,
        string? formula,
        IReadOnlyList<SourceReference> derivedSources) =>
        new(
            alias,
            objectName.DisplayName,
            objectName.Server,
            objectName.Database,
            objectName.Schema,
            objectName.Table,
            sourceKind,
            column,
            unresolved,
            formula,
            derivedSources);

    private IReadOnlyDictionary<string, TableSource> CurrentScope => _scopes.Peek();
    private TableSource? SingleLocalSource => _singleLocalSources.Peek();

    private IReadOnlyList<TableSource> AddFromSources(FromClause? fromClause, Dictionary<string, TableSource> localScope)
    {
        if (fromClause is null)
        {
            return Array.Empty<TableSource>();
        }

        var localSources = new List<TableSource>();
        foreach (var reference in fromClause.TableReferences)
        {
            AddTableReference(reference, localScope, localSources);
        }

        return localSources
            .DistinctBy(source => source.Alias, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private void AddTableReference(TableReference reference, Dictionary<string, TableSource> localScope, List<TableSource> localSources)
    {
        switch (reference)
        {
            case NamedTableReference named:
                AddNamedTable(named, localScope, localSources);
                break;
            case QualifiedJoin qualifiedJoin:
                AddTableReference(qualifiedJoin.FirstTableReference, localScope, localSources);
                AddTableReference(qualifiedJoin.SecondTableReference, localScope, localSources);
                break;
            case UnqualifiedJoin unqualifiedJoin:
                AddTableReference(unqualifiedJoin.FirstTableReference, localScope, localSources);
                AddTableReference(unqualifiedJoin.SecondTableReference, localScope, localSources);
                break;
            case JoinParenthesisTableReference parenthesizedJoin:
                AddTableReference(parenthesizedJoin.Join, localScope, localSources);
                break;
        }
    }

    private void AddNamedTable(NamedTableReference named, Dictionary<string, TableSource> localScope, List<TableSource> localSources)
    {
        var objectName = SqlObjectNameParser.FromSchemaObject(named.SchemaObject, defaultServer);
        var tableName = objectName.DisplayName;
        var alias = named.Alias?.Value;
        if (string.IsNullOrWhiteSpace(alias))
        {
            alias = named.SchemaObject?.BaseIdentifier?.Value ?? tableName;
        }

        if (!string.IsNullOrWhiteSpace(alias))
        {
            var source = new TableSource(alias, objectName, new Dictionary<string, DerivedColumn>(StringComparer.OrdinalIgnoreCase));
            localScope[alias] = source;
            localSources.Add(source);
        }
    }

    private static bool IsDatePart(string value) =>
        value.Equals("YEAR", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("YY", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("YYYY", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("QUARTER", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("MONTH", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("MM", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("DAY", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("DD", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("HOUR", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("MINUTE", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("SECOND", StringComparison.OrdinalIgnoreCase);
}
