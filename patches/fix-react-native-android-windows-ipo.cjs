/**
 * Patches React Native's Android app CMake helper for Windows local builds.
 *
 * React Native enables IPO/LTO for app-level native builds when CMake reports
 * support. On Windows with the Android NDK/clang toolchain used here, that
 * probe can fail because CMake tries `-fuse-ld=gold`, which this toolchain
 * rejects. The result is a local release build failure before APK packaging.
 *
 * Fix: skip the IPO probe on Windows by forcing `IPO_SUPPORT` to false in the
 * generated app helper. This keeps native release builds working locally while
 * leaving non-Windows platforms unchanged.
 */
const fs = require('fs');
const path = require('path');

const targets = [
    path.resolve(__dirname, '..', 'node_modules', 'react-native', 'ReactAndroid', 'cmake-utils', 'ReactNative-application.cmake'),
    path.resolve(__dirname, '..', 'packages', 'happy-app', 'node_modules', 'react-native', 'ReactAndroid', 'cmake-utils', 'ReactNative-application.cmake'),
];

const anchor = [
    'include(CheckIPOSupported)',
    'check_ipo_supported(RESULT IPO_SUPPORT)',
    'if (IPO_SUPPORT)',
    '  set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)',
    'endif()',
].join('\n');

const replacement = [
    'if(WIN32)',
    '  set(IPO_SUPPORT FALSE)',
    'else()',
    '  include(CheckIPOSupported)',
    '  check_ipo_supported(RESULT IPO_SUPPORT)',
    'endif()',
    'if (IPO_SUPPORT)',
    '  set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)',
    'endif()',
].join('\n');

let patched = 0;

for (const file of targets) {
    if (!fs.existsSync(file)) continue;

    const content = fs.readFileSync(file, 'utf8');
    if (content.includes('if(WIN32)\n  set(IPO_SUPPORT FALSE)')) {
        continue;
    }

    if (!content.includes(anchor)) {
        console.warn(`[patch] Could not find IPO block in ${file}`);
        continue;
    }

    fs.writeFileSync(file, content.replace(anchor, replacement), 'utf8');
    patched++;
}

if (patched > 0) {
    console.log(`[patch] Disabled React Native Android IPO probe on Windows (${patched} file(s))`);
}
