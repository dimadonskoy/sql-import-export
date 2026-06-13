# SQL Import / Export — POS Migration Toolkit

A Windows batch toolkit for migrating POS database tables between SQL Server instances using Microsoft's **BCP (Bulk Copy Program)**. Supports Hebrew character encoding (Windows-1255 / codepage 1255) and handles schema drift between source and target databases automatically.

---

## Requirements

| Dependency | Notes |
|---|---|
| **SQL Server Express** (`.\sqlexpress`) | Or any named instance — update the `Server` variable |
| **BCP utility** | Ships with SQL Server / SSMS client tools |
| **sqlcmd** | Used for TRUNCATE and connectivity probes |
| **PowerShell 5+** | Used for format-file alignment |

---

## Quick Start

```bat
:: Export all tables from the source database
new-export.bat

:: Import all tables into the target database
new-import.bat
```

Both scripts connect to `.\sqlexpress`, database `POS`, with credentials `sa`/`sa`.
Edit the variables at the top of each script to point at a different server or database.

---

## Scripts

### `new-export.bat`

Runs in two phases:

1. **BCP Export** — dumps each table to a binary `.bcp` file (native format, codepage 1255).
2. **Format Files** — generates a `*map.txt` BCP format file for each table, capturing column types and sizes from the source schema.

Both phases respect the `Force` flag (default `true`): when set, existing files are overwritten on every run.

### `new-import.bat`

Runs in two phases:

1. **Truncate** — clears all target tables in dependency order before importing (handles FK constraints via explicit `TRUNC:` lines before `IMPT:` lines).
2. **BCP Import** — loads each `.bcp` file, with automatic format-file alignment and a one-time retry on failure.

#### Schema Drift Handling

Because the source and target databases may differ in column sizes, the importer aligns format files before each load:

```
Source map.txt  --+
                  +--> PowerShell diff --> *_bridge.fmt --> BCP import
Fresh schema fmt -+
```

1. Generates a **fresh** format file from the current target table schema.
2. Diffs column sizes between the original `*map.txt` and the fresh file.
3. Writes a **bridge** format file with sizes updated to match the target schema.
4. Falls back to the original format file if the bridge cannot be built.
5. Retries the BCP import once on transient failure.

#### Failure Detection

BCP exits with code `0` even when it encounters errors. The import script detects real failures by scanning BCP's stdout for the string `Error = [Microsoft]`, avoiding false positives from empty tables or duplicate-key retries.

---

## Configuration

### Key Variables

| Variable | Default | Purpose |
|---|---|---|
| `Server` | `.\sqlexpress` | SQL Server instance |
| `Database` | `POS` | Target database name |
| `Username` | `sa` | SQL authentication username |
| `Password` | `sa` | SQL authentication password |
| `Force` | `true` | Overwrite existing `.bcp` / format files on export |
| `EnableLogging` | `false` | Write timestamped log file to `Logs\` |
| `BcpVersion` | *(empty)* | SQL Server version compatibility format (e.g., `140` for SQL Server 2017) |


### Logging

Logs are written to `Logs\export_sql_<timestamp>.log` or `Logs\import_sql_<timestamp>.log`.

Override `EnableLogging` at runtime with command-line flags:

```bat
:: Disable logging
new-import.bat --no-log
new-import.bat -nolog
new-import.bat /nolog

:: Force logging on
new-import.bat --log
new-import.bat -log
new-import.bat /log
```

### Version Compatibility (Export Only)

By default, exports use the native BCP format of the source SQL Server instance. If you need to import the data into an older SQL Server version (such as migrating from SQL Server 2022 to SQL Server 2017), you must export it with version compatibility.

Override `BcpVersion` at runtime with command-line flags:

```bat
:: Export in SQL Server 2017 format (passes -V 140 to BCP)
new-export.bat --sql2017
new-export.bat -sql2017
new-export.bat /sql2017
```


Log output uses ANSI color codes for level visibility:

| Level | Color | Meaning |
|---|---|---|
| `[Header]` | Magenta | Phase separator |
| `[Info]` | Cyan | General info |
| `[Ok]` | Green | Success |
| `[Warn]` | Yellow | Skipped / non-fatal |
| `[Error]` | Red | Failure |
| `[Detail]` | Gray | BCP raw output |

---

## File Types

| Extension | Description |
|---|---|
| `.bcp` | Binary native-format bulk copy data (not human-readable) |
| `*map.txt` | BCP non-XML format file — describes column types, sizes, and names |

---

## Data Manifest (Table List)

Each script is **self-referential**: the list of tables to process is embedded at the bottom of the same `.bat` file and parsed at runtime using `findstr /b`.

### Directives

| Directive | Syntax | Effect |
|---|---|---|
| `EXPT:` | `EXPT:<table>,<file>.bcp,<file>map.txt` | Export table data + generate format file |
| `IMPT:` | `IMPT:<table>,<file>.bcp,<file>map.txt` | Truncate table, then BCP import |
| `TRUNC:` | `TRUNC:<table>` | Truncate only (no import) |

### Adding or Removing a Table

Edit the `REM >>> DATA SECTION <<<` block at the bottom of the relevant `.bat` file:

```bat
REM >>> DATA SECTION <<<
EXPT:POS.dbo.MyTable,999.bcp,999map.txt
```

> **Constraint:** Table names and file names must not contain `,` or `:` — these are the field delimiters used by the parser.

### FK Dependency Order

Tables with foreign key dependencies that block direct `TRUNCATE` must be cleared first with an explicit `TRUNC:` line before their `IMPT:` line:

```bat
TRUNC:POS.dbo.ChildTable
IMPT:POS.dbo.ParentTable,parent.bcp,parentmap.txt
IMPT:POS.dbo.ChildTable,child.bcp,childmap.txt
```

---

## Repository Structure

```
.
+-- new-export.bat      # Export script + EXPT table manifest
+-- new-import.bat      # Import script + TRUNC/IMPT table manifest
+-- Logs\               # Timestamped log files (created when logging is enabled)
+-- *.bcp               # Exported binary data files (generated by new-export.bat)
+-- *map.txt            # BCP format files (generated by new-export.bat)
```

---

## Tables Managed

<details>
<summary>Export manifest (40 tables)</summary>

| Table | Data File | Format File |
|---|---|---|
| `POS.dbo.PraxellTablesCode` | 189.bcp | 189map.txt |
| `POS.dbo.PraxelTbls` | 195.bcp | 195map.txt |
| `POS.dbo.VeriCardTbls` | 528.bcp | 528map.txt |
| `POS.dbo.VeriCardClubs` | 529.bcp | 529map.txt |
| `POS.dbo.Settings` | 8.bcp | 8map.txt |
| `POS.dbo.CreditTypes` | 10.bcp | 10map.txt |
| `POS.dbo.WayBillMenu` | 15.bcp | 15map.txt |
| `POS.dbo.Cards` | 26.bcp | 26map.txt |
| `POS.dbo.Items` | 27.bcp | 27map.txt |
| `POS.dbo.ItemTypes` | 34.bcp | 34map.txt |
| `POS.dbo.PriceLists` | 35.bcp | 35map.txt |
| `POS.dbo.ItemsBundle_package` | 37.bcp | 37map.txt |
| `POS.dbo.Colors` | 45.bcp | 45map.txt |
| `POS.dbo.Models` | 54.bcp | 54map.txt |
| `POS.dbo.ItemsCatalogDetection` | 65.bcp | 65map.txt |
| `POS.dbo.CampaignTypes` | 67.bcp | 67map.txt |
| `POS.dbo.CampaignFields` | 68.bcp | 68map.txt |
| `POS.dbo.Campaigns` | 69.bcp | 69map.txt |
| `POS.dbo.TblTbls` | 75.bcp | 75map.txt |
| `POS.dbo.GeneralCarrierFile` | 76.bcp | 76map.txt |
| `POS.dbo.MenusOnDemand` | 100.bcp | 100map.txt |
| `POS.dbo.ProgramsList` | 101.bcp | 101map.txt |
| `POS.dbo.Rulers` | 103.bcp | 103map.txt |
| `POS.dbo.POSPermanentMessages` | 106.bcp | 106map.txt |
| `POS.dbo.EmpPermission` | 107.bcp | 107map.txt |
| `POS.dbo.CreditInvoiceTable` | 118.bcp | 118map.txt |
| `POS.dbo.Accounts` | 149.bcp | 149map.txt |
| `POS.dbo.Cards_continue` | 185.bcp | 185map.txt |
| `POS.dbo.SaleItems` | 270.bcp | 270map.txt |
| `POS.dbo.SaleItems_local` | 271.bcp | 271map.txt |
| `POS.dbo.ClubCardsTypes` | 181.bcp | 181map.txt |
| `POS.dbo.Pre_Paid_Prefixes2` | 326.bcp | 326map.txt |
| `POS.dbo.GeneralMenus` | 365.bcp | 365map.txt |
| `POS.dbo.ProtoTypeMenus` | 369.bcp | 369map.txt |
| `POS.dbo.PaymentMethodMonitoring` | 188.bcp | 188map.txt |
| `POS.dbo.CoinsRates` | 19.bcp | 19map.txt |
| `POS.dbo.Coins_notes_details` | 119.bcp | 119map.txt |
| `POS.dbo.Multiple_Barcode` | 619.bcp | 619map.txt |
| `POS.dbo.MultipassTbls` | 273.bcp | 273map.txt |
| `POS.dbo.Banks` | 4.bcp | 4map.txt |

</details>

<details>
<summary>Import manifest (44 tables, including 4 truncate-only)</summary>

**Truncate-only** (no data import — cleared to satisfy FK constraints):

- `POS.dbo.AdditionalPriceLists`
- `POS.dbo.CardClassPaymentTerm`
- `POS.dbo.ItemsAdditionalClass`
- `POS.dbo.Multiple_Barcode`

**Import tables:** same as the export manifest above, plus `POS.dbo.CardClassPaymentTerm` (36.bcp).

</details>