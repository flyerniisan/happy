/**
 * Patches React Native's bundle task so local Windows builds can opt out of
 * `--reset-cache`.
 *
 * The upstream Gradle task always passes `--reset-cache` to the JS bundler,
 * forcing Metro to cold-start every release bundle. That is safe but very slow
 * for local repeat builds. We keep the default behavior unless
 * `HAPPY_REACT_NATIVE_RESET_CACHE=0` is set in the environment.
 */
const fs = require('fs');
const path = require('path');

const files = [
    'node_modules/@react-native/gradle-plugin/react-native-gradle-plugin/src/main/kotlin/com/facebook/react/tasks/BundleHermesCTask.kt',
    'packages/happy-app/node_modules/@react-native/gradle-plugin/react-native-gradle-plugin/src/main/kotlin/com/facebook/react/tasks/BundleHermesCTask.kt',
];

const needle = '          add("--reset-cache")';
const replacement = [
    '          if (System.getenv("HAPPY_REACT_NATIVE_RESET_CACHE") != "0") {',
    '            add("--reset-cache")',
    '          }',
].join('\n');

let patched = 0;

for (const file of files) {
    const filePath = path.resolve(__dirname, '..', file);
    if (!fs.existsSync(filePath)) continue;

    const content = fs.readFileSync(filePath, 'utf8');
    if (content.includes('HAPPY_REACT_NATIVE_RESET_CACHE')) continue;
    if (!content.includes(needle)) {
        console.warn(`[patch] Could not find Metro reset-cache anchor in ${filePath}`);
        continue;
    }

    fs.writeFileSync(filePath, content.replace(needle, replacement), 'utf8');
    patched++;
}

if (patched > 0) {
    console.log(`[patch] Made React Native Metro cache reset optional (${patched} file(s))`);
}
