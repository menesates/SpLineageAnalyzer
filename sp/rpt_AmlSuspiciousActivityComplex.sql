USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [RPT].[rpt_AmlSuspiciousActivityComplex]
(
    @BeginDate      DATE = NULL,
    @EndDate        DATE = NULL,
    @MinRiskScore   DECIMAL(19,6) = 50.000000,
    @ScenarioCode   VARCHAR(30) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @BeginDate IS NULL SET @BeginDate = DATEADD(DAY, -7, CAST(GETDATE() AS DATE));
    IF @EndDate IS NULL SET @EndDate = CAST(GETDATE() AS DATE);

    ;WITH RawTransaction AS
    (
        SELECT
            'EFT' AS SourceType,
            eft.TranId,
            eft.CustomerId,
            eft.CounterpartyCustomerId,
            eft.TranDate,
            eft.Amount,
            eft.CurrencyCode,
            eft.CountryCode,
            eft.ChannelCode,
            eft.BranchId
        FROM BOA.PAY.EftTransfer eft WITH (NOLOCK)
        WHERE eft.TranDate BETWEEN @BeginDate AND @EndDate
            AND eft.StatusCode = 'A'
        UNION ALL
        SELECT
            'SWIFT' AS SourceType,
            sw.SwiftMessageId AS TranId,
            sw.CustomerId,
            sw.BeneficiaryCustomerId AS CounterpartyCustomerId,
            sw.ValueDate AS TranDate,
            sw.TransferAmount AS Amount,
            sw.CurrencyCode,
            sw.BeneficiaryCountryCode AS CountryCode,
            sw.ChannelCode,
            sw.BranchId
        FROM BOA.PAY.SwiftTransfer sw WITH (NOLOCK)
        WHERE sw.ValueDate BETWEEN @BeginDate AND @EndDate
            AND sw.MessageStatus = 'A'
        UNION ALL
        SELECT
            'CASH' AS SourceType,
            cash.CashTranId AS TranId,
            cash.CustomerId,
            NULL AS CounterpartyCustomerId,
            cash.TranDate,
            cash.Amount,
            cash.CurrencyCode,
            cash.CountryCode,
            'BRANCH' AS ChannelCode,
            cash.BranchId
        FROM BOA.OPR.CashTransaction cash WITH (NOLOCK)
        WHERE cash.TranDate BETWEEN @BeginDate AND @EndDate
            AND cash.TranStatus = 'A'
        UNION ALL
        SELECT
            'CARD' AS SourceType,
            card.CardTranId AS TranId,
            card.CustomerId,
            card.MerchantCustomerId AS CounterpartyCustomerId,
            card.TranDate,
            card.TranAmount AS Amount,
            card.CurrencyCode,
            card.MerchantCountryCode AS CountryCode,
            card.ChannelCode,
            card.BranchId
        FROM BOA.CRD.CardTransaction card WITH (NOLOCK)
        WHERE card.TranDate BETWEEN @BeginDate AND @EndDate
            AND card.TranStatus = 'A'
    ),
    TransactionTL AS
    (
        SELECT
            rt.SourceType,
            rt.TranId,
            rt.CustomerId,
            rt.CounterpartyCustomerId,
            rt.TranDate,
            rt.Amount,
            rt.CurrencyCode,
            CASE WHEN rt.CurrencyCode = 'TRY' THEN rt.Amount ELSE rt.Amount * fx.BidRate END AS AmountTL,
            rt.CountryCode,
            rt.ChannelCode,
            rt.BranchId
        FROM RawTransaction rt
            OUTER APPLY
            (
                SELECT TOP (1)
                    fr.BidRate
                FROM BOA.TRE.FxRate fr WITH (NOLOCK)
                WHERE fr.CurrencyCode = rt.CurrencyCode
                    AND fr.RateDate <= rt.TranDate
                ORDER BY fr.RateDate DESC
            ) fx
    ),
    CustomerVelocity AS
    (
        SELECT
            ttl.CustomerId,
            COUNT_BIG(*) AS TransactionCount,
            COUNT(DISTINCT ttl.CounterpartyCustomerId) AS CounterpartyCount,
            SUM(ttl.AmountTL) AS TotalAmountTL,
            SUM(CASE WHEN ttl.SourceType = 'CASH' THEN ttl.AmountTL ELSE 0 END) AS CashAmountTL,
            SUM(CASE WHEN cr.RiskLevel = 'HIGH' THEN ttl.AmountTL ELSE 0 END) AS HighRiskCountryAmountTL,
            MAX(ttl.AmountTL) AS MaxSingleAmountTL
        FROM TransactionTL ttl
            LEFT JOIN BOA.AML.CountryRisk cr WITH (NOLOCK) ON cr.CountryCode = ttl.CountryCode
        GROUP BY ttl.CustomerId
    ),
    ScenarioScore AS
    (
        SELECT
            cv.CustomerId,
            cv.TransactionCount,
            cv.CounterpartyCount,
            cv.TotalAmountTL,
            cv.CashAmountTL,
            cv.HighRiskCountryAmountTL,
            cv.MaxSingleAmountTL,
            CASE
                WHEN cv.HighRiskCountryAmountTL > 1000000 THEN 'HIGH_RISK_COUNTRY'
                WHEN cv.CashAmountTL > 750000 THEN 'CASH_INTENSIVE'
                WHEN cv.CounterpartyCount > 25 THEN 'COUNTERPARTY_SPREAD'
                ELSE 'VELOCITY'
            END AS ScenarioCode,
            CAST(
                ISNULL(cv.HighRiskCountryAmountTL / NULLIF(cv.TotalAmountTL, 0), 0) * 40
                + ISNULL(cv.CashAmountTL / NULLIF(cv.TotalAmountTL, 0), 0) * 25
                + CASE WHEN cv.CounterpartyCount > 25 THEN 20 ELSE 0 END
                + CASE WHEN cv.MaxSingleAmountTL > 500000 THEN 20 ELSE 0 END
                AS DECIMAL(19,6)) AS RiskScore
        FROM CustomerVelocity cv
    )
    SELECT
        c.CustomerNumber,
        c.FullName AS CustomerName,
        b.BranchId,
        b.Name AS BranchName,
        ss.ScenarioCode,
        ss.TransactionCount,
        ss.CounterpartyCount,
        ss.TotalAmountTL AS SuspiciousAmountTL,
        ss.CashAmountTL,
        ss.HighRiskCountryAmountTL,
        ss.MaxSingleAmountTL,
        ss.RiskScore,
        CASE WHEN ss.RiskScore >= @MinRiskScore THEN 1 ELSE 0 END AS AlertFlag,
        CASE WHEN wl.MatchId IS NOT NULL THEN 1 ELSE 0 END AS WatchlistMatchFlag,
        wl.MatchScore AS WatchlistMatchScore,
        lastAlert.LastAlertDate,
        lastAlert.LastScenarioCode,
        CAST(ss.HighRiskCountryAmountTL / NULLIF(ss.TotalAmountTL, 0) AS DECIMAL(19,6)) AS HighRiskCountryRatio,
        @BeginDate AS ReportBeginDate,
        @EndDate AS ReportEndDate
    FROM ScenarioScore ss
        INNER JOIN BOA.CUS.Customer c WITH (NOLOCK) ON c.CustomerId = ss.CustomerId
        INNER JOIN BOA.COR.Branch b WITH (NOLOCK) ON b.BranchId = c.BranchId
        LEFT JOIN AML_LINK.BOA.AML.WatchListMatch wl WITH (NOLOCK) ON wl.CustomerId = ss.CustomerId
            AND wl.MatchStatus = 'ACTIVE'
        OUTER APPLY
        (
            SELECT TOP (1)
                al.AlertDate AS LastAlertDate,
                al.ScenarioCode AS LastScenarioCode
            FROM BOA.AML.Alert al WITH (NOLOCK)
            WHERE al.CustomerId = ss.CustomerId
            ORDER BY al.AlertDate DESC
        ) lastAlert
    WHERE ss.RiskScore >= @MinRiskScore
        AND ss.ScenarioCode = COALESCE(@ScenarioCode, ss.ScenarioCode)
    ORDER BY ss.RiskScore DESC, ss.TotalAmountTL DESC;
END
