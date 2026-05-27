const { execSync } = require('child_process');

function getPnpmCommand() {
  return process.platform === 'win32' ? 'corepack pnpm' : 'pnpm';
}

// Apply patches to node_modules
require('../patches/fix-pglite-prisma-bytes.cjs');
require('../patches/fix-livekit-room-reuse.cjs');
require('../patches/expose-pierre-diffs-style.cjs');
require('../patches/force-preact-cjs.cjs');
require('../patches/fix-pierre-trees-preact-hooks.cjs');
require('../patches/fix-react-native-libsodium-windows.cjs');
require('../patches/fix-react-native-android-windows-ipo.cjs');

if (process.env.SKIP_HAPPY_WIRE_BUILD === '1') {
  console.log('[postinstall] SKIP_HAPPY_WIRE_BUILD=1, skipping @slopus/happy-wire build');
  process.exit(0);
}

execSync(`${getPnpmCommand()} --filter @slopus/happy-wire build`, {
  stdio: 'inherit',
});
