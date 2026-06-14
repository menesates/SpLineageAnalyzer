# Stored Procedure Lineage Analyzer

Bu proje, `sp/` dizinindeki SQL Server stored procedure dosyalarını okuyup output kolonlarının hangi tablo, kolon ve formullerden geldiğini analiz eden bir .NET 8 console uygulamasıdır.

Analiz motoru T-SQL'i metin olarak ayiklamak yerine `Microsoft.SqlServer.TransactSql.ScriptDom` ile parse eder. Bu sayede tablo alias'lari, join kaynaklari, `OUTER APPLY` ile uretilen kolonlar, `CASE`, `ISNULL`, aritmetik ifadeler ve dogrudan kolon referanslari AST uzerinden takip edilir.

## Proje Icerigi

- `src/SpLineageAnalyzer`: Console uygulamasi ve analiz motoru.
- `src/SpLineageAnalyzer/Analysis`: ScriptDom parser, SELECT analizi, alias scope, kaynak kolon ve operasyon toplama kodlari.
- `src/SpLineageAnalyzer/Output`: Markdown cikti formatlayici.
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

Varsayilan olarak `sp/` dizinindeki tum `.sql` dosyalari analiz edilir. Uygulama secilen JSON/Markdown ciktisini korur ve ek olarak terminalde kolay okunabilir bir console raporu gosterir:

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

Markdown cikti almak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --format markdown
```

JSON ve Markdown ciktiyi birlikte almak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --format both
```

Sonuclari bir dizine yazmak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --format both --output output
```

Bu komut su dosyalari uretir ve ayni analiz sonucunu terminalde okunabilir rapor olarak da gosterir:

```text
output/lineage.json
output/lineage.md
```

Sadece dosya uretip terminalde okunabilir raporu kapatmak icin:

```bash
dotnet run --project src/SpLineageAnalyzer/SpLineageAnalyzer.csproj -- --input sp --format both --output output --no-console
```

## CLI Parametreleri

```text
--input <file-or-dir>       Analiz edilecek SQL dosyasi veya dizin. Varsayilan: sp
--format json|markdown|both Cikti formati. Varsayilan: json
--output <file-or-dir>      Cikti yolu. Verilmezse terminale yazar.
--no-console                Okunabilir console raporunu kapatir.
--help                      Yardim metnini gosterir.
```

## Cikti Icerigi

JSON, Markdown ve console raporunda her procedure icin output kolonlari merge edilmis olarak listelenir. Her kolon icin su bilgiler bulunur:

- Output kolon adi
- Kolonu ureten SQL formulu
- Kaynak alias, tablo ve kolonlar
- `CASE`, `ISNULL`, `Subtract`, `MAX` gibi operasyonlar
- IF/ELSE gibi farkli SELECT dallarinda kolonun hangi branch'ten geldigine dair bilgi
- `OUTER APPLY` veya derived table ile uretilen kolonlarda alt formuller ve turetilmis kaynaklar

Ornek olarak `Rediscount5` gibi bir output kolonu, ana `CASE` formulunu ve `mtx.Rediscount5` / `mtxl.Rediscount5` gibi `OUTER APPLY` kaynaklarinin alt formullerini birlikte tasir.

## Notlar

- Uygulama SQL Server'a baglanmaz; tamamen statik analiz yapar.
- Parse edilemeyen veya cozulemeyen referanslar sonuc icinde `unresolved` olarak korunur.
- Buyuk ve karmasik SP'lerde kismi sonuc uretmek, tum analizi durdurmaktan daha onceliklidir.
