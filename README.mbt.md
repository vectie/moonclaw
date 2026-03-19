# MoonClaw

> 🦀 MoonBit-native agent runtime + 📡 gateway + 🧠 memory + 🗂️ job system + 🤖 ACP remote-agent control

MoonClaw is an agent and automation system built on top of [moonbitlang/maria](https://github.com/moonbitlang/maria), inspired by [openclaw/openclaw](https://github.com/openclaw/openclaw), and shaped around a full job runtime instead of a thin chat wrapper.

It is designed for:

- 💬 chat-driven planning
- ⚙️ long-running background jobs
- 🧪 analysis workflows
- 📁 dedicated run workspaces with git checkpoints
- 🧠 structured long-term memory
- 🌐 gateway + operator UI
- 🤖 local jobs working alongside ACP remote agents

## ✨ What MoonClaw Feels Like

```text
chat / CLI / Feishu / web UI
  -> draft a proposal
  -> compile to workflow
  -> execute as a job
  -> persist artifacts, memory, and workspace state
  -> inspect local + remote activity from one operator surface
```

MoonClaw is strongest when you want one system to handle:

- 🛠️ local execution
- 🔄 async orchestration
- 🧾 durable outputs
- 🧭 operator control
- 🤝 local-agent + remote-agent handoff

## 🚀 Current Capabilities

- 🖥️ `interactive` and `tui` local modes
- 📡 long-running HTTP/RPC `gateway`
- 🪽 Feishu integration
- 🧠 memory capture, retrieval, and workspace materialization
- 🗂️ per-run and per-subjob workspaces
- 🌳 git-managed run history inside each workspace
- 📦 artifact storage and grounded artifact Q&A
- 🔬 generic job workflows
- 🤖 ACP targets, sessions, and runs for remote agent control
- 🪟 Rabbita operator UI with:
  - local job expansion
  - ACP remote-agent lane
  - mixed local↔remote lineage view
  - transcript and case export

## 🧩 Main Subsystems

- `agent`
  core conversation and execution runtime
- `gateway`
  long-running service, HTTP/RPC surface, channels, ACP control
- `job`
  planning, compilation, execution, artifacts, memory, workspace integration
- `workspace`
  configured workspace runtime plus dedicated run workspaces
- `security`
  session scope, approval, pairing, command policy
- `acp`
  remote-agent control plane and Codex-oriented execution bridge
- `ui/rabbita-job`
  operator UI for local + remote execution

## ⚡ Quick Start

From the repo root:

```bash
cd ~/Workspace/moonclaw
```

Run onboarding status:

```bash
moon run cmd/main -- onboard status --home ~/.moonclaw
```

Use Codex OAuth and switch the primary model automatically:

```bash
moon run cmd/main -- onboard auth codex --home ~/.moonclaw
```

Provision a Codex ACP target that the gateway can launch later:

```bash
moon run cmd/main -- acp add codex --home ~/.moonclaw
```

If you want multiple ACP targets, add them with explicit ids:

```bash
moon run cmd/main -- acp add codex --home ~/.moonclaw --id codex-review --workspace ~/Workspace/review-scratch --model gpt-5
```

Configure Feishu:

```bash
moon run cmd/main -- onboard configure \
  --home ~/.moonclaw \
  --enable-feishu \
  --feishu-app-id <app_id> \
  --feishu-app-secret <app_secret>
```

Start the gateway:

```bash
moon run cmd/main -- gateway start --home ~/.moonclaw
```

Important:

- `--home ~/.moonclaw` stores MoonClaw runtime state such as jobs, runs, memories, and gateway data.
- `gateway start` now falls back to the configured `agents.defaults.cwd` and `gateway.port` from `moonclaw.json`.
- `acp add codex` now falls back to `agents.defaults.workspace` for the target workspace and `agents.defaults.cwd` for the target cwd.
- `--cwd` still overrides the writable workspace explicitly when you want to point the gateway somewhere else.
- If you point `--cwd` at a git repo, MoonClaw may create or edit files inside that repo.
- Use a separate workspace if you do not want generated files mixed into your source tree.

Example with an isolated workspace instead of the repo:

```bash
mkdir -p ~/.moonclaw/workspace
moon run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/.moonclaw/workspace
```

Open the operator UI:

```text
http://localhost:18123/ui
```

If `/ui` says the Rabbita bundle is missing, build it from the repo:

```bash
cd ~/Workspace/moonclaw/ui/rabbita-job
npm install
npm run build
```

The gateway serves the bundle at `/ui` and also serves the built `/assets/...`
files that the bundle references.

## 🧭 Onboarding Flow

Useful onboarding commands:

```bash
moon run cmd/main -- onboard status --home ~/.moonclaw
moon run cmd/main -- onboard auth status --home ~/.moonclaw
moon run cmd/main -- onboard auth codex --home ~/.moonclaw
moon run cmd/main -- onboard auth copilot --home ~/.moonclaw
moon run cmd/main -- onboard models --home ~/.moonclaw
moon run cmd/main -- onboard switch codex --home ~/.moonclaw
moon run cmd/main -- onboard print-config --home ~/.moonclaw
```

Current behavior:

- 🔐 `onboard auth codex` connects Codex OAuth and updates the primary model to `codex/gpt-5.4`
- 🔐 `onboard auth copilot` connects Copilot OAuth and updates the primary model to `copilot/gpt-5.2`
- 🎯 `onboard switch <model>` changes the active primary model explicitly
- 🪽 Feishu is built-in through `channels.feishu`, not through a plugin entry

ACP target provisioning is separate from onboarding:

```bash
moon run cmd/main -- acp add codex --home ~/.moonclaw
moon run cmd/main -- acp add codex --home ~/.moonclaw --id codex-review --workspace ~/Workspace/review-scratch
```

Current ACP behavior:

- `acp add codex` adds or updates a named Codex ACP target in `moonclaw.json`
- use `--id` when you want more than one ACP target on the same machine
- if `agents.defaults.workspace` is configured, `acp add codex` uses it as the default ACP workspace
- if `agents.defaults.cwd` is configured, `acp add codex` uses it as the default ACP cwd
- the command preserves unrelated config and only writes the target entry it manages
- if ACP can attach but `codex exec "<prompt>"` fails only from the gateway, pin `acp.targets.<id>.command` to the absolute path from `which codex`

Example:

```bash
which codex
```

Then set the ACP target command in `~/.moonclaw/moonclaw.json` to that exact path, for example:

```json
{
  "acp": {
    "targets": {
      "codex-main": {
        "command": "/absolute/path/to/codex"
      }
    }
  }
}
```

## Research Job Example

A concrete research-style controller profile is available at [research_job_moonclaw.json](/Users/kq/Workspace/moonclaw/docs/examples/research_job_moonclaw.json), with a matching test guide at [research_job_test_guide.md](/Users/kq/Workspace/moonclaw/docs/examples/research_job_test_guide.md).

This is the intended way to test research ability right now:

- copy the example `moonclaw.json` into an isolated workspace
- start the gateway against that workspace
- run `/plan-job` with a real literature-review style prompt
- confirm it and inspect `/job-status`
- verify that behavior changes when you edit the JSON profile, without changing MoonBit code

## 🪽 Feishu Usage

Once Feishu is configured and the gateway is running, the important commands are:

- `/plan-job <description>`
- `/confirm <proposal_id>`
- `/revise <proposal_id> <guidance>`
- `/reject <proposal_id>`
- `/job-status <job_id|run_id>`
- `/jobs`
- `/job-stop <job_id|run_id>`
- `/job-force-stop <job_id|run_id>`
- `/remember <text>`
- `/memory-search <query>`

## 🤖 Operator UI

The Rabbita UI exposes three main surfaces:

- 🧩 `Jobs`
  generative local workflow expansion
- 🌐 `ACP`
  remote-agent targets, sessions, runs, stdout/stderr, cancel/reset/detach
- 🔀 `Overview`
  mixed local↔remote lineage, handoffs, and case export

Exports currently include:

- 📄 ACP run transcript
- 📚 ACP session transcript
- 🕰️ ACP session timeline transcript
- 🔗 focused mixed-lineage transcript
- 🧳 combined case export

## 🛠️ Local Modes

Run local chat:

```bash
moon run cmd/main -- interactive
```

Run the terminal UI:

```bash
moon run cmd/main -- tui
```

## 📚 Docs

Start here:

- [docs/system_architecture.md](docs/system_architecture.md)
- [docs/job_system_architecture.md](docs/job_system_architecture.md)
- [docs/GATEWAY_USAGE.md](docs/GATEWAY_USAGE.md)
- [docs/expected_behaviors/README.md](docs/expected_behaviors/README.md)

Behavior docs:

- [docs/expected_behaviors/chat_and_job_flow.md](docs/expected_behaviors/chat_and_job_flow.md)
- [docs/expected_behaviors/workspace_and_memory.md](docs/expected_behaviors/workspace_and_memory.md)
- [docs/expected_behaviors/use_cases.md](docs/expected_behaviors/use_cases.md)
- [docs/expected_behaviors/operator_ui.md](docs/expected_behaviors/operator_ui.md)

## 🔧 Development

MoonClaw is a MoonBit project.

Useful commands:

```bash
moon check
moon test
moon info
moon fmt
```

## 💡 Positioning

MoonClaw is not trying to be only:

- a simple chat bot
- a bare CLI coding wrapper
- a single-step prompt runner

It is trying to be:

- 🧠 an agent runtime
- 🗂️ a durable job system
- 🪵 a workspace-centric execution environment
- 📡 an operator-controlled gateway
- 🤖 a local + remote multi-surface control plane
