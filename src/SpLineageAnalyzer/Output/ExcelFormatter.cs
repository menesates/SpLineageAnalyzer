using ClosedXML.Excel;
using SpLineageAnalyzer.Analysis;

namespace SpLineageAnalyzer.Output;

public static class ExcelFormatter
{
    public static void Save(IReadOnlyList<SqlFileAnalysis> analyses, string path)
    {
        using var workbook = new XLWorkbook();
        AddSummary(workbook, analyses);
        AddOutputs(workbook, analyses);
        AddSources(workbook, analyses);
        AddDiagnostics(workbook, analyses);

        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? ".");
        workbook.SaveAs(path);
    }

    private static void AddSummary(XLWorkbook workbook, IReadOnlyList<SqlFileAnalysis> analyses)
    {
        var sheet = workbook.Worksheets.Add("Summary");
        var rows = analyses
            .SelectMany(file => file.Procedures.Select(procedure => new
            {
                File = Path.GetFileName(file.File),
                Procedure = procedure.Name,
                OutputColumns = procedure.OutputColumns.Count,
                Diagnostics = file.Diagnostics.Count + procedure.Diagnostics.Count
            }))
            .ToArray();

        InsertTable(sheet, rows, "SummaryTable");
    }

    private static void AddOutputs(XLWorkbook workbook, IReadOnlyList<SqlFileAnalysis> analyses)
    {
        var rows = analyses
            .SelectMany(file => file.Procedures.SelectMany(procedure => procedure.OutputColumns.Select(column => new
            {
                File = Path.GetFileName(file.File),
                Procedure = procedure.Name,
                OutputColumn = column.Name,
                Formulas = string.Join(Environment.NewLine, column.Formulas),
                Operations = string.Join(", ", column.Operations),
                Branches = string.Join(Environment.NewLine, column.Branches.Select(branch => $"{branch.Branch} line {branch.Line}"))
            })))
            .ToArray();

        InsertTable(workbook.Worksheets.Add("Outputs"), rows, "OutputsTable");
    }

    private static void AddSources(XLWorkbook workbook, IReadOnlyList<SqlFileAnalysis> analyses)
    {
        var rows = new List<object>();
        foreach (var file in analyses)
        {
            foreach (var procedure in file.Procedures)
            {
                foreach (var column in procedure.OutputColumns)
                {
                    foreach (var source in FlattenSources(column.Sources))
                    {
                        rows.Add(new
                        {
                            File = Path.GetFileName(file.File),
                            Procedure = procedure.Name,
                            OutputColumn = column.Name,
                            SourceDepth = source.Depth,
                            Alias = source.Source.Alias,
                            Server = source.Source.Server,
                            Database = source.Source.Database,
                            Schema = source.Source.Schema,
                            Table = source.Source.Table,
                            ObjectName = source.Source.ObjectName,
                            SourceKind = source.Source.SourceKind,
                            Column = source.Source.Column,
                            Unresolved = source.Source.Unresolved,
                            DerivedFormula = source.Source.Formula
                        });
                    }
                }
            }
        }

        InsertTable(workbook.Worksheets.Add("Sources"), rows, "SourcesTable");
    }

    private static void AddDiagnostics(XLWorkbook workbook, IReadOnlyList<SqlFileAnalysis> analyses)
    {
        var rows = analyses
            .SelectMany(file => file.Diagnostics.Select(diagnostic => new
            {
                File = Path.GetFileName(file.File),
                Procedure = "",
                diagnostic.Severity,
                diagnostic.Message,
                diagnostic.Line,
                diagnostic.Column
            }).Concat(file.Procedures.SelectMany(procedure => procedure.Diagnostics.Select(diagnostic => new
            {
                File = Path.GetFileName(file.File),
                Procedure = procedure.Name,
                diagnostic.Severity,
                diagnostic.Message,
                diagnostic.Line,
                diagnostic.Column
            }))))
            .ToArray();

        InsertTable(workbook.Worksheets.Add("Diagnostics"), rows, "DiagnosticsTable");
    }

    private static void InsertTable<T>(IXLWorksheet sheet, IReadOnlyCollection<T> rows, string tableName)
    {
        if (rows.Count == 0)
        {
            sheet.Cell(1, 1).Value = "No rows";
            sheet.Columns().AdjustToContents();
            return;
        }

        var table = sheet.Cell(1, 1).InsertTable(rows, tableName, true);
        table.Theme = XLTableTheme.TableStyleMedium2;
        sheet.SheetView.FreezeRows(1);
        sheet.Columns().AdjustToContents(5, 60);
        sheet.Rows().Style.Alignment.Vertical = XLAlignmentVerticalValues.Top;
        sheet.CellsUsed().Style.Alignment.WrapText = true;
    }

    private static IEnumerable<(SourceReference Source, int Depth)> FlattenSources(IReadOnlyList<SourceReference> sources, int depth = 0)
    {
        foreach (var source in sources)
        {
            yield return (source, depth);
            foreach (var derived in FlattenSources(source.DerivedSources, depth + 1))
            {
                yield return derived;
            }
        }
    }
}
