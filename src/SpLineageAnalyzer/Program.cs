using System.Text.Json;
using SpLineageAnalyzer.Analysis;
using SpLineageAnalyzer.Output;

CliOptions options;
try
{
    options = CliOptions.Parse(args);
}
catch (ArgumentException ex)
{
    Console.Error.WriteLine(ex.Message);
    return 2;
}

var analyzer = new StoredProcedureAnalyzer();

var analyses = new List<SqlFileAnalysis>();
foreach (var file in ResolveInputFiles(options.InputPath))
{
    var sql = await File.ReadAllTextAsync(file);
    analyses.Add(analyzer.Analyze(file, sql, options.DefaultServer));
}

var jsonOptions = new JsonSerializerOptions
{
    WriteIndented = true,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
};

var emitJson = options.Format is OutputFormat.Json or OutputFormat.Both;
var emitExcel = options.Format is OutputFormat.Excel or OutputFormat.Both;
var json = emitJson ? JsonSerializer.Serialize(analyses, jsonOptions) : null;
var consoleReport = options.NoConsole ? null : ConsoleReportFormatter.Format(analyses);
var excelPath = emitExcel ? ResolveExcelOutputPath(options.OutputPath) : null;

if (string.IsNullOrWhiteSpace(options.OutputPath))
{
    if (json is not null)
    {
        Console.WriteLine(json);
    }
}
else
{
    WriteJsonOutput(options, json);
}

if (excelPath is not null)
{
    ExcelFormatter.Save(analyses, excelPath);
}

if (consoleReport is not null)
{
    if (string.IsNullOrWhiteSpace(options.OutputPath) && json is not null)
    {
        Console.WriteLine();
    }

    Console.WriteLine(consoleReport);
}

return 0;

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

static string ResolveExcelOutputPath(string? outputPath)
{
    if (string.IsNullOrWhiteSpace(outputPath))
    {
        return Path.Combine("output", "lineage.xlsx");
    }

    if (Directory.Exists(outputPath) || !Path.HasExtension(outputPath))
    {
        return Path.Combine(outputPath, "lineage.xlsx");
    }

    return outputPath;
}

static void WriteJsonOutput(CliOptions options, string? json)
{
    if (json is null)
    {
        return;
    }

    var outputPath = options.OutputPath ?? throw new InvalidOperationException("Output path is required.");
    if (Directory.Exists(outputPath) || options.Format == OutputFormat.Both)
    {
        Directory.CreateDirectory(outputPath);
        File.WriteAllText(Path.Combine(outputPath, "lineage.json"), json);
        return;
    }

    File.WriteAllText(outputPath, json);
}

internal sealed record CliOptions(string InputPath, OutputFormat Format, string? OutputPath, bool NoConsole, string DefaultServer)
{
    public static CliOptions Parse(string[] args)
    {
        var input = "sp";
        var format = OutputFormat.Json;
        string? output = null;
        var noConsole = false;
        var defaultServer = "vkdb";

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
                case "--server":
                    defaultServer = RequireValue(args, ref i, "--server");
                    break;
                case "--help":
                case "-h":
                    PrintHelpAndExit();
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {args[i]}");
            }
        }

        return new CliOptions(input, format, output, noConsole, defaultServer);
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
            "excel" => OutputFormat.Excel,
            "both" => OutputFormat.Both,
            _ => throw new ArgumentException("--format must be json, excel, or both.")
        };

    private static void PrintHelpAndExit()
    {
        Console.WriteLine("Usage: SpLineageAnalyzer [--input <file-or-dir>] [--server <name>] [--format json|excel|both] [--output <file-or-dir>] [--no-console]");
        Environment.Exit(0);
    }
}

internal enum OutputFormat
{
    Json,
    Excel,
    Both
}
