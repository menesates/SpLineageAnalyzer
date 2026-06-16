USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_DigitalChannelFraudKpiComplex]
(
    @BeginDate          DATE = NULL,
    @EndDate            DATE = NULL,
    @ChannelCode        VARCHAR(20) = NULL,
    @IncludeDeviceView  BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @BeginDate IS NULL SET @BeginDate = DATEADD(DAY, -30, CAST(GETDATE() AS DATE));
        IF @EndDate IS NULL SET @EndDate = CAST(GETDATE() AS DATE);

        IF OBJECT_ID('tempdb..#DigitalBase') IS NOT NULL DROP TABLE #DigitalBase;
        IF OBJECT_ID('tempdb..#FraudAgg') IS NOT NULL DROP TABLE #FraudAgg;

        CREATE TABLE #DigitalBase
        (
            CustomerId              BIGINT,
            SegmentCode             VARCHAR(20),
            ChannelCode             VARCHAR(20),
            DeviceId                VARCHAR(80),
            TranCount               BIGINT,
            ApprovedTranCount       BIGINT,
            BlockedTranCount        BIGINT,
            TotalAmountTL           DECIMAL(19,2),
            PreventedAmountTL       DECIMAL(19,2),
            RuleHitCount            BIGINT,
            FalsePositiveCount      BIGINT
        );

        INSERT INTO #DigitalBase
        SELECT
            dt.CustomerId,
            seg.SegmentCode,
            dt.ChannelCode,
            dt.DeviceId,
            COUNT_BIG(*) AS TranCount,
            SUM(CASE WHEN dt.DecisionCode = 'APPROVE' THEN 1 ELSE 0 END) AS ApprovedTranCount,
            SUM(CASE WHEN dt.DecisionCode = 'BLOCK' THEN 1 ELSE 0 END) AS BlockedTranCount,
            SUM(dt.AmountTL) AS TotalAmountTL,
            SUM(CASE WHEN dt.DecisionCode = 'BLOCK' THEN dt.AmountTL ELSE 0 END) AS PreventedAmountTL,
            SUM(CASE WHEN rh.RuleHitId IS NOT NULL THEN 1 ELSE 0 END) AS RuleHitCount,
            SUM(CASE WHEN rh.RuleHitId IS NOT NULL AND ISNULL(fc.IsFraudConfirmed, 0) = 0 THEN 1 ELSE 0 END) AS FalsePositiveCount
        FROM BOA.DIG.DigitalTransaction dt WITH (NOLOCK)
            INNER JOIN BOA.CUS.CustomerSegment seg WITH (NOLOCK) ON seg.CustomerId = dt.CustomerId
                AND seg.ValidFrom <= dt.TranDate
                AND ISNULL(seg.ValidTo, dt.TranDate) >= dt.TranDate
            LEFT JOIN BOA.FRD.FraudRuleHit rh WITH (NOLOCK) ON rh.TranId = dt.TranId
            LEFT JOIN BOA.FRD.FraudCase fc WITH (NOLOCK) ON fc.TranId = dt.TranId
        WHERE dt.TranDate BETWEEN @BeginDate AND @EndDate
            AND dt.ChannelCode = COALESCE(@ChannelCode, dt.ChannelCode)
        GROUP BY dt.CustomerId, seg.SegmentCode, dt.ChannelCode, dt.DeviceId;

        SELECT
            fc.CustomerId,
            fc.ChannelCode,
            fc.DeviceId,
            fr.RuleCode,
            COUNT_BIG(*) AS FraudCaseCount,
            SUM(fc.LossAmountTL) AS FraudLossTL,
            SUM(CASE WHEN fc.RecoveryStatus = 'RECOVERED' THEN fc.RecoveredAmountTL ELSE 0 END) AS RecoveredAmountTL
        INTO #FraudAgg
        FROM BOA.FRD.FraudCase fc WITH (NOLOCK)
            INNER JOIN BOA.FRD.FraudRule fr WITH (NOLOCK) ON fr.RuleId = fc.PrimaryRuleId
        WHERE fc.CaseDate BETWEEN @BeginDate AND @EndDate
        GROUP BY fc.CustomerId, fc.ChannelCode, fc.DeviceId, fr.RuleCode;

        IF @IncludeDeviceView = 1
        BEGIN
            SELECT
                db.ChannelCode,
                db.SegmentCode,
                db.DeviceId AS ReportDimension,
                ISNULL(fa.RuleCode, 'NO_CASE') AS FraudRuleCode,
                SUM(db.TranCount) AS TransactionCount,
                SUM(db.ApprovedTranCount) AS ApprovedTransactionCount,
                SUM(db.BlockedTranCount) AS BlockedTransactionCount,
                SUM(db.TotalAmountTL) AS TotalAmountTL,
                SUM(db.PreventedAmountTL) AS PreventedAmountTL,
                SUM(ISNULL(fa.FraudCaseCount, 0)) AS FraudCaseCount,
                SUM(ISNULL(fa.FraudLossTL, 0)) AS FraudLossTL,
                SUM(ISNULL(fa.RecoveredAmountTL, 0)) AS RecoveredAmountTL,
                CAST(SUM(ISNULL(fa.FraudLossTL, 0)) / NULLIF(SUM(db.TotalAmountTL), 0) AS DECIMAL(19,6)) AS FraudLossRatio,
                CAST(SUM(db.FalsePositiveCount) / NULLIF(SUM(db.RuleHitCount), 0) AS DECIMAL(19,6)) AS FalsePositiveRatio,
                CASE
                    WHEN SUM(ISNULL(fa.FraudLossTL, 0)) > 100000 THEN 'CRITICAL'
                    WHEN SUM(ISNULL(fa.FraudLossTL, 0)) > 25000 THEN 'WATCH'
                    ELSE 'NORMAL'
                END AS FraudRiskBand,
                @BeginDate AS ReportBeginDate,
                @EndDate AS ReportEndDate
            FROM #DigitalBase db
                LEFT JOIN #FraudAgg fa ON fa.CustomerId = db.CustomerId
                    AND fa.ChannelCode = db.ChannelCode
                    AND fa.DeviceId = db.DeviceId
            GROUP BY db.ChannelCode, db.SegmentCode, db.DeviceId, ISNULL(fa.RuleCode, 'NO_CASE')
            ORDER BY FraudLossTL DESC, TransactionCount DESC;
        END
        ELSE
        BEGIN
            SELECT
                db.ChannelCode,
                db.SegmentCode,
                CAST('ALL_DEVICES' AS VARCHAR(80)) AS ReportDimension,
                ISNULL(fa.RuleCode, 'NO_CASE') AS FraudRuleCode,
                SUM(db.TranCount) AS TransactionCount,
                SUM(db.ApprovedTranCount) AS ApprovedTransactionCount,
                SUM(db.BlockedTranCount) AS BlockedTransactionCount,
                SUM(db.TotalAmountTL) AS TotalAmountTL,
                SUM(db.PreventedAmountTL) AS PreventedAmountTL,
                SUM(ISNULL(fa.FraudCaseCount, 0)) AS FraudCaseCount,
                SUM(ISNULL(fa.FraudLossTL, 0)) AS FraudLossTL,
                SUM(ISNULL(fa.RecoveredAmountTL, 0)) AS RecoveredAmountTL,
                CAST((SUM(ISNULL(fa.FraudLossTL, 0)) - SUM(ISNULL(fa.RecoveredAmountTL, 0)))
                    / NULLIF(SUM(db.TotalAmountTL), 0) AS DECIMAL(19,6)) AS FraudLossRatio,
                CAST(SUM(db.FalsePositiveCount) / NULLIF(SUM(db.RuleHitCount), 0) AS DECIMAL(19,6)) AS FalsePositiveRatio,
                CASE
                    WHEN SUM(db.BlockedTranCount) / NULLIF(CAST(SUM(db.TranCount) AS DECIMAL(19,6)), 0) > 0.150000 THEN 'STRICT'
                    WHEN SUM(ISNULL(fa.FraudLossTL, 0)) > 25000 THEN 'WATCH'
                    ELSE 'NORMAL'
                END AS FraudRiskBand,
                @BeginDate AS ReportBeginDate,
                @EndDate AS ReportEndDate
            FROM #DigitalBase db
                LEFT JOIN #FraudAgg fa ON fa.CustomerId = db.CustomerId
                    AND fa.ChannelCode = db.ChannelCode
            GROUP BY db.ChannelCode, db.SegmentCode, ISNULL(fa.RuleCode, 'NO_CASE')
            ORDER BY FraudLossTL DESC, TransactionCount DESC;
        END
    END TRY
    BEGIN CATCH
        SELECT
            CAST('ERROR' AS VARCHAR(20)) AS ChannelCode,
            CAST('ERROR' AS VARCHAR(20)) AS SegmentCode,
            CAST(ERROR_MESSAGE() AS VARCHAR(80)) AS ReportDimension,
            CAST('ERROR' AS VARCHAR(30)) AS FraudRuleCode,
            CAST(0 AS BIGINT) AS TransactionCount,
            CAST(0 AS BIGINT) AS ApprovedTransactionCount,
            CAST(0 AS BIGINT) AS BlockedTransactionCount,
            CAST(0 AS DECIMAL(19,2)) AS TotalAmountTL,
            CAST(0 AS DECIMAL(19,2)) AS PreventedAmountTL,
            CAST(0 AS BIGINT) AS FraudCaseCount,
            CAST(0 AS DECIMAL(19,2)) AS FraudLossTL,
            CAST(0 AS DECIMAL(19,2)) AS RecoveredAmountTL,
            CAST(0 AS DECIMAL(19,6)) AS FraudLossRatio,
            CAST(0 AS DECIMAL(19,6)) AS FalsePositiveRatio,
            CAST('ERROR' AS VARCHAR(20)) AS FraudRiskBand,
            @BeginDate AS ReportBeginDate,
            @EndDate AS ReportEndDate;
    END CATCH
END
