#Requires -Version 7.0
<#
    Installs the CI-built setup.exe for real, then runs the launch smoke test
    against the INSTALLED copy.

    The portable package has always been executed by CI, but the installer -
    which is the package the README recommends - was only ever compiled and
    uploaded. That leaves the copy step, the target folder, the shortcuts and
    the registry entry unproven: an installer that installs to the wrong place,
    drops the runtime DLLs, or produces an exe that cannot start would still
    have shipped green. This script catches exactly that.

    Three rules shape the implementation, and the first run of this script on a
    real runner is what taught us two of them:

    1. Exit codes are evidence, never proof. A setup.exe that has to elevate
       hands the work to a child, so success is decided by finding the file Inno
       writes last (unins000.exe) within a deadline - not by the exit code of
       the process we started.
    2. The uninstall registration is matched by pointing it at the folder that
       was just installed into. The first run installed everything correctly and
       then went red on a DisplayName -eq 'CCloud' check, because that string is
       not guaranteed to be the bare app name.
    3. It only proves anything on a clean machine, which a GitHub-hosted Windows
       runner always is. If CCloud is somehow already installed the script
       refuses to guess and exits 4 rather than crediting an old install.

    Any functional failure exits non-zero so the workflow goes red.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SetupPath,

    [string]$ScreenshotPath = 'windows-smoke-installed.png',

    [int]$InstallTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Write-Failure {
    param([string]$Message)
    Write-Host "::error::$Message"
}

$setup = (Resolve-Path -LiteralPath $SetupPath).Path
Write-Host "Installer under test: $setup ($((Get-Item -LiteralPath $setup).Length) bytes)"

$smoke = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\windows-smoke.ps1'
if (-not (Test-Path -LiteralPath $smoke)) {
    Write-Failure 'windows-smoke.ps1 was not found next to this script'
    exit 1
}

# The installer writes its own log; on failure it is the only explanation CI has.
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$installLog = Join-Path $tempRoot 'ccloud-install.log'
if (Test-Path -LiteralPath $installLog) {
    Remove-Item -LiteralPath $installLog -Force
}

# Where Inno's {autopf} lands: Program Files (the 64-bit one, never (x86),
# because ArchitecturesInstallIn64BitMode=x64) for a machine-wide install, and
# %LOCALAPPDATA%\Programs\CCloud for a /CURRENTUSER install.
$prefixes = @(
    (Join-Path $env:ProgramFiles 'CCloud'),
    (Join-Path $env:LOCALAPPDATA 'Programs\CCloud')
)

function Get-InstallDir {
    # unins000.exe is written in Inno's post-install step, so by default only a
    # finished install counts. -Partial also accepts a folder where ccloud.exe
    # appeared without the uninstaller: that is a half-copied install and has to
    # be reported as such instead of as 'nothing installed'.
    param([switch]$Partial)

    foreach ($prefix in $prefixes) {
        $exe = Join-Path $prefix 'ccloud.exe'
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        if ($Partial -or (Test-Path -LiteralPath (Join-Path $prefix 'unins000.exe'))) {
            return (Resolve-Path -LiteralPath $prefix).Path
        }
    }
    return $null
}

function Wait-InstallDir {
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $dir = Get-InstallDir
        if ($dir) { return $dir }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Show-InstallLog {
    if (Test-Path -LiteralPath $installLog) {
        Write-Host '--- last 40 lines of the Inno Setup log ---'
        Get-Content -LiteralPath $installLog -Tail 40 | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host '::warning::the installer wrote no log file'
    }
}

function Invoke-Installer {
    param([string[]]$Arguments)

    Write-Host ("Running {0} {1}" -f (Split-Path -Leaf $setup), ($Arguments -join ' '))
    # Start-Process rather than a direct call keeps the argument list literal.
    $proc = Start-Process -FilePath $setup -ArgumentList $Arguments -PassThru
    if ($proc.WaitForExit($InstallTimeoutSeconds * 1000)) {
        Write-Host ("setup.exe (PID {0}) exited with code {1}" -f $proc.Id, $proc.ExitCode)
    }
    else {
        Write-Host ("::warning::setup.exe (PID {0}) has not exited after {1}s" -f
            $proc.Id, $InstallTimeoutSeconds)
    }
}

$stale = Get-InstallDir -Partial
if ($stale) {
    Write-Failure ("CCloud is already installed at $stale; this test only proves anything on a clean machine, so uninstall it and re-run.")
    exit 4
}

$quiet = @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    '/CLOSEAPPLICATIONS',
    "/LOG=$installLog"
)

Invoke-Installer -Arguments $quiet
$installed = Wait-InstallDir -Seconds $InstallTimeoutSeconds

if (-not $installed) {
    # /CURRENTUSER exists from Inno Setup 6.3; windows-installer.ps1 logs the
    # compiler version, so an 'unknown parameter' outcome can be attributed
    # instead of guessed at.
    Write-Host '::warning::machine-wide install produced no completed install; retrying per-user'
    Show-InstallLog
    Invoke-Installer -Arguments (@('/CURRENTUSER') + $quiet)
    $installed = Wait-InstallDir -Seconds $InstallTimeoutSeconds
}

if (-not $installed) {
    $partial = Get-InstallDir -Partial
    if ($partial) {
        Write-Failure ("setup.exe left an incomplete install at ${partial}: ccloud.exe exists but unins000.exe does not.")
    }
    else {
        Write-Failure ("CCloud was not installed into any of: {0}" -f ($prefixes -join ', '))
    }
    Show-InstallLog
    exit 1
}

Write-Host "Installed to: $installed"
Get-ChildItem -LiteralPath $installed -Recurse -File | Sort-Object FullName | ForEach-Object {
    Write-Host ("  {0,12}  {1}" -f $_.Length, $_.FullName.Substring($installed.Length).TrimStart('\'))
}

# BUILD.md promises an Add/Remove Programs entry, so assert the entry belongs to
# THIS install: an Inno uninstall registration is a *_is1 subkey whose
# InstallLocation or UninstallString points into the folder just created. If no
# such key exists the run lists every *_is1 it can see, which is the evidence
# needed to tell 'not registered' apart from 'registered under another name'.
$arpRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
$normalized = $installed.TrimEnd('\')
$registered = @()
$seen = @()
foreach ($root in $arpRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notlike '*_is1') { continue }
        $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        $entry = [pscustomobject]@{
            Key            = "$root\$($key.PSChildName)"
            DisplayName    = [string]$p.DisplayName
            DisplayVersion = [string]$p.DisplayVersion
            Location       = [string]$p.InstallLocation
            Uninstall      = [string]$p.UninstallString
        }
        $seen += $entry
        $locationMatches = $entry.Location -and ($entry.Location.TrimEnd('\') -ieq $normalized)
        $uninstallMatches = $entry.Uninstall -and
            $entry.Uninstall.StartsWith($normalized, [StringComparison]::OrdinalIgnoreCase)
        if ($locationMatches -or $uninstallMatches) { $registered += $entry }
    }
}

if ($registered.Count -eq 0) {
    Write-Failure 'no Add/Remove Programs registration points into the folder that was just installed'
    Write-Host ("Inno uninstall registrations found ({0}):" -f $seen.Count)
    foreach ($entry in $seen) {
        Write-Host ("  name=[{0}] version=[{1}] location=[{2}] key={3}" -f
            $entry.DisplayName, $entry.DisplayVersion, $entry.Location, $entry.Key)
    }
    if ($seen.Count -eq 0) { Write-Host '  (none - not even a *_is1 key exists)' }
    Show-InstallLog
    exit 1
}
foreach ($entry in $registered) {
    Write-Host ("Add/Remove Programs entry: name=[{0}] version=[{1}] location=[{2}] key={3}" -f
        $entry.DisplayName, $entry.DisplayVersion, $entry.Location, $entry.Key)
}

# The same assertions and the same launch test the portable package passes -
# against the files that are now actually on disk in the install location.
# It runs in a child pwsh on purpose: windows-smoke.ps1 ends with `exit`, and
# `exit` inside a script called with & would abort this script before the
# installer log could be printed. A separate process turns that into a plain
# exit code.
$pwsh = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    (Get-Command pwsh).Source
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}

& $pwsh -NoProfile -ExecutionPolicy Bypass -File $smoke `
    -ReleaseDir $installed `
    -ScreenshotPath $ScreenshotPath
$smokeExit = $LASTEXITCODE
if ($smokeExit -ne 0) {
    Write-Failure "the installed ccloud.exe failed the launch smoke test (exit $smokeExit)"
    Show-InstallLog
    exit $smokeExit
}

Write-Host "OK: setup.exe installed CCloud and the installed binary passed the launch smoke test."
exit 0
