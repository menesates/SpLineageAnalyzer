using System.Text.Json;
using SpLineageAnalyzer.Analysis;
using SpLineageAnalyzer.Output;

var options = CliOptions.Parse(args);
var analyzer = new StoredProcedureAnalyzer();

var analyses = new List<SqlFileAnalysis>();
foreach (var file in ResolveInputFiles(options.InputPath))
{
    var sql = await File.ReadAllTextAsync(file);
    analyses.Add(analyzer.Analyze(file, sql));
}

var jsonOptions = new JsonSerializerOptions
{
    WriteIndented = true,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
};

var emitJson = options.Format is OutputFormat.Json or OutputFormat.Both;
var emitMarkdown = options.Format is OutputFormat.Markdown or OutputFormat.Both;
var json = emitJson ? JsonSerializer.Serialize(analyses, jsonOptions) : null;
var markdown = emitMarkdown ? MarkdownFormatter.Format(analyses) : null;
var consoleReport = options.NoConsole ? null : ConsoleReportFormatter.Format(analyses);

if (string.IsNullOrWhiteSpace(options.OutputPath))
{
    if (json is not null)
    {
        Console.WriteLine(json);
    }

    if (markdown is not null)
    {
        if (json is not null)
        {
            Console.WriteLine();
        }

        Console.WriteLine(markdown);
    }
}
else
{
    WriteOutput(options, json, markdown);
}

if (consoleReport is not null)
{
    if (string.IsNullOrWhiteSpace(options.OutputPath) && (json is not null || markdown is not null))
    {
        Console.WriteLine();
    }

    Console.WriteLine(consoleReport);
}

static IReadOnlyList<string> ResolveInputFiles(string inputPath)
{
    if (File.Exists(inputPath))
    {
        return new[] { Path.GetFullPath(inputPath) };
    }

    if (!Directory.Exists(inputPath))
    {
        throw new DirectoryNotFoundException($"Input path was not found: {inputPath}");
    }

    return Directory.GetFiles(inputPath, "*.sql", SearchOption.AllDirectories)
        .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
        .Select(Path.GetFullPath)
        .ToArray();
}

static void WriteOutput(CliOptions options, string? json, string? markdown)
{
    var outputPath = options.OutputPath ?? throw new InvalidOperationException("Output path is required.");
    if (Directory.Exists(outputPath) || options.Format == OutputFormat.Both)
    {
        Directory.CreateDirectory(outputPath);
        if (json is not null)
        {
            File.WriteAllText(Path.Combine(outputPath, "lineage.json"), json);
        }

        if (markdown is not null)
        {
            File.WriteAllText(Path.Combine(outputPath, "lineage.md"), markdown);
        }

        return;
    }

    File.WriteAllText(outputPath, json ?? markdown ?? string.Empty);
}

internal sealed record CliOptions(string InputPath, OutputFormat Format, string? OutputPath, bool NoConsole)
{
    public static CliOptions Parse(string[] args)
    {
        var input = "sp";
        var format = OutputFormat.Json;
        string? output = null;
        var noConsole = false;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--input":
                    input = RequireValue(args, ref i, "--input");
                    break;
                case "--format":
                    format = ParseFormat(RequireValue(args, ref i, "--format"));
                    break;
                case "--output":
                    output = RequireValue(args, ref i, "--output");
                    break;
                case "--no-console":
                    noConsole = true;
                    break;
                case "--help":
                case "-h":
                    PrintHelpAndExit();
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {args[i]}");
            }
        }

        return new CliOptions(input, format, output, noConsole);
    }

    private static string RequireValue(string[] args, ref int index, string name)
    {
        if (index + 1 >= args.Length)
        {
            throw new ArgumentException($"{name} requires a value.");
        }

        index++;
        return args[index];
    }

    private static OutputFormat ParseFormat(string value) =>
        value.ToLowerInvariant() switch
        {
            "json" => OutputFormat.Json,
            "markdown" => OutputFormat.Markdown,
            "both" => OutputFormat.Both,
            _ => throw new ArgumentException("--format must be json, markdown, or both.")
        };

    private static void PrintHelpAndExit()
    {
        Console.WriteLine("Usage: SpLineageAnalyzer [--input <file-or-dir>] [--format json|markdown|both] [--output <file-or-dir>] [--no-console]");
        Environment.Exit(0);
    }
}

internal enum OutputFormat
{
    Json,
    Markdown,
    Both
}
