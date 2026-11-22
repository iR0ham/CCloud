#Requires -Version 7.0
<#
    Runs the Windows binary that CI just produced and proves it actually starts.

    A green `flutter build windows` only means the compiler and linker were happy;
    it says nothing about whether the embedder can come up, whether libmpv loads,
    or whether the window ever appears. This script closes that gap on the CI
    runner: it launches ccloud.exe, waits for a visible top-level window titled
    "CCloud", keeps the process under observation for a few more seconds so an
    early renderer/codec crash cannot pass as success, and grabs a screenshot as
    rendering evidence.

    Any functional failure exits non-zero so the workflow goes red. The screenshot
    is best-effort: a runner without a compositing desktop must not turn a working
    app into a failing build.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [string]$ScreenshotPath = 'windows-smoke.png',

    [int]$WindowTimeoutSeconds = 60,

    [int]$SettleSeconds = 10
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $ReleaseDir).Path
$exe = Join-Path $root 'ccloud.exe'

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "::error::ccloud.exe is missing from $root"
    exit 1
}

Write-Host "Contents of $root :"
Get-ChildItem -LiteralPath $root -File | ForEach-Object {
    Write-Host ("  {0,12}  {1}" -f $_.Length, $_.Name)
}

# media_kit ships libmpv as a loose DLL next to the exe. Without it the app opens
# and then fails on every playback request, which is exactly the class of bug a
# build-only check would miss. The three MSVC runtime DLLs are imported by
# ccloud.exe and every plugin DLL; a package without them dies before any window
# and used to pass CI silently.
foreach ($required in @(
    'libmpv-2.dll',
    'flutter_windows.dll',
    'data\app.so',
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $required))) {
        Write-Host "::error::$required is missing next to ccloud.exe"
        exit 1
    }
}

$app = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru
Write-Host "Started ccloud.exe as PID $($app.Id)"

function Stop-App {
    param($Process)
    $Process.Refresh()
    if (-not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

$title = ''
$deadline = (Get-Date).AddSeconds($WindowTimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $app.Refresh()
    if ($app.HasExited) { break }
    if ($app.MainWindowHandle -ne 0) {
        $title = $app.MainWindowTitle
        if ($title) { break }
    }
    Start-Sleep -Milliseconds 500
}

if ($app.HasExited) {
    Write-Host ("::error::ccloud.exe exited on its own with code {0} before showing any window" -f $app.ExitCode)
    exit 1
}

$app.Refresh()
if ($app.MainWindowHandle -eq 0) {
    Write-Host ("::error::ccloud.exe is alive but MainWindowHandle is still zero after {0}s" -f $WindowTimeoutSeconds)
    Stop-App $app
    exit 1
}

if (-not $title) {
    Write-Host ("::error::ccloud.exe is alive but created no visible top-level window within {0}s" -f $WindowTimeoutSeconds)
    Get-Process -Id $app.Id |
        Format-List Id, MainWindowHandle, MainWindowTitle, Responding |
        Out-String -Width 200 | Write-Host
    # Distinguishes "the app is broken" from "this runner has no interactive
    # desktop to draw on": if the native libraries are loaded and the process is
    # responding, the embedder came up and only the window is unverifiable here.
    try {
        $modules = $app.Modules | ForEach-Object { $_.ModuleName }
        Write-Host ("Loaded modules ({0}): {1}" -f $modules.Count, ($modules -join ', '))
        $responding = (Get-Process -Id $app.Id).Responding
        Write-Host "Responding: $responding"
    }
    catch {
        Write-Host "Could not inspect modules: $($_.Exception.Message)"
    }
    Stop-App $app
    exit 1
}

Write-Host "Window title: [$title]"
$startupLog = Join-Path $env:LOCALAPPDATA 'CCloud\startup.log'
if (Test-Path -LiteralPath $startupLog) {
    Write-Host "startup.log ($startupLog):"
    Get-Content -LiteralPath $startupLog -Tail 20 | ForEach-Object { Write-Host "  $_" }
}
else {
    Write-Host "::warning::startup.log was not written to $startupLog"
}
# The runner owns two diagnostic dialogs ("CCloud - startup failed" and
# "CCloud - window did not appear"). Those are top-level windows with the
# product name in the title, so they would otherwise pass the title check
# exactly when the app is broken.
if ($title -like 'CCloud - *') {
    Write-Host "::error::ccloud.exe is showing its own failure dialog [$title] - see startup.log above"
    Stop-App $app
    exit 1
}
if ($title -notlike '*CCloud*') {
    Write-Host "::error::unexpected window title '$title' - expected the product name CCloud"
    Stop-App $app
    exit 1
}

Start-Sleep -Seconds $SettleSeconds
$app.Refresh()
if ($app.HasExited) {
    Write-Host ("::error::ccloud.exe crashed {0}s after its window appeared (exit code {1})" -f $SettleSeconds, $app.ExitCode)
    exit 1
}

try {
    $loaded = @($app.Modules | ForEach-Object { $_.ModuleName })
    foreach ($probe in @('libmpv-2.dll', 'flutter_windows.dll', 'libEGL.dll', 'media_kit_video_plugin.dll', 'cnativeapi.dll')) {
        if ($loaded -contains $probe) {
            Write-Host "loaded in process: $probe"
        }
        else {
            Write-Host "::warning::$probe was not loaded by the running process"
        }
    }
}
catch {
    Write-Host "Module inspection skipped: $($_.Exception.Message)"
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save((Join-Path (Get-Location) $ScreenshotPath))
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Host "Screenshot written to $ScreenshotPath"
}
catch {
    Write-Host "Screenshot skipped: $($_.Exception.Message)"
}

Write-Host 'OK: ccloud.exe started, owns a visible window titled CCloud, and stayed alive.'
Stop-App $app
exit 0
