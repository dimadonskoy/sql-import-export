# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a SQL Server data migration toolkit for a POS (Point of Sale) system. It exports and imports tables from a `POS` SQL Server database using Microsoft's BCP (Bulk Copy Program) utility, with Hebrew character support (Windows-1255 / codepage 1255).

## Running the Scripts

```bat
new-export.bat   :: Export all tables to .bcp + format files
new-import.bat   :: Truncate target tables, then BCP import from .bcp files
```

Both scripts connect to `.\sqlexpress` (SQL Server Express on localhost), database `POS`, as `sa`/`sa`. Logs are written to `Logs\` with a timestamp suffix.

## Architecture

### Self-referential data sections
Each `.bat` file contains its own data manifest at the bottom, parsed at runtime using `findstr /b`. The script reads its own lines to discover what to process:

- `TRUNC:<table>` — truncate only (no import)
- `IMPT:<table>,<file>.bcp,<file>map.txt` — truncate + BCP import
- `EXPT:<table>,<file>.bcp,<file>map.txt` — BCP export

### Format file alignment (import only)
`new-import.bat` handles schema drift between the source database (where data was exported) and the target database:

1. Generates a **fresh** format file from the current target table schema.
2. Runs an inline PowerShell command to diff column sizes between the original `*map.txt` and the fresh file.
3. Writes a **bridge** format file with size values updated to match the current schema.
4. Falls back to the original format if the bridge cannot be generated.
5. Retries the BCP import once on failure.

### File types
- `.bcp` — binary native-format bulk copy data (not human-readable)
- `*map.txt` — BCP non-XML format files describing column types, sizes, and names

## Modifying the Table List

To add or remove a table, edit the `REM >>> DATA SECTION <<<` block at the bottom of each `.bat` file. The parser uses comma and colon as delimiters, so table or file names must not contain those characters.

Import-only tables that need a prior `TRUNC:` (e.g. those with FK dependencies blocking truncation via `IMPT:` alone) require a separate `TRUNC:` line before the `IMPT:` line.

## Key Variables

| Variable | Default | Purpose |
|---|---|---|
| `Server` | `.\sqlexpress` | SQL Server instance |
| `Database` | `POS` | Target database |
| `Username` / `Password` | `sa` / `sa` | SQL auth credentials |
| `Force` | `true` (export only) | Overwrite existing `.bcp`/format files |

## Failure Detection

BCP exits 0 even on errors. `new-import.bat` detects real failures by scanning BCP stdout for the string `Error = [Microsoft]` in the captured output file, which avoids false positives from empty tables or duplicate-key retries.
