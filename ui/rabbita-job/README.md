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

By default the app talks to the gateway at `http://localhost:4242`.

## Serve Through Gateway

Build the app bundle:

```bash
cd ui/rabbita-job
npm run build
```

Then start the gateway and open:

```text
http://localhost:4242/ui
```

The gateway serves the built bundle from `ui/rabbita-job/dist`. If the bundle
has not been built yet, `/ui` returns a small HTML page explaining how to build
it.

Current surfaces:

- job runs list
- local job expansion viewer
- ACP remote-agent viewer
- mixed overview linking local and remote activity
- artifact, workspace, memory, and ACP stdio inspection
- managed polling refresh for active runs and ACP state

Current limitation:

- local jobs stream timeline updates, but ACP still refreshes through polling
