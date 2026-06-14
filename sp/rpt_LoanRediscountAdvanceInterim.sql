USE [OPTReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [LNS].[rpt_LoanRediscountAdvanceInterim]
(
  @AccountNumber  INT        = NULL,
  @AccountSuffix  INT        = NULL,
  @BranchId    INT        = NULL,
  @DateBegin    SMALLDATETIME  = NULL,
  @DateEnd    SMALLDATETIME  = NULL,
  @UserName    VARCHAR(10)    = NULL,    
  @LanguageId    SMALLINT    = NULL    
)  
AS
SET NOCOUNT ON
BEGIN
  IF(@DateBegin IS NULL OR @DateEnd IS NULL)
  BEGIN
    SELECT lra.LoanRediscountAdvanceInterimId,
      lra.AccountNumber,
      lra.AccountSuffix ,
      lra.LoanMaturityType,
      lra.LoanType ,
      lra.LedgerId,
      lra.ProjectFECType ,    
          dvz.FecCode,    
      lra.FundPool ,
      lra.RediscountAmount ,
      lra.RediscountAmountTL,
      lra.TranBranch AS TranBranchId ,
      b.Name AS TranBranchName ,
      lra.TranDate ,
      lra.BusinessKey,
        --lra.TranReference,  /* Gün İçi Raporu için Interim tablosunda alan bulunmadığından NULL olarak beslendi. t.ms250005 -- 2025-04-30 */
        null as TranReference, /* Gün İçi Raporu için Interim tablosunda alan bulunmadığından NULL olarak beslendi. t.ms250005 -- 2025-04-30 */
      payb.AnnualSimpleProfitRate,
      payb.AnnualCompoundProfitRate,
      prwk.ParamDescription,
      p1.ParamDescription AS FundPoolDesc,
      p2.ParamDescription AS  LoanTypeDesc,
      prme.ParamDescription AS SpecialPool,
      (CASE WHEN p.AgreementType = 3 
         Then  mtxl.Rediscount5
         Else  mtx.Rediscount5 END)
         AS Rediscount5 ,
         (CASE WHEN p.AgreementType = 3 
         Then  mtxl.Rediscount2
         Else  mtx.Rediscount2 END)
         AS Rediscount2 ,
      (lra.RediscountAmount-ISNULL(lr.RediscountAmount,0)) DailyRediscount,
      (lra.RediscountAmountTL-ISNULL(lr.RediscountAmountTL,0)) DailyRediscountTL
    FROM  BOA.LNS.LoanRediscountAdvanceInterim lra WITH (NOLOCK)
      INNER JOIN  BOA.COR.Branch          AS b  WITH (NOLOCK) ON b.BranchId=lra.TranBranch
      INNER JOIN  boa.lns.Project          AS p  WITH (NOLOCK) ON p.AccountNumber = lra.AccountNumber AND p.AccountSuffix = lra.AccountSuffix
      INNER JOIN  BOA.cor.[Parameter]        AS p1  WITH (NOLOCK) ON p1.ParamType ='HPGRB2Y'   AND p1.LanguageId=1 AND p1.ParamCode = lra.FundPool  
      INNER JOIN  BOA.COR.ProductLoanProperty    AS plp  WITH (NOLOCK) ON plp.ProductCode = p.ProductCode AND plp.CustomerClass = p.CustomerClass AND plp.PersonType = p.PersonType
      INNER JOIN  BOA.cor.[Parameter]        AS p2  WITH (NOLOCK) ON p2.ParamType ='HPRDGRUPY'   AND  p2.LanguageId=1 AND p2.ParamCode = plp.LoanType
      LEFT JOIN  BOA.lns.ProjectExtension    AS pe  WITH (NOLOCK) ON pe.ProjectId = p.ProjectId AND pe.ProjectExtensionType = 5
      LEFT JOIN  BOA.cor.[Parameter]        AS prme  WITH (NOLOCK) ON prme.ParamType ='YATVEKHAVUZ'   AND  prme.LanguageId=@languageId AND prme.ParamCode = pe.ReferenceId
          LEFT JOIN   boa.cor.Parameter               AS prwk WITH (NOLOCK) ON prwk.ParamType ='WAKALAPOOLTYPE' and prwk.ParamCode = p.FundPoolDetail 
        INNER JOIN  BOA.Cor.Account          AS a    WITH (NOLOCK) ON a.AccountNumber =lra.AccountNumber and a.AccountSuffix =lra.AccountSuffix
      INNER JOIN BOA.lns.ProjectPayBackPlan       AS payb   WITH (NOLOCK) ON payb.ProjectId = p.ProjectId 
      INNER JOIN boa.cor.fec                       AS  dvz   WITH (NOLOCK) ON dvz.FecId = p.DebtFEC
      LEFT JOIN  BOA.LNS.LoanRediscountAdvanceInterim  AS lr  WITH (NOLOCK) ON lr.TranDate = lra.Trandate-1 and lra.AccountNumber = lr.AccountNumber and lra.AccountSuffix = lr.AccountSuffix
    OUTER APPLY ( 
    SELECT 
                ma.MainLedgerId,
                MAX(CASE WHEN ma.ColumnNo = 1 THEN ma.LedgerId ELSE 0 END) AS Rediscount5,
                MAX(CASE WHEN ma.ColumnNo = 6 THEN ma.LedgerId ELSE 0 END) AS Rediscount2
            FROM boa.acc.MatrixAccounts ma WITH (NOLOCK) WHERE ma.TableNo = 2 and ma.MainLedgerId= a.LedgerId and ma.ColumnNo IN (1,6)
            GROUP by ma.MainLedgerId
       ) mtx
      OUTER APPLY ( 
            SELECT 
                ma.MainLedgerId,
                MAX(CASE WHEN ma.ColumnNo = 10 THEN ma.LedgerId ELSE 0 END) AS Rediscount5,
                MAX(CASE WHEN ma.ColumnNo = 7 THEN ma.LedgerId ELSE 0 END) AS Rediscount2
            FROM boa.acc.MatrixAccounts ma WITH (NOLOCK) WHERE ma.TableNo = 5 and ma.MainLedgerId= a.LedgerId and ma.ColumnNo IN (10,7)
            GROUP by ma.MainLedgerId
       ) mtxl
    WHERE
      lra.AccountNumber= (CASE WHEN @AccountNumber IS NULL THEN lra.AccountNumber ELSE @AccountNumber END) AND
      lra.AccountSuffix= (CASE WHEN @AccountSuffix IS NULL THEN lra.AccountSuffix ELSE @AccountSuffix END) AND
      lra.TranBranch= (CASE WHEN @BranchId IS NULL THEN lra.TranBranch ELSE @BranchId END)
  END
  ELSE
  BEGIN
      SELECT lra.LoanRediscountAdvanceInterimId,
        lra.AccountNumber,
        lra.AccountSuffix ,
        lra.LoanMaturityType,
        lra.LoanType ,
        lra.LedgerId,
        lra.ProjectFECType ,    
      dvz.FecCode,      
        lra.FundPool,
        payb.AnnualSimpleProfitRate,
      payb.AnnualCompoundProfitRate,        
        prwk.ParamDescription,      
        lra.RediscountAmount ,
        lra.RediscountAmountTL,
        lra.TranBranch AS TranBranchId ,
        b.Name AS TranBranchName ,
        lra.TranDate ,
        lra.BusinessKey,
        --lra.TranReference,  /* Gün İçi Raporu için Interim tablosunda alan bulunmadığından NULL olarak beslendi. t.ms250005 -- 2025-04-30 */
        null as TranReference, /* Gün İçi Raporu için Interim tablosunda alan bulunmadığından NULL olarak beslendi. t.ms250005 -- 2025-04-30 */
      p1.ParamDescription AS 'FundPoolDesc',
      p2.ParamDescription AS 'LoanTypeDesc',
      prme.ParamDescription AS SpecialPool
      ,
      (CASE WHEN p.AgreementType = 3 
         Then  mtxl.Rediscount5
         Else  mtx.Rediscount5 END)
         AS Rediscount5 ,
         (CASE WHEN p.AgreementType = 3 
         Then  mtxl.Rediscount2
         Else  mtx.Rediscount2 END)
         AS Rediscount2,
      (lra.RediscountAmount-ISNULL(lr.RediscountAmount,0)) DailyRediscount,
      (lra.RediscountAmountTL-ISNULL(lr.RediscountAmountTL,0)) DailyRediscountTL 
    FROM  BOA.LNS.LoanRediscountAdvanceInterim lra WITH (NOLOCK)
      INNER JOIN  BOA.COR.Branch          AS b  WITH (NOLOCK) ON b.BranchId=lra.TranBranch
      INNER JOIN  boa.lns.Project          AS p  WITH (NOLOCK) ON p.AccountNumber = lra.AccountNumber AND p.AccountSuffix = lra.AccountSuffix
      INNER JOIN  BOA.cor.[Parameter]        AS p1  WITH (NOLOCK) ON p1.ParamType ='HPGRB2Y'   AND p1.LanguageId=@languageId AND p1.ParamCode = lra.FundPool  
      INNER JOIN  BOA.COR.ProductLoanProperty    AS plp  WITH (NOLOCK) ON plp.ProductCode = p.ProductCode AND plp.CustomerClass = p.CustomerClass AND plp.PersonType = p.PersonType
      INNER JOIN  BOA.cor.[Parameter]        AS p2  WITH (NOLOCK) ON p2.ParamType ='HPRDGRUPY'   AND  p2.LanguageId=@languageId AND p2.ParamCode = plp.LoanType
      LEFT JOIN  BOA.lns.ProjectExtension    AS pe  WITH (NOLOCK) ON pe.ProjectId = p.ProjectId AND pe.ProjectExtensionType = 5
      LEFT JOIN  BOA.cor.[Parameter]        AS prme  WITH (NOLOCK) ON prme.ParamType ='YATVEKHAVUZ'   AND  prme.LanguageId=@languageId AND prme.ParamCode = pe.ReferenceId
          LEFT JOIN   boa.cor.Parameter               AS prwk WITH (NOLOCK) ON prwk.ParamType ='WAKALAPOOLTYPE' and prwk.ParamCode = p.FundPoolDetail 
      INNER JOIN  BOA.Cor.Account          AS a    WITH (NOLOCK) ON a.AccountNumber =lra.AccountNumber and a.AccountSuffix =lra.AccountSuffix
      INNER JOIN boa.cor.fec                       AS  dvz   WITH (NOLOCK) ON dvz.FecId = p.DebtFEC
      INNER JOIN BOA.lns.ProjectPayBackPlan       AS payb   WITH (NOLOCK) ON payb.ProjectId = p.ProjectId 
      LEFT JOIN  BOA.LNS.LoanRediscountAdvanceInterim  AS lr  WITH (NOLOCK) ON lr.TranDate = lra.Trandate-1 and lra.AccountNumber = lr.AccountNumber and lra.AccountSuffix = lr.AccountSuffix
    OUTER APPLY ( 
    SELECT 
                ma.MainLedgerId,
                MAX(CASE WHEN ma.ColumnNo = 1 THEN ma.LedgerId ELSE 0 END) AS Rediscount5,
                MAX(CASE WHEN ma.ColumnNo = 6 THEN ma.LedgerId ELSE 0 END) AS Rediscount2
            FROM boa.acc.MatrixAccounts ma WITH (NOLOCK) WHERE ma.TableNo = 2 and ma.MainLedgerId= a.LedgerId and ma.ColumnNo IN (1,6)
            GROUP by ma.MainLedgerId
       ) mtx
      OUTER APPLY ( 
            SELECT 
                ma.MainLedgerId,
                MAX(CASE WHEN ma.ColumnNo = 10 THEN ma.LedgerId ELSE 0 END) AS Rediscount5,
                MAX(CASE WHEN ma.ColumnNo = 7 THEN ma.LedgerId ELSE 0 END) AS Rediscount2
            FROM boa.acc.MatrixAccounts ma WITH (NOLOCK) WHERE ma.TableNo = 5 and ma.MainLedgerId= a.LedgerId and ma.ColumnNo IN (10,7)
            GROUP by ma.MainLedgerId
       ) mtxl
    WHERE
        lra.AccountNumber= (CASE WHEN @AccountNumber IS NULL THEN lra.AccountNumber ELSE @AccountNumber END) AND
        lra.AccountSuffix= (CASE WHEN @AccountSuffix IS NULL THEN lra.AccountSuffix ELSE @AccountSuffix END) AND
        lra.TranBranch= (CASE WHEN @BranchId IS NULL THEN lra.TranBranch ELSE @BranchId END) AND
        lra.TranDate BETWEEN @DateBegin AND @DateEnd
  END
END