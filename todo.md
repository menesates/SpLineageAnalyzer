# TODO - SP Lineage JSON ve SQL Script Karşılaştırma Notları

Denetlenen kaynaklar:
- JSON çıktı: `output/lineage.json`
- SQL scriptleri: `sp/*.sql`

## Mevcut Karşılaştırma Sonucu

`output/lineage.json` içindeki output kolon listeleri, her stored procedure içindeki final result-set `SELECT` ifadeleriyle karşılaştırıldı.

| SP dosyası | Final result SELECT | JSON output sayısı | Sonuç |
|---|---:|---:|---|
| `rpt_BranchOperationalKpiComplex.sql` | satır 106 | 32 | OK |
| `rpt_CreditPortfolioRiskComplex.sql` | satır 155 | 22 | OK |
| `rpt_CustomerProfitabilityComplex.sql` | satır 140 | 30 | OK |
| `rpt_LoanRediscountAdvanceInterim.sql` | satır 23 ve 92 | 26 merge edilmiş | OK |
| `rpt_TreasuryFxLiquidityComplex.sql` | satır 150 | 24 | OK |

Ek kontroller:
- Tüm SP dosyaları için JSON diagnostic sayısı `0`.
- JSON içinde unresolved kaynak sayısı `0`.
- `rpt_BranchOperationalKpiComplex.sql`: `SELECT INTO #ChannelMix` artık hatalı şekilde output olarak raporlanmıyor. `TotalCount` final output kolonu değil; ancak oran kolonları için doğru şekilde derived temp kaynak olarak görünüyor.
- `rpt_CreditPortfolioRiskComplex.sql`: `SELECT INTO #RiskBucket` artık hatalı şekilde output olarak raporlanmıyor. `LoanAccountId`, `RiskBucketCode`, `ProvisionRate` gibi internal kolonlar final output listesinde yok.
- JSON, Excel ve console çıktıları final `SELECT` kolon sırasını koruyor.

## Bulunan Konular / Düzeltme TODO

### 1. `COUNT_BIG(*)` yanlışlıkla `Multiply` operasyonu gibi sınıflandırılıyor

Mevcut davranış:
- JSON içinde `COUNT_BIG(*)` kullanılan output kolonlarında operasyon listesine `Multiply` eklenebiliyor.
- Örnek: `rpt_CreditPortfolioRiskComplex.sql` içindeki `LoanCount` output kolonu.

Beklenen davranış:
- `COUNT(*)` veya `COUNT_BIG(*)` içindeki `*`, aritmetik çarpma değil count-all/wildcard söz dizimi olarak değerlendirilmelidir.

Önerilen çözüm:
- `OperationCollector`, aggregate fonksiyonlar içindeki `StarExpression` veya wildcard argümanlarını çarpma operasyonu olarak saymamalı.
- `COUNT(*)` ve `COUNT_BIG(*)` için unit test eklenmeli.

### 2. Predicate lineage ayrı olarak gösterilmiyor

Mevcut davranış:
- Kaynak lineage, output expression ve derived column expression içinden toplanıyor.
- `WHERE`, `JOIN ON`, `HAVING`, `GROUP BY`, `ORDER BY` ve `TOP ORDER BY` bağımlılıkları ayrı bir predicate lineage olarak raporlanmıyor.

Neden önemli:
- Örnek: `rpt_BranchOperationalKpiComplex.sql` içindeki `#BranchKpi`, `br.IsActive`, `br.RegionId`, `br.BranchId`, işlem tarihleri ve işlem statüsü gibi filtrelere bağlı.
- Örnek: `rpt_CreditPortfolioRiskComplex.sql` içindeki `#LoanBase`, aktiflik tarih aralıkları ve ürün/şube filtrelerine bağlı.
- Output değer formülü doğru görünse de, satırların hangi koşullarla oluştuğu tam görünmüyor.

Önerilen çözüm:
- Output/source/derived column seviyesinde `Predicates` veya `Conditions` bölümü eklenmeli.
- `WHERE`, `JOIN ON`, `HAVING`, `TOP ORDER BY` ve `GROUP BY` içindeki kaynaklar toplanmalı.
- Predicate referansları, değer formülü kaynaklarından ayrı işaretlenmeli; böylece rapor okunabilir kalır.

### 3. Temp tablo `UPDATE` lineage final SET ifadesini yakalıyor, fakat mutation geçmişini açık versiyonlar olarak göstermiyor

Mevcut davranış:
- `rpt_CreditPortfolioRiskComplex.sql`, `#RiskBucket.ProvisionRate` kolonunu update ediyor.
- JSON şu anda güncellenmiş `CASE ... rb.ProvisionRate * ...` formülünü raporluyor ve önceki temp kolonlarına zincirliyor.
- Ancak lineage bunu açık bir versiyon geçmişi olarak göstermiyor. Örneğin `ProvisionRate initial formula` ve ardından `ProvisionRate updated formula` gibi ayrı adımlar yok.

Beklenen davranış:
- Denetim amaçlı raporlarda `UPDATE` ile değişen temp kolonları, işlem sırasına göre mutation adımlarıyla gösterilmeli.

Önerilen çözüm:
- `DerivedColumn.Mutations` veya benzeri bir model eklenmeli:
  - `Initial: SELECT INTO #RiskBucket`
  - `Update: UPDATE rb SET ProvisionRate = ...`
- Bu mutation adımları JSON ve Excel çıktısında gösterilmeli.

### 4. `INSERT INTO #temp SELECT` eşlemesi şema/sıra bilgisine bağlı; ordinal kanıtı görünür olmalı

Mevcut davranış:
- `INSERT INTO #LoanBase SELECT ...` ve `INSERT INTO #CollateralAgg SELECT ...`, explicit insert column list olmadığı için hedef tablo kolon sırasına göre eşleniyor.
- Mevcut örneklerde bu eşleme doğru görünüyor.

Risk:
- Gelecekte 2000-3000 satırlık SP'lerde eksik veya sırası değişmiş kolonlar sessizce yanıltıcı lineage üretebilir.

Önerilen çözüm:
- Temp lineage kolonları için `TargetOrdinal` ve `SelectOrdinal` bilgisi tutulmalı.
- Hedef kolon sayısı ve select expression sayısı farklıysa warning üretilmeli.
- Explicit insert column list ve insert/select sayısı uyuşmazlığı için test eklenmeli.

### 5. `SELECT *` output expansion desteklenmiyor

Mevcut durum:
- Şu anki örnek SP'lerde final output olarak `SELECT *` kullanılmıyor.

Risk:
- Gelecekteki rapor SP'lerinde özellikle temp tablo üzerinden `SELECT t.*` kullanımı gelebilir.

Önerilen çözüm:
- `SELECT *` bilinen bir temp tablo/CTE/derived table üzerinden geliyorsa, bilinen derived kolonlarla expand edilmeli.
- Base table metadata yoksa wildcard kaynak `unresolved=true` olarak korunmalı ve diagnostic warning eklenmeli.

### 6. Dynamic SQL ve çağrılan SP result lineage desteklenmiyor

Mevcut durum:
- `rpt_BranchOperationalKpiComplex.sql`, `EXEC BOA.RPT.usp_PrepareBranchKpiSnapshot ...` çağrısı içeriyor.
- Analyzer bu çağrıyı parse ediyor, ancak çağrılan procedure'ün side effect veya result lineage bilgisini çıkarmıyor.

Önerilen çözüm:
- Output modeline açık bir `ProcedureCalls` alanı eklenmeli.
- Gelecekte ek SP dosyaları yüklenerek `EXEC schema.proc` çağrıları bilinen procedure definition'larıyla ilişkilendirilebilir.
- Dynamic SQL (`EXEC(@sql)` / `sp_executesql`) için desteklenmeyen durum olarak raporlanmalı veya literal SQL varsa kısmi parse denenmeli.

### 7. Parametreler ve sabitler formula olarak görünüyor, fakat first-class source değil

Mevcut davranış:
- `ReportDate => @ReportDate` ve `ReportBeginDate => @BeginDate` gibi output kolonlarının table source bilgisi yok.
- Bu tablo lineage açısından doğru; fakat denetim yapan kullanıcılar parametre lineage bilgisini ayrı görmek isteyebilir.

Önerilen çözüm:
- Her output kolonu için `Parameters` listesi eklenmeli.
- Sabit değerler, parametreler ve tablo kaynakları birbirinden ayrı tutulmalı.

## Öneriler

### Denetim için okunabilir bir Excel sheet eklenebilir

`OutputComparison` veya `AuditSummary` adında yeni bir sheet eklenebilir.

İçerik:
- SP dosyası
- Procedure adı
- Final SELECT satırı
- JSON output sayısı
- Beklenen output sayısı
- Durum
- Notlar

Bu, tüm `Sources` sheet'ini okumadan manuel kontrol yapmayı kolaylaştırır.

### Analyzer confidence level eklenebilir

Her output/source için `Confidence` alanı eklenebilir:
- `High`: doğrudan table/CTE/temp/derived mapping
- `Medium`: ordinal insert mapping veya merge edilmiş branch mapping
- `Low`: unresolved, wildcard, dynamic SQL, bilinmeyen metadata

### Gerekirse generated output source review dışına alınabilir

`output/lineage.json` büyük ve generated bir dosya.

Bu proje git review sürecine girecekse şu seçenekler değerlendirilebilir:
- `output/` dizinini `.gitignore` içine almak
- veya source control altında küçük, seçilmiş bir sample output tutmak

