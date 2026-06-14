USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_TreasuryFxLiquidityComplex]
(
    @ReportDate     DATE        = NULL,
    @CurrencyCode   CHAR(3)     = NULL,
    @DeskCode       VARCHAR(20) = NULL,
    @ScenarioCode   VARCHAR(20) = 'BASE'
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @ReportDate IS NULL
    BEGIN
        SET @ReportDate = CAST(GETDATE() AS DATE);
    END

    ;WITH RawCashFlow AS
    (
        SELECT
            'SECURITY' AS SourceType,
            sec.SecurityId AS InstrumentId,
            sec.DeskCode,
            sec.CurrencyCode,
            cf.CashFlowDate,
            cf.PrincipalAmount + cf.CouponAmount AS CashFlowAmount,
            CASE WHEN cf.CashFlowType = 'OUT' THEN -1 ELSE 1 END AS DirectionSign,
            sec.BookCode,
            sec.PortfolioCode
        FROM BOA.TRE.Security sec WITH (NOLOCK)
            INNER JOIN BOA.TRE.SecurityCashFlow cf WITH (NOLOCK) ON cf.SecurityId = sec.SecurityId
        WHERE cf.CashFlowDate >= @ReportDate
            AND sec.StatusCode = 'A'
        UNION ALL
        SELECT
            'MM' AS SourceType,
            mm.MoneyMarketDealId AS InstrumentId,
            mm.DeskCode,
            mm.CurrencyCode,
            mm.MaturityDate AS CashFlowDate,
            mm.PrincipalAmount + ISNULL(mm.AccruedInterestAmount, 0) AS CashFlowAmount,
            CASE WHEN mm.DealSide = 'BORROW' THEN -1 ELSE 1 END AS DirectionSign,
            mm.BookCode,
            mm.PortfolioCode
        FROM BOA.TRE.MoneyMarketDeal mm WITH (NOLOCK)
        WHERE mm.TradeDate <= @ReportDate
            AND mm.MaturityDate >= @ReportDate
            AND mm.StatusCode = 'A'
        UNION ALL
        SELECT
            'FXSWAP' AS SourceType,
            sw.FxSwapDealId AS InstrumentId,
            sw.DeskCode,
            sw.NearCurrencyCode AS CurrencyCode,
            sw.NearValueDate AS CashFlowDate,
            sw.NearAmount AS CashFlowAmount,
            CASE WHEN sw.BuySell = 'BUY' THEN 1 ELSE -1 END AS DirectionSign,
            sw.BookCode,
            sw.PortfolioCode
        FROM BOA.TRE.FxSwapDeal sw WITH (NOLOCK)
        WHERE sw.NearValueDate >= @ReportDate
            AND sw.StatusCode = 'A'
        UNION ALL
        SELECT
            'FXSWAP' AS SourceType,
            sw.FxSwapDealId AS InstrumentId,
            sw.DeskCode,
            sw.FarCurrencyCode AS CurrencyCode,
            sw.FarValueDate AS CashFlowDate,
            sw.FarAmount AS CashFlowAmount,
            CASE WHEN sw.BuySell = 'BUY' THEN -1 ELSE 1 END AS DirectionSign,
            sw.BookCode,
            sw.PortfolioCode
        FROM BOA.TRE.FxSwapDeal sw WITH (NOLOCK)
        WHERE sw.FarValueDate >= @ReportDate
            AND sw.StatusCode = 'A'
    ),
    BucketedFlow AS
    (
        SELECT
            rcf.SourceType,
            rcf.InstrumentId,
            rcf.DeskCode,
            rcf.CurrencyCode,
            rcf.CashFlowDate,
            DATEDIFF(DAY, @ReportDate, rcf.CashFlowDate) AS DaysToMaturity,
            CASE
                WHEN DATEDIFF(DAY, @ReportDate, rcf.CashFlowDate) = 0 THEN 'ON'
                WHEN DATEDIFF(DAY, @ReportDate, rcf.CashFlowDate) BETWEEN 1 AND 7 THEN '1W'
                WHEN DATEDIFF(DAY, @ReportDate, rcf.CashFlowDate) BETWEEN 8 AND 30 THEN '1M'
                WHEN DATEDIFF(DAY, @ReportDate, rcf.CashFlowDate) BETWEEN 31 AND 90 THEN '3M'
                WHEN DATEDIFF(DAY, @ReportDate, rcf.CashFlowDate) BETWEEN 91 AND 180 THEN '6M'
                ELSE '6M+'
            END AS MaturityBucket,
            rcf.CashFlowAmount * rcf.DirectionSign AS SignedCashFlow,
            rcf.BookCode,
            rcf.PortfolioCode
        FROM RawCashFlow rcf
        WHERE rcf.CurrencyCode = COALESCE(@CurrencyCode, rcf.CurrencyCode)
            AND rcf.DeskCode = COALESCE(@DeskCode, rcf.DeskCode)
    ),
    PositionBase AS
    (
        SELECT
            pos.DeskCode,
            pos.CurrencyCode,
            SUM(pos.CurrentPositionAmount) AS CurrentPositionAmount,
            SUM(pos.CurrentPositionAmount * fx.BidRate) AS CurrentPositionTL,
            SUM(CASE WHEN pos.PositionType = 'TRADING' THEN pos.CurrentPositionAmount ELSE 0 END) AS TradingPositionAmount,
            SUM(CASE WHEN pos.PositionType = 'BANKING' THEN pos.CurrentPositionAmount ELSE 0 END) AS BankingPositionAmount
        FROM BOA.TRE.CurrencyPosition pos WITH (NOLOCK)
            OUTER APPLY
            (
                SELECT TOP (1)
                    fr.CurrencyCode,
                    fr.BidRate,
                    fr.AskRate
                FROM BOA.TRE.FxRate fr WITH (NOLOCK)
                WHERE fr.CurrencyCode = pos.CurrencyCode
                    AND fr.RateDate <= @ReportDate
                ORDER BY fr.RateDate DESC
            ) fx
        WHERE pos.PositionDate = @ReportDate
            AND pos.CurrencyCode = COALESCE(@CurrencyCode, pos.CurrencyCode)
            AND pos.DeskCode = COALESCE(@DeskCode, pos.DeskCode)
        GROUP BY pos.DeskCode, pos.CurrencyCode
    ),
    AggregatedFlow AS
    (
        SELECT
            bf.DeskCode,
            bf.CurrencyCode,
            SUM(CASE WHEN bf.MaturityBucket = 'ON' THEN bf.SignedCashFlow ELSE 0 END) AS BucketON,
            SUM(CASE WHEN bf.MaturityBucket = '1W' THEN bf.SignedCashFlow ELSE 0 END) AS Bucket1W,
            SUM(CASE WHEN bf.MaturityBucket = '1M' THEN bf.SignedCashFlow ELSE 0 END) AS Bucket1M,
            SUM(CASE WHEN bf.MaturityBucket = '3M' THEN bf.SignedCashFlow ELSE 0 END) AS Bucket3M,
            SUM(CASE WHEN bf.MaturityBucket = '6M' THEN bf.SignedCashFlow ELSE 0 END) AS Bucket6M,
            SUM(CASE WHEN bf.MaturityBucket = '6M+' THEN bf.SignedCashFlow ELSE 0 END) AS Bucket6MPlus,
            SUM(bf.SignedCashFlow) AS TotalForwardCashFlow,
            COUNT_BIG(*) AS CashFlowCount
        FROM BucketedFlow bf
        GROUP BY bf.DeskCode, bf.CurrencyCode
    )
    SELECT
        pb.DeskCode,
        desk.DeskName,
        pb.CurrencyCode,
        ISNULL(pb.CurrentPositionAmount, 0) AS CurrentPositionAmount,
        ISNULL(pb.CurrentPositionTL, 0) AS CurrentPositionTL,
        ISNULL(pb.TradingPositionAmount, 0) AS TradingPositionAmount,
        ISNULL(pb.BankingPositionAmount, 0) AS BankingPositionAmount,
        ISNULL(af.BucketON, 0) AS BucketON,
        ISNULL(af.Bucket1W, 0) AS Bucket1W,
        ISNULL(af.Bucket1M, 0) AS Bucket1M,
        ISNULL(af.Bucket3M, 0) AS Bucket3M,
        ISNULL(af.Bucket6M, 0) AS Bucket6M,
        ISNULL(af.Bucket6MPlus, 0) AS Bucket6MPlus,
        ISNULL(af.TotalForwardCashFlow, 0) AS TotalForwardCashFlow,
        stress.StressedOutflowAmount,
        stress.StressedInflowAmount,
        ISNULL(pb.CurrentPositionAmount, 0) + ISNULL(af.TotalForwardCashFlow, 0) AS ProjectedClosingPosition,
        ISNULL(pb.CurrentPositionAmount, 0)
            + ISNULL(af.BucketON, 0)
            + ISNULL(af.Bucket1W, 0) AS OneWeekLiquidityPosition,
        CAST((ISNULL(pb.CurrentPositionAmount, 0) + ISNULL(af.TotalForwardCashFlow, 0))
            / NULLIF(ABS(ISNULL(stress.StressedOutflowAmount, 0)), 0) AS DECIMAL(19,6)) AS LiquiditySurvivalRatio,
        limitDef.PositionLimitAmount,
        CASE
            WHEN ABS(ISNULL(pb.CurrentPositionAmount, 0) + ISNULL(af.TotalForwardCashFlow, 0)) > ISNULL(limitDef.PositionLimitAmount, 0) THEN 1
            ELSE 0
        END AS LimitBreachFlag,
        varCalc.EstimatedVarTL,
        @ScenarioCode AS ScenarioCode,
        @ReportDate AS ReportDate
    FROM PositionBase pb
        LEFT JOIN AggregatedFlow af ON af.DeskCode = pb.DeskCode AND af.CurrencyCode = pb.CurrencyCode
        LEFT JOIN BOA.TRE.TreasuryDesk desk WITH (NOLOCK) ON desk.DeskCode = pb.DeskCode
        OUTER APPLY
        (
            SELECT
                SUM(CASE WHEN sf.FlowDirection = 'OUT' THEN sf.Amount * sf.StressFactor ELSE 0 END) AS StressedOutflowAmount,
                SUM(CASE WHEN sf.FlowDirection = 'IN' THEN sf.Amount * sf.StressFactor ELSE 0 END) AS StressedInflowAmount
            FROM BOA.TRE.LiquidityStressFlow sf WITH (NOLOCK)
            WHERE sf.ScenarioCode = @ScenarioCode
                AND sf.CurrencyCode = pb.CurrencyCode
                AND sf.DeskCode = pb.DeskCode
                AND sf.ReportDate = @ReportDate
        ) stress
        CROSS APPLY
        (
            SELECT TOP (1)
                lim.PositionLimitAmount,
                lim.WarningLimitAmount
            FROM BOA.TRE.PositionLimit lim WITH (NOLOCK)
            WHERE lim.DeskCode = pb.DeskCode
                AND lim.CurrencyCode = pb.CurrencyCode
                AND lim.ValidFrom <= @ReportDate
                AND ISNULL(lim.ValidTo, @ReportDate) >= @ReportDate
            ORDER BY lim.ValidFrom DESC
        ) limitDef
        OUTER APPLY
        (
            SELECT
                SQRT(SUM(hist.ReturnRate * hist.ReturnRate) / NULLIF(COUNT_BIG(*), 0))
                    * ABS(ISNULL(pb.CurrentPositionTL, 0)) * 2.33 AS EstimatedVarTL
            FROM BOA.TRE.FxHistoricalReturn hist WITH (NOLOCK)
            WHERE hist.CurrencyCode = pb.CurrencyCode
                AND hist.ReturnDate BETWEEN DATEADD(DAY, -250, @ReportDate) AND @ReportDate
        ) varCalc
    WHERE
        ABS(ISNULL(pb.CurrentPositionAmount, 0))
        + ABS(ISNULL(af.TotalForwardCashFlow, 0)) > 0
    ORDER BY pb.DeskCode, pb.CurrencyCode;
END
