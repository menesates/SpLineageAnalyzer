using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal static class SqlObjectNameParser
{
    public static SqlObjectName FromSchemaObject(SchemaObjectName? name, string defaultServer)
    {
        if (name is null)
        {
            return SqlObjectName.Unknown;
        }

        var parts = name.Identifiers.Select(identifier => identifier.Value).ToArray();
        return FromParts(parts, defaultServer);
    }

    public static SqlObjectName FromDisplayName(string? displayName, string defaultServer)
    {
        if (string.IsNullOrWhiteSpace(displayName))
        {
            return SqlObjectName.Unknown;
        }

        return FromParts(displayName.Split('.', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries), defaultServer);
    }

    public static SqlObjectName ForCte(string name) => new($"CTE: {name}", null, null, null, name);

    public static SqlObjectName ForDerived(string alias) => new($"Derived: {alias}", null, null, null, alias);

    private static SqlObjectName FromParts(IReadOnlyList<string> parts, string defaultServer)
    {
        if (parts.Count == 0)
        {
            return SqlObjectName.Unknown;
        }

        if (parts.Count == 1 && parts[0].StartsWith('#'))
        {
            return new SqlObjectName(parts[0], defaultServer, "tempdb", null, parts[0]);
        }

        return parts.Count switch
        {
            >= 4 => new SqlObjectName(
                string.Join(".", parts.TakeLast(4)),
                parts[^4],
                parts[^3],
                parts[^2],
                parts[^1]),
            3 => new SqlObjectName(
                string.Join(".", new[] { defaultServer, parts[^3], parts[^2], parts[^1] }),
                defaultServer,
                parts[^3],
                parts[^2],
                parts[^1]),
            2 => new SqlObjectName(
                string.Join(".", new[] { defaultServer, parts[^2], parts[^1] }),
                defaultServer,
                null,
                parts[^2],
                parts[^1]),
            _ => new SqlObjectName(
                string.Join(".", new[] { defaultServer, parts[^1] }),
                defaultServer,
                null,
                null,
                parts[^1])
        };
    }
}
