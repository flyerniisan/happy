[CmdletBinding()]
param(
    [ValidateSet('doctor', 'install', 'web', 'apk', 'apk-release', 'full')]
    [string]$Mode = 'full',
    [switch]$ForceInstall,
    [switch]$SkipInstall,
    [switch]$SkipHappyWireBuild,
    [switch]$SkipTypecheck,
    [switch]$SkipPrebuild,
    [switch]$ResetMetroCache,
    [switch]$NoDaemon,
    [string]$Architectures = 'arm64-v8a',
    [int]$WebPort = 19006
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HappyAppDir = Join-Path $RepoRoot 'packages/happy-app'
$AndroidDir = Join-Path $HappyAppDir 'android'
$WebLog = Join-Path $HappyAppDir 'web-test.log'
$GradleMirrorScript = Join-Path $RepoRoot 'scripts/happy-gradle-mirrors.init.gradle'
$GradleVersion = '8.13'
$GradleHome = Join-Path $env:USERPROFILE ".gradle/local-dist/gradle-$GradleVersion"
$GradleBin = Join-Path $GradleHome 'bin/gradle.bat'
$ApkPath = Join-Path $AndroidDir 'app/build/outputs/apk/debug/app-debug.apk'
$ApkLog = Join-Path $AndroidDir "assembleDebug-$($Architectures -replace '[^A-Za-z0-9_-]', '_').log"
$ReleaseApkPath = Join-Path $AndroidDir 'app/build/outputs/apk/release/app-release.apk'
$ReleaseApkLog = Join-Path $AndroidDir "assembleRelease-$($Architectures -replace '[^A-Za-z0-9_-]', '_').log"
$DefaultJavaHome = 'C:\Program Files\Android\Android Studio\jbr'
$DefaultAndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'

function Write-Step {
    param([string]$Message)
    Write-Host "[happy-app] $Message" -ForegroundColor Cyan
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "[happy-app] $Message" -ForegroundColor Yellow
}

function Require-Path {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path $Path)) {
        throw "$Label not found: $Path"
    }
}

function Add-PathPrefix {
    param([string]$PathToAdd)

    if (-not (Test-Path $PathToAdd)) {
        return
    }

    $entries = @($env:PATH -split ';' | Where-Object { $_ -ne '' })
    if ($entries -contains $PathToAdd) {
        return
    }

    $env:PATH = "$PathToAdd;$env:PATH"
}

function Initialize-Environment {
    Add-PathPrefix 'C:\Program Files\Git\usr\bin'

    if (-not $env:JAVA_HOME -and (Test-Path $DefaultJavaHome)) {
        $env:JAVA_HOME = $DefaultJavaHome
    }

    if (-not $env:ANDROID_SDK_ROOT -and (Test-Path $DefaultAndroidSdk)) {
        $env:ANDROID_SDK_ROOT = $DefaultAndroidSdk
    }

    if (-not $env:ANDROID_HOME -and $env:ANDROID_SDK_ROOT) {
        $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
    }

    if (-not $env:JAVA_HOME) {
        throw 'JAVA_HOME is not set and Android Studio JBR was not found.'
    }

    if (-not $env:ANDROID_SDK_ROOT) {
        throw 'ANDROID_SDK_ROOT is not set and the default Android SDK path was not found.'
    }

    Require-Path (Join-Path $env:JAVA_HOME 'bin/java.exe') 'java.exe'
    Require-Path (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools/adb.exe') 'adb.exe'
    Require-Path $GradleMirrorScript 'Gradle mirror init script'
}

function Invoke-Pnpm {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = $RepoRoot,
        [hashtable]$ExtraEnv = @{}
    )

    Push-Location $WorkingDirectory
    $saved = @{}

    try {
        foreach ($key in $ExtraEnv.Keys) {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, [string]$ExtraEnv[$key], 'Process')
        }

        & corepack pnpm @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "corepack pnpm $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        foreach ($key in $ExtraEnv.Keys) {
            [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process')
        }
        Pop-Location
    }
}

function Get-CommandOutput {
    param([scriptblock]$Script)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Script 2>&1 | Out-String
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return $output.Trim()
}

function Show-Doctor {
    Write-Step 'Environment summary'
    $javaVersion = Get-CommandOutput { java -version }
    $adbVersion = Get-CommandOutput { & (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools/adb.exe') version }

    Write-Host "Repo root: $RepoRoot"
    Write-Host "JAVA_HOME: $env:JAVA_HOME"
    Write-Host "ANDROID_SDK_ROOT: $env:ANDROID_SDK_ROOT"
    Write-Host "ANDROID_HOME: $env:ANDROID_HOME"
    Write-Host "Gradle mirror init: $GradleMirrorScript"
    Write-Host "Local Gradle home: $GradleHome"
    Write-Host "java -version:`n$javaVersion"
    Write-Host "adb version:`n$adbVersion"

    if (Test-Path (Join-Path $env:ANDROID_SDK_ROOT 'cmake')) {
        Write-Host 'Installed CMake versions:'
        Get-ChildItem (Join-Path $env:ANDROID_SDK_ROOT 'cmake') | Select-Object -ExpandProperty Name
    }

    if (Test-Path (Join-Path $env:ANDROID_SDK_ROOT 'ndk')) {
        Write-Host 'Installed NDK versions:'
        Get-ChildItem (Join-Path $env:ANDROID_SDK_ROOT 'ndk') | Select-Object -ExpandProperty Name
    }
}

function Install-HappyAppDependencies {
    $storeDir = Join-Path $RepoRoot 'node_modules/.pnpm'
    if ((Test-Path $storeDir) -and -not $ForceInstall) {
        Write-Step 'Dependencies already installed, skipping install'
        return
    }

    Write-Step 'Installing workspace dependencies required by happy-app'
    Invoke-Pnpm -Arguments @(
        'install',
        '--filter',
        'happy-app...',
        '--reporter',
        'append-only',
        '--no-frozen-lockfile'
    )
}

function Build-HappyWire {
    Write-Step 'Building @slopus/happy-wire'
    Invoke-Pnpm -Arguments @('--filter', '@slopus/happy-wire', 'build')
}

function Typecheck-HappyApp {
    Write-Step 'Running happy-app typecheck'
    Invoke-Pnpm -Arguments @('--filter', 'happy-app', 'typecheck')
}

function Invoke-HappyAppBuildPreparation {
    if ($SkipInstall) {
        Write-Step 'Skipping dependency install'
    }
    else {
        Install-HappyAppDependencies
    }

    if ($SkipHappyWireBuild) {
        Write-Step 'Skipping @slopus/happy-wire build'
    }
    else {
        Build-HappyWire
    }

    if ($SkipTypecheck) {
        Write-Step 'Skipping happy-app typecheck'
    }
    else {
        Typecheck-HappyApp
    }
}

function Test-WebEndpoint {
    param([int]$Port)

    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port" -UseBasicParsing -TimeoutSec 5
        return $response.StatusCode -ge 200
    }
    catch {
        return $false
    }
}

function Verify-HappyAppWeb {
    if (Test-WebEndpoint -Port $WebPort) {
        Write-Step "Web endpoint already responding on http://127.0.0.1:$WebPort"
        return
    }

    if (Test-Path $WebLog) {
        Remove-Item $WebLog -Force
    }

    Write-Step "Starting Expo Web on port $WebPort"
    $cmd = "set CI=1&& set NODE_ENV=development&& set APP_ENV=development&& corepack pnpm --filter happy-app exec expo start --web --port $WebPort --non-interactive > `"$WebLog`" 2>&1"
    $process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/d', '/c', $cmd -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru

    try {
        $deadline = (Get-Date).AddMinutes(3)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3

            if ($process.HasExited) {
                break
            }

            if (Test-WebEndpoint -Port $WebPort) {
                Write-Step "Web verification passed: http://127.0.0.1:$WebPort"
                return
            }
        }

        if (Test-WebEndpoint -Port $WebPort) {
            Write-Step "Web verification passed: http://127.0.0.1:$WebPort"
            return
        }

        $tail = if (Test-Path $WebLog) { Get-Content $WebLog -Tail 80 | Out-String } else { 'web log missing' }
        throw "Expo Web did not become ready in time.`n$tail"
    }
    finally {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}

function Ensure-GradleDistribution {
    if (Test-Path $GradleBin) {
        Write-Step "Using cached Gradle $GradleVersion at $GradleHome"
        return
    }

    $downloadDir = Split-Path -Parent $GradleHome
    $zipPath = Join-Path $env:TEMP "gradle-$GradleVersion-bin.zip"
    $extractRoot = Join-Path $env:TEMP "gradle-$GradleVersion-extract"

    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    if (Test-Path $extractRoot) {
        Remove-Item -Recurse -Force $extractRoot
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    $urls = @(
        "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip",
        "https://downloads.gradle.org/distributions/gradle-$GradleVersion-bin.zip",
        "https://mirrors.aliyun.com/gradle/distributions/v8.13.0/gradle-$GradleVersion-bin.zip",
        "https://mirrors.cloud.tencent.com/gradle/gradle-$GradleVersion-bin.zip"
    )

    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Write-Step "Downloading Gradle $GradleVersion from $url"
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 900
            $downloaded = $true
            break
        }
        catch {
            Write-WarnLine "Gradle download failed from $url"
        }
    }

    if (-not $downloaded) {
        throw "Unable to download Gradle $GradleVersion from the configured mirrors."
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    $sourceDir = Join-Path $extractRoot "gradle-$GradleVersion"
    Require-Path $sourceDir "Expanded Gradle directory"

    if (Test-Path $GradleHome) {
        Remove-Item -Recurse -Force $GradleHome
    }

    Move-Item -LiteralPath $sourceDir -Destination $GradleHome
    Remove-Item -Force $zipPath
    Remove-Item -Recurse -Force $extractRoot
}

function Invoke-AndroidPrebuild {
    param(
        [string]$NodeEnv = 'development',
        [string]$AppEnv = 'development'
    )

    Write-Step "Running Expo Android prebuild for APP_ENV=$AppEnv"
    $envVars = @{
        NODE_ENV = $NodeEnv
        APP_ENV = $AppEnv
    }

    try {
        Invoke-Pnpm -Arguments @('--filter', 'happy-app', 'exec', 'expo', 'prebuild', '--platform', 'android', '--clean') -ExtraEnv $envVars
    } catch {
        $message = $_.Exception.Message
        if ($message -notmatch 'EBUSY|Access to the path is denied|Failed to delete android code') {
            throw
        }

        Write-WarnLine 'Expo prebuild --clean hit a Windows file lock inside android/.cxx. Retrying without --clean.'
        Invoke-Pnpm -Arguments @('--filter', 'happy-app', 'exec', 'expo', 'prebuild', '--platform', 'android') -ExtraEnv $envVars
    }
}

function Set-GradleWrapperVersion {
    $wrapperProps = Join-Path $AndroidDir 'gradle/wrapper/gradle-wrapper.properties'
    Require-Path $wrapperProps 'gradle-wrapper.properties'

    $content = Get-Content $wrapperProps -Raw
    $updated = $content -replace 'gradle-\d+\.\d+(?:\.\d+)?-bin\.zip', "gradle-$GradleVersion-bin.zip"

    if ($updated -ne $content) {
        Set-Content -Path $wrapperProps -Value $updated -Encoding ASCII
        Write-Step "Pinned generated Gradle wrapper to $GradleVersion"
    }
}

function Test-UseNoDaemon {
    if ($NoDaemon) {
        return $true
    }

    $ci = [Environment]::GetEnvironmentVariable('CI', 'Process')
    return $ci -match '^(1|true|yes)$'
}

function Get-GradleArguments {
    param([string]$TaskName)

    $arguments = @(
        '-I',
        $GradleMirrorScript,
        $TaskName,
        "-PreactNativeArchitectures=$Architectures",
        '--console=plain'
    )

    if (Test-UseNoDaemon) {
        $arguments += '--no-daemon'
    }
    else {
        $arguments += '--daemon'
    }

    return $arguments
}

function Invoke-GradleLogged {
    param(
        [string[]]$Arguments,
        [string]$LogPath
    )

    $savedErrorActionPreference = $ErrorActionPreference
    $hasNativeErrorPreference = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($hasNativeErrorPreference) {
        $savedNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        # Some Android native modules print informational messages to stderr.
        # Treat those as log output and rely on the Gradle exit code instead.
        $ErrorActionPreference = 'Continue'
        if ($hasNativeErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        (& $GradleBin @Arguments 2>&1 | Tee-Object -FilePath $LogPath) | Out-Host
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
        if ($hasNativeErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $savedNativeErrorPreference
        }
    }
}

function Remove-StaleArtifact {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item $Path -Force
    }
}

function Assert-ApkContainsArchitectures {
    param(
        [string]$ApkPath,
        [string]$ExpectedArchitectures
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
    try {
        $actualArchitectures = $archive.Entries |
            Where-Object { $_.FullName -like 'lib/*' } |
            ForEach-Object { ($_.FullName -split '/')[1] } |
            Where-Object { $_ } |
            Sort-Object -Unique

        $expected = $ExpectedArchitectures.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }

        $missing = @($expected | Where-Object { $actualArchitectures -notcontains $_ })
        if ($missing.Count -gt 0) {
            throw "APK architectures mismatch. Missing: $($missing -join ', '). Actual: $($actualArchitectures -join ', ')"
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Build-DebugApk {
    Require-Path $GradleBin 'Gradle executable'
    Require-Path $AndroidDir 'Android project directory'

    if (Test-Path $ApkLog) {
        Remove-Item $ApkLog -Force
    }
    Remove-StaleArtifact -Path $ApkPath

    Write-Step "Building debug APK for architectures: $Architectures"
    Write-Step ($(if (Test-UseNoDaemon) { 'Running Gradle without daemon' } else { 'Reusing Gradle daemon for faster local builds' }))

    Push-Location $AndroidDir
    $savedNodeEnv = [Environment]::GetEnvironmentVariable('NODE_ENV', 'Process')
    $savedAppEnv = [Environment]::GetEnvironmentVariable('APP_ENV', 'Process')
    $savedMetroReset = [Environment]::GetEnvironmentVariable('HAPPY_REACT_NATIVE_RESET_CACHE', 'Process')

    try {
        [Environment]::SetEnvironmentVariable('NODE_ENV', 'development', 'Process')
        [Environment]::SetEnvironmentVariable('APP_ENV', 'development', 'Process')
        [Environment]::SetEnvironmentVariable('HAPPY_REACT_NATIVE_RESET_CACHE', $(if ($ResetMetroCache) { '1' } else { '0' }), 'Process')

        $gradleArgs = Get-GradleArguments -TaskName 'assembleDebug'
        $exitCode = Invoke-GradleLogged -Arguments $gradleArgs -LogPath $ApkLog
        if ($exitCode -ne 0) {
            throw "Gradle assembleDebug failed with exit code $exitCode. See $ApkLog"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('NODE_ENV', $savedNodeEnv, 'Process')
        [Environment]::SetEnvironmentVariable('APP_ENV', $savedAppEnv, 'Process')
        [Environment]::SetEnvironmentVariable('HAPPY_REACT_NATIVE_RESET_CACHE', $savedMetroReset, 'Process')
        Pop-Location
    }

    Require-Path $ApkPath 'Debug APK'
    Assert-ApkContainsArchitectures -ApkPath $ApkPath -ExpectedArchitectures $Architectures
    Write-Step "APK ready: $ApkPath"
}

function Build-ReleaseApk {
    Require-Path $GradleBin 'Gradle executable'
    Require-Path $AndroidDir 'Android project directory'

    if (Test-Path $ReleaseApkLog) {
        Remove-Item $ReleaseApkLog -Force
    }
    Remove-StaleArtifact -Path $ReleaseApkPath

    Write-Step "Building release APK for architectures: $Architectures"
    Write-Step ($(if (Test-UseNoDaemon) { 'Running Gradle without daemon' } else { 'Reusing Gradle daemon for faster local builds' }))
    Write-Step ($(if ($ResetMetroCache) { 'Resetting Metro cache for a cold release bundle' } else { 'Reusing Metro cache for faster release bundling' }))

    Push-Location $AndroidDir
    $savedNodeEnv = [Environment]::GetEnvironmentVariable('NODE_ENV', 'Process')
    $savedAppEnv = [Environment]::GetEnvironmentVariable('APP_ENV', 'Process')
    $savedExpoNoWorkspaceRoot = [Environment]::GetEnvironmentVariable('EXPO_NO_METRO_WORKSPACE_ROOT', 'Process')
    $savedMetroReset = [Environment]::GetEnvironmentVariable('HAPPY_REACT_NATIVE_RESET_CACHE', 'Process')

    try {
        [Environment]::SetEnvironmentVariable('NODE_ENV', 'production', 'Process')
        [Environment]::SetEnvironmentVariable('APP_ENV', 'production', 'Process')
        [Environment]::SetEnvironmentVariable('EXPO_NO_METRO_WORKSPACE_ROOT', '1', 'Process')
        [Environment]::SetEnvironmentVariable('HAPPY_REACT_NATIVE_RESET_CACHE', $(if ($ResetMetroCache) { '1' } else { '0' }), 'Process')

        $gradleArgs = Get-GradleArguments -TaskName 'assembleRelease'
        $exitCode = Invoke-GradleLogged -Arguments $gradleArgs -LogPath $ReleaseApkLog
        if ($exitCode -ne 0) {
            throw "Gradle assembleRelease failed with exit code $exitCode. See $ReleaseApkLog"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('NODE_ENV', $savedNodeEnv, 'Process')
        [Environment]::SetEnvironmentVariable('APP_ENV', $savedAppEnv, 'Process')
        [Environment]::SetEnvironmentVariable('EXPO_NO_METRO_WORKSPACE_ROOT', $savedExpoNoWorkspaceRoot, 'Process')
        [Environment]::SetEnvironmentVariable('HAPPY_REACT_NATIVE_RESET_CACHE', $savedMetroReset, 'Process')
        Pop-Location
    }

    Require-Path $ReleaseApkPath 'Release APK'
    Assert-ApkContainsArchitectures -ApkPath $ReleaseApkPath -ExpectedArchitectures $Architectures
    Write-Step "Release APK ready: $ReleaseApkPath"
}

Initialize-Environment

switch ($Mode) {
    'doctor' {
        Show-Doctor
        exit 0
    }
    'install' {
        Invoke-HappyAppBuildPreparation
        exit 0
    }
    'web' {
        Invoke-HappyAppBuildPreparation
        Verify-HappyAppWeb
        exit 0
    }
    'apk' {
        Invoke-HappyAppBuildPreparation
        Ensure-GradleDistribution
        if ($SkipPrebuild) {
            Write-Step 'Skipping Expo Android prebuild'
        }
        else {
            Invoke-AndroidPrebuild
        }
        Set-GradleWrapperVersion
        Build-DebugApk
        exit 0
    }
    'apk-release' {
        Invoke-HappyAppBuildPreparation
        Ensure-GradleDistribution
        if ($SkipPrebuild) {
            Write-Step 'Skipping Expo Android prebuild'
        }
        else {
            Invoke-AndroidPrebuild -NodeEnv 'production' -AppEnv 'production'
        }
        Set-GradleWrapperVersion
        Build-ReleaseApk
        exit 0
    }
    'full' {
        Invoke-HappyAppBuildPreparation
        Verify-HappyAppWeb
        Ensure-GradleDistribution
        if ($SkipPrebuild) {
            Write-Step 'Skipping Expo Android prebuild'
        }
        else {
            Invoke-AndroidPrebuild
        }
        Set-GradleWrapperVersion
        Build-DebugApk
        exit 0
    }
}
