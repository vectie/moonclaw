# MoonClaw

> 🦀 MoonBit-native agent runtime + 📡 gateway + 🧠 memory + 🗂️ job system + 🤖 ACP remote-agent control

MoonClaw is an agent and automation system built on top of [moonbitlang/maria](https://github.com/moonbitlang/maria), inspired by [openclaw/openclaw](https://github.com/openclaw/openclaw), and shaped around a full job runtime instead of a thin chat wrapper.

It is designed for:

- 💬 chat-driven planning
- ⚙️ long-running background jobs
- 🧪 research / analysis workflows
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
- 🔬 research-oriented job families
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
~/.moon/bin/moon run cmd/main -- onboard status --home ~/.moonclaw
```

Use Codex OAuth and switch the primary model automatically:

```bash
~/.moon/bin/moon run cmd/main -- onboard auth codex --home ~/.moonclaw
```

Configure Feishu:

```bash
~/.moon/bin/moon run cmd/main -- onboard configure \
  --home ~/.moonclaw \
  --enable-feishu \
  --feishu-app-id <app_id> \
  --feishu-app-secret <app_secret>
```

Start the gateway:

```bash
~/.moon/bin/moon run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/Workspace/moonclaw
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

## 🧭 Onboarding Flow

Useful onboarding commands:

```bash
~/.moon/bin/moon run cmd/main -- onboard status --home ~/.moonclaw
~/.moon/bin/moon run cmd/main -- onboard auth status --home ~/.moonclaw
~/.moon/bin/moon run cmd/main -- onboard auth codex --home ~/.moonclaw
~/.moon/bin/moon run cmd/main -- onboard auth copilot --home ~/.moonclaw
~/.moon/bin/moon run cmd/main -- onboard models --home ~/.moonclaw
~/.moon/bin/moon run cmd/main -- onboard switch codex --home ~/.moonclaw
~/.moon/bin/moon run cmd/main -- onboard print-config --home ~/.moonclaw
```

Current behavior:

- 🔐 `onboard auth codex` connects Codex OAuth and updates the primary model to `codex/gpt-5.4`
- 🔐 `onboard auth copilot` connects Copilot OAuth and updates the primary model to `copilot/gpt-5.2`
- 🎯 `onboard switch <model>` changes the active primary model explicitly
- 🪽 Feishu is built-in through `channels.feishu`, not through a plugin entry

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
~/.moon/bin/moon run cmd/main -- interactive
```

Run the terminal UI:

```bash
~/.moon/bin/moon run cmd/main -- tui
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
~/.moon/bin/moon check
~/.moon/bin/moon test
~/.moon/bin/moon info
~/.moon/bin/moon fmt
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
