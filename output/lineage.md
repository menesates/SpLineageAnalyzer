# rpt_BranchOperationalKpiComplex.sql

## RPT.rpt_BranchOperationalKpiComplex

| Output | Sources | Operations | Branches |
| --- | --- | --- | --- |
| AtmCount | cm.AtmCount [#ChannelMix]<br>tr.ChannelCode [BOA.OPR.BranchTransaction] | CASE, SUM | select@line:92 (line 95)<br>select@line:106 (line 125) |
| AvgActiveCustomerCount | bk.ActiveCustomerCount [#BranchKpi] | AVG, CAST, DECIMAL | select@line:106 (line 122) |
| AvgWeightedScore | bk.WeightedScore [#BranchKpi] | AVG | select@line:106 (line 123) |
| BranchId | br.BranchId [BOA.COR.Branch]<br>tr.BranchId [BOA.OPR.BranchTransaction] |  | select@line:92 (line 93)<br>select@line:106 (line 109) |
| BranchName | br.Name [BOA.COR.Branch] |  | select@line:106 (line 110) |
| CashInTL | bk.CashInTL [#BranchKpi] | SUM | select@line:106 (line 119) |
| CashOutTL | bk.CashOutTL [#BranchKpi] | SUM | select@line:106 (line 120) |
| ComplaintCount | bk.ComplaintCount [#BranchKpi] | SUM | select@line:106 (line 115) |
| DigitalAssistedCount | bk.DigitalAssistedCount [#BranchKpi] | SUM | select@line:106 (line 114) |
| DigitalChannelRatio | cm.InternetCount [#ChannelMix]<br>cm.MobileCount [#ChannelMix]<br>cm.TotalCount [#ChannelMix] | Add, CAST, DECIMAL, Divide, NULLIF | select@line:106 (line 129) |
| ExpenseLimitUsageRatio | bk.TotalExpenseTL [#BranchKpi]<br>target.MonthlyExpenseLimitTL [Derived: target] <= bt.MonthlyExpenseLimitTL | CAST, DECIMAL, Divide, NULLIF, SUM | select@line:106 (line 134) |
| FeeIncomeTL | bk.FeeIncomeTL [#BranchKpi] | SUM | select@line:106 (line 118) |
| FeeTargetRealizationRatio | bk.FeeIncomeTL [#BranchKpi]<br>target.MonthlyFeeTargetTL [Derived: target] <= bt.MonthlyFeeTargetTL | CAST, DECIMAL, Divide, NULLIF, SUM | select@line:106 (line 133) |
| InternetCount | cm.InternetCount [#ChannelMix]<br>tr.ChannelCode [BOA.OPR.BranchTransaction] | CASE, SUM | select@line:92 (line 97)<br>select@line:106 (line 127) |
| ManagerEmployeeNumber | mgr.EmployeeNumber [BOA.HR.Employee] |  | select@line:106 (line 111) |
| ManagerName | mgr.FullName [BOA.HR.Employee] |  | select@line:106 (line 112) |
| ManualCorrectionCount | cm.ManualCorrectionCount [#ChannelMix]<br>tr.IsManualCorrection [BOA.OPR.BranchTransaction] | CASE, SUM | select@line:92 (line 99)<br>select@line:106 (line 128) |
| ManualCorrectionRatio | cm.ManualCorrectionCount [#ChannelMix]<br>cm.TotalCount [#ChannelMix] | CAST, DECIMAL, Divide, NULLIF | select@line:106 (line 130) |
| MobileCount | cm.MobileCount [#ChannelMix]<br>tr.ChannelCode [BOA.OPR.BranchTransaction] | CASE, SUM | select@line:92 (line 96)<br>select@line:106 (line 126) |
| MonthlyExpenseLimitTL | target.MonthlyExpenseLimitTL [Derived: target] <= bt.MonthlyExpenseLimitTL |  | select@line:106 (line 132) |
| MonthlyFeeTargetTL | target.MonthlyFeeTargetTL [Derived: target] <= bt.MonthlyFeeTargetTL |  | select@line:106 (line 131) |
| NetCashFlowTL | bk.CashInTL [#BranchKpi]<br>bk.CashOutTL [#BranchKpi] | Subtract, SUM | select@line:106 (line 121) |
| OperationalRiskBand | perf.OperationalRiskBand [Derived: perf] <= CASE
                    WHEN SUM(bk2.ComplaintCount + bk2.SlaBreachCount) > 100 THEN 'Critical'
                    WHEN SUM(bk2.ComplaintCount + bk2.SlaBreachCount) > 25 THEN 'Watch'
                    ELSE 'Normal'
                END |  | select@line:106 (line 136) |
| PerformanceBand | perf.PerformanceBand [Derived: perf] <= CASE
                    WHEN SUM(bk2.WeightedScore) > 100000 THEN 'High'
                    WHEN SUM(bk2.WeightedScore) > 25000 THEN 'Medium'
                    ELSE 'Low'
                END |  | select@line:106 (line 135) |
| RegionId | reg.RegionId [BOA.COR.Region] |  | select@line:106 (line 107) |
| RegionName | reg.RegionName [BOA.COR.Region] |  | select@line:106 (line 108) |
| ReportBeginDate |  |  | select@line:106 (line 137) |
| ReportEndDate |  |  | select@line:106 (line 138) |
| SlaBreachCount | bk.SlaBreachCount [#BranchKpi] | SUM | select@line:106 (line 116) |
| TellerCount | cm.TellerCount [#ChannelMix]<br>tr.ChannelCode [BOA.OPR.BranchTransaction] | CASE, SUM | select@line:92 (line 94)<br>select@line:106 (line 124) |
| TellerTranCount | bk.TellerTranCount [#BranchKpi] | SUM | select@line:106 (line 113) |
| TotalCount |  | COUNT_BIG, Multiply | select@line:92 (line 98) |
| TotalExpenseTL | bk.TotalExpenseTL [#BranchKpi] | SUM | select@line:106 (line 117) |
# rpt_CreditPortfolioRiskComplex.sql

## RPT.rpt_CreditPortfolioRiskComplex

| Output | Sources | Operations | Branches |
| --- | --- | --- | --- |
| AccruedInterestTL | lb.AccruedInterestTL [#LoanBase] |  | select@line:115 (line 123) |
| BranchId | b.BranchId [BOA.COR.Branch]<br>lb.BranchId [#LoanBase] |  | select@line:115 (line 118)<br>select@line:155 (line 156) |
| BranchName | b.Name [BOA.COR.Branch] |  | select@line:155 (line 157) |
| CollateralCoverageRatio | ca.EligibleCollateralTL [#CollateralAgg]<br>lb.AccruedInterestTL [#LoanBase]<br>lb.PrincipalBalanceTL [#LoanBase] | Add, CAST, DECIMAL, Divide, ISNULL, NULLIF | select@line:115 (line 126) |
| CurrencyCode | lb.CurrencyCode [#LoanBase] |  | select@line:115 (line 121) |
| CustomerCount | rb.CustomerId [#RiskBucket] | COUNT | select@line:155 (line 161) |
| CustomerExposureRank | lb.CustomerId [#LoanBase]<br>lb.PrincipalBalanceTL [#LoanBase] | ROW_NUMBER | select@line:115 (line 139) |
| CustomerId | lb.CustomerId [#LoanBase] |  | select@line:115 (line 117) |
| EarlyDelayExposureTL | rb.AccruedInterestTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket]<br>rb.RiskBucketCode [#RiskBucket] | Add, CASE, SUM | select@line:155 (line 170) |
| EligibleCollateralTL | ca.EligibleCollateralTL [#CollateralAgg]<br>rb.EligibleCollateralTL [#RiskBucket] | ISNULL, SUM | select@line:115 (line 125)<br>select@line:155 (line 166) |
| LoanAccountId | lb.LoanAccountId [#LoanBase] |  | select@line:115 (line 116) |
| LoanCount |  | COUNT_BIG, Multiply | select@line:155 (line 160) |
| NplExposureTL | rb.AccruedInterestTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket]<br>rb.RiskBucketCode [#RiskBucket] | Add, CASE, SUM | select@line:155 (line 168) |
| NplRatio | rb.AccruedInterestTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket]<br>rb.RiskBucketCode [#RiskBucket] | Add, CASE, CAST, DECIMAL, Divide, NULLIF, SUM | select@line:155 (line 171) |
| PortfolioCollateralCoverageRatio | rb.AccruedInterestTL [#RiskBucket]<br>rb.EligibleCollateralTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket] | Add, CAST, DECIMAL, Divide, NULLIF, SUM | select@line:155 (line 167) |
| PrincipalBalanceTL | lb.PrincipalBalanceTL [#LoanBase] |  | select@line:115 (line 122) |
| ProductCode | lb.ProductCode [#LoanBase] |  | select@line:115 (line 119) |
| ProductGroup | lb.ProductGroup [#LoanBase]<br>rb.ProductGroup [#RiskBucket] |  | select@line:115 (line 120)<br>select@line:155 (line 158) |
| ProductGroupName | prm.ParamDescription [BOA.COR.Parameter] |  | select@line:155 (line 159) |
| ProvisionRate | lb.DaysPastDue [#LoanBase]<br>lb.StageCode [#LoanBase] | CASE | select@line:115 (line 133) |
| ReportDate |  |  | select@line:155 (line 178) |
| RequiredProvisionTL | rb.AccruedInterestTL [#RiskBucket]<br>rb.EligibleCollateralTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket]<br>rb.ProvisionRate [#RiskBucket] | Add, Multiply, Subtract, SUM | select@line:155 (line 173) |
| RiskBucketCode | lb.DaysPastDue [#LoanBase]<br>lb.StageCode [#LoanBase] | CASE | select@line:115 (line 127) |
| TopCustomerExposureTL | concentration.TopCustomerExposureTL [Derived: concentration] <= MAX(cx.CustomerExposureTL) |  | select@line:155 (line 175) |
| TopLoanAvgCoverageRatio | rb.CollateralCoverageRatio [#RiskBucket]<br>rb.CustomerExposureRank [#RiskBucket] | AVG, CASE | select@line:155 (line 174) |
| TopTenConcentrationRatio | concentration.TopTenCustomerExposureTL [Derived: concentration] <= SUM(CASE WHEN cx.ExposureRank <= 10 THEN cx.CustomerExposureTL ELSE 0 END)<br>rb.AccruedInterestTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket] | Add, CAST, DECIMAL, Divide, NULLIF, SUM | select@line:155 (line 177) |
| TopTenCustomerExposureTL | concentration.TopTenCustomerExposureTL [Derived: concentration] <= SUM(CASE WHEN cx.ExposureRank <= 10 THEN cx.CustomerExposureTL ELSE 0 END) |  | select@line:155 (line 176) |
| TotalAccruedInterestTL | rb.AccruedInterestTL [#RiskBucket] | SUM | select@line:155 (line 163) |
| TotalCollateralTL | ca.TotalCollateralTL [#CollateralAgg]<br>rb.TotalCollateralTL [#RiskBucket] | ISNULL, SUM | select@line:115 (line 124)<br>select@line:155 (line 165) |
| TotalExposureTL | rb.AccruedInterestTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket] | Add, SUM | select@line:155 (line 164) |
| TotalPrincipalTL | rb.PrincipalBalanceTL [#RiskBucket] | SUM | select@line:155 (line 162) |
| WatchListExposureTL | rb.AccruedInterestTL [#RiskBucket]<br>rb.PrincipalBalanceTL [#RiskBucket]<br>rb.RiskBucketCode [#RiskBucket] | Add, CASE, SUM | select@line:155 (line 169) |
# rpt_CustomerProfitabilityComplex.sql

## RPT.rpt_CustomerProfitabilityComplex

| Output | Sources | Operations | Branches |
| --- | --- | --- | --- |
| BalanceRole | dc.DepositBalanceTL [CTE: DepositCost] <= SUM(CASE WHEN d.CurrencyCode = 'TRY' THEN d.Balance ELSE d.Balance * fx.BidRate END)<br>li.LoanBalanceTL [CTE: LoanIncome] <= SUM(CASE WHEN l.CurrencyCode = 'TRY' THEN l.PrincipalBalance ELSE l.PrincipalBalance * fx.BidRate END) | CASE, ISNULL | select@line:31 (line 175) |
| BranchFeeIncome | fi.BranchFeeIncome [CTE: FeeIncome] <= SUM(CASE WHEN ft.ChannelCode = 'BRANCH' THEN ft.AmountTL ELSE 0 END) | ISNULL | select@line:31 (line 157) |
| BranchId | cb.BranchId [CTE: CustomerBase] <= c.BranchId |  | select@line:31 (line 141) |
| BranchName | cb.BranchName [CTE: CustomerBase] <= b.Name |  | select@line:31 (line 142) |
| CustomerClass | cb.CustomerClass [CTE: CustomerBase] <= c.CustomerClass |  | select@line:31 (line 147) |
| CustomerName | cb.CustomerName [CTE: CustomerBase] <= c.CustomerName |  | select@line:31 (line 146) |
| CustomerNumber | cb.CustomerNumber [CTE: CustomerBase] <= c.CustomerNumber |  | select@line:31 (line 145) |
| DepositBalanceTL | dc.DepositBalanceTL [CTE: DepositCost] <= SUM(CASE WHEN d.CurrencyCode = 'TRY' THEN d.Balance ELSE d.Balance * fx.BidRate END) | ISNULL | select@line:31 (line 151) |
| DepositRediscountExpense | dc.DepositRediscountExpense [CTE: DepositCost] <= SUM(ISNULL(ia.RediscountExpenseAmount, 0)) | ISNULL | select@line:31 (line 155) |
| DigitalFeeIncome | fi.DigitalFeeIncome [CTE: FeeIncome] <= SUM(CASE WHEN ft.ChannelCode IN ('MOBILE', 'INTERNET') THEN ft.AmountTL ELSE 0 END) | ISNULL | select@line:31 (line 158) |
| DigitalVolumeRatio | pv.DigitalVolumeTL [CTE: PaymentVolume] <= SUM(CASE WHEN tr.ChannelCode IN ('MOBILE', 'INTERNET', 'ATM') THEN ABS(tr.AmountTL) ELSE 0 END)<br>pv.TotalTransactionVolumeTL [CTE: PaymentVolume] <= SUM(ABS(tr.AmountTL)) | CAST, DECIMAL, Divide, ISNULL, NULLIF | select@line:31 (line 161) |
| DigitalVolumeTL | pv.DigitalVolumeTL [CTE: PaymentVolume] <= SUM(CASE WHEN tr.ChannelCode IN ('MOBILE', 'INTERNET', 'ATM') THEN ABS(tr.AmountTL) ELSE 0 END) | ISNULL | select@line:31 (line 160) |
| ExpectedLossAmount | risk.ExpectedLossAmount [Derived: risk] <= ISNULL(li.LoanBalanceTL, 0) *
                    CASE
                        WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 0.45
                        WHEN cb.CustomerClass IN ('CORP', 'COMM') THEN 0.08
                        ELSE 0.03
                    END |  | select@line:31 (line 164) |
| InterestExpense | dc.InterestExpense [CTE: DepositCost] <= SUM(ISNULL(ia.InterestExpenseAmount, 0)) | ISNULL | select@line:31 (line 154) |
| InterestIncome | li.InterestIncome [CTE: LoanIncome] <= SUM(ISNULL(accr.InterestAccrualAmount, 0)) | ISNULL | select@line:31 (line 152) |
| LoanBalanceTL | li.LoanBalanceTL [CTE: LoanIncome] <= SUM(CASE WHEN l.CurrencyCode = 'TRY' THEN l.PrincipalBalance ELSE l.PrincipalBalance * fx.BidRate END) | ISNULL | select@line:31 (line 150) |
| NetFeeIncome | fi.NetFeeIncome [CTE: FeeIncome] <= SUM(CASE WHEN ft.FeeDirection = 'C' THEN ft.AmountTL ELSE -1 * ft.AmountTL END) | ISNULL | select@line:31 (line 156) |
| NetProfitTL | dc.DepositRediscountExpense [CTE: DepositCost] <= SUM(ISNULL(ia.RediscountExpenseAmount, 0))<br>dc.InterestExpense [CTE: DepositCost] <= SUM(ISNULL(ia.InterestExpenseAmount, 0))<br>fi.NetFeeIncome [CTE: FeeIncome] <= SUM(CASE WHEN ft.FeeDirection = 'C' THEN ft.AmountTL ELSE -1 * ft.AmountTL END)<br>li.InterestIncome [CTE: LoanIncome] <= SUM(ISNULL(accr.InterestAccrualAmount, 0))<br>li.RediscountIncome [CTE: LoanIncome] <= SUM(ISNULL(accr.RediscountAmount, 0))<br>risk.ExpectedLossAmount [Derived: risk] <= ISNULL(li.LoanBalanceTL, 0) *
                    CASE
                        WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 0.45
                        WHEN cb.CustomerClass IN ('CORP', 'COMM') THEN 0.08
                        ELSE 0.03
                    END | Add, ISNULL, Subtract | select@line:31 (line 167) |
| PortfolioId | cb.PortfolioId [CTE: CustomerBase] <= p.PortfolioId |  | select@line:31 (line 143) |
| PortfolioName | cb.PortfolioName [CTE: CustomerBase] <= p.PortfolioName |  | select@line:31 (line 144) |
| ProfitabilityGrade | score.ProfitabilityGrade [Derived: score] <= CASE
                    WHEN (
                        ISNULL(li.InterestIncome, 0)
                        + ISNULL(fi.NetFeeIncome, 0)
                        - ISNULL(dc.InterestExpense, 0)
                        - ISNULL(risk.ExpectedLossAmount, 0)
                    ) > 100000 THEN 'A'
                    WHEN ISNULL(fi.NetFeeIncome, 0) > 25000 THEN 'B'
                    WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 'D'
                    ELSE 'C'
                END |  | select@line:31 (line 166) |
| ProfitabilityGroup | cb.ProfitabilityGroup [CTE: CustomerBase] <= CASE
                WHEN c.CustomerClass IN ('CORP', 'COMM') THEN 'Commercial'
                WHEN c.CustomerClass IN ('PRIV', 'VIP') THEN 'Private'
                ELSE 'Retail'
            END |  | select@line:31 (line 149) |
| ProfitabilityScore | score.ProfitabilityScore [Derived: score] <= (
                    ISNULL(li.InterestIncome, 0)
                    + ISNULL(fi.NetFeeIncome, 0)
                    - ISNULL(dc.InterestExpense, 0)
                    - ISNULL(risk.ExpectedLossAmount, 0)
                ) / NULLIF(ISNULL(li.LoanBalanceTL, 0) + ISNULL(dc.DepositBalanceTL, 0), 0) |  | select@line:31 (line 165) |
| RediscountIncome | li.RediscountIncome [CTE: LoanIncome] <= SUM(ISNULL(accr.RediscountAmount, 0)) | ISNULL | select@line:31 (line 153) |
| ReportBeginDate |  |  | select@line:31 (line 180) |
| ReportEndDate |  |  | select@line:31 (line 181) |
| RiskWeight | risk.RiskWeight [Derived: risk] <= CASE
                    WHEN ISNULL(li.Stage3Balance, 0) > 0 THEN 1.00
                    WHEN cb.CustomerClass IN ('CORP', 'COMM') THEN 0.55
                    WHEN ISNULL(li.LoanBalanceTL, 0) > 5000000 THEN 0.75
                    ELSE 0.35
                END |  | select@line:31 (line 163) |
| SegmentName | cb.SegmentName [CTE: CustomerBase] <= seg.ParamDescription |  | select@line:31 (line 148) |
| Stage3LoanRatio | li.LoanBalance [CTE: LoanIncome] <= SUM(l.PrincipalBalance)<br>li.Stage3Balance [CTE: LoanIncome] <= SUM(CASE WHEN l.StageCode = 3 THEN l.PrincipalBalance ELSE 0 END) | CAST, DECIMAL, Divide, ISNULL, NULLIF | select@line:31 (line 162) |
| TotalTransactionVolumeTL | pv.TotalTransactionVolumeTL [CTE: PaymentVolume] <= SUM(ABS(tr.AmountTL)) | ISNULL | select@line:31 (line 159) |
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
| Rediscount2 | mtx.Rediscount2 [Derived: mtx] <= MAX(CASE WHEN ma.ColumnNo = 6 THEN ma.LedgerId ELSE 0 END)<br>mtxl.Rediscount2 [Derived: mtxl] <= MAX(CASE WHEN ma.ColumnNo = 7 THEN ma.LedgerId ELSE 0 END)<br>p.AgreementType [boa.lns.Project] | CASE | select@line:23 (line 50)<br>select@line:92 (line 120) |
| Rediscount5 | mtx.Rediscount5 [Derived: mtx] <= MAX(CASE WHEN ma.ColumnNo = 1 THEN ma.LedgerId ELSE 0 END)<br>mtxl.Rediscount5 [Derived: mtxl] <= MAX(CASE WHEN ma.ColumnNo = 10 THEN ma.LedgerId ELSE 0 END)<br>p.AgreementType [boa.lns.Project] | CASE | select@line:23 (line 46)<br>select@line:92 (line 116) |
| RediscountAmount | lra.RediscountAmount [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 32)<br>select@line:92 (line 104) |
| RediscountAmountTL | lra.RediscountAmountTL [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 33)<br>select@line:92 (line 105) |
| SpecialPool | prme.ParamDescription [BOA.cor.Parameter] |  | select@line:23 (line 45)<br>select@line:92 (line 114) |
| TranBranchId | lra.TranBranch [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 34)<br>select@line:92 (line 106) |
| TranBranchName | b.Name [BOA.COR.Branch] |  | select@line:23 (line 35)<br>select@line:92 (line 107) |
| TranDate | lra.TranDate [BOA.LNS.LoanRediscountAdvanceInterim] |  | select@line:23 (line 36)<br>select@line:92 (line 108) |
| TranReference |  |  | select@line:23 (line 39)<br>select@line:92 (line 111) |
# rpt_TreasuryFxLiquidityComplex.sql

## RPT.rpt_TreasuryFxLiquidityComplex

| Output | Sources | Operations | Branches |
| --- | --- | --- | --- |
| BankingPositionAmount | pb.BankingPositionAmount [CTE: PositionBase] <= SUM(CASE WHEN pos.PositionType = 'BANKING' THEN pos.CurrentPositionAmount ELSE 0 END) | ISNULL | select@line:24 (line 157) |
| Bucket1M | af.Bucket1M [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = '1M' THEN bf.SignedCashFlow ELSE 0 END) | ISNULL | select@line:24 (line 160) |
| Bucket1W | af.Bucket1W [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = '1W' THEN bf.SignedCashFlow ELSE 0 END) | ISNULL | select@line:24 (line 159) |
| Bucket3M | af.Bucket3M [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = '3M' THEN bf.SignedCashFlow ELSE 0 END) | ISNULL | select@line:24 (line 161) |
| Bucket6M | af.Bucket6M [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = '6M' THEN bf.SignedCashFlow ELSE 0 END) | ISNULL | select@line:24 (line 162) |
| Bucket6MPlus | af.Bucket6MPlus [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = '6M+' THEN bf.SignedCashFlow ELSE 0 END) | ISNULL | select@line:24 (line 163) |
| BucketON | af.BucketON [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = 'ON' THEN bf.SignedCashFlow ELSE 0 END) | ISNULL | select@line:24 (line 158) |
| CurrencyCode | pb.CurrencyCode [CTE: PositionBase] <= pos.CurrencyCode |  | select@line:24 (line 153) |
| CurrentPositionAmount | pb.CurrentPositionAmount [CTE: PositionBase] <= SUM(pos.CurrentPositionAmount) | ISNULL | select@line:24 (line 154) |
| CurrentPositionTL | pb.CurrentPositionTL [CTE: PositionBase] <= SUM(pos.CurrentPositionAmount * fx.BidRate) | ISNULL | select@line:24 (line 155) |
| DeskCode | pb.DeskCode [CTE: PositionBase] <= pos.DeskCode |  | select@line:24 (line 151) |
| DeskName | desk.DeskName [BOA.TRE.TreasuryDesk] |  | select@line:24 (line 152) |
| EstimatedVarTL | varCalc.EstimatedVarTL [Derived: varCalc] <= SQRT(SUM(hist.ReturnRate * hist.ReturnRate) / NULLIF(COUNT_BIG(*), 0))
                    * ABS(ISNULL(pb.CurrentPositionTL, 0)) * 2.33 |  | select@line:24 (line 178) |
| LimitBreachFlag | af.TotalForwardCashFlow [CTE: AggregatedFlow] <= SUM(bf.SignedCashFlow)<br>limitDef.PositionLimitAmount [Derived: limitDef] <= lim.PositionLimitAmount<br>pb.CurrentPositionAmount [CTE: PositionBase] <= SUM(pos.CurrentPositionAmount) | ABS, Add, CASE, ISNULL | select@line:24 (line 174) |
| LiquiditySurvivalRatio | af.TotalForwardCashFlow [CTE: AggregatedFlow] <= SUM(bf.SignedCashFlow)<br>pb.CurrentPositionAmount [CTE: PositionBase] <= SUM(pos.CurrentPositionAmount)<br>stress.StressedOutflowAmount [Derived: stress] <= SUM(CASE WHEN sf.FlowDirection = 'OUT' THEN sf.Amount * sf.StressFactor ELSE 0 END) | ABS, Add, CAST, DECIMAL, Divide, ISNULL, NULLIF | select@line:24 (line 171) |
| OneWeekLiquidityPosition | af.Bucket1W [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = '1W' THEN bf.SignedCashFlow ELSE 0 END)<br>af.BucketON [CTE: AggregatedFlow] <= SUM(CASE WHEN bf.MaturityBucket = 'ON' THEN bf.SignedCashFlow ELSE 0 END)<br>pb.CurrentPositionAmount [CTE: PositionBase] <= SUM(pos.CurrentPositionAmount) | Add, ISNULL | select@line:24 (line 168) |
| PositionLimitAmount | limitDef.PositionLimitAmount [Derived: limitDef] <= lim.PositionLimitAmount |  | select@line:24 (line 173) |
| ProjectedClosingPosition | af.TotalForwardCashFlow [CTE: AggregatedFlow] <= SUM(bf.SignedCashFlow)<br>pb.CurrentPositionAmount [CTE: PositionBase] <= SUM(pos.CurrentPositionAmount) | Add, ISNULL | select@line:24 (line 167) |
| ReportDate |  |  | select@line:24 (line 180) |
| ScenarioCode |  |  | select@line:24 (line 179) |
| StressedInflowAmount | stress.StressedInflowAmount [Derived: stress] <= SUM(CASE WHEN sf.FlowDirection = 'IN' THEN sf.Amount * sf.StressFactor ELSE 0 END) |  | select@line:24 (line 166) |
| StressedOutflowAmount | stress.StressedOutflowAmount [Derived: stress] <= SUM(CASE WHEN sf.FlowDirection = 'OUT' THEN sf.Amount * sf.StressFactor ELSE 0 END) |  | select@line:24 (line 165) |
| TotalForwardCashFlow | af.TotalForwardCashFlow [CTE: AggregatedFlow] <= SUM(bf.SignedCashFlow) | ISNULL | select@line:24 (line 164) |
| TradingPositionAmount | pb.TradingPositionAmount [CTE: PositionBase] <= SUM(CASE WHEN pos.PositionType = 'TRADING' THEN pos.CurrentPositionAmount ELSE 0 END) | ISNULL | select@line:24 (line 156) |
