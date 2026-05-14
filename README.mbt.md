# MoonClaw

> 🐇 MoonBit-native agent runtime + 📡 gateway + 🧠 memory + 🗂️ job system + 🤖 ACP remote-agent control

`MoonBit` `Agent Runtime` `Gateway` `Jobs` `ACP` `Feishu` `Weixin` `Memory` `Artifacts` `Operator UI`

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

## News

- `2026-04-21`: hardened provider-backed bootstrap execution for town/book integrations; provider tasks now run bounded `bootstrap_gather`, `source_materialize`, `knowledge_revise`, and `review_finalize` phases, emit parent `child_run.*` lifecycle events, compact long provider task ids before they reach journals, and refresh catalog surfaces so generated `wiki/index.md` lists durable source/entity/concept pages
- `2026-04-18`: fixed provider-run closeout so broadcast listeners stop cleanly after `PostConversation`; provider-backed wiki ingest now advances through adaptive child phases like `bootstrap_gather` and `source_materialize` instead of leaving completed child analysis runs stuck in `Running`
- `2026-04-15`: shortened persisted per-step metadata filenames to a bounded slug-plus-hash form so long delegated requests no longer crash with `File name too long`; logical `step_id` values remain unchanged in run state and UI
- `2026-04-13`: added external proposal packet import with `moonclaw proposal import <packet.json> [--confirm]`; imported packets are validated, converted into normal stored proposals, mapped onto configured job profiles, and optionally confirmed/executed through the standard workflow engine
- `2026-04-13`: generalized provider-backed execution into a reusable extension-task boundary; analysis and delegate steps can now target task providers via `execution_mode: "provider"` / `"extension"` plus `execution_target`, with backward-compatible `bookapi` aliases kept only for transition
- `2026-04-05`: added a concrete wiki-maintainer extension pack, a wiki-specific test guide, and automatic workspace detection for `raw/` + `wiki/` layouts so planning/execution can see `wiki/index.md`, `wiki/log.md`, and key wiki directories as part of runtime context
- `2026-04-04`: added the Rabbita `Cowork` surface with a conversation sidebar, transcript, composer, plan-mode actions, linked proposal/run cards, and a right-side context pane for preview, workspace, artifacts, and run state
- `2026-04-04`: added thread-local `/plan` mode with `/preview` and `/promote`; made final run `report.md` and `result.json` appear as clickable Rabbita cards; added a full-screen canvas toggle, aggregated starter documents into one operator-facing input card, and upgraded artifact opening from a small popup into a full-screen editor surface
- `2026-04-01`: clarified the execution layer with uniquely named analysis helpers, `delegate_run`, `patch_edit`, and `resource_providers`; hardened the analysis backbone by separating execution and tool contracts; added a first-class `web_fetch` tool and made analysis distinguish web search from web fetch instead of relying on loose booleans
- `2026-03-26`: split classic `/plan-job` from the E2E `/e2e` flow; added job-level preprocess and optional postprocess planning, in-place `/resume` from `WaitingForInput`, tighter planner skill enforcement, and assumption-based continuation for blocked analytical runs
- `2026-03-25`: added adaptive step expansion with `needs_input` / `needs_subplan`, `WaitingForInput` pause-and-resume via `/resume`, run-workspace output materialization, and fixed Feishu channel chat to honor the configured primary model from `~/.moonclaw/moonclaw.json`
- `2026-03-24`: merged `opc`, `weixin`, and `canvas`; added Weixin Official Account support; upgraded the controller/company canvas; made the generic fallback a single `execute` step
- `2026-03-23`: added generic worker routing with `child_profile`, `execution_mode`, and `execution_target`; routed analysis through ACP
- `2026-03-20`: made job and run ids human-readable; moved run workspaces under `<workspace>/moonclaw-jobs`; fixed local time display; improved Feishu progress UX
- `2026-03-19`: added the research job example and test guide; made controller policy more declarative and JSON-driven
- `2026-03-17`: added `acp add codex`; fixed `~/.moonclaw` defaults and ACP repeated-run handling

## Operator UX

Current job behavior is designed to stay readable from chat and from the workspace:

- new proposal ids are human-readable and time-prefixed instead of raw UUIDs
- new run ids use a readable `run-YYYYMMDD-HHMMSS-...` format
- `/job-status` and `/jobs` show job title and created time alongside ids
- top-level run workspaces are created under `<workspace>/moonclaw-jobs/<run-id>`
- child runs are created under the parent run workspace at `moonclaw-subjobs/<run-id>`
- run workspaces are run-owned and no longer copy workspace markdown like `AGENTS.md`, `USER.md`, `MEMORY.md`, `IDENTITY.md`, or `ROUTINES.md`
- job timestamps are rendered in local time with an explicit offset
- if a run reaches `WaitingForInput`, Feishu status replies now tell you to reply in-thread with `/resume` plus the missing text, optionally with attachments
- normal Feishu chat uses the configured primary model from `~/.moonclaw/moonclaw.json`; stale thread-local bare model ids no longer override it
- provider-backed adaptive phases are expected to close their event session after the final assistant turn so parent runs can move on to the next phase instead of remaining `Running`
- provider-backed child runs emit parent `child_run.started`, `child_run.succeeded`, and `child_run.failed` events so operators can see which bounded child run is currently blocking or closing a provider phase
- provider-task results use compact stable task ids for long prompt-derived provider tasks before they are persisted through extension providers; runtime step ids remain unique and hash-backed

## 🚀 Current Capabilities

- 🖥️ `interactive` and `tui` local modes
- 📡 long-running HTTP/RPC `gateway`
- 🪽 Feishu integration
- 💬 Weixin Official Account integration
- 🧠 memory capture, retrieval, and workspace materialization
- 🗂️ per-run and per-subjob workspaces
- 🌳 git-managed run history inside each workspace
- 📦 artifact storage and grounded artifact Q&A
- 🔬 generic job workflows
- 📥 external proposal packet import into the normal proposal lifecycle
- 🤖 ACP targets, sessions, and runs for remote agent control
- 🪟 Rabbita operator UI with:
  - cowork conversation surface
  - local job expansion
  - ACP remote-agent lane
  - mixed local↔remote lineage view
  - controller/company board lanes
  - final run report/result cards
  - starter-doc aggregation
  - linked conversation proposal/run cards
  - conversation preview/workspace/artifact/run context tabs
  - full-screen canvas
  - full-screen artifact editor
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

Import an external proposal packet:

```bash
moon run cmd/main -- proposal import keeper/jobs/ingest-001.json --home ~/.moonclaw
```

Gateway-path alias:

```bash
moon run cmd/main -- gateway proposal import keeper/jobs/ingest-001.json --home ~/.moonclaw
```

Import and execute immediately:

```bash
moon run cmd/main -- proposal import keeper/jobs/ingest-001.json --home ~/.moonclaw --confirm
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

With that setup, new run workspaces will appear under:

```text
~/.moonclaw/workspace/moonclaw-jobs/
```

instead of being hidden under a nested `.moonclaw/job-workspaces/` path.

Open the operator UI:

```text
http://localhost:18123/ui
```

If `/ui` says the Rabbita bundle is missing, build it from the repo:

```bash
./scripts/build-rabbita-ui.sh
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

Local/controller analysis can also run through ACP when a step carries:

- `execution_mode: "acp"`
- `execution_target: "<target-id>"`

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

- copy the example `moonclaw.jobs.json` into an isolated workspace
- start the gateway against that workspace
- run `/plan-job` with a real literature-review style prompt
- confirm it and inspect `/job-status`
- inspect the generated run workspace under `<workspace>/moonclaw-jobs/<run-id>`
- verify that behavior changes when you edit the JSON profile, without changing MoonBit code

## Wiki Maintainer Example

A concrete wiki-maintainer controller pack is available at [wiki_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/wiki_moonclaw.jobs.json), with a matching test guide at [wiki_job_test_guide.md](/Users/kq/Workspace/moonclaw/docs/examples/wiki_job_test_guide.md).

This is the intended MoonClaw side of a persistent markdown-wiki workflow:

- copy the example `moonclaw.jobs.json` into a wiki workspace
- start the gateway against that workspace
- run `/plan-job` for wiki ingest, wiki query, or wiki lint requests
- confirm the draft and inspect `/job-status`
- inspect the generated run workspace under `<workspace>/moonclaw-jobs/<run-id>`
- verify that behavior changes when you revise the workspace-local pack instead of changing MoonBit code

MoonClaw now also detects wiki-shaped workspaces automatically when they contain:

- `raw/`
- `wiki/`
- `wiki/index.md`
- `wiki/log.md`

and includes compact wiki structure plus index/log excerpts in runtime prompt context. That keeps the agent side aligned with a maintained wiki workspace without hardcoding any specific host system into core.

## OPC Job Example

A concrete one-person-company controller profile is available at [opc_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/opc_moonclaw.jobs.json), with a matching test guide at [opc_job_test_guide.md](/Users/kq/Workspace/moonclaw/docs/examples/opc_job_test_guide.md).

This example is meant to prove the extension boundary:

- MoonClaw core stays generic
- OPC behavior comes from `moonclaw.jobs.json`
- role behavior comes from workspace `skills/`
- controller bookkeeping, delegation, artifacts, and notifications are reused

The recommended architecture for keeping research, wiki, and OPC packs side by side is documented in [extension_packs.md](/Users/kq/Workspace/moonclaw/docs/extension_packs.md).

The Rabbita jobs surface can now render controller runs as a company-style board with:

- split / merge anchors
- horizontal role lanes
- company health strip
- lane sequence and handoff cards

If a profile wants to control the board explicitly, step metadata can set:

- `board_lane`
- `board_order`

otherwise the UI falls back to heuristics such as OPC skill and worker-role names.

## Weixin Usage

MoonClaw can now run Feishu and Weixin together in one gateway instance.

Weixin is currently implemented as a webhook-driven Official Account channel:

- callback path: `/webhook/weixin`
- plaintext text messages in the current slice
- replies sent through the custom-service API

See [openclaw_weixin_reference.md](/Users/kq/Workspace/moonclaw/docs/openclaw_weixin_reference.md).

## 🪽 Feishu Usage

Once Feishu is configured and the gateway is running, the important commands are:

- `/plan <description>`
- `/preview`
- `/plan-job <description>`
- `/e2e <description>`
- `/promote`
- `/confirm <proposal_id>`
- `/revise <proposal_id> <guidance>`
- `/reject <proposal_id>`
- `/job-status <job_id|run_id>`
- `/jobs`

If a job pauses in `WaitingForInput`:

- use `/job-status <job_id|run_id>` to see what is missing
- reply to the waiting Feishu message with `/resume` followed by the missing text, optionally with attachments
- `/resume` resumes the same run in place from the blocked step
- operator guidance like `/resume guess missing data` tells MoonClaw to continue with explicit assumptions when a usable screening result is still possible
- plain non-reply chat still goes to the normal conversation path
- `/job-stop <job_id|run_id>`
- `/job-force-stop <job_id|run_id>`
- `/remember <text>`
- `/memory-search <query>`

Command roles:

- `/plan` starts thread-local plan mode and replies with a transient plan preview
- while plan mode is active, plain follow-up messages in the same thread refine that plan instead of going to normal chat
- `/preview` shows the current plan-mode candidate again; if you add guidance, it refreshes the candidate first without promoting it
- `/promote` turns the current plan-mode candidate into a normal durable proposal
- `/plan-job` creates a durable draft proposal that can later be revised and confirmed
- `/e2e` creates the augmented draft flow with preprocess and optional postprocess

CLI-only import:

- `moon run cmd/main -- proposal import <packet.json> [--confirm]`

## 🤖 Operator UI

The Rabbita UI exposes three main surfaces:

- 🧩 `Jobs`
  generative local workflow expansion
- 🌐 `ACP`
  remote-agent targets, sessions, runs, stdout/stderr, cancel/reset/detach
- 🔀 `Overview`
  mixed local↔remote lineage, handoffs, and case export

Current Rabbita behavior also includes:

- final run `report.md` and `result.json` surfaced as clickable cards even when they only exist as workspace files
- starter attachment artifacts collapsed into one `Starter Docs` card instead of many low-level cards
- report and artifact clicks opening a full-screen editor-style surface
- a `Full Screen` toggle on the run canvas route

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

## Star Growth

<!-- STAR_GROWTH:START -->
_Last updated: 2026-05-14_

```mermaid
xychart-beta
    title "GitHub Stars"
    x-axis ["05-01","05-02","05-03","05-04","05-05","05-06","05-07","05-08","05-09","05-10","05-11","05-12","05-13","05-14"]
    y-axis "Stars" 22 --> 24
    line [23,23,23,23,23,23,23,23,23,23,23,23,23,23]
```
<!-- STAR_GROWTH:END -->
