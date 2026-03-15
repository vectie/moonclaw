# MoonClaw

MoonClaw is a MoonBit-native agent and automation system.

It is:

- built on top of the [moonbitlang/maria](https://github.com/moonbitlang/maria) lineage
- inspired by [openclaw/openclaw](https://github.com/openclaw/openclaw)
- tailored toward a full job system with chat-driven planning, background execution, dedicated run workspaces, memory, and channel integrations

## What MoonClaw Is Now

The current system is centered on a long-running `gateway` runtime plus a generic job platform.

Main capabilities:

- local interactive and TUI modes
- HTTP/RPC gateway service
- Feishu channel integration
- chat-initiated job drafting and confirmation
- async job execution with scheduler, retries, notifications, and subjobs
- dedicated per-run and per-subjob workspaces
- run-local git checkpoints
- artifact storage and grounded artifact Q&A
- structured long-term memory plus workspace materialization
- research as the first built-in job family

This is no longer just a thin coding assistant wrapper. The main direction is:

```text
chat / CLI / HTTP
  -> proposal
  -> compile to workflow
  -> execute as job
  -> persist artifacts, memory, and workspace state
  -> notify and inspect through the gateway
```

## Runtime Modes

Top-level entry points:

- `interactive`
- `tui`
- `gateway`
- `daemon`
- `server`

For always-on operation, `gateway` is the main runtime.

## Core Architecture

At a high level:

```text
Feishu / CLI / TUI / HTTP / RPC
  -> gateway adapters
  -> job application/services
  -> workflow runtime
  -> artifacts + memory + workspaces
  -> notifications and status surfaces
```

Important subsystems:

- `agent`
  core conversation/agent runtime
- `gateway`
  long-running HTTP/RPC/channel service
- `job`
  planning, compilation, execution, artifacts, memory, chat control
- `workspace`
  configured workspace runtime plus run workspaces
- `plugin`
  plugin registry/runtime view
- `security`
  session scope, pairing, approval, command policy

## Current Strengths

MoonClaw is strongest today as:

- a gateway-backed async job system
- a chat-controlled operator surface for background work
- a workspace-centric execution system
- a research and analysis automation platform

It is less complete today in:

- full OpenClaw binding parity
- mature plugin install lifecycle
- polished onboarding/wizard UX

## Typical Use Cases

- Draft a job in Feishu, revise it, confirm it, and let it run in the background.
- Run research jobs that fetch, parse, analyze, and summarize papers.
- Give each run its own isolated workspace and inspect the git history afterward.
- Ask grounded questions over produced artifacts and stored memories.
- Run recurring automation through the gateway scheduler.

## Basic Usage

From the repo root:

```bash
cd ~/Workspace/mcl

~/.moon/bin/moon run cmd/main -- interactive
~/.moon/bin/moon run cmd/main -- tui
~/.moon/bin/moon run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/Workspace/mcl
```

Useful gateway commands:

```bash
~/.moon/bin/moon run cmd/main -- gateway health
~/.moon/bin/moon run cmd/main -- gateway jobs
~/.moon/bin/moon run cmd/main -- gateway job-runs
~/.moon/bin/moon run cmd/main -- gateway channels
```

In Feishu, the important commands are:

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

## Docs

Start here:

- [docs/system_architecture.md](docs/system_architecture.md)
- [docs/job_system_architecture.md](docs/job_system_architecture.md)
- [docs/GATEWAY_USAGE.md](docs/GATEWAY_USAGE.md)
- [docs/expected_behaviors/README.md](docs/expected_behaviors/README.md)

Behavior and operator docs:

- [docs/expected_behaviors/chat_and_job_flow.md](docs/expected_behaviors/chat_and_job_flow.md)
- [docs/expected_behaviors/workspace_and_memory.md](docs/expected_behaviors/workspace_and_memory.md)
- [docs/expected_behaviors/use_cases.md](docs/expected_behaviors/use_cases.md)

## Development

MoonClaw is a MoonBit project.

Useful commands:

```bash
~/.moon/bin/moon check
~/.moon/bin/moon test
~/.moon/bin/moon info
~/.moon/bin/moon fmt
```

The repo currently checks clean with `moon check`.
