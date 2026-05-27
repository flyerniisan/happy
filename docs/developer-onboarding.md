# Developer Onboarding

This guide is the fastest way to build a working mental model of the Happy codebase before making changes.

Happy is a `pnpm` monorepo with five core packages:

- `happy-app`: Expo app for web, iOS, Android, and Tauri desktop
- `happy-cli`: the `happy` CLI, daemon, and provider runners
- `happy-server`: Fastify + Socket.IO backend for auth and encrypted sync
- `happy-agent`: standalone remote-control CLI for machines and sessions
- `happy-wire`: shared wire schemas and session protocol types

The main product flow is:

1. `happy-cli` starts or resumes local agent sessions on a machine.
2. `happy-server` authenticates clients and syncs encrypted updates.
3. `happy-app` displays and controls sessions from web, mobile, and desktop.
4. `happy-wire` defines the protocol all clients and services agree on.
5. `happy-agent` consumes the same machine and session APIs from a lighter CLI.

## Read This First

Build the top-level map before diving into any package:

1. Root `README.md` and [README.md](./README.md)
   Understand product goals, package names, and the internal docs index.
2. [`packages/happy-server/sources/main.ts`](../packages/happy-server/sources/main.ts)
   This is the real backend entrypoint and shows startup order for DB, auth, files, API, metrics, and presence.
3. [cli-architecture.md](./cli-architecture.md) and [backend-architecture.md](./backend-architecture.md)
   Use these to understand daemon lifecycle, realtime sync, update routing, and storage boundaries.
4. [`packages/happy-wire/src/index.ts`](../packages/happy-wire/src/index.ts), `messages.ts`, and `sessionProtocol.ts`
   Treat these as the protocol source of truth before changing message or state flow.

## Package Reading Order

Read the code in this order and answer the same three questions for each package:

- What is the entrypoint?
- Where is state stored?
- What does it talk to?

### 1. `happy-wire`

Start here whenever a change might affect message shape or compatibility.

- Entrypoint: [`packages/happy-wire/src/index.ts`](../packages/happy-wire/src/index.ts)
- Key files: `messages.ts`, `legacyProtocol.ts`, `sessionProtocol.ts`
- State: none beyond schemas and helpers
- Talks to: every other package through shared types

Focus on:

- discriminated unions for `new-message`, `update-session`, and `update-machine`
- session protocol event types and envelope rules
- tests that lock down compatibility expectations

### 2. `happy-server`

Understand how encrypted blobs move through the backend.

- Entrypoint: [`packages/happy-server/sources/main.ts`](../packages/happy-server/sources/main.ts)
- Key areas: `sources/app/api`, `sources/app/events`, `sources/app/session`, `sources/app/presence`
- State: Postgres or PGlite, uploaded files, machine and session presence caches
- Talks to: CLI, app, agent, and storage providers

Focus on:

- HTTP routes vs Socket.IO update flow
- user-level monotonic `seq`
- the three persisted update body types
- machine and session presence lifecycle

### 3. `happy-cli`

This is the local execution side of the system.

- Entrypoint: [`packages/happy-cli/src/index.ts`](../packages/happy-cli/src/index.ts)
- Key areas: `src/api`, `src/daemon`, `src/sessionProtocol`, provider folders such as `claude`, `codex`, and `gemini`
- State: `~/.happy` or `HAPPY_HOME_DIR`
- Talks to: `happy-server`, local child processes, and provider CLIs

Focus on:

- command routing and setup flow
- daemon control server and local IPC
- how sessions are spawned, resumed, and bridged to remote clients
- where provider output becomes session-protocol events

### 4. `happy-app`

This is the multi-client UI layer that consumes the shared protocol.

- Entrypoint: [`packages/happy-app/index.ts`](../packages/happy-app/index.ts)
- Key areas: `sources/app`, `sources/auth`, `sources/realtime`, `sources/sync`, `sources/encryption`
- State: local app stores plus synced encrypted session and machine state
- Talks to: `happy-server`, uploaded files, and platform-specific runtime APIs

Focus on:

- how realtime updates are received and merged
- how session events are rendered across platforms
- where encryption and sync boundaries sit
- where environment and platform switches happen

### 5. `happy-agent`

Read this after the main flow is clear.

- Entrypoint: [`packages/happy-agent/src/index.ts`](../packages/happy-agent/src/index.ts)
- Key areas: `src/api.ts`, `src/session.ts`, `src/machineRpc.ts`
- State: local credentials under `~/.happy`
- Talks to: `happy-server` and remote machines and sessions

Focus on:

- machine listing and session control
- authentication and encryption reuse
- how it overlaps with, but does not replace, `happy-cli`

## Stable Interfaces To Treat As Public

Changes here can ripple across packages and require compatibility checks.

### Session protocol events

`happy-wire` defines the canonical event set:

- `text`
- `service`
- `tool-call-start`
- `tool-call-end`
- `file`
- `turn-start`
- `turn-end`
- `start`
- `stop`

### Server update bodies

The backend sync layer centers on three update types:

- `new-message`
- `update-session`
- `update-machine`

### CLI daemon control surface

The local daemon control server exposes:

- `/list`
- `/spawn-session`
- `/stop-session`
- `/stop`

### Shared local environment variables

These are the defaults to understand before debugging local behavior:

- `HAPPY_SERVER_URL`
- `HAPPY_WEBAPP_URL`
- `HAPPY_HOME_DIR`
- `HAPPY_PROJECT_DIR`

## Recommended Learning Path

### Phase 1: Build a codebase map

Do a read-only pass first.

- Write down the role of each core package in one sentence.
- For each package, note entrypoint, state location, and communication edges.
- Do not start from UI screens or one CLI command in isolation. Start from the protocol or state source.

### Phase 2: Run the smallest full-stack path

Use the built-in environment manager instead of assembling env vars by hand.

```bash
pnpm install
pnpm env:up:authenticated
pnpm env:cli
pnpm env:web
```

Then observe one full loop:

1. Start a local session through the CLI.
2. Confirm the server sees machine and session state.
3. Open the web app from the environment output.
4. Verify the same session stream appears remotely.

The goal is not feature work yet. The goal is to validate your mental model of the data flow.

### Phase 3: Use one cross-stack change as a template

The best first exercise is adding support for a new session event display.

1. Update the `happy-wire` schema.
2. Follow how `happy-cli` produces the event.
3. Confirm `happy-server` stores or forwards it without breaking shape.
4. Update `happy-app` parsing and rendering.

This path teaches the shared architecture with the least guesswork.

### Phase 4: Classify future work before editing

Before coding, put each task into one of these buckets:

- Protocol change: start in `happy-wire`, then review app, cli, and server impact
- Session execution change: start in `happy-cli`
- Sync, auth, or storage change: start in `happy-server`
- UI or interaction change: start in `happy-app`

If a task touches message shape, state fields, or event semantics, assume it is a cross-package compatibility change until proven otherwise.

## Validation Checklist

Use this checklist both while learning and while shipping changes.

- Protocol: run `happy-wire` tests when schemas or event types change.
- CLI: run `happy-cli` unit tests first; add integration coverage when daemon or session orchestration changes.
- Server: run `happy-server` tests and verify auth, session updates, and machine updates.
- App: run `happy-app` Vitest coverage and a minimal web session render flow.
- End to end: use an isolated environment and verify CLI to server to web or app propagation.

Priority scenarios to cover:

- creating a session
- machine registration and presence
- appending session messages
- updating metadata and `agentState`
- rendering session protocol events
- daemon survival, restart, and resume behavior

## Defaults And Assumptions

- Use `pnpm` for workspace install, build, and test flows.
- Prefer full-stack understanding before package-specific optimization.
- Prefer `environments/environments.ts` for local integration work instead of manual shell setup.
- Treat protocol and state shape changes as compatibility-sensitive by default.
- Start with architecture understanding and verification before making broad refactors.
