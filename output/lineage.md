# rpt_LoanRediscountAdvanceInterim.sql

## LNS.rpt_LoanRediscountAdvanceInterim

| Output | Sources | Operations | Branches |
| --- | --- | --- | --- |
| AccountNumber | lra.AccountNumber [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 24)<br>select@line:92 (line 93) |
| AccountSuffix | lra.AccountSuffix [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 25)<br>select@line:92 (line 94) |
| AnnualCompoundProfitRate | payb.AnnualCompoundProfitRate [BOA.lns.ProjectPayBackPlan] |  | select@line:23 (line 41)<br>select@line:92 (line 102) |
| AnnualSimpleProfitRate | payb.AnnualSimpleProfitRate [BOA.lns.ProjectPayBackPlan] |  | select@line:23 (line 40)<br>select@line:92 (line 101) |
| BusinessKey | lra.BusinessKey [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 37)<br>select@line:92 (line 109) |
| DailyRediscount | lr.RediscountAmount [BOA.LNS.LoanRediscountAdvanceInterim]<br>lra.RediscountAmount [BOA.LNS.LoanRediscountAdvanceInterim] | ISNULL, Subtract | select@line:23 (line 54)<br>select@line:92 (line 124) |
| DailyRediscountTL | lr.RediscountAmountTL [BOA.LNS.LoanRediscountAdvanceInterim]<br>lra.RediscountAmountTL [BOA.LNS.LoanRediscountAdvanceInterim] | ISNULL, Subtract | select@line:23 (line 55)<br>select@line:92 (line 125) |
| FecCode | dvz.FecCode [boa.cor.fec] |  | select@line:23 (line 30)<br>select@line:92 (line 99) |
| FundPool | lra.FundPool [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 31)<br>select@line:92 (line 100) |
| FundPoolDesc | p1.ParamDescription [BOA.cor.Parameter] |  | select@line:23 (line 43)<br>select@line:92 (line 112) |
| LedgerId | lra.LedgerId [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 28)<br>select@line:92 (line 97) |
| LoanMaturityType | lra.LoanMaturityType [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 26)<br>select@line:92 (line 95) |
| LoanRediscountAdvanceInterimId | lra.LoanRediscountAdvanceInterimId [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 23)<br>select@line:92 (line 92) |
| LoanType | lra.LoanType [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 27)<br>select@line:92 (line 96) |
| LoanTypeDesc | p2.ParamDescription [BOA.cor.Parameter] |  | select@line:23 (line 44)<br>select@line:92 (line 113) |
| ParamDescription | prwk.ParamDescription [boa.cor.Parameter] |  | select@line:23 (line 42)<br>select@line:92 (line 103) |
| ProjectFECType | lra.ProjectFECType [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 29)<br>select@line:92 (line 98) |
| Rediscount2 | mtx.Rediscount2 [?] <= MAX(CASE WHEN ma.ColumnNo = 6 THEN ma.LedgerId ELSE 0 END)<br>mtxl.Rediscount2 [?] <= MAX(CASE WHEN ma.ColumnNo = 7 THEN ma.LedgerId ELSE 0 END)<br>p.AgreementType [boa.lns.Project] | CASE | select@line:23 (line 50)<br>select@line:92 (line 120) |
| Rediscount5 | mtx.Rediscount5 [?] <= MAX(CASE WHEN ma.ColumnNo = 1 THEN ma.LedgerId ELSE 0 END)<br>mtxl.Rediscount5 [?] <= MAX(CASE WHEN ma.ColumnNo = 10 THEN ma.LedgerId ELSE 0 END)<br>p.AgreementType [boa.lns.Project] | CASE | select@line:23 (line 46)<br>select@line:92 (line 116) |
| RediscountAmount | lra.RediscountAmount [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 32)<br>select@line:92 (line 104) |
| RediscountAmountTL | lra.RediscountAmountTL [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 33)<br>select@line:92 (line 105) |
| SpecialPool | prme.ParamDescription [BOA.cor.Parameter] |  | select@line:23 (line 45)<br>select@line:92 (line 114) |
| TranBranchId | lra.TranBranch [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 34)<br>select@line:92 (line 106) |
| TranBranchName | b.Name [BOA.COR.Branch] |  | select@line:23 (line 35)<br>select@line:92 (line 107) |
| TranDate | lra.TranDate [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 36)<br>select@line:92 (line 108) |
| TranReference |  |  | select@line:23 (line 39)<br>select@line:92 (line 111) |
