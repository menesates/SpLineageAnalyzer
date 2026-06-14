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
            .GroupBy(source => $"{source.Alias}|{source.ObjectName}|{source.Column}|{source.Formula}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderBy(source => source.Alias, StringComparer.OrdinalIgnoreCase)
            .ThenBy(source => source.Column, StringComparer.OrdinalIgnoreCase)
            .ToArray();
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

            _sources.Add(CreateReference("", SqlObjectName.Unknown, "Unknown", parts[0], true, null, Array.Empty<SourceReference>()));
            return;
        }

        var alias = parts[^2];
        var column = parts[^1];
        if (!scope.TryGetValue(alias, out var tableSource))
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
