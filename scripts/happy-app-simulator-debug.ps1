[CmdletBinding()]
param(
    [switch]$ForceInstall,
    [switch]$SkipInstall,
    [switch]$SkipHappyWireBuild,
    [switch]$SkipTypecheck,
    [switch]$SkipPrebuild,
    [switch]$ResetMetroCache,
    [switch]$NoDaemon
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SharedScript = Join-Path $PSScriptRoot 'happy-app-local.ps1'
$DebugApkPath = Join-Path $RepoRoot 'packages/happy-app/android/app/build/outputs/apk/debug/app-debug.apk'
$AliasApkPath = Join-Path $RepoRoot 'packages/happy-app/android/app/build/outputs/apk/debug/happy-simulator-debug-x86_64.apk'

function Write-Step {
    param([string]$Message)
    Write-Host "[happy-app] $Message" -ForegroundColor Cyan
}

function Add-SwitchArgument {
    param(
        [ref]$Arguments,
        [switch]$Enabled,
        [string]$Name
    )

    if ($Enabled) {
        $Arguments.Value += $Name
    }
}

$arguments = @(
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $SharedScript,
    '-Mode',
    'apk',
    '-Architectures',
    'x86_64'
)

Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$ForceInstall -Name '-ForceInstall'
Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$SkipInstall -Name '-SkipInstall'
Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$SkipHappyWireBuild -Name '-SkipHappyWireBuild'
Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$SkipTypecheck -Name '-SkipTypecheck'
Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$SkipPrebuild -Name '-SkipPrebuild'
Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$ResetMetroCache -Name '-ResetMetroCache'
Add-SwitchArgument -Arguments ([ref]$arguments) -Enabled:$NoDaemon -Name '-NoDaemon'

& powershell @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    exit $exitCode
}

if (-not (Test-Path $DebugApkPath)) {
    throw "Debug APK not found: $DebugApkPath"
}

Copy-Item -LiteralPath $DebugApkPath -Destination $AliasApkPath -Force
Write-Step "Simulator debug APK alias ready: $AliasApkPath"
