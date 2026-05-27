# Contributing to Happy

Happy is built by engineers who use AI coding tools all day and we built Happy so we could use them from anywhere. Contributions that make Happy better for that workflow are welcome.

If you don't get a response on your PR or issue, tag **@bra1ndump**.

## Contribution Priorities

We review contributions in this order:

1. **Bug fixes** - crashes, broken flows, data loss
2. **UI touchups** - polish, layout fixes, visual consistency
3. **New features** - new capabilities that serve the core use case
4. **Refactors** - code quality improvements, test coverage
5. **Core refactors** - sync engine, RPC layer, server changes (discuss first)

If your contribution is lower on this list, it may take longer to get reviewed. That's not a reflection of its value. It's just how we triage.

## Issues

We currently can't reply to every issue individually. We review them in bulk using AI-assisted triage. They're useful, keep filing them, but PRs with clear fixes will always get priority.

Every issue should start with a **one-paragraph summary** of the problem. Don't bury the lede in reproduction steps or logs. Lead with what's broken and what you expected.

## Pull Requests

### The Rules

1. **Start with a one-paragraph summary.** What was broken or missing? What does this PR do about it? A human skimming 20 PRs needs to understand yours in 10 seconds.
2. **Show proof it works.** Include a video, screenshots, or actual log output demonstrating the fix in a real running app. The "before" state can be described with words. The "after" must be shown visually. Unit tests passing is not enough. Show it working end to end.
3. **Address Codex review comments before requesting human review.** We use automated Codex reviews on all PRs. Resolve those first. They catch the obvious stuff so human reviewers can focus on the important stuff.
4. **Keep PRs focused.** One fix per PR. One feature per PR. If you touched something unrelated, split it out.
5. **Core changes need a discussion first.** If your PR touches the sync engine, RPC protocol, encryption, or server, open an issue or Discord thread before writing code. These areas affect every user and need design alignment.

### What Makes a Good PR

- **Show proof it works.** Screenshots, screen recordings, or actual log output demonstrating the fix in a real running app. Unit tests passing is not enough. Show it working end to end.
- Links to the issue it fixes if one exists
- Short, clear title (`fix: voice session stuck in connecting state` not `Update voice.ts`)
- No unrelated changes and no drive-by refactors

## Development Setup

Start with the internal [developer-onboarding.md](./developer-onboarding.md) guide if you are new to the repo. It explains package responsibilities, the recommended reading order, and the preferred full-stack dev workflow before you start changing code.

### Prerequisites

- Node.js >= 20
- pnpm (`npm install -g pnpm`)
- Git

### Getting Started

```bash
git clone https://github.com/slopus/happy.git
cd happy
pnpm install
```

### Happy App (Mobile + Web)

```bash
pnpm --filter happy-app start          # Expo dev server
pnpm --filter happy-app ios:dev        # iOS simulator
pnpm --filter happy-app android:dev    # Android emulator
pnpm web                               # Browser shortcut
pnpm --filter happy-app typecheck      # Run after all changes
```

The app has three build variants. All can be installed simultaneously on the same device:

| Variant | Bundle ID | App Name | Use Case |
|---------|-----------|----------|----------|
| Development | `com.slopus.happy.dev` | Happy (dev) | Local development with hot reload |
| Preview | `com.slopus.happy.preview` | Happy (preview) | Beta testing and OTA updates |
| Production | `com.ex3ndr.happy` | Happy | App Store release |

Swap `ios:dev` for `ios:preview` or `ios:production` and do the same for `android:`.

#### macOS Desktop (Tauri)

```bash
pnpm --filter happy-app tauri:dev      # Run with hot reload
pnpm --filter happy-app tauri:build:dev
```

### Happy CLI

```bash
pnpm --filter happy build
pnpm --filter happy test
pnpm --filter happy cli:install   # Build + link this workspace as the global `happy` + restart daemon
```

`cli:install` replaces the `happy` binary installed from npm with a symlink to this workspace. It reuses `~/.happy/` for auth and sessions, so there is no separate dev home by default. To undo:

```bash
npm unlink -g happy && npm i -g happy@latest
```

To sandbox dev data, set `HAPPY_HOME_DIR=~/.happy-dev` in your shell before running `happy`.

### Happy Server

```bash
pnpm --filter happy-server standalone:dev   # Local server with embedded PGlite
```

Runs on `localhost:3005`. To point the app at your local server:

```bash
EXPO_PUBLIC_HAPPY_SERVER_URL=http://localhost:3005 pnpm --filter happy-app start
```

### Preferred Full-Stack Local Flow

For integration work, prefer the environment manager instead of manually wiring multiple terminals:

```bash
pnpm env:up:authenticated
pnpm env:cli
pnpm env:web
```

This gives you an isolated server, CLI home, fixture project, and web app URL that are all configured to work together.

## Project Structure

This is a monorepo with five core packages:

- **happy-app** - React Native + Expo mobile/web client
- **happy-cli** - Node.js CLI that wraps Claude Code and Codex
- **happy-agent** - Remote agent control
- **happy-server** - Backend for encrypted sync
- **happy-wire** - Shared wire schemas and session protocol types

Recommended starting points:

- [developer-onboarding.md](./developer-onboarding.md) for the guided reading path
- [cli-architecture.md](./cli-architecture.md) for CLI and daemon internals
- [backend-architecture.md](./backend-architecture.md) for server structure and realtime flow
- [happy-wire.md](./happy-wire.md) for shared protocol and schema boundaries

## Community

- [Discord](https://discord.gg/fX9WBAhyfD) - best place for questions and discussion
- [Documentation](https://happy.engineering/docs/)
