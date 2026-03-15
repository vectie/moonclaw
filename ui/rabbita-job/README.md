# Rabbita Job Expansion Viewer

Standalone MoonBit web app for MoonClaw's generative job expansion UI.

## Run

```bash
cd ui/rabbita-job
moon check main
moon info main
npm i
npm run dev
```

By default the app talks to the gateway at `http://localhost:4242`.

Current surfaces:

- job runs list
- job expansion snapshot viewer
- timeline/events viewer
- artifact and memory side panels
- managed polling refresh for active runs

Current limitation:

- it uses polling instead of a true event stream subscription
