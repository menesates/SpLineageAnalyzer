# Stored Procedure Lineage Analyzer

Bu proje, `sp/` dizinindeki SQL Server stored procedure dosyalarını okuyup output kolonlarının hangi tablo, kolon ve formullerden geldiğini analiz eden bir .NET 8 console uygulamasıdır.

Analiz motoru T-SQL'i metin olarak ayiklamak yerine `Microsoft.SqlServer.TransactSql.ScriptDom` ile parse eder. Bu sayede tablo alias'lari, join kaynaklari, `OUTER APPLY` ile uretilen kolonlar, `CASE`, `ISNULL`, aritmetik ifadeler ve dogrudan kolon referanslari AST uzerinden takip edilir.

## Proje Icerigi

- `src/SpLineageAnalyzer`: Console uygulamasi ve analiz motoru.
- `src/SpLineageAnalyzer/Analysis`: ScriptDom parser, SELECT analizi, alias scope, kaynak kolon ve operasyon toplama kodlari.
- `src/SpLineageAnalyzer/Output`: JSON, Excel ve okunabilir console raporu formatlayicilari.
- `tests/SpLineageAnalyzer.Tests`: Ornek SP uzerinden beklenen lineage davranisini dogrulayan testler.
- `sp/`: Analiz edilecek stored procedure dosyalari. Su an ornek olarak `rpt_LoanRediscountAdvanceInterim.sql` bulunur.
- `global.json`: Projenin .NET 8 SDK ile calismasini sabitler.

## Gereksinimler

- .NET SDK `8.0.422` veya uyumlu .NET 8 SDK
- macOS/Linux/Windows terminal

Kurulumu kontrol etmek icin:

```bash
dotnet --version
dotnet --list-sdks
dotnet --list-runtimes
```

Bu repo icin beklenen SDK:

```text
8.0.422
```

## Build

Repo kok dizininde:

```bash
dotnet restore SpLineageAnalyzer.sln
dotnet build SpLineageAnalyzer.sln
```

## Test

```bash
dotnet test SpLineageAnalyzer.sln
```

## Uygulamayi Calistirma

Varsayilan olarak `sp/` dizinindeki tum `.sql` dosyalari analiz edilir. Uygulama secilen JSON/Excel ciktisini korur ve ek olarak terminalde kolay okunabilir bir console raporu gosterir:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj
```

Belirli bir dosyayi analiz etmek icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp/rpt_LoanRediscountAdvanceInterim.sql
```

Belirli bir dizindeki tum SQL dosyalarini analiz etmek icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp
```

Excel cikti almak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --format excel
```

JSON ve Excel ciktiyi birlikte almak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --format both
```

Sonuclari bir dizine yazmak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --server vkdb --format both --output output
```

Bu komut su dosyalari uretir ve ayni analiz sonucunu terminalde okunabilir rapor olarak da gosterir:

```text
output/lineage.json
output/lineage.xlsx
```

Sadece dosya uretip terminalde okunabilir raporu kapatmak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --server vkdb --format both --output output --no-console
```

## Web Sayfalari

`output/lineage.json` dosyasini tarayicida incelemek icin once proje kok dizininde lokal viewer sunucusunu baslatin:

```bash
scripts/view-lineage
```

Komut varsayilan olarak `127.0.0.1:5177` adresinde calisir. Farkli port kullanmak isterseniz:

```bash
scripts/view-lineage --port=5180
```

Sunucu calisirken tarayicida su sayfalari acabilirsiniz:

| Sayfa | Adres | Aciklama |
|---|---|---|
| Genel JSON viewer | `http://127.0.0.1:5177/` | Ozet metrikler, procedure listesi, kolon detaylari, source turleri ve ham JSON gorunumu. |
| SP lineage tablosu | `http://127.0.0.1:5177/tools/lineage-viewer/sp-table.html` | Secilen SP icin output kolon, formul, kullanilan tablo/kolon ve output satir bilgisi. |

Sayfalar her acildiginda veya yenile butonuna basildiginda `output/lineage.json` dosyasinin guncel halini okur. Bu nedenle analiz ciktisini yeniden urettikten sonra tarayiciyi yenilemeniz yeterlidir.

## CLI Parametreleri

```text
--input <file-or-dir>       Analiz edilecek SQL dosyasi veya dizin. Varsayilan: sp
--server <server-name>      Varsayilan server adi. Varsayilan: vkdb
--format json|excel|both    Cikti formati. Varsayilan: json
--output <file-or-dir>      Cikti yolu. Verilmezse terminale yazar.
--no-console                Okunabilir console raporunu kapatir.
--help                      Yardim metnini gosterir.
```

## Cikti Icerigi

JSON, Excel ve console raporunda her procedure icin output kolonlari merge edilmis olarak listelenir. Her kolon icin su bilgiler bulunur:

- Output kolon adi
- Kolonu ureten SQL formulu
- Kaynak alias, server, database, schema, table ve kolonlar
- `CASE`, `ISNULL`, `Subtract`, `MAX` gibi operasyonlar
- IF/ELSE gibi farkli SELECT dallarinda kolonun hangi branch'ten geldigine dair bilgi
- `OUTER APPLY` veya derived table ile uretilen kolonlarda alt formuller ve turetilmis kaynaklar

Ornek olarak `Rediscount5` gibi bir output kolonu, ana `CASE` formulunu ve `mtx.Rediscount5` / `mtxl.Rediscount5` gibi `OUTER APPLY` kaynaklarinin alt formullerini birlikte tasir.

## JSON Output Formatı

JSON, uygulamanın kanonik çıktısıdır. `--format json` veya `--format both` kullanıldığında üretilir. `--output output` verilirse dosya yolu varsayılan olarak şöyledir:

```text
output/lineage.json
```

Kök JSON yapısı bir array'dir. Her eleman analiz edilen bir SQL dosyasını temsil eder:

```json
[
  {
    "file": "/abs/path/sp/rpt_Example.sql",
    "procedures": [],
    "diagnostics": []
  }
]
```

### Dosya Seviyesi

Her dosya nesnesinde şu alanlar bulunur:

| Alan | Tip | Açıklama |
|---|---|---|
| `file` | string | Analiz edilen SQL dosyasının absolute path bilgisidir. |
| `procedures` | array | Dosya içinde bulunan procedure analizleri. Genelde tek procedure olur. |
| `diagnostics` | array | Parse veya dosya geneli analiz uyarı/hataları. Boş olabilir. |

### Procedure Seviyesi

`procedures` içindeki her nesne bir stored procedure sonucunu temsil eder:

```json
{
  "name": "RPT.rpt_TreasuryFxLiquidityComplex",
  "outputColumns": [],
  "diagnostics": []
}
```

| Alan | Tip | Açıklama |
|---|---|---|
| `name` | string | Procedure adı. Schema ile birlikte yazılır. |
| `outputColumns` | array | Procedure'ün client'a döndürdüğü final output kolonları. |
| `diagnostics` | array | Procedure seviyesindeki analiz uyarı/hataları. |

Notlar:
- `SELECT INTO #Temp`, `INSERT INTO #Temp SELECT`, CTE iç SELECT'leri, `APPLY` iç SELECT'leri ve derived table/subquery SELECT'leri output olarak raporlanmaz.
- IF/ELSE gibi birden fazla final SELECT path'i varsa kolonlar output adına göre merge edilir.
- Output kolon sırası, ilk görülen final SELECT sırasına göre korunur.

### Output Kolonu

`outputColumns` içindeki her nesne bir rapor kolonunu temsil eder:

```json
{
  "name": "ProjectedClosingPosition",
  "formulas": [
    "ISNULL(pb.CurrentPositionAmount, 0) + ISNULL(af.TotalForwardCashFlow, 0)"
  ],
  "sources": [],
  "operations": ["Add", "ISNULL"],
  "branches": []
}
```

| Alan | Tip | Açıklama |
|---|---|---|
| `name` | string | Output kolon adı. `AS` alias varsa alias kullanılır; yoksa expression'dan infer edilir. |
| `formulas` | array(string) | Kolonu üreten SQL expression metni. Branch'ler arasında farklı formül varsa birden fazla değer olabilir. |
| `sources` | array | Kolon formülünde kullanılan kaynak tablo/kolon referansları. |
| `operations` | array(string) | Formülde yakalanan fonksiyon ve operator bilgileri. Örnek: `CASE`, `ISNULL`, `Add`, `Subtract`, `SUM`. |
| `branches` | array | Kolonun hangi SELECT branch'lerinden geldiğini gösteren detay liste. |

### Source Reference

`sources` içindeki her nesne bir kaynak kolon referansıdır:

```json
{
  "alias": "lim",
  "objectName": "vkdb.BOA.TRE.PositionLimit",
  "server": "vkdb",
  "database": "BOA",
  "schema": "TRE",
  "table": "PositionLimit",
  "sourceKind": "Table",
  "column": "PositionLimitAmount",
  "unresolved": false,
  "formula": null,
  "derivedSources": []
}
```

| Alan | Tip | Açıklama |
|---|---|---|
| `alias` | string | SQL içinde kullanılan alias. Örnek: `lim`, `pb`, `rb`. Alias yoksa boş string olabilir. |
| `objectName` | string/null | Okunabilir kaynak adı. Base table için server dahil full ad; CTE/derived/temp için açıklayıcı ad. |
| `server` | string/null | Kaynak server adı. Linked server varsa SQL'deki 4 parçalı adın ilk parçasından gelir; yoksa `--server` parametresi kullanılır. |
| `database` | string/null | Database adı. Temp tablolar için `tempdb`. CTE/derived kaynaklarda null olabilir. |
| `schema` | string/null | Schema adı. Temp tablo, CTE ve derived kaynaklarda null olabilir. |
| `table` | string/null | Table adı, temp tablo adı veya CTE/derived alias adı. |
| `sourceKind` | string | Kaynak türü. Şu değerler görülebilir: `Table`, `Temp`, `CTE`, `Derived`, `Unknown`. |
| `column` | string | Referans verilen kolon adı. |
| `unresolved` | boolean | Alias veya tablo çözülemediyse `true`; çözülen kaynaklarda `false`. |
| `formula` | string/null | Kaynak bir CTE/temp/derived kolon ise o kolonu üreten alt formül. Base table kolonlarında genelde null olur. |
| `derivedSources` | array | `formula` alanındaki alt formülün kullandığı daha derin kaynaklar. Recursive yapıdadır. |

Örnekler:

```text
lim.PositionLimitAmount -> vkdb.BOA.TRE.PositionLimit
rb.ProvisionRate -> #RiskBucket
af.TotalForwardCashFlow -> CTE: AggregatedFlow
target.MonthlyFeeTargetTL -> Derived: target
```

### Derived Source Zinciri

CTE, temp tablo, `OUTER APPLY`, `CROSS APPLY` veya derived table kaynaklarında lineage zinciri `derivedSources` ile derinleşir.

Örnek mantık:

```text
ProjectedClosingPosition
  af.TotalForwardCashFlow -> CTE: AggregatedFlow
    formula: SUM(bf.SignedCashFlow)
      bf.SignedCashFlow -> CTE: BucketedFlow
        formula: rcf.CashFlowAmount * rcf.DirectionSign
          rcf.CashFlowAmount -> CTE: RawCashFlow
```

Bu yapı JSON'da recursive olarak tutulur. Excel çıktısındaki `Sources` sheet'i aynı zinciri `SourceDepth` alanıyla düzleştirerek gösterir.

### Branch Bilgisi

`branches` alanı, output kolonunun hangi SELECT path'inden geldiğini gösterir:

```json
{
  "branch": "select@line:150",
  "line": 167,
  "formula": "ISNULL(pb.CurrentPositionAmount, 0) + ISNULL(af.TotalForwardCashFlow, 0)",
  "sources": [],
  "operations": ["Add", "ISNULL"]
}
```

| Alan | Tip | Açıklama |
|---|---|---|
| `branch` | string | SELECT statement başlangıç satırını içeren branch etiketi. |
| `line` | number | Output kolon expression'ının başladığı satır. |
| `formula` | string | Bu branch'teki kolon formülü. |
| `sources` | array | Bu branch'e özel kaynaklar. |
| `operations` | array(string) | Bu branch'e özel operasyonlar. |

IF/ELSE içinde aynı output kolon adı iki farklı SELECT'te üretilirse:
- `outputColumns` içinde tek kolon olarak görünür.
- `formulas`, `sources` ve `operations` merge edilir.
- `branches` içinde her SELECT path'i ayrı korunur.

### Diagnostics

Diagnostic nesneleri parse veya analiz sırasında oluşan uyarı/hataları temsil eder:

```json
{
  "severity": "Warning",
  "message": "Could not analyze SELECT at line 42: ...",
  "line": 42,
  "column": 5
}
```

| Alan | Tip | Açıklama |
|---|---|---|
| `severity` | string | `Error` veya `Warning`. |
| `message` | string | Açıklama metni. |
| `line` | number/null | SQL dosyasındaki satır bilgisi. |
| `column` | number/null | SQL dosyasındaki kolon bilgisi. |

### Server, Database, Schema, Table Çözümleme Kuralları

Kaynak tablo adı parça sayısına göre çözülür:

| SQL referansı | Çözüm |
|---|---|
| `LINK01.BOA.TRE.FxSwapDeal sw` | `server=LINK01`, `database=BOA`, `schema=TRE`, `table=FxSwapDeal` |
| `BOA.TRE.PositionLimit lim` | `server=--server`, `database=BOA`, `schema=TRE`, `table=PositionLimit` |
| `TRE.PositionLimit lim` | `server=--server`, `database=null`, `schema=TRE`, `table=PositionLimit` |
| `PositionLimit lim` | `server=--server`, `database=null`, `schema=null`, `table=PositionLimit` |
| `#RiskBucket rb` | `server=--server`, `database=tempdb`, `schema=null`, `table=#RiskBucket` |

Varsayılan server adı `vkdb` değeridir. Çalıştırırken değiştirmek için:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --server MyServer --format json
```

## Notlar

- Uygulama SQL Server'a baglanmaz; tamamen statik analiz yapar.
- Parse edilemeyen veya cozulemeyen referanslar sonuc icinde `unresolved` olarak korunur.
- Buyuk ve karmasik SP'lerde kismi sonuc uretmek, tum analizi durdurmaktan daha onceliklidir.
