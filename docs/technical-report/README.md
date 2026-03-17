# MoonClaw Technical Report

Date: 2026-03-17  
Branch basis: `sandbox`  
Module: `moonbitlang/moonclaw`

## 1. Executive Summary

MoonClaw is a MoonBit-native agent platform that combines:

- a local agent runtime
- a long-running HTTP/RPC gateway
- a generic job orchestration system
- persistent memory and workspace management
- ACP remote-agent control
- chat/channel integrations
- operator-facing UI surfaces

The current codebase is not a thin chat client. It is a multi-surface execution system with durable state, workflow persistence, operator controls, and both local and remote execution lanes.

At the module level, the project currently contains 98 MoonBit packages. The heaviest concentration is in `internal/`, which provides shared runtime primitives. The primary product-facing subsystems are `agent`, `job`, `gateway`, `security`, `workspace`, `acp`, `onboarding`, `channel`, `channels/feishu`, `cmd/*`, and `ui/rabbita-job`.

The current branch also contains an active sandbox/approval feature slice. Risky shell commands can now be assessed, blocked, or approval-gated through the `security` subsystem, and gateway-backed chat sessions can scope those approvals to a specific chat/thread.

## 2. System Scope and Product Shape

MoonClaw currently supports these interaction modes:

- local interactive CLI
- local TUI
- HTTP/RPC gateway
- Feishu chat commands
- ACP remote-agent sessions and runs
- operator UI served by the gateway

At a high level, the system supports this lifecycle:

1. receive a request from CLI, chat, UI, or channel
2. create or resume an agent session
3. use tools and model-backed reasoning
4. optionally draft and execute a durable job workflow
5. persist state, outputs, timeline events, and workspace artifacts
6. expose state back through chat replies, APIs, and the operator UI

## 3. Module and Package Topology

Observed package count by top-level area:

- root package set: 17
- `cmd`: 16
- `gateway`: 3
- `channels`: 1
- `oauth`: 2
- `tools`: 11
- `ui`: 4
- `internal`: 44

This distribution shows a clear split:

- product/runtime packages live near the root
- reusable substrate is concentrated under `internal/`
- command entrypoints are isolated under `cmd/`
- UI exists as a separate module under `ui/rabbita-job`

See [package-inventory.md](./package-inventory.md) for a categorized package appendix.

## 4. Core Runtime Architecture

### 4.1 Agent Layer

The `agent` package is the core conversation runtime. Publicly, it exposes:

- `agent.new(...)`
- `agent.load(...)`
- `Agent::queue_message(...)`
- `Agent::start(...)`
- `Agent::add_tool(...)`
- `Agent::add_tools(...)`

This layer is responsible for:

- maintaining conversation state
- managing model interaction
- attaching tools
- emitting runtime events
- resuming persisted sessions

The root package `moonclaw` is a product-oriented wrapper around `agent`. It constructs a configured agent, wires in standard tools, and exposes the higher-level `Moonclaw::new`, `Moonclaw::resume_`, `Moonclaw::start`, and `Moonclaw::close` lifecycle.

### 4.2 Tool Layer

The standard local toolchain currently includes:

- `tools/execute_command`
- `tools/list_files`
- `tools/read_file`
- `tools/search_files`
- `tools/todo`
- `tools/apply_patch`
- `tools/write_to_file`

These tools are injected from the root `moonclaw` wrapper. Tool behavior is not only convenience logic; it is increasingly policy-aware. The clearest example is `execute_command`, which now integrates with `security` for simulation, blocking, and approval-gated execution.

### 4.3 Model Layer

The `model` package abstracts provider-backed model selection. The broader system treats model choice as configurable state rather than a compile-time constant. Onboarding and config can switch active defaults, and ACP targets can carry their own model selection.

### 4.4 Prompt Layer

The `prompt` package provides shared system prompt material. The root `moonclaw` package assembles prompt prelude and tool-specific prompt fragments when creating the agent.

## 5. Gateway Architecture

The gateway is the long-running product surface. It is the central operational service for:

- HTTP endpoints
- RPC-like operations
- agent session orchestration
- channel integrations
- ACP target/session/run handling
- job runtime visibility and controls
- operator UI hosting

The public surface of `gateway/server` shows several architectural concerns bundled into one service:

- channel manager and persistent channel state
- agent mailboxes
- coordination tasks and pipelines
- ACP HTTP methods and run execution
- job chat commands and workflow notifications
- UI snapshots and timelines

This is not yet a narrowly isolated microservice design. The gateway is the operational core and acts as the convergence point between chat sessions, jobs, ACP, UI snapshots, and approval state.

Important current gateway behaviors include:

- serving `/ui` and root-level `/assets/...` for the built Rabbita bundle
- persisting runtime state under the configured home directory
- creating or resuming channel-bound agent sessions
- exposing ACP targets/sessions/runs
- exposing job data for the operator UI
- applying security pairing and approval logic to channel traffic

## 6. Job System Architecture

The `job` package is one of the largest and most important parts of the system. Its public API shows that it currently owns:

- proposal drafting and planning
- proposal-to-workflow translation
- workflow execution
- subjob orchestration
- run lifecycle
- memory capture
- workspace preparation and checkpointing
- notifications
- UI snapshots and timeline generation
- chat command rendering and parsing

Key concepts visible from the public API:

- `JobProposal`
- `JobDefinition`
- `WorkflowDefinition`
- `JobRun`
- `WorkflowEngine`
- `RuntimeManager`
- memory and artifact records
- UI snapshot and timeline types

Important current design characteristic:

The embedded template system was previously removed or heavily reduced in favor of more mechanical proposal-to-workflow behavior. The current public API still exposes proposal compilation, but the intended direction is much thinner than the earlier hardcoded template approach.

Current execution shape:

1. a proposal is drafted or planned
2. it is compiled into a job/workflow definition
3. the workflow engine executes it step by step
4. run state, events, workspace updates, and artifacts are persisted
5. jobs are surfaced through chat, gateway APIs, and the UI

The job system also now participates in command safety:

- `job.Manager::spawn(...)` performs command risk assessment
- blocked commands raise `CommandBlocked`
- high-risk commands raise `CommandApprovalRequired`

That is a strong sign that safety policy is moving into shared execution infrastructure rather than remaining a tool-local concern.

## 7. ACP Architecture

The `acp` package is the remote-agent control plane. It handles:

- ACP targets
- ACP sessions
- ACP runs
- launch plans and launch commands
- target-specific runtime metadata
- UI snapshot generation
- chat command parsing and rendering

Core runtime objects:

- `AcpTarget`
- `AcpSession`
- `AcpRun`
- `AcpLaunchPlan`
- `AcpLaunchCommand`
- `AcpRuntime`

This subsystem gives MoonClaw a second execution lane:

- local jobs and tools run inside MoonClaw-controlled execution
- remote ACP runs delegate work to an external agent backend such as Codex

This is strategically important because the system is not forced into a single-agent model. Instead, MoonClaw can act as coordinator/operator surface while ACP agents perform delegated execution.

Current ACP behavior includes:

- config-backed target definitions in `moonclaw.json`
- attach/detach semantics for session-bound control
- run creation and persistence
- status/timeline reporting
- operator UI inspection
- Feishu chat commands for ACP attach/run/status flows

## 8. Security and Approval Architecture

The `security` package currently has two major roles:

- chat/channel pairing and approval state
- command safety assessment and approval tracking

Core primitives now include:

- `SecurityRuntime`
- `ApprovalRecord`
- `PairingRecord`
- `approval_scope_key(...)`
- `assess_shell_command(...)`
- `CommandAssessment`
- `CommandRiskLevel`
- `command_approval_target(...)`
- `command_approval_token(...)`

The current approval model is scope-based. A scope key is derived from channel/account/recipient/thread for chat-originated actions. That allows approvals to be isolated to a specific conversation context.

Current security capabilities:

- require explicit pairing for restricted DM policies
- store and list pending approvals
- approve tokens and consume approvals
- render user-facing approval prompts
- classify shell commands into low, medium, high, or blocked risk

Current sandbox feature state on this branch:

- risky `execute_command` calls can be simulated instead of executed
- blocked commands are denied outright
- high-risk commands require approval
- gateway-backed sessions inject channel/thread approval scope
- a user can approve via the existing approval path and then retry the command

This is not yet a full enterprise sandbox, but the foundational model is in place:

- command assessment
- approval tokens
- persisted approval state
- scope-aware enforcement

## 9. Workspace and Persistence Model

MoonClaw distinguishes three important roots:

- `home`
- `cwd`
- `workspace`

Their current responsibilities are:

- `home`: persistent MoonClaw state such as jobs, security state, ACP state, sessions, config
- `cwd`: default process working directory for agent/tool execution
- `workspace`: project or corpus root used for workspace-aware behavior

The `workspace` package currently exposes:

- workspace snapshot loading
- managed workspace file names
- prompt context generation

The `job` package further extends this with dedicated run workspaces and workspace checkpointing. The system therefore has both:

- global/configured workspace context
- per-run isolated workspace materialization

This is important operationally because it lets the platform support both:

- direct mutation of a live repo/workspace
- isolated job execution in dedicated run workspaces

## 10. Configuration Model

The system is configured primarily through `moonclaw.json`, with onboarding and command helpers writing or updating it.

Important current config themes:

- primary model selection
- gateway port and token
- agent default `cwd`
- agent default `workspace`
- ACP targets
- channel configuration, especially Feishu
- session/security defaults

The current user-facing home default is `~/.moonclaw`. That is where MoonClaw expects to persist runtime state and commonly where it resolves its primary config.

Operationally, config and state are intentionally separated from the source repo:

- source repo holds code and documentation
- `~/.moonclaw` holds persistent product state

## 11. Onboarding and Operational Bootstrap

The `onboarding` package owns local setup inspection and config generation. It currently supports:

- auth readiness inspection
- OAuth-driven auth bootstrap
- model discovery
- config rendering
- workspace bootstrap
- Feishu configuration

This is product-significant because MoonClaw is not assuming a hand-edited config-only experience. It provides an explicit guided bootstrap path for local installation and operations.

## 12. Channel and Feishu Integration

The `channel` and `channels/feishu` packages provide the external chat surface. Feishu is currently a first-class built-in channel, not a plugin-only extension.

Current Feishu capabilities include:

- inbound message handling
- DM policy enforcement
- pairing requirements
- job command dispatch
- ACP command dispatch
- approval commands
- session-bound agent conversation

This means the gateway is not just a machine API; it is also a channel-native operational bot surface.

## 13. Operator UI

The operator UI lives in a separate module under `ui/rabbita-job`.

Current characteristics:

- standalone MoonBit web app
- built bundle served by the gateway
- integrates local job visibility and ACP visibility
- polls snapshots for reconciliation while also using live event flows

Current operator surfaces described by the code and README:

- Jobs
- ACP
- Overview

Current inspected objects include:

- local runs
- ACP targets, sessions, runs
- mixed lineage between local and remote activity
- artifact and memory views
- workspace inspection
- transcript export and case export

Architecturally, this UI is an operator surface over the gateway state model, not a separate product backend.

## 14. CLI and Entry Point Structure

The main CLI entry is `cmd/main/main.mbt`. Current top-level command routing includes:

- `conversation`
- `server`
- `daemon`
- `gateway`
- `acp`
- `onboard`
- `exec`
- `tui`
- default interactive mode

The `cmd` directory is intentionally decomposed into targeted command packages rather than one large monolith. This keeps operational concerns separated:

- `cmd/gateway` for service control and gateway client operations
- `cmd/acp` for ACP target provisioning
- `cmd/onboard` for bootstrap/setup flows
- `cmd/main/*` for interactive, exec, and TUI user modes

## 15. SDK and Multi-Client Surface

The repo contains `sdk/nodejs`, `sdk/python`, and `sdk/java`. That indicates the product is intended to be consumed from more than just MoonBit-native code and CLI surfaces.

This is strategically important because it suggests the gateway/protocol model is meant to be externally consumable and not purely internal implementation detail.

## 16. Internal Substrate

The `internal/` area is very large and currently contains 44 packages. It includes:

- process spawning
- filesystem helpers
- HTTP and websocket support
- conversation persistence
- logging
- UUID/random helpers
- git helpers
- token counting
- TUI internals
- mock/test support
- path utilities
- provider-specific integrations

This substrate is the technical foundation of the higher-level product packages. The current structure favors internal package extraction over large utility files, which is a good sign for long-term maintainability.

## 17. Build, Test, and Documentation Conventions

The repository follows standard MoonBit package/module structure:

- `moon.mod.json` at module root
- `moon.pkg` at package boundaries
- `*_test.mbt` and `*_wbtest.mbt` for tests
- `pkg.generated.mbti` for generated public API snapshots

The normal engineering loop is:

- `moon check`
- `moon test`
- `moon info`
- `moon fmt`

The project is also documentation-aware:

- many packages include `README.mbt.md`
- UI and command subtrees include dedicated READMEs
- generated `.mbti` files are used as public API summaries

## 18. Current Architectural Strengths

- clear separation between product-facing packages and internal substrate
- strong operational surface through the gateway
- durable job and ACP state instead of ephemeral-only execution
- explicit home/cwd/workspace separation
- multiple interaction modes sharing common runtime pieces
- growing security model that is becoming infrastructure rather than ad hoc logic
- operator UI tightly aligned with runtime state

## 19. Current Architectural Tensions

- the gateway remains a large convergence point with many responsibilities
- the job system is still broad and owns many concerns at once
- the codebase still carries historical complexity from earlier planning/template approaches
- the line between generic runtime and product-specific orchestration can still drift
- approval UX exists in the runtime, but richer first-class UI/API management is still maturing

## 20. Recommended Near-Term Technical Priorities

1. Finish the approval model end-to-end.
   Add explicit gateway/UI surfaces for pending command approvals and approval auditability.

2. Keep proposal compilation mechanical.
   Avoid reintroducing hidden template logic that rewrites confirmed workflow structure.

3. Continue narrowing subsystem boundaries.
   In particular, reduce responsibility density inside `gateway/server` and `job`.

4. Formalize execution policy.
   Turn current command assessment heuristics into a documented policy layer with clearer config hooks.

5. Document storage contracts.
   Write explicit docs for what persists under `home`, what is workspace-derived, and what is per-run.

## 21. Conclusion

Based on the current code structure, MoonClaw is best understood as a durable agent operations platform rather than a simple assistant shell.

Its defining characteristics are:

- persistent execution state
- multiple operator surfaces
- local and remote execution lanes
- workflow/job orchestration
- channel-native operation
- growing policy and approval enforcement

The current `sandbox` branch work strengthens that direction by moving command safety into shared infrastructure and by binding approvals to real execution scopes instead of one-off tool-local behavior.

## Appendix

- [Package Inventory](./package-inventory.md)
