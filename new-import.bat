@echo off
setlocal enabledelayedexpansion

set Server=.\sqlexpress
set Database=POS
set Username=sa
set Password=sa
set LogDir=Logs
set ScriptRoot=%~dp0
set EnableLogging=false

:: Parse command-line arguments
for %%x in (%*) do (
    if /i "%%x"=="-nolog" set EnableLogging=false
    if /i "%%x"=="--no-log" set EnableLogging=false
    if /i "%%x"=="/nolog" set EnableLogging=false
    if /i "%%x"=="-log" set EnableLogging=true
    if /i "%%x"=="--log" set EnableLogging=true
    if /i "%%x"=="/log" set EnableLogging=true
)

powershell -ExecutionPolicy Bypass -File "%ScriptRoot%import.ps1" -BatFile "%~f0"
exit /b %errorlevel%

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
