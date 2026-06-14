USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_CustomerProfitabilityComplex]
(
    @BeginDate      DATE        = NULL,
    @EndDate        DATE        = NULL,
    @BranchId       INT         = NULL,
    @PortfolioId    INT         = NULL,
    @CustomerClass  VARCHAR(20) = NULL,
    @LanguageId     SMALLINT    = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @BeginDate IS NULL
    BEGIN
        SET @BeginDate = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    END

    IF @EndDate IS NULL
    BEGIN
        SET @EndDate = EOMONTH(@BeginDate);
    END

    ;WITH CustomerBase AS
    (
        SELECT
            c.CustomerId,
            c.CustomerNumber,
            c.CustomerName,
            c.CustomerClass,
            c.BranchId,
            b.Name AS BranchName,
            p.PortfolioId,
            p.PortfolioName,
            seg.ParamDescription AS SegmentName,
            CASE
                WHEN c.CustomerClass IN ('CORP', 'COMM') THEN 'Commercial'
                WHEN c.CustomerClass IN ('PRIV', 'VIP') THEN 'Private'
                ELSE 'Retail'
            END AS ProfitabilityGroup
        FROM BOA.CUS.Customer c WITH (NOLOCK)
            INNER JOIN BOA.COR.Branch b WITH (NOLOCK) ON b.BranchId = c.BranchId
            LEFT JOIN BOA.CRM.PortfolioCustomer pc WITH (NOLOCK) ON pc.CustomerId = c.CustomerId AND pc.IsActive = 1
            LEFT JOIN BOA.CRM.Portfolio p WITH (NOLOCK) ON p.PortfolioId = pc.PortfolioId
            LEFT JOIN BOA.COR.Parameter seg WITH (NOLOCK) ON seg.ParamType = 'CUSTOMERSEGMENT'
                AND seg.ParamCode = c.CustomerSegment
                AND seg.LanguageId = @LanguageId
        WHERE c.IsActive = 1
            AND c.BranchId = COALESCE(@BranchId, c.BranchId)
            AND ISNULL(p.PortfolioId, -1) = COALESCE(@PortfolioId, ISNULL(p.PortfolioId, -1))
            AND c.CustomerClass = COALESCE(@CustomerClass, c.CustomerClass)
    ),
    LoanIncome AS
    (
        SELECT
            l.CustomerId,
            SUM(l.PrincipalBalance) AS LoanBalance,
            SUM(CASE WHEN l.CurrencyCode = 'TRY' THEN l.PrincipalBalance ELSE l.PrincipalBalance * fx.BidRate END) AS LoanBalanceTL,
            SUM(ISNULL(accr.InterestAccrualAmount, 0)) AS InterestIncome,
            SUM(ISNULL(accr.RediscountAmount, 0)) AS RediscountIncome,
            SUM(CASE WHEN l.StageCode = 3 THEN l.PrincipalBalance ELSE 0 END) AS Stage3Balance,
            MAX(l.MaturityDate) AS MaxLoanMaturityDate
        FROM BOA.LNS.LoanAccount l WITH (NOLOCK)
            LEFT JOIN BOA.LNS.LoanAccrual accr WITH (NOLOCK) ON accr.LoanAccountId = l.LoanAccountId
                AND accr.TranDate BETWEEN @BeginDate AND @EndDate
            OUTER APPLY
            (
                SELECT TOP (1)
                    fxr.CurrencyCode,
                    fxr.BidRate,
                    fxr.AskRate
                FROM BOA.TRE.FxRate fxr WITH (NOLOCK)
                WHERE fxr.CurrencyCode = l.CurrencyCode
                    AND fxr.RateDate <= @EndDate
                ORDER BY fxr.RateDate DESC
            ) fx
        WHERE l.OpenDate <= @EndDate
            AND ISNULL(l.CloseDate, @EndDate) >= @BeginDate
        GROUP BY l.CustomerId
    ),
    DepositCost AS
    (
        SELECT
            d.CustomerId,
            SUM(d.Balance) AS DepositBalance,
            SUM(CASE WHEN d.CurrencyCode = 'TRY' THEN d.Balance ELSE d.Balance * fx.BidRate END) AS DepositBalanceTL,
            SUM(ISNULL(ia.InterestExpenseAmount, 0)) AS InterestExpense,
            SUM(ISNULL(ia.RediscountExpenseAmount, 0)) AS DepositRediscountExpense,
            SUM(CASE WHEN d.ProductCode LIKE 'TIME%' THEN d.Balance ELSE 0 END) AS TimeDepositBalance
        FROM BOA.DEP.DepositAccount d WITH (NOLOCK)
            LEFT JOIN BOA.DEP.DepositInterestAccrual ia WITH (NOLOCK) ON ia.AccountId = d.AccountId
                AND ia.TranDate BETWEEN @BeginDate AND @EndDate
            OUTER APPLY
            (
                SELECT TOP (1)
                    fxr.CurrencyCode,
                    fxr.BidRate
                FROM BOA.TRE.FxRate fxr WITH (NOLOCK)
                WHERE fxr.CurrencyCode = d.CurrencyCode
                    AND fxr.RateDate <= @EndDate
                ORDER BY fxr.RateDate DESC
            ) fx
        WHERE d.OpenDate <= @EndDate
            AND ISNULL(d.CloseDate, @EndDate) >= @BeginDate
        GROUP BY d.CustomerId
    ),
    FeeIncome AS
    (
        SELECT
            ft.CustomerId,
            SUM(CASE WHEN ft.FeeDirection = 'C' THEN ft.AmountTL ELSE -1 * ft.AmountTL END) AS NetFeeIncome,
            SUM(CASE WHEN ft.ChannelCode = 'BRANCH' THEN ft.AmountTL ELSE 0 END) AS BranchFeeIncome,
            SUM(CASE WHEN ft.ChannelCode IN ('MOBILE', 'INTERNET') THEN ft.AmountTL ELSE 0 END) AS DigitalFeeIncome,
            COUNT_BIG(*) AS FeeTranCount
        FROM BOA.FEE.FeeTransaction ft WITH (NOLOCK)
        WHERE ft.TranDate BETWEEN @BeginDate AND @EndDate
            AND ft.CancelFlag = 0
        GROUP BY ft.CustomerId
    ),
    PaymentVolume AS
    (
        SELECT
            tr.CustomerId,
            SUM(ABS(tr.AmountTL)) AS TotalTransactionVolumeTL,
            SUM(CASE WHEN tr.ChannelCode IN ('MOBILE', 'INTERNET', 'ATM') THEN ABS(tr.AmountTL) ELSE 0 END) AS DigitalVolumeTL,
            COUNT_BIG(*) AS TransactionCount,
            ROW_NUMBER() OVER (PARTITION BY tr.CustomerId ORDER BY SUM(ABS(tr.AmountTL)) DESC) AS VolumeRank
        FROM BOA.TRN.CustomerTransaction tr WITH (NOLOCK)
        WHERE tr.TranDate BETWEEN @BeginDate AND @EndDate
            AND tr.TranStatus = 'A'
        GROUP BY tr.CustomerId
    )
    SELECT
        cb.BranchId,
        cb.BranchName,
        cb.PortfolioId,
        cb.PortfolioName,
        cb.CustomerNumber,
        cb.CustomerName,
        cb.CustomerClass,
        cb.SegmentName,
        cb.ProfitabilityGroup,
        ISNULL(li.LoanBalanceTL, 0) AS LoanBalanceTL,
        ISNULL(dc.DepositBalanceTL, 0) AS DepositBalanceTL,
        ISNULL(li.InterestIncome, 0) AS InterestIncome,
        ISNULL(li.RediscountIncome, 0) AS RediscountIncome,
        ISNULL(dc.InterestExpense, 0) AS InterestExpense,
        ISNULL(dc.DepositRediscountExpense, 0) AS DepositRediscountExpense,
        ISNULL(fi.NetFeeIncome, 0) AS NetFeeIncome,
        ISNULL(fi.BranchFeeIncome, 0) AS BranchFeeIncome,
        ISNULL(fi.DigitalFeeIncome, 0) AS DigitalFeeIncome,
        ISNULL(pv.TotalTransactionVolumeTL, 0) AS TotalTransactionVolumeTL,
        ISNULL(pv.DigitalVolumeTL, 0) AS DigitalVolumeTL,
        CAST(ISNULL(pv.DigitalVolumeTL, 0) / NULLIF(pv.TotalTransactionVolumeTL, 0) AS DECIMAL(19, 6)) AS DigitalVolumeRatio,
        CAST(ISNULL(li.Stage3Balance, 0) / NULLIF(li.LoanBalance, 0) AS DECIMAL(19, 6)) AS Stage3LoanRatio,
        risk.RiskWeight,
        risk.ExpectedLossAmount,
        score.ProfitabilityScore,
        score.ProfitabilityGrade,
        (
            ISNULL(li.InterestIncome, 0)
            + ISNULL(li.RediscountIncome, 0)
            + ISNULL(fi.NetFeeIncome, 0)
            - ISNULL(dc.InterestExpense, 0)
            - ISNULL(dc.DepositRediscountExpense, 0)
            - ISNULL(risk.ExpectedLossAmount, 0)
        ) AS NetProfitTL,
        CASE
            WHEN ISNULL(dc.DepositBalanceTL, 0) > ISNULL(li.LoanBalanceTL, 0) THEN 'FundProvider'
            WHEN ISNULL(li.LoanBalanceTL, 0) > ISNULL(dc.DepositBalanceTL, 0) THEN 'FundUser'
            ELSE 'Balanced'
        END AS BalanceRole,
        @BeginDate AS ReportBeginDate,
        @EndDate AS ReportEndDate
    FROM CustomerBase cb
        LEFT JOIN LoanIncome li ON li.CustomerId = cb.CustomerId
        LEFT JOIN DepositCost dc ON dc.CustomerId = cb.CustomerId
        LEFT JOIN FeeIncome fi ON fi.CustomerId = cb.CustomerId
        LEFT JOIN PaymentVolume pv ON pv.CustomerId = cb.CustomerId
        OUTER APPLY
        (
            SELECT
                CASE
                    WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 1.00
                    WHEN cb.CustomerClass IN ('CORP', 'COMM') THEN 0.55
                    WHEN ISNULL(li.LoanBalanceTL, 0) > 5000000 THEN 0.75
                    ELSE 0.35
                END AS RiskWeight,
                ISNULL(li.LoanBalanceTL, 0) *
                    CASE
                        WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 0.45
                        WHEN cb.CustomerClass IN ('CORP', 'COMM') THEN 0.08
                        ELSE 0.03
                    END AS ExpectedLossAmount
        ) risk
        OUTER APPLY
        (
            SELECT
                (
                    ISNULL(li.InterestIncome, 0)
                    + ISNULL(fi.NetFeeIncome, 0)
                    - ISNULL(dc.InterestExpense, 0)
                    - ISNULL(risk.ExpectedLossAmount, 0)
                ) / NULLIF(ISNULL(li.LoanBalanceTL, 0) + ISNULL(dc.DepositBalanceTL, 0), 0) AS ProfitabilityScore,
                CASE
                    WHEN (
                        ISNULL(li.InterestIncome, 0)
                        + ISNULL(fi.NetFeeIncome, 0)
                        - ISNULL(dc.InterestExpense, 0)
                        - ISNULL(risk.ExpectedLossAmount, 0)
                    ) > 100000 THEN 'A'
                    WHEN ISNULL(fi.NetFeeIncome, 0) > 25000 THEN 'B'
                    WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 'D'
                    ELSE 'C'
                END AS ProfitabilityGrade
        ) score
    WHERE
        ISNULL(li.LoanBalanceTL, 0) <> 0
        OR ISNULL(dc.DepositBalanceTL, 0) <> 0
        OR ISNULL(fi.NetFeeIncome, 0) <> 0
    ORDER BY NetProfitTL DESC, cb.CustomerNumber;
END
