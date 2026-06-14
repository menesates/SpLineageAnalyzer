USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_BranchOperationalKpiComplex]
(
    @BeginDate      DATE        = NULL,
    @EndDate        DATE        = NULL,
    @RegionId       INT         = NULL,
    @BranchId       INT         = NULL,
    @LanguageId     SMALLINT    = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @BeginDate IS NULL SET @BeginDate = DATEADD(DAY, 1 - DAY(GETDATE()), CAST(GETDATE() AS DATE));
    IF @EndDate IS NULL SET @EndDate = CAST(GETDATE() AS DATE);

    EXEC BOA.RPT.usp_PrepareBranchKpiSnapshot
        @BeginDate = @BeginDate,
        @EndDate = @EndDate,
        @RegionId = @RegionId,
        @BranchId = @BranchId;

    IF OBJECT_ID('tempdb..#BranchKpi') IS NOT NULL DROP TABLE #BranchKpi;
    IF OBJECT_ID('tempdb..#ChannelMix') IS NOT NULL DROP TABLE #ChannelMix;

    CREATE TABLE #BranchKpi
    (
        BranchId                INT,
        TranDate                DATE,
        TellerTranCount         INT,
        DigitalAssistedCount    INT,
        ComplaintCount          INT,
        SlaBreachCount          INT,
        TotalExpenseTL          DECIMAL(19,2),
        FeeIncomeTL             DECIMAL(19,2),
        CashInTL                DECIMAL(19,2),
        CashOutTL               DECIMAL(19,2),
        ActiveCustomerCount     INT,
        WeightedScore           DECIMAL(19,6) NULL
    );

    INSERT INTO #BranchKpi
    SELECT
        br.BranchId,
        cal.CalendarDate,
        SUM(CASE WHEN tr.ChannelCode = 'TELLER' THEN 1 ELSE 0 END) AS TellerTranCount,
        SUM(CASE WHEN tr.ChannelCode IN ('MOBILE_ASSIST', 'INTERNET_ASSIST') THEN 1 ELSE 0 END) AS DigitalAssistedCount,
        SUM(CASE WHEN cmp.ComplaintId IS NOT NULL THEN 1 ELSE 0 END) AS ComplaintCount,
        SUM(CASE WHEN DATEDIFF(MINUTE, tr.CreatedTime, tr.CompletedTime) > sla.TargetMinute THEN 1 ELSE 0 END) AS SlaBreachCount,
        SUM(ISNULL(exp.ExpenseAmountTL, 0)) AS TotalExpenseTL,
        SUM(ISNULL(fee.FeeAmountTL, 0)) AS FeeIncomeTL,
        SUM(CASE WHEN tr.DebitCreditFlag = 'C' THEN tr.AmountTL ELSE 0 END) AS CashInTL,
        SUM(CASE WHEN tr.DebitCreditFlag = 'D' THEN tr.AmountTL ELSE 0 END) AS CashOutTL,
        COUNT(DISTINCT tr.CustomerId) AS ActiveCustomerCount,
        NULL AS WeightedScore
    FROM BOA.COR.Branch br WITH (NOLOCK)
        INNER JOIN BOA.COR.Calendar cal WITH (NOLOCK) ON cal.CalendarDate BETWEEN @BeginDate AND @EndDate
        LEFT JOIN BOA.OPR.BranchTransaction tr WITH (NOLOCK) ON tr.BranchId = br.BranchId
            AND tr.TranDate = cal.CalendarDate
            AND tr.TranStatus = 'A'
        LEFT JOIN BOA.OPR.OperationSlaDefinition sla WITH (NOLOCK) ON sla.OperationCode = tr.OperationCode
        LEFT JOIN BOA.CRM.CustomerComplaint cmp WITH (NOLOCK) ON cmp.BranchId = br.BranchId
            AND cmp.ComplaintDate = cal.CalendarDate
            AND cmp.RelatedTranId = tr.TranId
        LEFT JOIN BOA.ACC.BranchExpense exp WITH (NOLOCK) ON exp.BranchId = br.BranchId
            AND exp.ExpenseDate = cal.CalendarDate
        LEFT JOIN BOA.FEE.BranchFeeDaily fee WITH (NOLOCK) ON fee.BranchId = br.BranchId
            AND fee.FeeDate = cal.CalendarDate
    WHERE br.IsActive = 1
        AND br.BranchId = COALESCE(@BranchId, br.BranchId)
        AND br.RegionId = COALESCE(@RegionId, br.RegionId)
    GROUP BY br.BranchId, cal.CalendarDate;

    UPDATE bk
    SET WeightedScore =
        (
            ISNULL(bk.FeeIncomeTL, 0) * 0.35
            + ISNULL(bk.ActiveCustomerCount, 0) * 12.00
            + ISNULL(bk.DigitalAssistedCount, 0) * 3.50
            - ISNULL(bk.ComplaintCount, 0) * 150.00
            - ISNULL(bk.SlaBreachCount, 0) * 25.00
            - ISNULL(bk.TotalExpenseTL, 0) * 0.10
        )
    FROM #BranchKpi bk;

    SELECT
        tr.BranchId,
        SUM(CASE WHEN tr.ChannelCode = 'TELLER' THEN 1 ELSE 0 END) AS TellerCount,
        SUM(CASE WHEN tr.ChannelCode = 'ATM' THEN 1 ELSE 0 END) AS AtmCount,
        SUM(CASE WHEN tr.ChannelCode = 'MOBILE' THEN 1 ELSE 0 END) AS MobileCount,
        SUM(CASE WHEN tr.ChannelCode = 'INTERNET' THEN 1 ELSE 0 END) AS InternetCount,
        COUNT_BIG(*) AS TotalCount,
        SUM(CASE WHEN tr.IsManualCorrection = 1 THEN 1 ELSE 0 END) AS ManualCorrectionCount
    INTO #ChannelMix
    FROM BOA.OPR.BranchTransaction tr WITH (NOLOCK)
    WHERE tr.TranDate BETWEEN @BeginDate AND @EndDate
        AND tr.TranStatus = 'A'
    GROUP BY tr.BranchId;

    SELECT
        reg.RegionId,
        reg.RegionName,
        br.BranchId,
        br.Name AS BranchName,
        mgr.EmployeeNumber AS ManagerEmployeeNumber,
        mgr.FullName AS ManagerName,
        SUM(bk.TellerTranCount) AS TellerTranCount,
        SUM(bk.DigitalAssistedCount) AS DigitalAssistedCount,
        SUM(bk.ComplaintCount) AS ComplaintCount,
        SUM(bk.SlaBreachCount) AS SlaBreachCount,
        SUM(bk.TotalExpenseTL) AS TotalExpenseTL,
        SUM(bk.FeeIncomeTL) AS FeeIncomeTL,
        SUM(bk.CashInTL) AS CashInTL,
        SUM(bk.CashOutTL) AS CashOutTL,
        SUM(bk.CashInTL - bk.CashOutTL) AS NetCashFlowTL,
        AVG(CAST(bk.ActiveCustomerCount AS DECIMAL(19,6))) AS AvgActiveCustomerCount,
        AVG(bk.WeightedScore) AS AvgWeightedScore,
        cm.TellerCount,
        cm.AtmCount,
        cm.MobileCount,
        cm.InternetCount,
        cm.ManualCorrectionCount,
        CAST((cm.MobileCount + cm.InternetCount) / NULLIF(CAST(cm.TotalCount AS DECIMAL(19,6)), 0) AS DECIMAL(19,6)) AS DigitalChannelRatio,
        CAST(cm.ManualCorrectionCount / NULLIF(CAST(cm.TotalCount AS DECIMAL(19,6)), 0) AS DECIMAL(19,6)) AS ManualCorrectionRatio,
        target.MonthlyFeeTargetTL,
        target.MonthlyExpenseLimitTL,
        CAST(SUM(bk.FeeIncomeTL) / NULLIF(target.MonthlyFeeTargetTL, 0) AS DECIMAL(19,6)) AS FeeTargetRealizationRatio,
        CAST(SUM(bk.TotalExpenseTL) / NULLIF(target.MonthlyExpenseLimitTL, 0) AS DECIMAL(19,6)) AS ExpenseLimitUsageRatio,
        perf.PerformanceBand,
        perf.OperationalRiskBand,
        @BeginDate AS ReportBeginDate,
        @EndDate AS ReportEndDate
    FROM #BranchKpi bk
        INNER JOIN BOA.COR.Branch br WITH (NOLOCK) ON br.BranchId = bk.BranchId
        INNER JOIN BOA.COR.Region reg WITH (NOLOCK) ON reg.RegionId = br.RegionId
        LEFT JOIN BOA.HR.Employee mgr WITH (NOLOCK) ON mgr.EmployeeId = br.ManagerEmployeeId
        LEFT JOIN #ChannelMix cm ON cm.BranchId = bk.BranchId
        OUTER APPLY
        (
            SELECT TOP (1)
                bt.MonthlyFeeTargetTL,
                bt.MonthlyExpenseLimitTL,
                bt.TargetMonth
            FROM BOA.RPT.BranchTarget bt WITH (NOLOCK)
            WHERE bt.BranchId = bk.BranchId
                AND bt.TargetMonth = DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1)
            ORDER BY bt.VersionNumber DESC
        ) target
        OUTER APPLY
        (
            SELECT
                CASE
                    WHEN SUM(bk2.WeightedScore) > 100000 THEN 'High'
                    WHEN SUM(bk2.WeightedScore) > 25000 THEN 'Medium'
                    ELSE 'Low'
                END AS PerformanceBand,
                CASE
                    WHEN SUM(bk2.ComplaintCount + bk2.SlaBreachCount) > 100 THEN 'Critical'
                    WHEN SUM(bk2.ComplaintCount + bk2.SlaBreachCount) > 25 THEN 'Watch'
                    ELSE 'Normal'
                END AS OperationalRiskBand
            FROM #BranchKpi bk2
            WHERE bk2.BranchId = bk.BranchId
        ) perf
    GROUP BY
        reg.RegionId,
        reg.RegionName,
        br.BranchId,
        br.Name,
        mgr.EmployeeNumber,
        mgr.FullName,
        cm.TellerCount,
        cm.AtmCount,
        cm.MobileCount,
        cm.InternetCount,
        cm.TotalCount,
        cm.ManualCorrectionCount,
        target.MonthlyFeeTargetTL,
        target.MonthlyExpenseLimitTL,
        perf.PerformanceBand,
        perf.OperationalRiskBand
    ORDER BY AvgWeightedScore DESC, br.BranchId;
END
