USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_TradeFinanceExposureComplex]
(
    @ReportDate     DATE = NULL,
    @BranchId       INT = NULL,
    @CustomerId     BIGINT = NULL,
    @LanguageId     SMALLINT = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @ReportDate IS NULL
    BEGIN
        SET @ReportDate = CAST(GETDATE() AS DATE);
    END

    EXEC BOA.RPT.usp_PrepareTradeFinanceDailySnapshot
        @ReportDate = @ReportDate,
        @BranchId = @BranchId,
        @CustomerId = @CustomerId;

    IF OBJECT_ID('tempdb..#TfBase') IS NOT NULL DROP TABLE #TfBase;
    IF OBJECT_ID('tempdb..#CollateralTf') IS NOT NULL DROP TABLE #CollateralTf;
    IF OBJECT_ID('tempdb..#ExposureTf') IS NOT NULL DROP TABLE #ExposureTf;

    CREATE TABLE #TfBase
    (
        FacilityId          BIGINT,
        ParentFacilityId    BIGINT NULL,
        CustomerId          BIGINT,
        BranchId            INT,
        ProductCode         VARCHAR(30),
        FacilityType        VARCHAR(30),
        CurrencyCode        CHAR(3),
        OutstandingAmount   DECIMAL(19,2),
        OutstandingTL       DECIMAL(19,2),
        CommissionRate      DECIMAL(19,6),
        MaturityDate        DATE,
        IssueDate           DATE
    );

    INSERT INTO #TfBase
    SELECT
        tf.FacilityId,
        tf.ParentFacilityId,
        tf.CustomerId,
        tf.BranchId,
        tf.ProductCode,
        tf.FacilityType,
        tf.CurrencyCode,
        tf.OutstandingAmount,
        tf.OutstandingAmount * CASE WHEN tf.CurrencyCode = 'TRY' THEN 1 ELSE fx.BidRate END AS OutstandingTL,
        ISNULL(price.CommissionRate, 0) AS CommissionRate,
        tf.MaturityDate,
        tf.IssueDate
    FROM BOA.TRF.TradeFinanceFacility tf WITH (NOLOCK)
        OUTER APPLY
        (
            SELECT TOP (1)
                fr.BidRate
            FROM BOA.TRE.FxRate fr WITH (NOLOCK)
            WHERE fr.CurrencyCode = tf.CurrencyCode
                AND fr.RateDate <= @ReportDate
            ORDER BY fr.RateDate DESC
        ) fx
        OUTER APPLY
        (
            SELECT TOP (1)
                pc.CommissionRate
            FROM BOA.TRF.TradeFinancePricing pc WITH (NOLOCK)
            WHERE pc.ProductCode = tf.ProductCode
                AND pc.CustomerClass = tf.CustomerClass
                AND pc.ValidFrom <= @ReportDate
            ORDER BY pc.ValidFrom DESC
        ) price
    WHERE tf.IssueDate <= @ReportDate
        AND ISNULL(tf.CloseDate, @ReportDate) >= @ReportDate
        AND tf.CustomerId = COALESCE(@CustomerId, tf.CustomerId)
        AND tf.BranchId = COALESCE(@BranchId, tf.BranchId);

    SELECT
        tc.FacilityId,
        SUM(CASE WHEN col.CollateralType = 'CASH' THEN col.CurrentValueTL ELSE 0 END) AS CashCollateralTL,
        SUM(CASE WHEN col.CollateralType = 'GUARANTEE' THEN col.CurrentValueTL ELSE 0 END) AS GuaranteeCollateralTL,
        SUM(CASE WHEN col.CollateralType = 'MORTGAGE' THEN col.CurrentValueTL ELSE 0 END) AS MortgageCollateralTL,
        SUM(col.CurrentValueTL *
            CASE
                WHEN col.CollateralType = 'CASH' THEN 1.000000
                WHEN col.CollateralType = 'GUARANTEE' THEN 0.600000
                WHEN col.CollateralType = 'MORTGAGE' THEN 0.500000
                ELSE 0.250000
            END) AS EligibleCollateralTL
    INTO #CollateralTf
    FROM BOA.TRF.TradeFinanceCollateral tc WITH (NOLOCK)
        INNER JOIN BOA.CRD.Collateral col WITH (NOLOCK) ON col.CollateralId = tc.CollateralId
    WHERE col.StatusCode = 'A'
    GROUP BY tc.FacilityId;

    SELECT
        base.FacilityId,
        base.CustomerId,
        base.BranchId,
        base.ProductCode,
        base.FacilityType,
        base.CurrencyCode,
        parent.FacilityId AS ParentFacilityId,
        parent.OutstandingTL AS ParentOutstandingTL,
        base.OutstandingTL,
        ISNULL(col.EligibleCollateralTL, 0) AS EligibleCollateralTL,
        CAST(base.OutstandingTL - ISNULL(col.EligibleCollateralTL, 0) AS DECIMAL(19,2)) AS UnsecuredExposureTL,
        DATEDIFF(DAY, @ReportDate, base.MaturityDate) AS DaysToMaturity,
        CAST(base.OutstandingTL * base.CommissionRate / 365.000000
            * DATEDIFF(DAY, @ReportDate, base.MaturityDate) AS DECIMAL(19,2)) AS CommissionAccrualTL
    INTO #ExposureTf
    FROM #TfBase base
        LEFT JOIN #TfBase parent ON parent.FacilityId = base.ParentFacilityId
        LEFT JOIN #CollateralTf col ON col.FacilityId = base.FacilityId;

    UPDATE ex
    SET UnsecuredExposureTL =
        CASE
            WHEN ex.UnsecuredExposureTL < 0 THEN 0
            ELSE ex.UnsecuredExposureTL
        END
    FROM #ExposureTf ex;

    SELECT
        c.CustomerNumber,
        c.FullName AS CustomerName,
        b.BranchId,
        b.Name AS BranchName,
        ex.FacilityId,
        ex.ParentFacilityId,
        ex.ProductCode,
        prm.ParamDescription AS ProductName,
        ex.FacilityType,
        ex.CurrencyCode,
        ex.OutstandingTL AS ExposureTL,
        ex.ParentOutstandingTL,
        ex.EligibleCollateralTL,
        CAST(ex.EligibleCollateralTL / NULLIF(ex.OutstandingTL, 0) AS DECIMAL(19,6)) AS CollateralCoverageRatio,
        ex.UnsecuredExposureTL,
        ex.CommissionAccrualTL,
        bucket.MaturityBucket,
        bucket.MaturityWeight,
        CASE WHEN ex.UnsecuredExposureTL > limitDef.CustomerTfLimitTL THEN 1 ELSE 0 END AS LimitBreachFlag,
        limitDef.CustomerTfLimitTL,
        @ReportDate AS ReportDate
    FROM #ExposureTf ex
        INNER JOIN BOA.CUS.Customer c WITH (NOLOCK) ON c.CustomerId = ex.CustomerId
        INNER JOIN BOA.COR.Branch b WITH (NOLOCK) ON b.BranchId = ex.BranchId
        LEFT JOIN BOA.COR.Parameter prm WITH (NOLOCK) ON prm.ParamType = 'TFPRODUCT'
            AND prm.ParamCode = ex.ProductCode
            AND prm.LanguageId = @LanguageId
        CROSS APPLY
        (
            SELECT
                CASE
                    WHEN ex.DaysToMaturity <= 30 THEN 'M01'
                    WHEN ex.DaysToMaturity <= 90 THEN 'M03'
                    WHEN ex.DaysToMaturity <= 180 THEN 'M06'
                    ELSE 'M12PLUS'
                END AS MaturityBucket,
                CASE
                    WHEN ex.DaysToMaturity <= 30 THEN 0.250000
                    WHEN ex.DaysToMaturity <= 90 THEN 0.500000
                    WHEN ex.DaysToMaturity <= 180 THEN 0.750000
                    ELSE 1.000000
                END AS MaturityWeight
        ) bucket
        OUTER APPLY
        (
            SELECT TOP (1)
                lim.ApprovedLimitTL AS CustomerTfLimitTL
            FROM BOA.TRF.TradeFinanceLimit lim WITH (NOLOCK)
            WHERE lim.CustomerId = ex.CustomerId
                AND lim.ValidFrom <= @ReportDate
            ORDER BY lim.ValidFrom DESC
        ) limitDef
    ORDER BY ex.UnsecuredExposureTL DESC, c.CustomerNumber;
END
