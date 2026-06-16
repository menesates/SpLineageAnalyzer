USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_RegulatoryBaselCapitalComplex]
(
    @ReportDate         DATE = NULL,
    @ConsolidationCode  VARCHAR(20) = 'SOLO',
    @MinimumCarRatio    DECIMAL(19,6) = 0.120000
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @ReportDate IS NULL
    BEGIN
        SET @ReportDate = CAST(GETDATE() AS DATE);
    END

    IF OBJECT_ID('tempdb..#CapitalComponent') IS NOT NULL DROP TABLE #CapitalComponent;
    IF OBJECT_ID('tempdb..#RiskWeightedAsset') IS NOT NULL DROP TABLE #RiskWeightedAsset;
    IF OBJECT_ID('tempdb..#TotalRiskWeightedAsset') IS NOT NULL DROP TABLE #TotalRiskWeightedAsset;

    CREATE TABLE #CapitalComponent
    (
        CapitalBucket       VARCHAR(30),
        ComponentCode       VARCHAR(30),
        ComponentName       VARCHAR(100),
        ComponentAmountTL   DECIMAL(19,2),
        DeductionAmountTL   DECIMAL(19,2),
        EligibleAmountTL    DECIMAL(19,2)
    );

    INSERT INTO #CapitalComponent
    SELECT
        map.CapitalBucket,
        gl.ComponentCode,
        map.ComponentName,
        SUM(gl.BalanceTL) AS ComponentAmountTL,
        SUM(CASE WHEN map.IsDeduction = 1 THEN ABS(gl.BalanceTL) ELSE 0 END) AS DeductionAmountTL,
        SUM(CASE WHEN map.IsDeduction = 1 THEN -ABS(gl.BalanceTL) ELSE gl.BalanceTL * map.EligibilityRatio END) AS EligibleAmountTL
    FROM BOA.REG.CapitalLedgerBalance gl WITH (NOLOCK)
        INNER JOIN BOA.REG.CapitalComponentMap map WITH (NOLOCK) ON map.ComponentCode = gl.ComponentCode
    WHERE gl.ReportDate = @ReportDate
        AND gl.ConsolidationCode = @ConsolidationCode
        AND map.ValidFrom <= @ReportDate
        AND ISNULL(map.ValidTo, @ReportDate) >= @ReportDate
    GROUP BY map.CapitalBucket, gl.ComponentCode, map.ComponentName;

    ;WITH ExposureUnion AS
    (
        SELECT
            'CREDIT' AS RiskType,
            la.PortfolioCode,
            la.CustomerId,
            la.ProductCode,
            la.CurrencyCode,
            la.PrincipalBalance + ISNULL(ac.AccruedInterestAmount, 0) AS ExposureAmount,
            la.StageCode,
            la.RatingGrade,
            la.CollateralGroupCode
        FROM BOA.LNS.LoanAccount la WITH (NOLOCK)
            LEFT JOIN BOA.LNS.LoanAccrualDaily ac WITH (NOLOCK) ON ac.LoanAccountId = la.LoanAccountId
                AND ac.AccrualDate = @ReportDate
        WHERE la.OpenDate <= @ReportDate
            AND ISNULL(la.CloseDate, @ReportDate) >= @ReportDate
        UNION ALL
        SELECT
            'COUNTERPARTY' AS RiskType,
            der.PortfolioCode,
            der.CounterpartyId AS CustomerId,
            der.ProductCode,
            der.CurrencyCode,
            ABS(der.PositiveReplacementCost) + der.AddOnAmount AS ExposureAmount,
            der.StageCode,
            der.RatingGrade,
            der.CollateralGroupCode
        FROM BOA.TRE.DerivativeExposure der WITH (NOLOCK)
        WHERE der.ReportDate = @ReportDate
            AND der.StatusCode = 'A'
        UNION ALL
        SELECT
            'MARKET' AS RiskType,
            pos.PortfolioCode,
            pos.IssuerCustomerId AS CustomerId,
            pos.InstrumentType AS ProductCode,
            pos.CurrencyCode,
            ABS(pos.MarketValue) AS ExposureAmount,
            1 AS StageCode,
            pos.RatingGrade,
            pos.CollateralGroupCode
        FROM BOA.TRE.TradingBookPosition pos WITH (NOLOCK)
        WHERE pos.PositionDate = @ReportDate
            AND pos.BookStatus = 'A'
    ),
    ExposureTL AS
    (
        SELECT
            eu.RiskType,
            eu.PortfolioCode,
            pf.PortfolioName,
            eu.CustomerId,
            eu.ProductCode,
            eu.CurrencyCode,
            CASE WHEN eu.CurrencyCode = 'TRY' THEN eu.ExposureAmount ELSE eu.ExposureAmount * fx.BidRate END AS ExposureAmountTL,
            eu.StageCode,
            eu.RatingGrade,
            eu.CollateralGroupCode
        FROM ExposureUnion eu
            INNER JOIN BOA.REG.RegulatoryPortfolio pf WITH (NOLOCK) ON pf.PortfolioCode = eu.PortfolioCode
            OUTER APPLY
            (
                SELECT TOP (1)
                    fr.BidRate
                FROM BOA.TRE.FxRate fr WITH (NOLOCK)
                WHERE fr.CurrencyCode = eu.CurrencyCode
                    AND fr.RateDate <= @ReportDate
                ORDER BY fr.RateDate DESC
            ) fx
    ),
    WeightedExposure AS
    (
        SELECT
            et.RiskType,
            et.PortfolioCode,
            et.PortfolioName,
            et.ProductCode,
            et.RatingGrade,
            SUM(et.ExposureAmountTL) AS ExposureAmountTL,
            SUM(et.ExposureAmountTL * rw.RiskWeight) AS RiskWeightedAmountTL,
            AVG(rw.RiskWeight) AS AverageRiskWeight,
            SUM(CASE WHEN et.StageCode = 3 THEN et.ExposureAmountTL ELSE 0 END) AS DefaultedExposureTL
        FROM ExposureTL et
            CROSS APPLY
            (
                SELECT
                    CASE
                        WHEN et.RiskType = 'MARKET' THEN 1.250000
                        WHEN et.RatingGrade IN ('AAA', 'AA') THEN 0.200000
                        WHEN et.RatingGrade IN ('A', 'BBB') THEN 0.500000
                        WHEN et.StageCode = 3 THEN 1.500000
                        WHEN et.CollateralGroupCode = 'CASH' THEN 0.100000
                        ELSE 1.000000
                    END AS RiskWeight
            ) rw
        GROUP BY et.RiskType, et.PortfolioCode, et.PortfolioName, et.ProductCode, et.RatingGrade
        HAVING SUM(et.ExposureAmountTL) <> 0
    )
    SELECT
        we.RiskType,
        we.PortfolioCode,
        we.PortfolioName,
        we.ProductCode,
        we.RatingGrade,
        we.ExposureAmountTL,
        we.RiskWeightedAmountTL,
        we.AverageRiskWeight,
        we.DefaultedExposureTL
    INTO #RiskWeightedAsset
    FROM WeightedExposure we;

    SELECT
        SUM(rwa.RiskWeightedAmountTL) AS TotalRiskWeightedAmountTL
    INTO #TotalRiskWeightedAsset
    FROM #RiskWeightedAsset rwa;

    SELECT
        we.RiskType,
        we.PortfolioCode,
        we.PortfolioName,
        we.ProductCode,
        we.RatingGrade,
        we.ExposureAmountTL,
        we.RiskWeightedAmountTL,
        we.AverageRiskWeight,
        we.DefaultedExposureTL,
        CAST(we.DefaultedExposureTL / NULLIF(we.ExposureAmountTL, 0) AS DECIMAL(19,6)) AS DefaultedExposureRatio,
        cap.Cet1CapitalTL,
        cap.Tier1CapitalTL,
        cap.TotalCapitalTL,
        CAST(we.RiskWeightedAmountTL * 0.080000 AS DECIMAL(19,2)) AS RequiredCapitalTL,
        CAST(cap.TotalCapitalTL / NULLIF(totalRwa.TotalRiskWeightedAmountTL, 0) AS DECIMAL(19,6)) AS TotalCapitalRatio,
        CASE
            WHEN cap.TotalCapitalTL / NULLIF(totalRwa.TotalRiskWeightedAmountTL, 0) < @MinimumCarRatio THEN 1
            ELSE 0
        END AS CapitalBreachFlag,
        @ConsolidationCode AS ConsolidationCode,
        @ReportDate AS ReportDate
    FROM #RiskWeightedAsset we
        CROSS APPLY
        (
            SELECT
                SUM(CASE WHEN cc.CapitalBucket = 'CET1' THEN cc.EligibleAmountTL ELSE 0 END) AS Cet1CapitalTL,
                SUM(CASE WHEN cc.CapitalBucket IN ('CET1', 'AT1') THEN cc.EligibleAmountTL ELSE 0 END) AS Tier1CapitalTL,
                SUM(cc.EligibleAmountTL) AS TotalCapitalTL
            FROM #CapitalComponent cc
        ) cap
        CROSS JOIN #TotalRiskWeightedAsset totalRwa
    ORDER BY we.RiskType, we.PortfolioCode, we.ProductCode;
END
