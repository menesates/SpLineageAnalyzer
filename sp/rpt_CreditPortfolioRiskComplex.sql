USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_CreditPortfolioRiskComplex]
(
    @ReportDate     DATE        = NULL,
    @BranchId       INT         = NULL,
    @ProductGroup   VARCHAR(30) = NULL,
    @MinExposureTL  DECIMAL(19,2) = 0,
    @LanguageId     SMALLINT    = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @ReportDate IS NULL
    BEGIN
        SET @ReportDate = CAST(GETDATE() AS DATE);
    END

    IF OBJECT_ID('tempdb..#LoanBase') IS NOT NULL DROP TABLE #LoanBase;
    IF OBJECT_ID('tempdb..#CollateralAgg') IS NOT NULL DROP TABLE #CollateralAgg;
    IF OBJECT_ID('tempdb..#RiskBucket') IS NOT NULL DROP TABLE #RiskBucket;

    CREATE TABLE #LoanBase
    (
        LoanAccountId       BIGINT,
        CustomerId          BIGINT,
        BranchId            INT,
        ProductCode         VARCHAR(30),
        ProductGroup        VARCHAR(30),
        CurrencyCode        CHAR(3),
        PrincipalBalance    DECIMAL(19,2),
        PrincipalBalanceTL  DECIMAL(19,2),
        AccruedInterestTL   DECIMAL(19,2),
        DaysPastDue         INT,
        StageCode           TINYINT,
        MaturityDate        DATE,
        LimitAmountTL       DECIMAL(19,2)
    );

    INSERT INTO #LoanBase
    SELECT
        la.LoanAccountId,
        la.CustomerId,
        la.BranchId,
        la.ProductCode,
        pg.ProductGroup,
        la.CurrencyCode,
        la.PrincipalBalance,
        CASE WHEN la.CurrencyCode = 'TRY' THEN la.PrincipalBalance ELSE la.PrincipalBalance * fx.BidRate END AS PrincipalBalanceTL,
        ISNULL(ac.AccruedInterest, 0) * CASE WHEN la.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END AS AccruedInterestTL,
        DATEDIFF(DAY, ISNULL(la.LastPaidInstallmentDate, la.FirstDueDate), @ReportDate) AS DaysPastDue,
        la.StageCode,
        la.MaturityDate,
        ISNULL(lim.ApprovedLimitTL, 0) AS LimitAmountTL
    FROM BOA.LNS.LoanAccount la WITH (NOLOCK)
        INNER JOIN BOA.PRD.ProductGroupMap pg WITH (NOLOCK) ON pg.ProductCode = la.ProductCode
        LEFT JOIN BOA.LNS.LoanAccrualDaily ac WITH (NOLOCK) ON ac.LoanAccountId = la.LoanAccountId
            AND ac.AccrualDate = @ReportDate
        LEFT JOIN BOA.LNS.CreditLimit lim WITH (NOLOCK) ON lim.CustomerId = la.CustomerId
            AND lim.ProductGroup = pg.ProductGroup
            AND lim.ValidFrom <= @ReportDate
            AND ISNULL(lim.ValidTo, @ReportDate) >= @ReportDate
        OUTER APPLY
        (
            SELECT TOP (1)
                r.CurrencyCode,
                r.BidRate
            FROM BOA.TRE.FxRate r WITH (NOLOCK)
            WHERE r.CurrencyCode = la.CurrencyCode
                AND r.RateDate <= @ReportDate
            ORDER BY r.RateDate DESC
        ) fx
    WHERE la.OpenDate <= @ReportDate
        AND ISNULL(la.CloseDate, @ReportDate) >= @ReportDate
        AND la.BranchId = COALESCE(@BranchId, la.BranchId)
        AND pg.ProductGroup = COALESCE(@ProductGroup, pg.ProductGroup);

    CREATE TABLE #CollateralAgg
    (
        LoanAccountId       BIGINT,
        MortgageValueTL     DECIMAL(19,2),
        CashValueTL         DECIMAL(19,2),
        GuaranteeValueTL    DECIMAL(19,2),
        TotalCollateralTL   DECIMAL(19,2),
        EligibleCollateralTL DECIMAL(19,2)
    );

    INSERT INTO #CollateralAgg
    SELECT
        lc.LoanAccountId,
        SUM(CASE WHEN col.CollateralType = 'MORTGAGE' THEN col.ExpertValueTL ELSE 0 END) AS MortgageValueTL,
        SUM(CASE WHEN col.CollateralType = 'CASH' THEN col.ExpertValueTL ELSE 0 END) AS CashValueTL,
        SUM(CASE WHEN col.CollateralType = 'GUARANTEE' THEN col.ExpertValueTL ELSE 0 END) AS GuaranteeValueTL,
        SUM(col.ExpertValueTL) AS TotalCollateralTL,
        SUM(col.ExpertValueTL *
            CASE
                WHEN col.CollateralType = 'CASH' THEN 1.00
                WHEN col.CollateralType = 'MORTGAGE' THEN 0.70
                WHEN col.CollateralType = 'GUARANTEE' THEN 0.50
                ELSE 0.25
            END) AS EligibleCollateralTL
    FROM BOA.LNS.LoanCollateral lc WITH (NOLOCK)
        INNER JOIN BOA.CRD.Collateral col WITH (NOLOCK) ON col.CollateralId = lc.CollateralId
    WHERE col.StatusCode = 'A'
        AND col.ValuationDate <= @ReportDate
    GROUP BY lc.LoanAccountId
    HAVING SUM(col.ExpertValueTL) > 0;

    SELECT
        lb.LoanAccountId,
        lb.CustomerId,
        lb.BranchId,
        lb.ProductCode,
        lb.ProductGroup,
        lb.CurrencyCode,
        lb.PrincipalBalanceTL,
        lb.AccruedInterestTL,
        ISNULL(ca.TotalCollateralTL, 0) AS TotalCollateralTL,
        ISNULL(ca.EligibleCollateralTL, 0) AS EligibleCollateralTL,
        CAST(ISNULL(ca.EligibleCollateralTL, 0) / NULLIF(lb.PrincipalBalanceTL + lb.AccruedInterestTL, 0) AS DECIMAL(19,6)) AS CollateralCoverageRatio,
        CASE
            WHEN lb.DaysPastDue >= 90 OR lb.StageCode = 3 THEN 'NPL'
            WHEN lb.DaysPastDue BETWEEN 31 AND 89 OR lb.StageCode = 2 THEN 'WatchList'
            WHEN lb.DaysPastDue BETWEEN 1 AND 30 THEN 'EarlyDelay'
            ELSE 'Performing'
        END AS RiskBucketCode,
        CASE
            WHEN lb.DaysPastDue >= 90 OR lb.StageCode = 3 THEN 0.45
            WHEN lb.DaysPastDue BETWEEN 31 AND 89 OR lb.StageCode = 2 THEN 0.12
            WHEN lb.DaysPastDue BETWEEN 1 AND 30 THEN 0.04
            ELSE 0.01
        END AS ProvisionRate,
        ROW_NUMBER() OVER (PARTITION BY lb.CustomerId ORDER BY lb.PrincipalBalanceTL DESC) AS CustomerExposureRank
    INTO #RiskBucket
    FROM #LoanBase lb
        LEFT JOIN #CollateralAgg ca ON ca.LoanAccountId = lb.LoanAccountId
    WHERE lb.PrincipalBalanceTL + lb.AccruedInterestTL >= @MinExposureTL;

    UPDATE rb
    SET
        ProvisionRate =
            CASE
                WHEN rb.CollateralCoverageRatio >= 1 AND rb.RiskBucketCode = 'Performing' THEN rb.ProvisionRate * 0.50
                WHEN rb.CollateralCoverageRatio < 0.25 AND rb.RiskBucketCode IN ('WatchList', 'NPL') THEN rb.ProvisionRate * 1.25
                ELSE rb.ProvisionRate
            END
    FROM #RiskBucket rb;

    SELECT
        b.BranchId,
        b.Name AS BranchName,
        rb.ProductGroup,
        prm.ParamDescription AS ProductGroupName,
        COUNT_BIG(*) AS LoanCount,
        COUNT(DISTINCT rb.CustomerId) AS CustomerCount,
        SUM(rb.PrincipalBalanceTL) AS TotalPrincipalTL,
        SUM(rb.AccruedInterestTL) AS TotalAccruedInterestTL,
        SUM(rb.PrincipalBalanceTL + rb.AccruedInterestTL) AS TotalExposureTL,
        SUM(rb.TotalCollateralTL) AS TotalCollateralTL,
        SUM(rb.EligibleCollateralTL) AS EligibleCollateralTL,
        CAST(SUM(rb.EligibleCollateralTL) / NULLIF(SUM(rb.PrincipalBalanceTL + rb.AccruedInterestTL), 0) AS DECIMAL(19,6)) AS PortfolioCollateralCoverageRatio,
        SUM(CASE WHEN rb.RiskBucketCode = 'NPL' THEN rb.PrincipalBalanceTL + rb.AccruedInterestTL ELSE 0 END) AS NplExposureTL,
        SUM(CASE WHEN rb.RiskBucketCode = 'WatchList' THEN rb.PrincipalBalanceTL + rb.AccruedInterestTL ELSE 0 END) AS WatchListExposureTL,
        SUM(CASE WHEN rb.RiskBucketCode = 'EarlyDelay' THEN rb.PrincipalBalanceTL + rb.AccruedInterestTL ELSE 0 END) AS EarlyDelayExposureTL,
        CAST(SUM(CASE WHEN rb.RiskBucketCode = 'NPL' THEN rb.PrincipalBalanceTL + rb.AccruedInterestTL ELSE 0 END)
            / NULLIF(SUM(rb.PrincipalBalanceTL + rb.AccruedInterestTL), 0) AS DECIMAL(19,6)) AS NplRatio,
        SUM((rb.PrincipalBalanceTL + rb.AccruedInterestTL - rb.EligibleCollateralTL) * rb.ProvisionRate) AS RequiredProvisionTL,
        AVG(CASE WHEN rb.CustomerExposureRank = 1 THEN rb.CollateralCoverageRatio ELSE NULL END) AS TopLoanAvgCoverageRatio,
        concentration.TopCustomerExposureTL,
        concentration.TopTenCustomerExposureTL,
        CAST(concentration.TopTenCustomerExposureTL / NULLIF(SUM(rb.PrincipalBalanceTL + rb.AccruedInterestTL), 0) AS DECIMAL(19,6)) AS TopTenConcentrationRatio,
        @ReportDate AS ReportDate
    FROM #RiskBucket rb
        INNER JOIN BOA.COR.Branch b WITH (NOLOCK) ON b.BranchId = rb.BranchId
        LEFT JOIN BOA.COR.Parameter prm WITH (NOLOCK) ON prm.ParamType = 'PRODUCTGROUP'
            AND prm.ParamCode = rb.ProductGroup
            AND prm.LanguageId = @LanguageId
        OUTER APPLY
        (
            SELECT
                MAX(cx.CustomerExposureTL) AS TopCustomerExposureTL,
                SUM(CASE WHEN cx.ExposureRank <= 10 THEN cx.CustomerExposureTL ELSE 0 END) AS TopTenCustomerExposureTL
            FROM
            (
                SELECT
                    rb2.CustomerId,
                    SUM(rb2.PrincipalBalanceTL + rb2.AccruedInterestTL) AS CustomerExposureTL,
                    DENSE_RANK() OVER (ORDER BY SUM(rb2.PrincipalBalanceTL + rb2.AccruedInterestTL) DESC) AS ExposureRank
                FROM #RiskBucket rb2
                WHERE rb2.BranchId = rb.BranchId
                    AND rb2.ProductGroup = rb.ProductGroup
                GROUP BY rb2.CustomerId
            ) cx
        ) concentration
    GROUP BY
        b.BranchId,
        b.Name,
        rb.ProductGroup,
        prm.ParamDescription,
        concentration.TopCustomerExposureTL,
        concentration.TopTenCustomerExposureTL
    HAVING SUM(rb.PrincipalBalanceTL + rb.AccruedInterestTL) > 0
    ORDER BY TotalExposureTL DESC;
END
