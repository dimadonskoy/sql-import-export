@echo off
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
setlocal enabledelayedexpansion

set Server=.\sqlexpress
set Database=POS
set Username=sa
set Password=sa
set LogDir=Logs
set ScriptRoot=%~dp0
set exitcode=0
set failedTrunc=0
set failedImport=0

if not exist "%LogDir%" mkdir "%LogDir%"

set Y=%date:~-4,4%
set M=%date:~-10,2%
set D=%date:~-7,2%
set HH=%time:~0,2%
set MI=%time:~3,2%
set SS=%time:~6,2%
set TS=%D%%M%%Y%_%HH%%MI%%SS%
set TS=%TS: =0%
set LogFile=%LogDir%\import_sql_%TS%.log

type nul > "%LogFile%"

call :log "=== new-import started ===" "Header"
call :log "Server: %Server% | Database: %Database%" "Info"
call :log "Log file: %LogFile%" "Info"
call :log "" ""

call :log "Waking SQL Server..." "Info"
for /l %%a in (1,1,3) do (
    sqlcmd -S%Server% -U%Username% -P%Password% -d %Database% -Q "SELECT 1" -l 10 >nul 2>&1
    if !errorlevel! equ 0 (
        call :log "  SQL Server ready." "Ok"
        goto :woke
    )
    call :log "  Attempt %%a/3 -- waiting..." "Warn"
    ping 127.0.0.1 -n 4 >nul
)
call :log "  [WARN] Cannot connect to SQL Server -- will retry per table." "Warn"
:woke

call :log "====== PHASE 1: TRUNCATE TABLES ======" "Header"

set total_trunc=0
for /f "tokens=1,* delims=:" %%a in ('findstr /b "TRUNC:" "%~f0"') do (
    set /a total_trunc+=1
)
for /f "tokens=1,2,3,4 delims=,:" %%a in ('findstr /b "IMPT:" "%~f0"') do (
    set /a total_trunc+=1
)

set current_trunc=0
for /f "tokens=1,* delims=:" %%a in ('findstr /b "TRUNC:" "%~f0"') do (
    set /a current_trunc+=1
    call :truncate "%%b" "!current_trunc!" "!total_trunc!"
)

for /f "tokens=1,2,3,4 delims=,:" %%a in ('findstr /b "IMPT:" "%~f0"') do (
    set /a current_trunc+=1
    call :truncate "%%b" "!current_trunc!" "!total_trunc!"
)

call :log "====== PHASE 2: BCP IMPORT ======" "Header"

set total_tables=0
for /f "tokens=1,2,3,4 delims=,:" %%a in ('findstr /b "IMPT:" "%~f0"') do (
    set /a total_tables+=1
)

set current_table=0
for /f "tokens=1,2,3,4 delims=,:" %%a in ('findstr /b "IMPT:" "%~f0"') do (
    set /a current_table+=1
    set TableName=%%b
    set BcpFile=%%c
    set FmtFile=%%d
    set DataPath=%ScriptRoot%%%c
    set FmtPath=%ScriptRoot%%%d

    if not exist "!DataPath!" (
        call :log "  [!current_table!/!total_tables!] [WARN] %%c not found - skip %%b" "Warn"
    ) else if not exist "!FmtPath!" (
        call :log "  [!current_table!/!total_tables!] [WARN] %%d not found - skip %%b" "Warn"
    ) else (
        call :bcp_import "%%b" "!DataPath!" "!FmtPath!" "!current_table!" "!total_tables!"
    )
)

call :log "" ""
call :log "====== IMPORT COMPLETE ======" "Header"
call :log "  Tables truncated" "Ok"
call :log "  Tables imported" "Ok"
if %exitcode% neq 0 (
    call :log "  Import FAILED -- check log." "Error"
    echo.
    echo Import failed. Check the Logs folder for details.
    pause
) else (
    call :log "  Import completed successfully." "Ok"
)

exit /b %exitcode%

:truncate
set tbl=%~1
set cur_idx=%~2
set tot_idx=%~3
call :log "  [!cur_idx!/!tot_idx!] TRUNCATE TABLE %tbl%" "Detail"
sqlcmd -S%Server% -U%Username% -P%Password% -d %Database% -Q "TRUNCATE TABLE %tbl%" -b -r1 -I -l 15
if errorlevel 1 (
    call :log "  [FAIL] TRUNCATE %tbl%" "Error"
    set /a failedTrunc+=1
    set exitcode=1
) else (
    call :log "  [OK] TRUNCATE %tbl%" "Ok"
)
goto :eof

:bcp_import
set tbl=%~1
set data=%~2
set fmt=%~3
set cur_idx=%~4
set tot_idx=%~5
call :log "  [!cur_idx!/!tot_idx!] bcp %tbl% in %data%" "Detail"
set "FmtStem=%~dpn3"
set "FreshFmt=!FmtStem!_fresh.fmt"
set "BridgeFmt=!FmtStem!_bridge.fmt"
set "bcpLog=%TEMP%\bcp_%RANDOM%.log"

:: bcp returns exitcode 0 even on failure - detect via output text.
:: Failure = ("Error = [Microsoft]" AND "0 rows" at line start)
:: This avoids false-positives for: duplicate-key retries (no "0 rows") and empty tables (no errors).
set bcp_failed=1

:: 1. Generate fresh format file from current DB table schema
bcp "%tbl%" format nul -f"!FreshFmt!" -n -S%Server% -U%Username% -P%Password% >nul 2>&1

:: 2. Compare original mapping with DB schema and build aligned Bridge format
set "fmt_to_use=%fmt%"
if exist "!FreshFmt!" (
    powershell -ExecutionPolicy Bypass -Command "$o=[System.IO.File]::ReadAllText('%fmt%',[System.Text.Encoding]::Default);$ol=$o-split'\r?\n';if($ol.Count-lt2){exit 1};$of=[ordered]@{};for($i=2;$i-lt$ol.Count;$i++){$l=$ol[$i];if([string]::IsNullOrWhiteSpace($l)){continue};$p=$l-split'\s+',8;if($p.Length-lt7){continue};$of[$p[6]]=@{li=$i;sc=$p[5];te=$p[4]}};$n=[System.IO.File]::ReadAllText('!FreshFmt!',[System.Text.Encoding]::Default);$nl=$n-split'\r?\n';$nf=@{};for($i=2;$i-lt$nl.Count;$i++){$l=$nl[$i];if([string]::IsNullOrWhiteSpace($l)){continue};$p=$l-split'\s+',8;if($p.Length-lt7){continue};$nf[$p[6]]=@{sc=$p[5]}};$out=New-Object System.Collections.ArrayList;$null=$out.Add($ol[0]);$null=$out.Add($ol[1]);foreach($cn in $of.Keys){$inf=$of[$cn];$ln=$ol[$inf.li];$osc=$inf.sc;$te=$inf.te;$nsc=if($nf.ContainsKey($cn)){$nf[$cn]['sc']}else{'0'};if($nsc-ne$osc){$ete=[regex]::Escape($te);$ecn=[regex]::Escape($cn);$nln=$ln-replace('('+$ete+'\s+)'+$osc+'(\s+'+$ecn+')'),('${1}'+$nsc+'${2}');if($nln-eq$ln){$nln=$ln-replace('('+$ete+'\s+)'+$osc+'(\s+\S+)$'),('${1}'+$nsc+'${2}')};$null=$out.Add($nln)}else{$null=$out.Add($ln)}};$re=[Environment]::NewLine;($out-join$re)+$re|Out-File -FilePath '!BridgeFmt!' -Encoding Default -NoNewline;if(Test-Path '!BridgeFmt!'){exit 0}else{exit 1}" >nul 2>&1
    if exist "!BridgeFmt!" set "fmt_to_use=!BridgeFmt!"
)

:: 3. Import data using aligned format file
call :run_bcp "!fmt_to_use!"
call :bcp_check

:: 4. Retry once on failure
if !bcp_failed! equ 1 (
    ping 127.0.0.1 -n 3 >nul
    call :run_bcp "!fmt_to_use!"
    call :bcp_check
)

:: 5. Log import status
if !bcp_failed! equ 1 (
    call :log "  [FAIL] IMPORT %tbl%" "Error"
    set /a failedImport+=1
    set exitcode=1
) else (
    if "!fmt_to_use!"=="!BridgeFmt!" (
        call :log "  [OK] IMPORT %tbl% (aligned mapping)" "Ok"
    ) else (
        call :log "  [OK] IMPORT %tbl%" "Ok"
    )
)

:: clean up temp files
if exist "!FreshFmt!" del "!FreshFmt!"
if exist "!BridgeFmt!" del "!BridgeFmt!"
if exist "!bcpLog!" del "!bcpLog!"
goto :eof

:run_bcp
set "fmt_file=%~1"
powershell -ExecutionPolicy Bypass -Command "$p = Start-Process cmd -ArgumentList '/c', 'bcp', $env:tbl, 'in', $env:data, '-f', $env:fmt_file, '-E', '-C', '1255', '-S', $env:Server, '-U', $env:Username, '-P', $env:Password, '-b', '10000', '-a', '65535', '>', $env:bcpLog, '2>&1' -NoNewWindow -PassThru; $lastLineCount = 0; while (-not $p.HasExited) { Start-Sleep -Milliseconds 200; if (Test-Path $env:bcpLog) { $lines = Get-Content $env:bcpLog -Encoding Default -ErrorAction SilentlyContinue; if ($lines.Count -gt $lastLineCount) { for ($i = $lastLineCount; $i -lt $lines.Count; $i++) { $l = $lines[$i]; Write-Output ('    ' + $l); if ($env:LogFile) { $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); $now + ' [Detail]     ' + $l | Out-File -FilePath $env:LogFile -Append -Encoding Default } }; $lastLineCount = $lines.Count } } }; if (Test-Path $env:bcpLog) { $lines = Get-Content $env:bcpLog -Encoding Default -ErrorAction SilentlyContinue; if ($lines.Count -gt $lastLineCount) { for ($i = $lastLineCount; $i -lt $lines.Count; $i++) { $l = $lines[$i]; Write-Output ('    ' + $l); if ($env:LogFile) { $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); $now + ' [Detail]     ' + $l | Out-File -FilePath $env:LogFile -Append -Encoding Default } } } }; exit $p.ExitCode"
goto :eof

:bcp_check
:: Check bcp output in !bcpLog! for real failure
:: Failure = "Error = [Microsoft]" found anywhere (bcp errors to stdout)
:: Success = otherwise (normal rows-copied output, or 0-rows with no errors)
set bcp_failed=0
findstr /c:"Error = [Microsoft]" "!bcpLog!" >nul
if not errorlevel 1 set bcp_failed=1
goto :eof

:log
set "msg=%~1"
set level=%~2
if "%level%"=="" set level=Info
set Y=!date:~-4,4!
set M=!date:~-10,2!
set D=!date:~-7,2!
set HH=!time:~0,2!
set MI=!time:~3,2!
set SS=!time:~6,2!
set now=!Y!-!M!-!D! !HH!:!MI!:!SS!
set "col="
if "%level%"=="Info" set "col=%ESC%[36m"
if "%level%"=="Ok" set "col=%ESC%[32m"
if "%level%"=="Warn" set "col=%ESC%[33m"
if "%level%"=="Error" set "col=%ESC%[31m"
if "%level%"=="Header" set "col=%ESC%[35m"
if "%level%"=="Detail" set "col=%ESC%[90m"
echo %col%!now! [!level!] !msg!%ESC%[0m
echo !now! [!level!] !msg!>>"!LogFile!"
goto :eof

REM >>> DATA SECTION <<<
TRUNC:POS.dbo.AdditionalPriceLists
TRUNC:POS.dbo.CardClassPaymentTerm
TRUNC:POS.dbo.ItemsAdditionalClass
TRUNC:POS.dbo.Multiple_Barcode
IMPT:POS.dbo.Banks,4.bcp,4map.txt
IMPT:POS.dbo.Settings,8.bcp,8map.txt
IMPT:POS.dbo.CardClassPaymentTerm,36.bcp,36map.txt
IMPT:POS.dbo.CreditTypes,10.bcp,10map.txt
IMPT:POS.dbo.WayBillMenu,15.bcp,15map.txt
IMPT:POS.dbo.Cards,26.bcp,26map.txt
IMPT:POS.dbo.Items,27.bcp,27map.txt
IMPT:POS.dbo.ItemTypes,34.bcp,34map.txt
IMPT:POS.dbo.PriceLists,35.bcp,35map.txt
IMPT:POS.dbo.ItemsBundle_package,37.bcp,37map.txt
IMPT:POS.dbo.Colors,45.bcp,45map.txt
IMPT:POS.dbo.Models,54.bcp,54map.txt
IMPT:POS.dbo.ItemsCatalogDetection,65.bcp,65map.txt
IMPT:POS.dbo.CampaignTypes,67.bcp,67map.txt
IMPT:POS.dbo.CampaignFields,68.bcp,68map.txt
IMPT:POS.dbo.Campaigns,69.bcp,69map.txt
IMPT:POS.dbo.TblTbls,75.bcp,75map.txt
IMPT:POS.dbo.GeneralCarrierFile,76.bcp,76map.txt
IMPT:POS.dbo.MenusOnDemand,100.bcp,100map.txt
IMPT:POS.dbo.ProgramsList,101.bcp,101map.txt
IMPT:POS.dbo.POSPermanentMessages,106.bcp,106map.txt
IMPT:POS.dbo.EmpPermission,107.bcp,107map.txt
IMPT:POS.dbo.CreditInvoiceTable,118.bcp,118map.txt
IMPT:POS.dbo.Accounts,149.bcp,149map.txt
IMPT:POS.dbo.Cards_continue,185.bcp,185map.txt
IMPT:POS.dbo.SaleItems,270.bcp,270map.txt
IMPT:POS.dbo.SaleItems_local,271.bcp,271map.txt
IMPT:POS.dbo.ClubCardsTypes,181.bcp,181map.txt
IMPT:POS.dbo.Pre_Paid_Prefixes2,326.bcp,326map.txt
IMPT:POS.dbo.GeneralMenus,365.bcp,365map.txt
IMPT:POS.dbo.ProtoTypeMenus,369.bcp,369map.txt
IMPT:POS.dbo.PaymentMethodMonitoring,188.bcp,188map.txt
IMPT:POS.dbo.CoinsRates,19.bcp,19map.txt
IMPT:POS.dbo.Coins_notes_details,119.bcp,119map.txt
IMPT:POS.dbo.PraxellTablesCode,189.bcp,189map.txt
IMPT:POS.dbo.PraxelTbls,195.bcp,195map.txt
IMPT:POS.dbo.VeriCardTbls,528.bcp,528map.txt
IMPT:POS.dbo.VeriCardClubs,529.bcp,529map.txt
IMPT:POS.dbo.Rulers,103.bcp,103map.txt
IMPT:POS.dbo.Multiple_Barcode,619.bcp,619map.txt
IMPT:POS.dbo.MultipassTbls,273.bcp,273map.txt
