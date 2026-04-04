# Rabbita Job Expansion Viewer

Standalone MoonBit web app for MoonClaw's local job + ACP operator UI.

## Run

```bash
cd ui/rabbita-job
moon check main
moon info main
npm i
npm run dev
```

By default the app talks to the gateway at `http://localhost:18123`.

## Serve Through Gateway

Build the app bundle:

```bash
./scripts/build-rabbita-ui.sh
```

Equivalent manual steps:

```bash
cd ui/rabbita-job
npm install
npm run build
```

Then start the gateway and open:

```bash
moon -C /Users/kq/Workspace/moonclaw run cmd/main -- gateway start --home ~/.moonclaw --cwd /Users/kq/Workspace/moonclaw
```

```text
http://localhost:18123/ui
```

The gateway serves the built bundle from `ui/rabbita-job/dist`. It first checks
the gateway `--cwd`, then falls back to the MoonClaw repo's own
`ui/rabbita-job/dist` when the gateway is serving another workspace. It also
serves the bundle's root-level `/assets/...` files so the built app can load
correctly from `/ui`. If the bundle has not been built yet, `/ui` returns a
small HTML page explaining how to build it.

Be careful with `--cwd`: it is the gateway's default writable workspace. If
you start the gateway with `--cwd /Users/kq/Workspace/moonclaw`, agent actions
and generated files may be written into that repo. Use a separate workspace if
you want the UI and gateway to operate without mutating the source tree:

```bash
mkdir -p ~/.moonclaw/workspace
moon -C /Users/kq/Workspace/moonclaw run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/.moonclaw/workspace
```

Important: `ui/rabbita-job` is its own MoonBit module. If you run
`moon run cmd/main -- ...` from inside this directory, Moon will fail because
`cmd/main` only exists in the top-level MoonClaw repo. Run gateway commands
from the repo root, or use `moon -C /path/to/moonclaw run cmd/main -- ...`.

Current surfaces:

- job runs list
- local job expansion viewer
- full-screen run canvas toggle
- ACP remote-agent viewer
- mixed overview linking local and remote activity
- final run report/result cards
- aggregated starter-doc input card
- full-screen artifact editor surface
- artifact, workspace, memory, and ACP stdio inspection
- managed polling refresh for active runs and ACP state
- export surfaces for:
  - ACP run transcripts
  - ACP session transcripts
  - ACP session timeline transcripts
  - focused mixed-lineage transcripts
  - combined case exports bundling local run, focused lineage, and linked ACP session timelines

Current limitation:

- local jobs and ACP both use live event streams, but snapshots still refresh periodically for reconciliation

Current workflow notes:

- final run `report.md` and `result.json` are surfaced as synthetic artifact cards when they exist only as workspace files
- starter attachment digest/text/summary/manifest artifacts are grouped into one `Starter Docs` card in the main artifact-facing surfaces
- after frontend changes, rebuild with `./scripts/build-rabbita-ui.sh`
