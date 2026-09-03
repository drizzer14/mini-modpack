#requires -Version 5
<#
    Build the 14th_ua's Mini Modpack Windows installer (setup.exe) with Inno Setup.

    Prerequisites:
      1. The four payload .wotmods must already be staged into ..\payload by:
             python build\gather_payload.py
      2. Inno Setup must be installed (provides ISCC.exe):
             winget install -e --id JRSoftware.InnoSetup

    Usage:
        pwsh installer\build_installer.ps1
    Output:
        dist\14th_ua-MiniModpack-Setup-<version>.exe
#>

$ErrorActionPreference = 'Stop'

$InstallerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot     = Split-Path -Parent $InstallerDir
$Iss          = Join-Path $InstallerDir 'modpack-setup.iss'
$PayloadIss   = Join-Path $RepoRoot 'payload\payload.iss'

function Find-ISCC {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles        'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA        'Programs\Inno Setup 6\ISCC.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# --- preflight ---------------------------------------------------------------
if (-not (Test-Path $PayloadIss)) {
    throw "Payload manifest not found: $PayloadIss`nStage the payload first:`n    python build\gather_payload.py"
}
$iscc = Find-ISCC
if (-not $iscc) {
    throw "ISCC.exe (Inno Setup compiler) not found. Install it:`n    winget install -e --id JRSoftware.InnoSetup"
}

Write-Host "ISCC:    $iscc"
Write-Host "Payload: $PayloadIss"
Write-Host "Script:  $Iss"
Write-Host ''

# --- compile -----------------------------------------------------------------
& $iscc $Iss
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

$out = Get-ChildItem (Join-Path $RepoRoot 'dist') -Filter '14th_ua-MiniModpack-Setup-*.exe' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host ''
Write-Host "Built installer: $($out.FullName)" -ForegroundColor Green
