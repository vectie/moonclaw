# Package Inventory

Date: 2026-03-17

This appendix groups the current MoonClaw packages by architectural role, based on the repository structure and public package boundaries.

## 1. Root Product Packages

- `moonclaw`
- `agent`
- `ai`
- `channel`
- `clock`
- `event`
- `file`
- `job`
- `model`
- `onboarding`
- `plugin`
- `prompt`
- `sdk`
- `security`
- `tool`
- `workspace`
- `acp`

Purpose:

- core runtime, orchestration, shared product types, and high-level user-facing behavior

## 2. Gateway Packages

- `gateway/client`
- `gateway/protocol`
- `gateway/server`

Purpose:

- client/server transport, protocol types, long-running gateway operations, UI/API surface

## 3. Command Packages

- `cmd/main`
- `cmd/main/argument`
- `cmd/main/conversation`
- `cmd/main/exec`
- `cmd/main/interactive`
- `cmd/main/tui`
- `cmd/gateway`
- `cmd/acp`
- `cmd/onboard`
- `cmd/server`
- `cmd/daemon`
- `cmd/jsonl2md`
- `cmd/test`
- `cmd/test-lock`
- `cmd/test-to-be-killed`
- `cmd/internal/test_utils`

Purpose:

- operational entry points, CLI routing, and targeted command workflows

## 4. Tool Packages

- `tools/apply_patch`
- `tools/execute_command`
- `tools/list_files`
- `tools/list_jobs`
- `tools/read_file`
- `tools/read_multiple_files`
- `tools/replace_in_file`
- `tools/search_files`
- `tools/todo`
- `tools/wait_job`
- `tools/write_to_file`

Purpose:

- agent-exposed operational tools

## 5. Channel Integration Packages

- `channels/feishu`

Purpose:

- built-in external chat integration

## 6. OAuth Packages

- `oauth/codex`
- `oauth/copilot`

Purpose:

- provider authentication flows and account readiness integration

## 7. UI Packages and Modules

Top-level UI areas visible in the repo:

- `ui/rabbita-job`
- `ui/web`
- `ui/native`
- `ui/vsc-ext`

Current primary operator UI module:

- `ui/rabbita-job`

Purpose:

- web operator surface for jobs, ACP, lineage, artifacts, and exports

## 8. Internal Packages

Observed internal package count: 44

Major internal areas include:

- `internal/fsx`
- `internal/pathx`
- `internal/os`
- `internal/spawn`
- `internal/httpx`
- `internal/websocket`
- `internal/pino`
- `internal/conversation`
- `internal/git`
- `internal/mock`
- `internal/tui`
- `internal/token_counter`
- `internal/tiktoken`
- `internal/uuid`
- `internal/rand`
- `internal/buildinfo`
- `internal/signal`
- `internal/schema`
- `internal/skills`
- `internal/content_extractor`
- `internal/context_pruner`
- `internal/openai`
- `internal/openrouter`

Purpose:

- reusable runtime substrate, provider plumbing, test support, transport, filesystem/process primitives, and local UI internals

## 9. Non-MoonBit Supporting Areas

Other structurally important repo areas:

- `docs`
- `scripts`
- `skills`
- `sdk/nodejs`
- `sdk/python`
- `sdk/java`
- `unused`

Purpose:

- documentation, packaging/build helpers, reusable skill definitions, non-MoonBit SDK clients, and legacy or inactive state examples

## 10. Architectural Reading of the Package Layout

The layout suggests these architectural priorities:

- keep execution/runtime logic in MoonBit packages
- isolate end-user command surfaces in `cmd/*`
- centralize general substrate in `internal/*`
- expose long-running operational control through `gateway/server`
- keep UI as a separately buildable surface
- keep tools modular so they can be composed into agents selectively

The package layout also makes clear that MoonClaw is not a single binary with a small helper library. It is a platform codebase with:

- runtime layers
- protocol layers
- command layers
- UI layers
- external integration layers
- persistence and orchestration layers
