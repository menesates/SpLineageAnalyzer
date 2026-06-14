using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal sealed class SourceCollector(IReadOnlyDictionary<string, TableSource> scope) : TSqlFragmentVisitor
{
    private readonly List<SourceReference> _sources = [];

    public static IReadOnlyList<SourceReference> Collect(
        ScalarExpression expression,
        IReadOnlyDictionary<string, TableSource> scope)
    {
        var visitor = new SourceCollector(scope);
        expression.Accept(visitor);
        return visitor._sources
            .GroupBy(source => $"{source.Alias}|{source.Table}|{source.Column}|{source.Formula}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderBy(source => source.Alias, StringComparer.OrdinalIgnoreCase)
            .ThenBy(source => source.Column, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public override void ExplicitVisit(ColumnReferenceExpression node)
    {
        var parts = node.MultiPartIdentifier.Identifiers.Select(identifier => identifier.Value).ToArray();
        if (parts.Length == 0)
        {
            return;
        }

        if (parts.Length == 1)
        {
            _sources.Add(new SourceReference(
                "",
                null,
                parts[0],
                true,
                null,
                Array.Empty<SourceReference>()));
            return;
        }

        var alias = parts[^2];
        var column = parts[^1];
        if (!scope.TryGetValue(alias, out var tableSource))
        {
            _sources.Add(new SourceReference(
                alias,
                null,
                column,
                true,
                null,
                Array.Empty<SourceReference>()));
            return;
        }

        if (tableSource.DerivedColumns.TryGetValue(column, out var derivedColumn))
        {
            _sources.Add(new SourceReference(
                alias,
                tableSource.Table,
                column,
                false,
                derivedColumn.Formula,
                derivedColumn.Sources));
            return;
        }

        _sources.Add(new SourceReference(
            alias,
            tableSource.Table,
            column,
            false,
            null,
            Array.Empty<SourceReference>()));
    }
}
