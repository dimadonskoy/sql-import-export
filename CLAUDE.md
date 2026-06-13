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

### Script split: bat vs. PowerShell

- **`new-export.bat`** — pure batch; handles all export logic inline (two phases: BCP out + format file generation).
- **`new-import.bat`** — thin launcher only; sets environment variables, then delegates all import work to `import.ps1` via `powershell -File`. When modifying import behavior, edit `import.ps1`.
- **`import.ps1`** — the real import engine. Reads config from environment variables (`$env:Server`, `$env:EnableLogging`, etc.) that `new-import.bat` sets before launching it. Also receives `$BatFile` as a parameter so it can parse the `TRUNC:`/`IMPT:` data section from the calling `.bat` file.

### Self-referential data sections

Each `.bat` file contains its own data manifest at the bottom, parsed at runtime using `findstr /b` (in the bat) or `Get-Content` (in `import.ps1`):

- `TRUNC:<table>` — truncate only (no import)
- `IMPT:<table>,<file>.bcp,<file>map.txt` — truncate + BCP import
- `EXPT:<table>,<file>.bcp,<file>map.txt` — BCP export

### Format file alignment (import only)

`import.ps1` handles schema drift between the source database (where data was exported) and the target database:

1. Generates a **fresh** format file from the current target table schema.
2. Diffs column sizes between the original `*map.txt` and the fresh file (`Align-FormatFile`).
3. Writes a **bridge** format file with size values updated to match the current schema.
4. Falls back to the original format if the bridge cannot be generated.
5. Retries the BCP import once on failure (3-second pause before retry).

BCP import uses `-E` (preserve identity values), `-b 10000` (batch size), and `-a 65535` (network packet size). The script also runs a 3-attempt SQL Server wake-up probe (SELECT 1) before beginning truncation.

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
| `EnableLogging` | `false` | Enable/disable log file creation & writing |
| `BcpVersion` | *(empty)* | BCP format version compatibility (e.g. `140` for SQL 2017) |

## Logging & Version Flags

By default, logs are **disabled**. Override at runtime:

```bat
new-import.bat --log        :: enable logging
new-import.bat --no-log     :: disable logging (also: -nolog, /nolog)
new-export.bat --sql2017    :: export in SQL Server 2017 format (-V 140)
```

All flags are case-insensitive and accept `/`, `-`, or `--` prefix.

## Failure Detection

BCP exits 0 even on errors. `import.ps1` detects real failures by scanning BCP stdout for the string `Error = [Microsoft]` in the captured output, which avoids false positives from empty tables or duplicate-key retries.
