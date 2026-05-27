/**
 * Patches @more-tech/react-native-libsodium for Windows + CMake.
 *
 * The library passes NODE_MODULES_DIR to CMake using the native Windows path
 * separator. CMake then interprets backslashes in source paths like
 * `D:\codes\happy\node_modules\react-native\...` as escape sequences (`\c`)
 * and configure fails before any native compilation starts.
 *
 * Fix: normalize the discovered node_modules path to forward slashes before it
 * is injected into `-DNODE_MODULES_DIR=...`.
 */
const fs = require('fs');
const path = require('path');

const files = [
    'node_modules/@more-tech/react-native-libsodium/android/build.gradle',
    'packages/happy-app/node_modules/@more-tech/react-native-libsodium/android/build.gradle',
];

let patched = 0;

for (const file of files) {
    const filePath = path.resolve(__dirname, '..', file);
    if (!fs.existsSync(filePath)) continue;

    let content = fs.readFileSync(filePath, 'utf8');
    const original = content;

    content = content.replace(
        'def nodeModules = findNodeModules(projectDir)',
        'def nodeModules = findNodeModules(projectDir).replace("\\\\", "/")'
    );

    if (content !== original) {
        fs.writeFileSync(filePath, content, 'utf8');
        patched++;
    }
}

if (patched > 0) {
    console.log(`[patch] Fixed react-native-libsodium Windows CMake path handling (${patched} file(s))`);
}
