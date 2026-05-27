# Happy App Windows Local Guide

This guide documents the exact Windows local workflow that was verified on May 17, 2026 for `happy-app` web startup and Android APK packaging.

Use this when you need a repeatable path from a fresh checkout to:

- a working local `happy-app` web runtime
- a generated Android debug APK
- a generated Android release APK
- a clear troubleshooting path when Windows, Gradle, Expo, or mirrors get in the way

## Scope

This guide is intentionally narrow.

It covers:

- Windows local development
- `happy-app` dependency installation
- Expo Web verification
- Android `expo prebuild`
- Debug APK packaging
- domestic mirror fallback for Gradle and Maven downloads

It does not cover:

- iOS local builds
- EAS cloud builds
- publishing to stores
- device-side install and runtime debugging

## Quick Start

Run these from the repo root:

```powershell
corepack pnpm happy-app:doctor:windows
corepack pnpm happy-app:verify:windows
corepack pnpm happy-app:apk:release:windows
```

That one command chain will:

1. verify the local Java and Android SDK setup
2. install the workspace dependencies needed by `happy-app`
3. build `@slopus/happy-wire`
4. typecheck `happy-app`
5. start Expo Web and confirm it responds
6. prebuild the Android project
7. download or reuse Gradle `8.13`
8. build a debug APK for `arm64-v8a`
9. optionally build a release APK for `arm64-v8a`

Primary outputs:

- Web log: [`packages/happy-app/web-test.log`](../packages/happy-app/web-test.log)
- Android build log: [`packages/happy-app/android/assembleDebug-arm64_v8a.log`](../packages/happy-app/android/assembleDebug-arm64_v8a.log)
- APK: [`packages/happy-app/android/app/build/outputs/apk/debug/app-debug.apk`](../packages/happy-app/android/app/build/outputs/apk/debug/app-debug.apk)
- Release build log: [`packages/happy-app/android/assembleRelease-arm64-v8a.log`](../packages/happy-app/android/assembleRelease-arm64-v8a.log)
- Release APK: [`packages/happy-app/android/app/build/outputs/apk/release/app-release.apk`](../packages/happy-app/android/app/build/outputs/apk/release/app-release.apk)

## One-Click Commands

These commands were added to the root `package.json`:

```powershell
corepack pnpm happy-app:doctor:windows
corepack pnpm happy-app:install:windows
corepack pnpm happy-app:web:verify:windows
corepack pnpm happy-app:apk:windows
corepack pnpm happy-app:apk:release:windows
corepack pnpm happy-app:verify:windows
```

What each one does:

- `happy-app:doctor:windows`
  Prints Java, Android SDK, `adb`, CMake, and NDK information.
- `happy-app:install:windows`
  Installs the dependency subset needed by `happy-app`, builds `happy-wire`, and typechecks the app.
- `happy-app:web:verify:windows`
  Runs install plus web verification.
- `happy-app:apk:windows`
  Runs install plus Android prebuild plus debug APK packaging.
- `happy-app:apk:release:windows`
  Runs install plus production Android prebuild plus release APK packaging.
- `happy-app:verify:windows`
  Runs the full path: install, web verification, Android prebuild, and debug APK packaging.

## What The Script Assumes

The automation expects this baseline setup:

- Windows PowerShell
- `corepack` available
- Android Studio installed
- Android Studio JBR available at `C:\Program Files\Android\Android Studio\jbr`
- Android SDK available at `C:\Users\<you>\AppData\Local\Android\Sdk`

It also automatically does the following:

- prepends `C:\Program Files\Git\usr\bin` to `PATH` when available
- sets `JAVA_HOME` from Android Studio JBR if missing
- sets `ANDROID_SDK_ROOT` and `ANDROID_HOME` from the default SDK path if missing
- sets `NODE_ENV=development`
- sets `APP_ENV=development`

## Why This Flow Exists

This repo is a `pnpm` monorepo. A naive root install on Windows can drag in unrelated packages and fail before `happy-app` is usable.

The verified local path for `happy-app` is:

1. install only the `happy-app` dependency graph
2. build `@slopus/happy-wire`
3. typecheck `happy-app`
4. verify Expo Web
5. prebuild Android
6. package the debug APK with a pinned Gradle version and mirror-aware Maven config

That path avoids most unrelated failures from packages outside the `happy-app` slice.

## Problems Found And How They Were Solved

### 1. `pnpm` was not on PATH

Symptom:

- plain `pnpm` was unavailable in the shell

Resolution:

- use `corepack pnpm ...` consistently

This is now baked into the automation.

### 2. Root install could fail on unrelated packages

Symptom:

- a full workspace install could fail in packages outside `happy-app`
- one observed example was `codium` pulling `electron` and failing with `ECONNRESET`

Resolution:

- the new script installs only the dependency graph required by `happy-app`
- this keeps unrelated `electron` downloads out of the default mobile app flow

Command shape used by automation:

```powershell
corepack pnpm install --filter happy-app... --reporter append-only --no-frozen-lockfile
```

### 3. `@shopify/react-native-skia` postinstall used `rm` on Windows

Symptom:

- install failed because `rm` was not available in a plain Windows shell

Resolution:

- prepend Git Unix tools to `PATH`
- specifically: `C:\Program Files\Git\usr\bin`

The automation now does this automatically when Git for Windows is installed in the default location.

### 4. `happy-app` typecheck failed until `@slopus/happy-wire` was built

Symptom:

- TypeScript errors referenced unresolved workspace output from `@slopus/happy-wire`

Resolution:

- build `@slopus/happy-wire` before typechecking `happy-app`

Command:

```powershell
corepack pnpm --filter @slopus/happy-wire build
corepack pnpm --filter happy-app typecheck
```

### 5. Expo Web needed an explicit verification step

Symptom:

- install and typecheck alone did not prove that the Web runtime actually came up

Resolution:

- start Expo Web with `CI=1`, `APP_ENV=development`, and a fixed port
- wait until `http://127.0.0.1:19006` responds

The automation writes a reusable log file to:

- [`packages/happy-app/web-test.log`](../packages/happy-app/web-test.log)

### 6. `expo prebuild` generated an Android project, but the wrapper version was wrong

Symptom:

- after `expo prebuild --platform android --clean`, the generated wrapper used Gradle `9.0.0`
- that version was not compatible with the React Native and Android Gradle Plugin stack in this local setup

Resolution:

- pin the generated wrapper entry to Gradle `8.13`
- build with a locally cached Gradle `8.13` distribution

The automation updates:

- `packages/happy-app/android/gradle/wrapper/gradle-wrapper.properties`

## 7. Slow or blocked remote downloads required domestic mirrors

Symptom:

- Gradle or Maven dependency downloads could hang, reset, or fail

Resolution:

- use a Gradle init script that preserves local `file:` repositories
- remove only remote repositories
- append domestic Aliyun repositories and JitPack

Mirror init script:

- [`scripts/happy-gradle-mirrors.init.gradle`](../scripts/happy-gradle-mirrors.init.gradle)

What it changes:

- plugin repositories
- project repositories
- buildscript repositories

What it intentionally preserves:

- Expo and React Native local Maven repositories under `file:`

### 8. `@more-tech/react-native-libsodium` failed in CMake on Windows

Symptom:

- Android build failed during:

```text
:more-tech_react-native-libsodium:configureCMakeDebug[arm64-v8a]
```

- log showed:

```text
Invalid character escape '\c'
```

Root cause:

- the library discovered `node_modules` using Windows backslashes
- that path was injected into `-DNODE_MODULES_DIR=...`
- CMake parsed paths like `D:\codes\happy\node_modules\react-native\...` as escaped strings instead of normal file paths

Resolution:

- normalize that path to forward slashes before passing it to CMake

This fix is now automated in the root postinstall patch flow:

- [`patches/fix-react-native-libsodium-windows.cjs`](../patches/fix-react-native-libsodium-windows.cjs)

### 9. Gradle build required `NODE_ENV`

Symptom:

- Android packaging could fail with:

```text
The NODE_ENV environment variable is required but was not specified.
```

Resolution:

- set both `NODE_ENV=development` and `APP_ENV=development` for Android build commands

The automation now always sets both.

### 10. Release Metro bundling could not resolve workspace packages in production

Symptom:

- Android release build failed during `:app:createBundleReleaseJsAndAssets`
- Metro could not resolve `@slopus/happy-wire` in release mode
- after direct aliasing, Metro still failed with:

```text
Failed to get the SHA-1 for: D:\codes\happy\packages\happy-wire\dist\index.cjs
```

Root cause:

- `EXPO_NO_METRO_WORKSPACE_ROOT=1` is needed so Expo resolves the app entry from `packages/happy-app`
- but that same flag disables Expo's automatic monorepo discovery
- Metro then lost the watch roots and root-level `node_modules` lookup needed for workspace packages

Resolution:

- keep `EXPO_NO_METRO_WORKSPACE_ROOT=1` for release builds
- explicitly restore monorepo visibility in [`packages/happy-app/metro.config.js`](../packages/happy-app/metro.config.js)
- add:
  - `watchFolders` for the repo root and `packages/happy-wire`
  - `resolver.nodeModulesPaths` for app-local and repo-root `node_modules`
  - a direct resolver alias for `@slopus/happy-wire` to `packages/happy-wire/dist/index.cjs`

This is the key fix that made local Android release bundling succeed on Windows.

## Manual Recovery Commands

If you need to rerun the steps manually instead of using the one-click script, use this order.

### Install and typecheck

```powershell
corepack pnpm install --filter happy-app... --reporter append-only --no-frozen-lockfile
corepack pnpm --filter @slopus/happy-wire build
corepack pnpm --filter happy-app typecheck
```

### Verify Web

```powershell
$env:CI = '1'
$env:NODE_ENV = 'development'
$env:APP_ENV = 'development'
corepack pnpm --filter happy-app exec expo start --web --port 19006 --non-interactive
```

### Prebuild Android

```powershell
$env:NODE_ENV = 'development'
$env:APP_ENV = 'development'
corepack pnpm --filter happy-app exec expo prebuild --platform android --clean
```

### Build debug APK

```powershell
$env:NODE_ENV = 'development'
$env:APP_ENV = 'development'
C:\Users\<you>\.gradle\local-dist\gradle-8.13\bin\gradle.bat `
  -I scripts/happy-gradle-mirrors.init.gradle `
  assembleDebug `
  -PreactNativeArchitectures=arm64-v8a `
  --no-daemon `
  --console=plain
```

### Build release APK

```powershell
$env:NODE_ENV = 'production'
$env:APP_ENV = 'production'
$env:EXPO_NO_METRO_WORKSPACE_ROOT = '1'
C:\Users\<you>\.gradle\local-dist\gradle-8.13\bin\gradle.bat `
  -I scripts/happy-gradle-mirrors.init.gradle `
  assembleRelease `
  -PreactNativeArchitectures=arm64-v8a `
  --no-daemon `
  --console=plain
```

## Why The Default APK Build Uses `arm64-v8a`

The automation defaults to:

```text
-PreactNativeArchitectures=arm64-v8a
```

Reason:

- it is the fastest way to prove the machine can produce a real APK
- it avoids spending extra time on all four default ABIs during local verification

If you need the full default set later, rerun the build with:

```text
armeabi-v7a,arm64-v8a,x86,x86_64
```

## Logs And Artifacts

Useful locations:

- Web verification log:
  [`packages/happy-app/web-test.log`](../packages/happy-app/web-test.log)
- Android build log:
  [`packages/happy-app/android/assembleDebug-arm64_v8a.log`](../packages/happy-app/android/assembleDebug-arm64_v8a.log)
- Android release build log:
  [`packages/happy-app/android/assembleRelease-arm64-v8a.log`](../packages/happy-app/android/assembleRelease-arm64-v8a.log)
- Gradle wrapper:
  [`packages/happy-app/android/gradle/wrapper/gradle-wrapper.properties`](../packages/happy-app/android/gradle/wrapper/gradle-wrapper.properties)
- Generated APK:
  [`packages/happy-app/android/app/build/outputs/apk/debug/app-debug.apk`](../packages/happy-app/android/app/build/outputs/apk/debug/app-debug.apk)
- Generated release APK:
  [`packages/happy-app/android/app/build/outputs/apk/release/app-release.apk`](../packages/happy-app/android/app/build/outputs/apk/release/app-release.apk)

## Known Limitations

- This verifies local packaging, not store publishing.
- This does not confirm device install because no emulator or physical device is required for APK generation.
- `packages/happy-app/android` is generated by Expo prebuild and is ignored by Git.
- If Expo or React Native is upgraded, recheck Gradle compatibility before assuming `8.13` is still the right pinned version.

## Maintenance Checklist

When this flow breaks in the future, check these in order:

1. Did Expo or React Native change the generated Gradle wrapper version?
2. Did Android Studio upgrade the SDK, NDK, or CMake in a way that changes compatibility?
3. Did `@more-tech/react-native-libsodium` fix its Windows path handling upstream?
4. Did the Aliyun or Tencent mirror paths change?
5. Did Expo start requiring a different environment variable set during Android packaging?

If `react-native-libsodium` fixes the Windows issue upstream, remove:

- `patches/fix-react-native-libsodium-windows.cjs`
- the corresponding `require(...)` in [`scripts/postinstall.cjs`](../scripts/postinstall.cjs)

## Recommended Daily Workflow

For normal local work after the first successful setup:

```powershell
corepack pnpm happy-app:web:verify:windows
```

When you need a fresh Android package:

```powershell
corepack pnpm happy-app:apk:windows
```

When you need a fresh Android release package:

```powershell
corepack pnpm happy-app:apk:release:windows
```

When you want the full end-to-end local confidence check:

```powershell
corepack pnpm happy-app:verify:windows
```
