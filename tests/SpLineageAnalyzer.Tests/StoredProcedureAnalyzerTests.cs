using SpLineageAnalyzer.Analysis;
using SpLineageAnalyzer.Output;
using Xunit;

namespace SpLineageAnalyzer.Tests;

public sealed class StoredProcedureAnalyzerTests
{
    [Fact]
    public void Analyze_MergesOutputColumnsButKeepsBranches()
    {
        var procedure = AnalyzeSample();

        var accountNumber = Column(procedure, "AccountNumber");
        Assert.Single(procedure.OutputColumns, column => column.Name == "AccountNumber");
        Assert.Equal(2, accountNumber.Branches.Count);
        Assert.Contains(accountNumber.Branches, branch => branch.Branch == "select@line:23");
        Assert.Contains(accountNumber.Branches, branch => branch.Branch == "select@line:92");
    }

    [Fact]
    public void Analyze_ResolvesDirectAliasAndConstantOutputs()
    {
        var procedure = AnalyzeSample();

        var tranBranchName = Column(procedure, "TranBranchName");
        Assert.Contains(tranBranchName.Sources, source =>
            source.Alias == "b" &&
            source.Table == "BOA.COR.Branch" &&
            source.Column == "Name" &&
            !source.Unresolved);

        var tranReference = Column(procedure, "TranReference");
        Assert.Equal("null", Assert.Single(tranReference.Formulas));
        Assert.Empty(tranReference.Sources);
    }

    [Fact]
    public void Analyze_CapturesFormulaSourcesAndOperations()
    {
        var procedure = AnalyzeSample();

        var dailyRediscount = Column(procedure, "DailyRediscount");
        Assert.Contains(dailyRediscount.Operations, operation => operation == "ISNULL");
        Assert.Contains(dailyRediscount.Operations, operation => operation == "Subtract");
        Assert.Contains(dailyRediscount.Sources, source =>
            source.Alias == "lra" &&
            source.Table == "BOA.LNS.LoanRediscountAdvanceInterim" &&
            source.Column == "RediscountAmount");
        Assert.Contains(dailyRediscount.Sources, source =>
            source.Alias == "lr" &&
            source.Table == "BOA.LNS.LoanRediscountAdvanceInterim" &&
            source.Column == "RediscountAmount");
    }

    [Fact]
    public void Analyze_ChainsApplyDerivedColumnLineage()
    {
        var procedure = AnalyzeSample();

        var rediscount5 = Column(procedure, "Rediscount5");
        Assert.Contains(rediscount5.Operations, operation => operation == "CASE");
        Assert.Contains(rediscount5.Sources, source =>
            source.Alias == "p" &&
            source.Table == "boa.lns.Project" &&
            source.Column == "AgreementType");

        var mtx = Assert.Single(rediscount5.Sources, source => source.Alias == "mtx" && source.Column == "Rediscount5");
        Assert.Contains("MAX(CASE WHEN ma.ColumnNo = 1 THEN ma.LedgerId ELSE 0 END)", mtx.Formula);
        Assert.Contains(mtx.DerivedSources, source =>
            source.Alias == "ma" &&
            source.Table == "boa.acc.MatrixAccounts" &&
            source.Column == "LedgerId");

        var mtxl = Assert.Single(rediscount5.Sources, source => source.Alias == "mtxl" && source.Column == "Rediscount5");
        Assert.Contains("MAX(CASE WHEN ma.ColumnNo = 10 THEN ma.LedgerId ELSE 0 END)", mtxl.Formula);
        Assert.Contains(mtxl.DerivedSources, source =>
            source.Alias == "ma" &&
            source.Table == "boa.acc.MatrixAccounts" &&
            source.Column == "ColumnNo");
    }

    [Fact]
    public void Analyze_TreasuryCteProcedureResolvesFinalOutputColumns()
    {
        var analysis = AnalyzeFile("rpt_TreasuryFxLiquidityComplex.sql");
        Assert.Empty(analysis.Diagnostics);

        var procedure = Assert.Single(analysis.Procedures);
        Assert.Equal("RPT.rpt_TreasuryFxLiquidityComplex", procedure.Name);
        Assert.NotEmpty(procedure.OutputColumns);

        var projectedClosingPosition = Column(procedure, "ProjectedClosingPosition");
        Assert.Contains(projectedClosingPosition.Sources, source => source.Alias == "pb" && source.Column == "CurrentPositionAmount");
        Assert.Contains(projectedClosingPosition.Sources, source => source.Alias == "af" && source.Column == "TotalForwardCashFlow");

        var liquiditySurvivalRatio = Column(procedure, "LiquiditySurvivalRatio");
        Assert.Contains(liquiditySurvivalRatio.Sources, source => source.Alias == "stress" && source.Column == "StressedOutflowAmount");

        var limitBreachFlag = Column(procedure, "LimitBreachFlag");
        Assert.Contains(limitBreachFlag.Sources, source => source.Alias == "limitDef" && source.Column == "PositionLimitAmount");
    }

    [Fact]
    public void ConsoleReportFormatter_RendersReadableColumnDetails()
    {
        var analysis = AnalyzeFile("rpt_TreasuryFxLiquidityComplex.sql");
        var report = ConsoleReportFormatter.Format(new[] { analysis });

        Assert.Contains("Stored Procedure Lineage Report", report);
        Assert.Contains("FILE: rpt_TreasuryFxLiquidityComplex.sql", report);
        Assert.Contains("PROCEDURE: RPT.rpt_TreasuryFxLiquidityComplex", report);
        Assert.Contains("[", report);
        Assert.Contains("ProjectedClosingPosition", report);
        Assert.Contains("Formula:", report);
        Assert.Contains("Sources:", report);
        Assert.Contains("Operations:", report);
        Assert.Contains("pb.CurrentPositionAmount -> CTE: PositionBase", report);
        Assert.Contains("af.TotalForwardCashFlow -> CTE: AggregatedFlow", report);
    }

    private static ProcedureAnalysis AnalyzeSample()
    {
        var root = FindRepositoryRoot();
        var file = Path.Combine(root, "sp", "rpt_LoanRediscountAdvanceInterim.sql");
        var analysis = AnalyzePath(file);

        Assert.Empty(analysis.Diagnostics);
        return Assert.Single(analysis.Procedures);
    }

    private static SqlFileAnalysis AnalyzeFile(string fileName)
    {
        var root = FindRepositoryRoot();
        return AnalyzePath(Path.Combine(root, "sp", fileName));
    }

    private static SqlFileAnalysis AnalyzePath(string file)
    {
        var sql = File.ReadAllText(file);
        return new StoredProcedureAnalyzer().Analyze(file, sql);
    }

    private static OutputColumnAnalysis Column(ProcedureAnalysis procedure, string name) =>
        Assert.Single(procedure.OutputColumns, column => string.Equals(column.Name, name, StringComparison.OrdinalIgnoreCase));

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "sp")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not find repository root containing the sp directory.");
    }
}
