param(
    [string]$BatFile
)

# 1. Initialize configuration from environment variables or defaults
$Server = $env:Server
if ([string]::IsNullOrEmpty($Server)) { $Server = ".\sqlexpress" }
$Database = $env:Database
if ([string]::IsNullOrEmpty($Database)) { $Database = "POS" }
$Username = $env:Username
if ([string]::IsNullOrEmpty($Username)) { $Username = "sa" }
$Password = $env:Password
if ([string]::IsNullOrEmpty($Password)) { $Password = "sa" }
$LogDir = $env:LogDir
if ([string]::IsNullOrEmpty($LogDir)) { $LogDir = "Logs" }
$EnableLoggingEnv = $env:EnableLogging
if ($EnableLoggingEnv -eq "true") { $EnableLogging = $true } else { $EnableLogging = $false }

$ScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

# Setup log file
$TS = Get-Date -Format "ddMMyyyy_HHmmss"
if ($EnableLogging) {
    if (-not (Test-Path $LogDir)) {
        [void](New-Item -ItemType Directory -Path $LogDir -Force)
    }
    $LogFile = Join-Path $LogDir "import_sql_$TS.log"
    [void](New-Item -ItemType File -Path $LogFile -Force)
} else {
    $LogFile = $null
}

# Logger helper
function Write-Log {
    param(
        [string]$Msg,
        [string]$Level = "Info"
    )
    $now = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $color = "Cyan"
    switch ($Level) {
        "Info"   { $color = "Cyan" }
        "Ok"     { $color = "Green" }
        "Warn"   { $color = "Yellow" }
        "Error"  { $color = "Red" }
        "Header" { $color = "Magenta" }
        "Detail" { $color = "DarkGray" }
    }
    Write-Host "$now [$Level] $Msg" -ForegroundColor $color
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "$now [$Level] $Msg" -Encoding Default
    }
}

# Align format file helper
function Align-FormatFile {
    param(
        [string]$OriginalFmtPath,
        [string]$FreshFmtPath
    )
    $o = [System.IO.File]::ReadAllText($OriginalFmtPath, [System.Text.Encoding]::Default)
    $ol = $o -split '\r?\n'
    if ($ol.Count -lt 2) { throw "Invalid original format file" }
    
    $of = [ordered]@{}
    for ($i = 2; $i -lt $ol.Count; $i++) {
        $l = $ol[$i]
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $p = $l -split '\s+', 8
        if ($p.Length -lt 7) { continue }
        $of[$p[6]] = @{ li = $i; sc = $p[5]; te = $p[4] }
    }
    
    $n = [System.IO.File]::ReadAllText($FreshFmtPath, [System.Text.Encoding]::Default)
    $nl = $n -split '\r?\n'
    $nf = @{}
    for ($i = 2; $i -lt $nl.Count; $i++) {
        $l = $nl[$i]
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $p = $l -split '\s+', 8
        if ($p.Length -lt 7) { continue }
        $nf[$p[6]] = @{ sc = $p[5] }
    }
    
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add($ol[0])
    [void]$out.Add($ol[1])
    
    foreach ($cn in $of.Keys) {
        $inf = $of[$cn]
        $ln = $ol[$inf.li]
        $osc = $inf.sc
        $te = $inf.te
        $nsc = if ($nf.ContainsKey($cn)) { $nf[$cn]['sc'] } else { '0' }
        
        if ($nsc -ne $osc) {
            $ete = [regex]::Escape($te)
            $ecn = [regex]::Escape($cn)
            $nln = $ln -replace ('(' + $ete + '\s+)' + $osc + '(\s+' + $ecn + ')'), ('${1}' + $nsc + '${2}')
            if ($nln -eq $ln) {
                $nln = $ln -replace ('(' + $ete + '\s+)' + $osc + '(\s+\S+)$'), ('${1}' + $nsc + '${2}')
            }
            [void]$out.Add($nln)
        } else {
            [void]$out.Add($ln)
        }
    }
    
    $re = [Environment]::NewLine
    return ($out -join $re) + $re
}

# BCP Import runner helper
function Run-BcpImport {
    param(
        [string]$Table,
        [string]$Data,
        [string]$Format
    )
    
    $bcpArgs = @(
        $Table,
        "in",
        $Data,
        "-f",
        $Format,
        "-E",
        "-C",
        "1255",
        "-S",
        $Server,
        "-U",
        $Username,
        "-P",
        $Password,
        "-b",
        "10000",
        "-a",
        "65535"
    )
    
    $bcpOutput = New-Object System.Collections.Generic.List[string]
    & bcp $bcpArgs 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Write-Host "    $line" -ForegroundColor Gray
        $bcpOutput.Add($line)
        if ($LogFile) {
            Add-Content -Path $LogFile -Value "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) [Detail]     $line" -Encoding Default
        }
    }
    
    $bcpFailed = $false
    foreach ($line in $bcpOutput) {
        if ($line -like "*Error = [Microsoft]*") {
            $bcpFailed = $true
            break
        }
    }
    
    return $bcpFailed
}

# Begin Execution
Write-Log "=== new-import started ===" "Header"
Write-Log "Server: $Server | Database: $Database" "Info"
if ($LogFile) {
    Write-Log "Log file: $LogFile" "Info"
} else {
    Write-Log "Log file: Disabled" "Info"
}
Write-Log "" ""

# Wake SQL Server
Write-Log "Waking SQL Server..." "Info"
$connectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;Timeout=10;"
$woke = $false
for ($i = 1; $i -le 3; $i++) {
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT 1"
        $command.CommandTimeout = 10
        [void]$command.ExecuteScalar()
        $connection.Close()
        $woke = $true
        Write-Log "  SQL Server ready." "Ok"
        break
    } catch {
        Write-Log "  Attempt $i/3 -- waiting..." "Warn"
        Start-Sleep -Seconds 3
    }
}

if (-not $woke) {
    Write-Log "  [WARN] Cannot connect to SQL Server -- will retry per table." "Warn"
}

# Parse tables from batch file
$truncTables = @()
$importTables = @()
if (Test-Path $BatFile) {
    $lines = Get-Content -Path $BatFile
    foreach ($line in $lines) {
        if ($line -like "TRUNC:*") {
            $tbl = ($line -split ":", 2)[1].Trim()
            $truncTables += $tbl
        }
        elseif ($line -like "IMPT:*") {
            $parts = ($line -split ":", 2)[1] -split ","
            if ($parts.Length -eq 3) {
                $importTables += [PSCustomObject]@{
                    Table   = $parts[0].Trim()
                    BcpFile = $parts[1].Trim()
                    FmtFile = $parts[2].Trim()
                }
            }
        }
    }
}

$exitCode = 0

# PHASE 1: TRUNCATE TABLES
Write-Log "====== PHASE 1: TRUNCATE TABLES ======" "Header"
$failedTrunc = 0
$totalTrunc = $truncTables.Count + $importTables.Count
$currentTrunc = 0

if ($woke) {
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        
        foreach ($tbl in $truncTables) {
            $currentTrunc++
            Write-Log "  [$currentTrunc/$totalTrunc] TRUNCATE TABLE $tbl" "Detail"
            try {
                $command = $connection.CreateCommand()
                $command.CommandText = "TRUNCATE TABLE $tbl"
                $command.CommandTimeout = 15
                [void]$command.ExecuteNonQuery()
                Write-Log "  [OK] TRUNCATE $tbl" "Ok"
            } catch {
                Write-Log "  [FAIL] TRUNCATE $tbl" "Error"
                $failedTrunc++
                $exitCode = 1
            }
        }
        
        foreach ($item in $importTables) {
            $tbl = $item.Table
            $currentTrunc++
            Write-Log "  [$currentTrunc/$totalTrunc] TRUNCATE TABLE $tbl" "Detail"
            try {
                $command = $connection.CreateCommand()
                $command.CommandText = "TRUNCATE TABLE $tbl"
                $command.CommandTimeout = 15
                [void]$command.ExecuteNonQuery()
                Write-Log "  [OK] TRUNCATE $tbl" "Ok"
            } catch {
                Write-Log "  [FAIL] TRUNCATE $tbl" "Error"
                $failedTrunc++
                $exitCode = 1
            }
        }
        
        $connection.Close()
    } catch {
        Write-Log "  [FAIL] Failed to open connection for truncation: $($_.Exception.Message)" "Error"
        $exitCode = 1
    }
} else {
    Write-Log "  [FAIL] SQL Server connection failed, skipping truncate." "Error"
    $exitCode = 1
}

# PHASE 2: BCP IMPORT
Write-Log "====== PHASE 2: BCP IMPORT ======" "Header"
$failedImport = 0
$totalTables = $importTables.Count
$currentTable = 0

foreach ($item in $importTables) {
    $currentTable++
    $tbl = $item.Table
    $bcpFile = $item.BcpFile
    $fmtFile = $item.FmtFile
    
    $dataPath = Join-Path $ScriptRoot $bcpFile
    $fmtPath = Join-Path $ScriptRoot $fmtFile
    
    if (-not (Test-Path $dataPath)) {
        Write-Log "  [$currentTable/$totalTables] [WARN] $bcpFile not found - skip $tbl" "Warn"
        continue
    }
    if (-not (Test-Path $fmtPath)) {
        Write-Log "  [$currentTable/$totalTables] [WARN] $fmtFile not found - skip $tbl" "Warn"
        continue
    }
    
    # Generate fresh format file in temp directory
    $tempPath = [System.IO.Path]::GetTempPath()
    $randomName = [System.IO.Path]::GetRandomFileName()
    $freshFmt = [System.IO.Path]::Combine($tempPath, "bcp_fresh_${randomName}.fmt")
    $bridgeFmt = [System.IO.Path]::Combine($tempPath, "bcp_bridge_${randomName}.fmt")
    
    Write-Log "  [$currentTable/$totalTables] bcp $tbl in $bcpFile" "Detail"
    
    $fmtArgs = @(
        $tbl,
        "format",
        "nul",
        "-f",
        $freshFmt,
        "-n",
        "-S",
        $Server,
        "-U",
        $Username,
        "-P",
        $Password
    )
    $fmtProcess = Start-Process -FilePath "bcp" -ArgumentList $fmtArgs -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
    
    $fmtToUse = $fmtPath
    if (Test-Path $freshFmt) {
        try {
            $alignedContent = Align-FormatFile -OriginalFmtPath $fmtPath -FreshFmtPath $freshFmt
            [System.IO.File]::WriteAllText($bridgeFmt, $alignedContent, [System.Text.Encoding]::Default)
            if (Test-Path $bridgeFmt) {
                $fmtToUse = $bridgeFmt
            }
        } catch {
            Write-Log "  [WARN] Failed to align format file for ${tbl}: $($_.Exception.Message)" "Warn"
        }
    }
    
    $bcpFailed = Run-BcpImport -Table $tbl -Data $dataPath -Format $fmtToUse
    
    if ($bcpFailed) {
        Write-Log "  [WARN] Import failed, retrying once in 3 seconds..." "Warn"
        Start-Sleep -Seconds 3
        $bcpFailed = Run-BcpImport -Table $tbl -Data $dataPath -Format $fmtToUse
    }
    
    if ($bcpFailed) {
        Write-Log "  [FAIL] IMPORT $tbl" "Error"
        $failedImport++
        $exitCode = 1
    } else {
        if ($fmtToUse -eq $bridgeFmt) {
            Write-Log "  [OK] IMPORT $tbl (aligned mapping)" "Ok"
        } else {
            Write-Log "  [OK] IMPORT $tbl" "Ok"
        }
    }
    
    # Clean up temp files
    if (Test-Path $freshFmt) { Remove-Item $freshFmt -Force -ErrorAction SilentlyContinue }
    if (Test-Path $bridgeFmt) { Remove-Item $bridgeFmt -Force -ErrorAction SilentlyContinue }
}

Write-Log "" ""
Write-Log "====== IMPORT COMPLETE ======" "Header"

if ($exitCode -ne 0) {
    Write-Log "  Import FAILED -- check log." "Error"
    Write-Host ""
    if ($LogFile) {
        Write-Host "Import failed. Check the Logs folder for details."
    } else {
        Write-Host "Import failed."
    }
    Read-Host "Press Enter to continue..."
} else {
    Write-Log "  Import completed successfully." "Ok"
}

exit $exitCode
