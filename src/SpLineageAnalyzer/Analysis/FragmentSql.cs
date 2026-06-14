using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal static class FragmentSql
{
    public static string GetText(TSqlFragment fragment, string fallbackSql)
    {
        if (fragment.ScriptTokenStream is null ||
            fragment.FirstTokenIndex < 0 ||
            fragment.LastTokenIndex < fragment.FirstTokenIndex)
        {
            return string.Empty;
        }

        var tokens = fragment.ScriptTokenStream
            .Skip(fragment.FirstTokenIndex)
            .Take(fragment.LastTokenIndex - fragment.FirstTokenIndex + 1)
            .Where(token => token.TokenType != TSqlTokenType.EndOfFile)
            .Select(token => token.Text);

        var text = string.Concat(tokens).Trim();
        return string.IsNullOrWhiteSpace(text) ? fallbackSql.Substring(Math.Min(fragment.StartOffset, fallbackSql.Length), Math.Min(fragment.FragmentLength, Math.Max(0, fallbackSql.Length - fragment.StartOffset))).Trim() : text;
    }
}
