using System.Text;
using SpLineageAnalyzer.Analysis;

namespace SpLineageAnalyzer.Output;

public static class ConsoleReportFormatter
{
    public static string Format(IReadOnlyList<SqlFileAnalysis> analyses)
    {
        var builder = new StringBuilder();
        builder.AppendLine("Stored Procedure Lineage Report");
        builder.AppendLine(new string('=', 32));

        foreach (var file in analyses)
        {
            builder.AppendLine();
            builder.AppendLine($"FILE: {Path.GetFileName(file.File)}");

            var diagnostics = file.Diagnostics
                .Concat(file.Procedures.SelectMany(procedure => procedure.Diagnostics))
                .ToArray();

            if (diagnostics.Length > 0)
            {
                builder.AppendLine($"WARNINGS/ERRORS: {diagnostics.Length}");
                foreach (var diagnostic in diagnostics)
                {
                    var location = diagnostic.Line is null ? string.Empty : $" (line {diagnostic.Line}, col {diagnostic.Column})";
                    builder.AppendLine($"  - {diagnostic.Severity}: {diagnostic.Message}{location}");
                }
            }

            foreach (var procedure in file.Procedures)
            {
                builder.AppendLine($"PROCEDURE: {procedure.Name}");
                builder.AppendLine($"OUTPUT COLUMNS: {procedure.OutputColumns.Count}");

                if (procedure.OutputColumns.Count == 0)
                {
                    builder.AppendLine("  No output columns were detected.");
                    continue;
                }

                var index = 1;
                foreach (var column in procedure.OutputColumns)
                {
                    builder.AppendLine();
                    builder.AppendLine($"[{index}] {column.Name}");
                    AppendSection(builder, "Formula", column.Formulas.DefaultIfEmpty("<none>"));
                    AppendSection(builder, "Sources", FormatSources(column.Sources, indent: 4).DefaultIfEmpty("    - <none>"));
                    AppendSection(builder, "Operations", new[] { column.Operations.Count == 0 ? "<none>" : string.Join(", ", column.Operations) });
                    AppendSection(builder, "Branches", column.Branches.Select(branch => $"{branch.Branch}, output line {branch.Line}"));
                    index++;
                }
            }
        }

        return builder.ToString();
    }

    private static void AppendSection(StringBuilder builder, string title, IEnumerable<string> lines)
    {
        builder.AppendLine($"  {title}:");
        foreach (var line in lines)
        {
            builder.AppendLine(line.StartsWith("    ", StringComparison.Ordinal) ? line : $"    {line}");
        }
    }

    private static IEnumerable<string> FormatSources(IReadOnlyList<SourceReference> sources, int indent)
    {
        var prefix = new string(' ', indent);
        foreach (var source in sources)
        {
            var unresolved = source.Unresolved ? " [UNRESOLVED]" : string.Empty;
            var target = FormatTarget(source);
            yield return $"{prefix}- {FormatAliasColumn(source)} -> {target}{unresolved}";

            if (!string.IsNullOrWhiteSpace(source.Formula))
            {
                yield return $"{prefix}  Derived formula: {source.Formula}";
            }

            foreach (var derived in FormatSources(source.DerivedSources, indent + 4))
            {
                yield return derived;
            }
        }
    }

    private static string FormatAliasColumn(SourceReference source)
    {
        if (string.IsNullOrWhiteSpace(source.Alias))
        {
            return source.Column;
        }

        return $"{source.Alias}.{source.Column}";
    }

    private static string FormatTarget(SourceReference source)
    {
        if (source.SourceKind is "CTE" or "Derived")
        {
            return source.ObjectName ?? source.SourceKind;
        }

        return source.ObjectName ?? "unknown source";
    }
}
