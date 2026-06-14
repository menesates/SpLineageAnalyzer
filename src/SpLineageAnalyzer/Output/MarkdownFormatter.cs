using System.Text;
using SpLineageAnalyzer.Analysis;

namespace SpLineageAnalyzer.Output;

public static class MarkdownFormatter
{
    public static string Format(IReadOnlyList<SqlFileAnalysis> analyses)
    {
        var builder = new StringBuilder();
        foreach (var file in analyses)
        {
            builder.AppendLine($"# {Path.GetFileName(file.File)}");
            foreach (var diagnostic in file.Diagnostics)
            {
                builder.AppendLine($"> {diagnostic.Severity}: {diagnostic.Message}");
            }

            foreach (var procedure in file.Procedures)
            {
                builder.AppendLine();
                builder.AppendLine($"## {procedure.Name}");
                builder.AppendLine();
                builder.AppendLine("| Output | Sources | Operations | Branches |");
                builder.AppendLine("| --- | --- | --- | --- |");

                foreach (var column in procedure.OutputColumns)
                {
                    var sources = string.Join("<br>", column.Sources.Select(FormatSource));
                    var operations = string.Join(", ", column.Operations);
                    var branches = string.Join("<br>", column.Branches.Select(branch => $"{branch.Branch} (line {branch.Line})"));
                    builder.AppendLine($"| {Escape(column.Name)} | {Escape(sources)} | {Escape(operations)} | {Escape(branches)} |");
                }
            }
        }

        return builder.ToString();
    }

    private static string FormatSource(SourceReference source)
    {
        var table = source.ObjectName ?? "?";
        var unresolved = source.Unresolved ? " unresolved" : string.Empty;
        var derived = string.IsNullOrWhiteSpace(source.Formula) ? string.Empty : $" <= {source.Formula}";
        return $"{source.Alias}.{source.Column} [{table}]{unresolved}{derived}";
    }

    private static string Escape(string value) => value.Replace("|", "\\|", StringComparison.Ordinal);
}
