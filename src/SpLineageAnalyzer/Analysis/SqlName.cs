using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal static class SqlName
{
    public static string? Format(MultiPartIdentifier? name)
    {
        if (name is null)
        {
            return null;
        }

        return string.Join(".", name.Identifiers.Select(identifier => identifier.Value));
    }
}
