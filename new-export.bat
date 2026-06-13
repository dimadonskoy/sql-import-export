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
set Force=true
set EnableLogging=false
if not defined BcpVersion set BcpVersion=110

:: Parse command-line arguments
for %%x in (%*) do (
    if /i "%%x"=="-nolog" set EnableLogging=false
    if /i "%%x"=="--no-log" set EnableLogging=false
    if /i "%%x"=="/nolog" set EnableLogging=false
    if /i "%%x"=="-log" set EnableLogging=true
    if /i "%%x"=="--log" set EnableLogging=true
    if /i "%%x"=="/log" set EnableLogging=true
    if /i "%%x"=="-sql2017" set BcpVersion=110
    if /i "%%x"=="--sql2017" set BcpVersion=110
    if /i "%%x"=="/sql2017" set BcpVersion=110
)

set BcpOpt=
if defined BcpVersion (
    set BcpOpt= -V %BcpVersion%
)


set Y=%date:~-4,4%
set M=%date:~-10,2%
set D=%date:~-7,2%
set HH=%time:~0,2%
set MI=%time:~3,2%
set SS=%time:~6,2%
set TS=%D%%M%%Y%_%HH%%MI%%SS%
set TS=%TS: =0%

if "%EnableLogging%"=="true" (
    if not exist "%LogDir%" mkdir "%LogDir%"
    set "LogFile=%LogDir%\export_sql_%TS%.log"
    type nul > "!LogFile!"
) else (
    set LogFile=
)

call :log "=== new-export started ===" "Header"
call :log "Server: %Server% | Database: %Database%" "Info"
if defined BcpVersion (
    call :log "BCP Version Compatibility: %BcpVersion% (-V %BcpVersion%)" "Info"
)
if defined LogFile (
    call :log "Log file: %LogFile%" "Info"
) else (
    call :log "Log file: Disabled" "Info"
)
call :log "" ""

call :log "====== PHASE 1: BCP EXPORT ======" "Header"

for /f "tokens=1,2,3,4 delims=,:" %%a in ('findstr /b "EXPT:" "%~f0"') do (
    set TableName=%%b
    set BcpFile=%%c
    set DataPath=%ScriptRoot%%%c

    if "%Force%"=="true" (
        call :bcp_export "%%b" "!DataPath!"
    ) else (
        if not exist "!DataPath!" (
            call :bcp_export "%%b" "!DataPath!"
        ) else (
            call :log "  [SKIP] %%c exists (set Force=true to overwrite)" "Warn"
        )
    )
)

call :log "" ""
call :log "====== PHASE 2: FORMAT FILES ======" "Header"

for /f "tokens=1,2,3,4 delims=,:" %%a in ('findstr /b "EXPT:" "%~f0"') do (
    set TableName=%%b
    set FmtFile=%%d
    set FmtPath=%ScriptRoot%%%d

    if "%Force%"=="true" (
        call :bcp_format "%%b" "!FmtPath!"
    ) else (
        if not exist "!FmtPath!" (
            call :bcp_format "%%b" "!FmtPath!"
        ) else (
            call :log "  [SKIP] %%d exists (set Force=true to overwrite)" "Warn"
        )
    )
)

call :log "" ""
call :log "====== EXPORT COMPLETE ======" "Header"
if %exitcode% neq 0 (
    call :log "  Export FAILED -- check log." "Error"
    echo.
    if defined LogFile (
        echo Export failed. Check the Logs folder for details.
    ) else (
        echo Export failed.
    )
    pause
) else (
    call :log "  Export completed successfully." "Ok"
)

exit /b %exitcode%

:bcp_export
set tbl=%~1
set data=%~2
call :log "  bcp %tbl% out %data%%BcpOpt%" "Detail"
bcp "%tbl%" out "%data%" -n -C 1255 -S%Server% -U%Username% -P%Password%%BcpOpt%
if errorlevel 1 (
    call :log "  [FAIL] EXPORT %tbl%" "Error"
    set exitcode=1
) else (
    call :log "  [OK] EXPORT %tbl%" "Ok"
)
goto :eof

:bcp_format
set tbl=%~1
set fmt=%~2
call :log "  bcp %tbl% format -> %fmt%%BcpOpt%" "Detail"
bcp "%tbl%" format nul -f"%fmt%" -n -S%Server% -U%Username% -P%Password%%BcpOpt%
if errorlevel 1 (
    call :log "  [FAIL] FORMAT %tbl%" "Error"
    set exitcode=1
) else (
    call :log "  [OK] FORMAT %tbl%" "Ok"
)
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
if defined LogFile (
    echo !now! [!level!] !msg!>>"!LogFile!"
)
goto :eof

REM >>> DATA SECTION <<<
EXPT:POS.dbo.PraxellTablesCode,189.bcp,189map.txt
EXPT:POS.dbo.PraxelTbls,195.bcp,195map.txt
EXPT:POS.dbo.VeriCardTbls,528.bcp,528map.txt
EXPT:POS.dbo.VeriCardClubs,529.bcp,529map.txt
EXPT:POS.dbo.Settings,8.bcp,8map.txt
EXPT:POS.dbo.CreditTypes,10.bcp,10map.txt
EXPT:POS.dbo.WayBillMenu,15.bcp,15map.txt
EXPT:POS.dbo.Cards,26.bcp,26map.txt
EXPT:POS.dbo.Items,27.bcp,27map.txt
EXPT:POS.dbo.ItemTypes,34.bcp,34map.txt
EXPT:POS.dbo.PriceLists,35.bcp,35map.txt
EXPT:POS.dbo.ItemsBundle_package,37.bcp,37map.txt
EXPT:POS.dbo.Colors,45.bcp,45map.txt
EXPT:POS.dbo.Models,54.bcp,54map.txt
EXPT:POS.dbo.ItemsCatalogDetection,65.bcp,65map.txt
EXPT:POS.dbo.CampaignTypes,67.bcp,67map.txt
EXPT:POS.dbo.CampaignFields,68.bcp,68map.txt
EXPT:POS.dbo.Campaigns,69.bcp,69map.txt
EXPT:POS.dbo.TblTbls,75.bcp,75map.txt
EXPT:POS.dbo.GeneralCarrierFile,76.bcp,76map.txt
EXPT:POS.dbo.MenusOnDemand,100.bcp,100map.txt
EXPT:POS.dbo.ProgramsList,101.bcp,101map.txt
EXPT:POS.dbo.Rulers,103.bcp,103map.txt
EXPT:POS.dbo.POSPermanentMessages,106.bcp,106map.txt
EXPT:POS.dbo.EmpPermission,107.bcp,107map.txt
EXPT:POS.dbo.CreditInvoiceTable,118.bcp,118map.txt
EXPT:POS.dbo.Accounts,149.bcp,149map.txt
EXPT:POS.dbo.Cards_continue,185.bcp,185map.txt
EXPT:POS.dbo.SaleItems,270.bcp,270map.txt
EXPT:POS.dbo.SaleItems_local,271.bcp,271map.txt
EXPT:POS.dbo.ClubCardsTypes,181.bcp,181map.txt
EXPT:POS.dbo.Pre_Paid_Prefixes2,326.bcp,326map.txt
EXPT:POS.dbo.GeneralMenus,365.bcp,365map.txt
EXPT:POS.dbo.ProtoTypeMenus,369.bcp,369map.txt
EXPT:POS.dbo.PaymentMethodMonitoring,188.bcp,188map.txt
EXPT:POS.dbo.CoinsRates,19.bcp,19map.txt
EXPT:POS.dbo.Coins_notes_details,119.bcp,119map.txt
EXPT:POS.dbo.Multiple_Barcode,619.bcp,619map.txt
EXPT:POS.dbo.MultipassTbls,273.bcp,273map.txt
EXPT:POS.dbo.Banks,4.bcp,4map.txt
