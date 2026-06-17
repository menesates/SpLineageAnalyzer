namespace SpLineageAnalyzer.Analysis;

public sealed record SqlFileAnalysis(
    string File,
    IReadOnlyList<ProcedureAnalysis> Procedures,
    IReadOnlyList<AnalysisDiagnostic> Diagnostics);

public sealed record ProcedureAnalysis(
    string Name,
    IReadOnlyList<OutputColumnAnalysis> OutputColumns,
    IReadOnlyList<AnalysisDiagnostic> Diagnostics);

public sealed record OutputColumnAnalysis(
    string Name,
    IReadOnlyList<string> Formulas,
    IReadOnlyList<SourceReference> Sources,
    IReadOnlyList<string> Operations,
    IReadOnlyList<BranchColumnAnalysis> Branches);

public sealed record BranchColumnAnalysis(
    string Branch,
    int Line,
    string Formula,
    IReadOnlyList<SourceReference> Sources,
    IReadOnlyList<string> Operations);

public sealed record SourceReference(
    string Alias,
    string? ObjectName,
    string? Server,
    string? Database,
    string? Schema,
    string? Table,
    string SourceKind,
    string Column,
    bool Unresolved,
    string? Formula,
    IReadOnlyList<SourceReference> DerivedSources);

public sealed record AnalysisDiagnostic(string Severity, string Message, int? Line = null, int? Column = null);

internal sealed record ColumnOccurrence(
    string Name,
    string Branch,
    int Line,
    string Formula,
    IReadOnlyList<SourceReference> Sources,
    IReadOnlyList<string> Operations);

internal sealed record TableSource(
    string Alias,
    SqlObjectName ObjectName,
    IReadOnlyDictionary<string, DerivedColumn> DerivedColumns,
    string SourceKind = "Table");

internal sealed record SqlObjectName(
    string? DisplayName,
    string? Server,
    string? Database,
    string? Schema,
    string? Table)
{
    public static SqlObjectName Unknown { get; } = new(null, null, null, null, null);
}

internal sealed record DerivedColumn(
    string Name,
    string Formula,
    int Line,
    IReadOnlyList<SourceReference> Sources,
    IReadOnlyList<string> Operations,
    IReadOnlyList<DerivedColumnBranch> Branches);

internal sealed record DerivedColumnBranch(
    int Line,
    string Formula,
    IReadOnlyList<SourceReference> Sources,
    IReadOnlyList<string> Operations);
