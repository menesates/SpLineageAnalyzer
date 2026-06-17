using ClosedXML.Excel;
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
            source.ObjectName == "vkdb.BOA.COR.Branch" &&
            source.Server == "vkdb" &&
            source.Database == "BOA" &&
            source.Schema == "COR" &&
            source.Table == "Branch" &&
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
            source.ObjectName == "vkdb.BOA.LNS.LoanRediscountAdvanceInterim" &&
            source.Column == "RediscountAmount");
        Assert.Contains(dailyRediscount.Sources, source =>
            source.Alias == "lr" &&
            source.ObjectName == "vkdb.BOA.LNS.LoanRediscountAdvanceInterim" &&
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
            source.ObjectName == "vkdb.boa.lns.Project" &&
            source.Column == "AgreementType");

        var mtx = Assert.Single(rediscount5.Sources, source => source.Alias == "mtx" && source.Column == "Rediscount5");
        Assert.Contains("MAX(CASE WHEN ma.ColumnNo = 1 THEN ma.LedgerId ELSE 0 END)", mtx.Formula);
        Assert.Contains(mtx.DerivedSources, source =>
            source.Alias == "ma" &&
            source.ObjectName == "vkdb.boa.acc.MatrixAccounts" &&
            source.Column == "LedgerId");

        var mtxl = Assert.Single(rediscount5.Sources, source => source.Alias == "mtxl" && source.Column == "Rediscount5");
        Assert.Contains("MAX(CASE WHEN ma.ColumnNo = 10 THEN ma.LedgerId ELSE 0 END)", mtxl.Formula);
        Assert.Contains(mtxl.DerivedSources, source =>
            source.Alias == "ma" &&
            source.ObjectName == "vkdb.boa.acc.MatrixAccounts" &&
            source.Column == "ColumnNo");
    }

    [Fact]
    public void Analyze_ResolvesServerDatabaseSchemaAndTableParts()
    {
        const string sql = """
            ALTER PROCEDURE [RPT].[rpt_LinkedServerSmoke]
            AS
            BEGIN
                SELECT
                    lim.PositionLimitAmount,
                    sw.FarAmount,
                    rb.TotalExposureTL
                FROM BOA.TRE.PositionLimit lim
                    INNER JOIN LINK01.BOA.TRE.FxSwapDeal sw ON sw.DeskCode = lim.DeskCode
                    INNER JOIN #RiskBucket rb ON rb.CurrencyCode = sw.FarCurrencyCode
            END
            """;

        var analysis = new StoredProcedureAnalyzer().Analyze("inline.sql", sql, "vkdb");
        Assert.Empty(analysis.Diagnostics);
        var procedure = Assert.Single(analysis.Procedures);

        var positionLimit = Column(procedure, "PositionLimitAmount");
        Assert.Contains(positionLimit.Sources, source =>
            source.Alias == "lim" &&
            source.Server == "vkdb" &&
            source.Database == "BOA" &&
            source.Schema == "TRE" &&
            source.Table == "PositionLimit");

        var farAmount = Column(procedure, "FarAmount");
        Assert.Contains(farAmount.Sources, source =>
            source.Alias == "sw" &&
            source.Server == "LINK01" &&
            source.Database == "BOA" &&
            source.Schema == "TRE" &&
            source.Table == "FxSwapDeal");

        var totalExposure = Column(procedure, "TotalExposureTL");
        Assert.Contains(totalExposure.Sources, source =>
            source.Alias == "rb" &&
            source.Server == "vkdb" &&
            source.Database == "tempdb" &&
            source.Schema is null &&
            source.Table == "#RiskBucket");
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
    public void Analyze_BranchKpiIgnoresSelectIntoAndKeepsFinalOutputShape()
    {
        var analysis = AnalyzeFile("rpt_BranchOperationalKpiComplex.sql");
        Assert.Empty(analysis.Diagnostics);

        var procedure = Assert.Single(analysis.Procedures);
        Assert.Equal(32, procedure.OutputColumns.Count);
        Assert.DoesNotContain(procedure.OutputColumns, column => column.Name == "TotalCount");

        var names = procedure.OutputColumns.Select(column => column.Name).ToArray();
        Assert.Equal("RegionId", names[0]);
        Assert.Equal("RegionName", names[1]);
        Assert.Equal("ReportEndDate", names[^1]);

        var atmCount = Column(procedure, "AtmCount");
        var channelMixSource = Assert.Single(atmCount.Sources, source => source.Alias == "cm" && source.Column == "AtmCount");
        Assert.Equal("Temp", channelMixSource.SourceKind);
        Assert.Equal("#ChannelMix", channelMixSource.Table);
        Assert.Contains("SUM(CASE WHEN tr.ChannelCode = 'ATM' THEN 1 ELSE 0 END)", channelMixSource.Formula);
        Assert.Contains(channelMixSource.DerivedSources, source =>
            source.Alias == "tr" &&
            source.ObjectName == "vkdb.BOA.OPR.BranchTransaction" &&
            source.Column == "ChannelCode");
    }

    [Fact]
    public void Analyze_CreditRiskIgnoresSelectIntoAndKeepsFinalOutputShape()
    {
        var analysis = AnalyzeFile("rpt_CreditPortfolioRiskComplex.sql");
        Assert.Empty(analysis.Diagnostics);

        var procedure = Assert.Single(analysis.Procedures);
        Assert.Equal(22, procedure.OutputColumns.Count);
        Assert.DoesNotContain(procedure.OutputColumns, column => column.Name == "LoanAccountId");
        Assert.DoesNotContain(procedure.OutputColumns, column => column.Name == "RiskBucketCode");
        Assert.DoesNotContain(procedure.OutputColumns, column => column.Name == "ProvisionRate");

        var names = procedure.OutputColumns.Select(column => column.Name).ToArray();
        Assert.Equal("BranchId", names[0]);
        Assert.Equal("BranchName", names[1]);
        Assert.Equal("ReportDate", names[^1]);

        var requiredProvision = Column(procedure, "RequiredProvisionTL");
        Assert.Contains(requiredProvision.Sources, source =>
            source.Alias == "rb" &&
            source.SourceKind == "Temp" &&
            source.Table == "#RiskBucket" &&
            source.Column == "ProvisionRate" &&
            source.Formula is not null &&
            source.Formula.Contains("rb.ProvisionRate * 1.25", StringComparison.OrdinalIgnoreCase) &&
            source.DerivedSources.Any(derived => derived.Alias == "rb" && derived.Column == "CollateralCoverageRatio"));
    }

    [Fact]
    public void Analyze_LoanProfitShareExpandsFinalTempTableStar()
    {
        var analysis = AnalyzePath(Path.Combine(FindRepositoryRoot(), "new_sp", "rpt_LoanProfitShareDetailInterim.sql"));
        Assert.Empty(analysis.Diagnostics);

        var procedure = Assert.Single(analysis.Procedures);
        Assert.Equal("LNS.rpt_LoanProfitShareDetailInterim", procedure.Name);
        Assert.Equal(59, procedure.OutputColumns.Count);

        var names = procedure.OutputColumns.Select(column => column.Name).ToArray();
        Assert.Equal("BranchId", names[0]);
        Assert.Equal("BranchName", names[1]);
        Assert.Equal("PbpMethod", names[^1]);
        Assert.DoesNotContain(procedure.OutputColumns, column => column.Name == "TranBrancId");

        var branchId = Column(procedure, "BranchId");
        Assert.Equal("lps.BranchId", Assert.Single(branchId.Formulas));
        Assert.Equal(new[] { 182, 253 }, branchId.Branches.Select(branch => branch.Line).OrderBy(line => line).ToArray());

        var branchName = Column(procedure, "BranchName");
        Assert.Contains(branchName.Sources, source =>
            source.Alias == "b" &&
            source.ObjectName == "vkdb.BOA.COR.Branch" &&
            source.Column == "Name");

        var reginalOffice = Column(procedure, "ReginalOffice");
        Assert.Contains("ISNULL(p7.ParamDescription,'')", reginalOffice.Formulas);
        Assert.Contains(reginalOffice.Sources, source =>
            source.Alias == "p7" &&
            source.ObjectName == "vkdb.BOA.COR.Parameter" &&
            source.Column == "ParamDescription");

        var accrualAmount = Column(procedure, "AccrualAmount");
        Assert.Equal(2, accrualAmount.Branches.Count);
        Assert.Contains(accrualAmount.Formulas, formula => formula.Contains("BOA.LNS.Accrual", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(accrualAmount.Sources, source =>
            source.ObjectName == "vkdb.BOA.LNS.Accrual" &&
            source.Column == "Amount");

        var rediscount5 = Column(procedure, "Rediscount5");
        Assert.Contains(rediscount5.Operations, operation => operation == "CASE");
        Assert.Equal(new[] { 207, 276 }, rediscount5.Branches.Select(branch => branch.Line).OrderBy(line => line).ToArray());
        Assert.Contains(rediscount5.Sources, source => source.Alias == "p" && source.Column == "AgreementType");
        Assert.Contains(rediscount5.Sources, source =>
            source.Alias == "mtx" &&
            source.Column == "Rediscount5" &&
            source.DerivedSources.Any(derived => derived.ObjectName == "vkdb.BOA.ACC.MatrixAccounts"));

        var rediscount2 = Column(procedure, "Rediscount2");
        Assert.Equal(new[] { 208, 277 }, rediscount2.Branches.Select(branch => branch.Line).OrderBy(line => line).ToArray());
        Assert.Contains(rediscount2.Sources, source => source.Alias == "mtxl" && source.Column == "Rediscount2");

        var pbpMethod = Column(procedure, "PbpMethod");
        Assert.Equal(2, pbpMethod.Branches.Count);
        Assert.Contains(pbpMethod.Sources, source =>
            source.Alias == "p6" &&
            source.ObjectName == "vkdb.BOA.COR.Parameter" &&
            source.Column == "ParamDescription");
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

    [Fact]
    public void ExcelFormatter_WritesExpectedWorkbookSheets()
    {
        var analysis = AnalyzeFile("rpt_TreasuryFxLiquidityComplex.sql");
        var output = Path.Combine(Path.GetTempPath(), $"lineage-{Guid.NewGuid():N}.xlsx");

        ExcelFormatter.Save(new[] { analysis }, output);

        Assert.True(File.Exists(output));
        using var workbook = new XLWorkbook(output);
        Assert.Contains("Summary", workbook.Worksheets.Select(sheet => sheet.Name));
        Assert.Contains("Outputs", workbook.Worksheets.Select(sheet => sheet.Name));
        Assert.Contains("Sources", workbook.Worksheets.Select(sheet => sheet.Name));
        Assert.Contains("Diagnostics", workbook.Worksheets.Select(sheet => sheet.Name));
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
