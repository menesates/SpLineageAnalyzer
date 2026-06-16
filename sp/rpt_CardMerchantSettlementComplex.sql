USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_CardMerchantSettlementComplex]
(
    @BeginDate      DATE = NULL,
    @EndDate        DATE = NULL,
    @MerchantId     BIGINT = NULL,
    @CurrencyCode   CHAR(3) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @BeginDate IS NULL SET @BeginDate = DATEADD(DAY, -1, CAST(GETDATE() AS DATE));
    IF @EndDate IS NULL SET @EndDate = CAST(GETDATE() AS DATE);

    IF OBJECT_ID('tempdb..#MerchantTxn') IS NOT NULL DROP TABLE #MerchantTxn;
    IF OBJECT_ID('tempdb..#SettlementBase') IS NOT NULL DROP TABLE #SettlementBase;
    IF OBJECT_ID('tempdb..#ChargebackAgg') IS NOT NULL DROP TABLE #ChargebackAgg;

    CREATE TABLE #MerchantTxn
    (
        MerchantId          BIGINT,
        TerminalId          VARCHAR(30),
        BranchId            INT,
        CurrencyCode        CHAR(3),
        SaleCount           BIGINT,
        RefundCount         BIGINT,
        SaleAmount          DECIMAL(19,2),
        RefundAmount        DECIMAL(19,2),
        SaleAmountTL        DECIMAL(19,2),
        GrossCommissionTL   DECIMAL(19,2),
        InterchangeCostTL   DECIMAL(19,2),
        NetCommissionTL     DECIMAL(19,2)
    );

    INSERT INTO #MerchantTxn
    SELECT
        mt.MerchantId,
        mt.TerminalId,
        m.BranchId,
        mt.CurrencyCode,
        SUM(CASE WHEN mt.TranType = 'SALE' THEN 1 ELSE 0 END) AS SaleCount,
        SUM(CASE WHEN mt.TranType = 'REFUND' THEN 1 ELSE 0 END) AS RefundCount,
        SUM(CASE WHEN mt.TranType = 'SALE' THEN mt.TranAmount ELSE 0 END) AS SaleAmount,
        SUM(CASE WHEN mt.TranType = 'REFUND' THEN mt.TranAmount ELSE 0 END) AS RefundAmount,
        SUM((CASE WHEN mt.TranType = 'SALE' THEN mt.TranAmount ELSE -mt.TranAmount END)
            * CASE WHEN mt.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END) AS SaleAmountTL,
        SUM(mt.TranAmount * ISNULL(rate.MdrRate, 0) * CASE WHEN mt.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END) AS GrossCommissionTL,
        SUM(mt.TranAmount * ISNULL(rate.InterchangeRate, 0) * CASE WHEN mt.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END) AS InterchangeCostTL,
        SUM(mt.TranAmount * (ISNULL(rate.MdrRate, 0) - ISNULL(rate.InterchangeRate, 0))
            * CASE WHEN mt.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END) AS NetCommissionTL
    FROM BOA.CRD.MerchantTransaction mt WITH (NOLOCK)
        INNER JOIN BOA.CRD.Merchant m WITH (NOLOCK) ON m.MerchantId = mt.MerchantId
        OUTER APPLY
        (
            SELECT TOP (1)
                pr.MdrRate,
                pr.InterchangeRate
            FROM BOA.CRD.MerchantPricing pr WITH (NOLOCK)
            WHERE pr.MerchantId = mt.MerchantId
                AND pr.ProductCode = mt.CardProductCode
                AND pr.ValidFrom <= mt.TranDate
            ORDER BY pr.ValidFrom DESC
        ) rate
        OUTER APPLY
        (
            SELECT TOP (1)
                fr.BidRate
            FROM BOA.TRE.FxRate fr WITH (NOLOCK)
            WHERE fr.CurrencyCode = mt.CurrencyCode
                AND fr.RateDate <= mt.TranDate
            ORDER BY fr.RateDate DESC
        ) fx
    WHERE mt.TranDate BETWEEN @BeginDate AND @EndDate
        AND mt.TranStatus = 'A'
        AND mt.MerchantId = COALESCE(@MerchantId, mt.MerchantId)
        AND mt.CurrencyCode = COALESCE(@CurrencyCode, mt.CurrencyCode)
    GROUP BY mt.MerchantId, mt.TerminalId, m.BranchId, mt.CurrencyCode;

    SELECT
        cb.MerchantId,
        cb.TerminalId,
        COUNT_BIG(*) AS ChargebackCount,
        SUM(cb.ChargebackAmount) AS ChargebackAmount,
        SUM(cb.ChargebackAmount * CASE WHEN cb.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END) AS ChargebackAmountTL,
        SUM(CASE WHEN cb.ReasonCode IN ('FRAUD', 'NOAUTH') THEN cb.ChargebackAmount ELSE 0 END) AS FraudChargebackAmount
    INTO #ChargebackAgg
    FROM BOA.CRD.CardChargeback cb WITH (NOLOCK)
        OUTER APPLY
        (
            SELECT TOP (1)
                fr.BidRate
            FROM BOA.TRE.FxRate fr WITH (NOLOCK)
            WHERE fr.CurrencyCode = cb.CurrencyCode
                AND fr.RateDate <= cb.ChargebackDate
            ORDER BY fr.RateDate DESC
        ) fx
    WHERE cb.ChargebackDate BETWEEN @BeginDate AND @EndDate
        AND cb.StatusCode IN ('OPEN', 'WON', 'LOST')
    GROUP BY cb.MerchantId, cb.TerminalId
    HAVING SUM(cb.ChargebackAmount) > 0;

    SELECT
        mt.MerchantId,
        mt.TerminalId,
        mt.BranchId,
        mt.CurrencyCode,
        mt.SaleCount,
        mt.RefundCount,
        mt.SaleAmount,
        mt.RefundAmount,
        mt.SaleAmountTL,
        mt.GrossCommissionTL,
        mt.InterchangeCostTL,
        mt.NetCommissionTL,
        ISNULL(cb.ChargebackCount, 0) AS ChargebackCount,
        ISNULL(cb.ChargebackAmountTL, 0) AS ChargebackAmountTL,
        CAST(0 AS DECIMAL(19,2)) AS ReserveAmountTL,
        CAST(0 AS DECIMAL(19,2)) AS NetPayableAmountTL
    INTO #SettlementBase
    FROM #MerchantTxn mt
        LEFT JOIN #ChargebackAgg cb ON cb.MerchantId = mt.MerchantId
            AND cb.TerminalId = mt.TerminalId;

    UPDATE sb
    SET
        ReserveAmountTL =
            CASE
                WHEN sb.ChargebackAmountTL / NULLIF(sb.SaleAmountTL, 0) > 0.050000 THEN sb.SaleAmountTL * 0.100000
                WHEN sb.ChargebackAmountTL / NULLIF(sb.SaleAmountTL, 0) > 0.020000 THEN sb.SaleAmountTL * 0.050000
                ELSE sb.SaleAmountTL * 0.010000
            END,
        NetPayableAmountTL =
            sb.SaleAmountTL - sb.GrossCommissionTL - sb.ChargebackAmountTL
    FROM #SettlementBase sb;

    SELECT
        m.MerchantNumber,
        m.MerchantName,
        br.BranchId,
        br.Name AS BranchName,
        sb.TerminalId,
        sb.CurrencyCode,
        sb.SaleCount,
        sb.RefundCount,
        sb.SaleAmount,
        sb.RefundAmount,
        sb.SaleAmountTL AS GrossVolumeTL,
        sb.GrossCommissionTL,
        sb.InterchangeCostTL,
        sb.NetCommissionTL,
        sb.ChargebackCount,
        sb.ChargebackAmountTL,
        CAST(sb.ChargebackAmountTL / NULLIF(sb.SaleAmountTL, 0) AS DECIMAL(19,6)) AS ChargebackRatio,
        sb.ReserveAmountTL,
        sb.NetPayableAmountTL,
        CASE
            WHEN sb.NetPayableAmountTL < 0 THEN 1
            ELSE 0
        END AS NegativeSettlementFlag,
        risk.RiskBand,
        @BeginDate AS ReportBeginDate,
        @EndDate AS ReportEndDate
    FROM #SettlementBase sb
        INNER JOIN BOA.CRD.Merchant m WITH (NOLOCK) ON m.MerchantId = sb.MerchantId
        INNER JOIN BOA.COR.Branch br WITH (NOLOCK) ON br.BranchId = sb.BranchId
        OUTER APPLY
        (
            SELECT
                CASE
                    WHEN sb.ChargebackAmountTL / NULLIF(sb.SaleAmountTL, 0) > 0.050000 THEN 'HIGH'
                    WHEN sb.ChargebackAmountTL / NULLIF(sb.SaleAmountTL, 0) > 0.020000 THEN 'MEDIUM'
                    ELSE 'LOW'
                END AS RiskBand
        ) risk
    ORDER BY sb.NetPayableAmountTL DESC, m.MerchantNumber;
END
