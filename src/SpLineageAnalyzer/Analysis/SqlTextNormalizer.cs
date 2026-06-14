using System.Text;

namespace SpLineageAnalyzer.Analysis;

internal static class SqlTextNormalizer
{
    public static string Normalize(string sql)
    {
        var builder = new StringBuilder(sql.Length);
        foreach (var ch in sql)
        {
            builder.Append(ch switch
            {
                '\u00a0' => ' ',
                '\u2000' => ' ',
                '\u2001' => ' ',
                '\u2002' => ' ',
                '\u2003' => ' ',
                '\u2004' => ' ',
                '\u2005' => ' ',
                '\u2006' => ' ',
                '\u2007' => ' ',
                '\u2008' => ' ',
                '\u2009' => ' ',
                '\u200a' => ' ',
                '\u202f' => ' ',
                '\u205f' => ' ',
                '\u3000' => ' ',
                _ => ch
            });
        }

        return builder.ToString();
    }
}
