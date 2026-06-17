# Daemon Server

## Run

From the root directory of the repository, run:

```bash
moon run cmd/main -- daemon --port 8090 --serve cmd/daemon
```

It will first test if there is a running instance of the daemon server by
reading the `~/.moonclaw/daemon.json` file. If there is no running instance, it
will start a new one (detach from the terminal if `--detach` flag is specified);
if there is a running instance, it exit immediately.

To detach the daemon from the terminal, you can use `--detach` flag:

```bash
moon run cmd/main -- daemon --port 8090 --serve cmd/daemon --detach
```

Consumers of this daemon server would typically spawn the daemon server with
random port (`--port 0`) and `--detach` flag, as it provides a uniformed way
to spawn and obtain the port of the daemon server:

1. Spawn the daemon server with:

   ```bash
   moon run cmd/main -- daemon --port 0 --serve cmd/daemon --detach
   ```

2. Read the port from the `~/.moonclaw/daemon.json` file. Once the process
   exits with `0`, The file is guaranteed to exist and contains a valid JSON
   object with the `port` and `pid` fields.

   ```json
   {
     "port": 8090,
     "pid": 12345
   }
   ```

3. Interact with the daemon server using the port obtained from the file.

## Programmatic API

The `vectie/moonclaw/cmd/daemon` package exposes a small set of public
symbols so other MoonBit code can embed or manage the daemon without shelling
out to the CLI. The table below summarizes each entry point:

| Symbol | Description |
| --- | --- |
| `async fn start(args : ArrayView[String]) -> Unit` | Parses CLI-style flags, optionally detaches, validates model availability, and either reuses an existing daemon or creates a new `Daemon` and calls `serve`. |
| `async fn detach(exec_path? : String, port? : Int, serve? : StringView) -> Int` | Spawns (or reuses) a detached daemon process, waits for it to write `~/.moonclaw/daemon.json`, and returns the PID recorded in that file. |
| `struct Daemon` | In-memory supervisor that tracks moonclaw tasks, owns the HTTP server, and bridges REST calls to per-task processes. |
| `async fn Daemon::new(...) -> Daemon?` | Constructs a daemon with optional dependency injection, validates `exec_path`, grabs the daemon lock file, and binds the HTTP server. Returns `None` if another daemon already holds the lock. |
| `fn Daemon::port(self) -> Int` | Reports the actual TCP port the HTTP server bound to (handy when using port `0`). |
| `async fn Daemon::serve(self) -> Unit` | Starts the daemon event loop: background task manager plus the HTTP router with shared CORS middleware. |

Typical embedding code looks like this:

```moonbit
let daemon = match Daemon::new(exec_path~, port~, serve~, home~) {
  Some(daemon) => daemon
  None => return // another daemon already running
}
daemon.serve()
```

## API

MoonCode daemon code is split by runtime responsibility rather than by route
alone:

- `mooncode/core` owns the extractable MoonCode contract surface shared with
  Moondesk: the `mooncode.v1` protocol marker, native capability contract id,
  required endpoint/tool lists, canonical required capability surface, and its
  SHA-256 surface fingerprint. It is currently mirrored per repo so both builds
  remain independent; the intended next step is replacing those mirrors with one
  physically shared MoonCode module. While mirrored, Moondesk's
  `scripts/verify-mooncode-core-sync.sh` is the sync gate for this contract and
  compares the core source files plus normalized generated interfaces; Moondesk's
  `scripts/validate-core-boundaries.sh` composes that gate with targeted
  Moondesk, MoonClaw, MoonBook, and Moontown checks.
- `mooncode_protocol.mbt` owns daemon-local MoonCode wire constants such as
  runtime dispatch/turn kinds, package proof events, planner modes, canonical
  tool/test/control event names, and optional daemon endpoints. Required native
  endpoint/tool/contract values come from `mooncode/core` through local wrapper
  functions for compatibility with existing daemon call sites.
- `mooncode_capabilities.mbt` consumes that protocol-owned native capability
  surface through compatibility helpers, so `/v1/mooncode/capabilities`
  includes a canonical `capability_surface` object that Moondesk validates
  before enabling native MoonCode dispatch. The surface includes a SHA-256
  `capability_surface_fingerprint` over the required protocol, contract id,
  endpoints, and tools; the top-level endpoint, tool, contract, and fingerprint
  fields remain compatibility mirrors of that surface.
- `mooncode_request_helpers.mbt` owns route/query parameter parsing.
- `mooncode_persistence.mbt` owns command, event, and session sidecar writes.
- `mooncode_event_helpers.mbt` owns task-event normalization into
  `mooncode.v1` event records.
- `mooncode_json_helpers.mbt` owns small shared JSON field readers.
- `mooncode_tools.mbt` owns the generic native tool endpoint, shared tool
  result/event helpers, file read/write/edit tools, and patch application.
- `mooncode_process_tools.mbt` owns process-backed tools: `shell`,
  `moon_ide`, `moon_cmd`, and `moon_check` watcher state.
- `mooncode_runtime_turn.mbt` owns the native runtime-turn orchestration loop,
  command claiming, tool execution sequencing, package persistence handoff, and
  planner/tool/package/review/test/eval/commit boundary ordering.
- `mooncode_runtime_controls.mbt` owns serve-scheduler control decisions for
  idle `steer` / `cancel` commands and their settlement events.
- `mooncode_runtime_turn_receipts.mbt` owns native runtime-turn completion
  events and runtime-dispatch receipt projection.
- `mooncode_runtime_test_results.mbt` owns command-scoped test-result event
  projection from native `moon_check` tool output.
- `mooncode_runtime_model_planner.mbt` owns explicit/model tool-call planning,
  OpenAI tool schemas, model planner request/response decoding, bounded
  follow-up turns, and planner request/result contracts.
- `mooncode_runtime_planner_events.mbt` owns planner progress/failure event
  projection, reasoning/assistant deltas, and pre-execution tool-call events.
- `mooncode_runtime_prompt_fallback.mbt` owns deterministic command planning
  used when no explicit/model tool calls are available, including prompt-created
  MoonBook tools/miniapps and default `run_tests` / `run_eval` tool batches.
- `mooncode_runtime_reviews.mbt` owns accept/reject review receipt decisions,
  MoonBook review receipt JSON, and review-lane receipt event projection.
- `mooncode_runtime_packages.mbt` owns runtime-built package manifest/index
  creation, source promotion, package proof records, and MoonBook artifact
  paths produced by runtime-turn.
- Route-specific files such as `mooncode_serve_scheduler.mbt`,
  `mooncode_eval_report.mbt`, `mooncode_command_dispatch.mbt`,
  `mooncode_runtime_claims.mbt`, `mooncode_package_results.mbt`, and
  `mooncode_stream.mbt` own their endpoint projection and behavior.

### `GET /v1/events`

Streams server-sent events (SSE) related to all agent instances.

```plaintext
event: daemon.tasks.synchronized
data: { "tasks": [<task1>, <task2>, ...] }

event: daemon.task.changed
data: { "task": <task> }
```

### `GET /v1/models`

Returns a list of available models.

```json
{
  "models": [
    {
      "name": "anthropic/claude-sonnet-4"
    }
  ]
}
```

### `GET /v1/tasks`

Returns a list of all active agent instances.

```json
{
  "tasks": [
    {
      "name": "example-agent",
      "id": "some-unique-id",
      "cwd": "/path/to/working/directory",
      "port": 8080,
      "status": "idle",
      "created": 1625247600
    },
    {
      "name": "another-task",
      "id": "another-unique-id",
      "cwd": "/another/working/directory",
      "port": 8081,
      "status": "generating",
      "created": 1625247600
    }
  ]
}
```

### `POST /v1/task`

Creates to a task instance if the cwd is not yet associated with an existing
task. Attach to the existing task spawned on cwd otherwise.

- `name` is optional and purely informational. If not supplied, a empty string
  `""` will be used.

- `model` specifies the model to use for the task. It must be one of the models
  returned by `GET /v1/models`. If not specified, a default model will be used.

- `message` is the initial message to send to the task upon creation. This
  internally calls the `/v1/task/{id}/message` endpoint after the task is created
  or attached to.

- If `cwd` is supplied, a task is created (or attached to) in the specified
  working directory. If not supplied, a temporary directory is created for the
  task.

- `web_search` specifies whether to enable web search plugin for the task. If not
  supplied, defaults to `false`. Note that this option is persistent for the
  task and affects all subsequent requests to the agent.

Request:

```json
{
  "name": "example-task",
  "model": "anthropic/claude-sonnet-4",
  "cwd": "/path/to/working/directory",
  "message": {
    "role": "user",
    "content": "Write a JSON parser in MoonBit."
  },
  "web_search": true
}
```

Response:

- If the task is created successfully, returns HTTP 201 Created.

  ```json
  {
    "task": {
      "name": "example-task",
      "id": "some-unique-id",
      "cwd": "/path/to/working/directory",
      "port": 8080,
      "queued_messages": [],
      "web_search": true
    }
  }
  ```

- If there is already an existing task on the specified cwd, returns HTTP 409
  Conflict.

  ```json
  {
    "task": {
      "name": "example-task",
      "id": "some-unique-id",
      "cwd": "/path/to/working/directory",
      "port": 8080,
      "queued_messages": [],
      "web_search": true
    }
  }
  ```

If there are queued messages, the response would look like this:

```json
{
  "task": {
    "queued_messages": [
      {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "message": {
          "role": "user",
          "content": "Write a JSON parser in MoonBit."
        }
      }
    ]
  }
}
```

### `GET /v1/task/{id}`

Note that `"name"`/`"cwd"`/`"port"` can be `null` or unset.

Response:

```json
{
  "task": {
    "name": "example-task",
    "id": "some-unique-id",
    "cwd": "/path/to/working/directory",
    "port": 8080
  }
}
```

### `GET /v1/task/{id}/events`

Streams events related to the specified task instance.

### `POST /v1/task/{id}/message`

Sends a message to the specified task instance.

Request:

- `message`: The message to send to the moonclaw agent. It should be a JSON object
  with `role` as `"user"` and a non-empty `content` fields.
- `web_search` (optional): A boolean flag to enable web search for this message.
  Note that web search specified this way only affect request caused by this
  message, and does not change `web_search` state of the agent.

```json
{
  "message": {
    "role": "user",
    "content": "Write a JSON parser in MoonBit."
  }
}
```

### `POST /v1/task/{id}/cancel`

Cancels the current generation of the specified task instance.

If there is no ongoing task, i.e. current status is `"idle"`, returns 404 Not
Found:

```json
{
  "error": {
    "code": -1,
    "message": "No ongoing task to cancel."
  }
}
```

### `GET /v1/mooncode/sessions`

Lists MoonCode sessions for a selected MoonBook root. Pass
`book_root=<path>` to replay the durable book-local sidecar under
`.moonclaw/mooncode/sessions/`. The default response returns full
`mooncode-session-record` entries for diagnostics and recovery.

Query parameters:

- `book_root`: optional, but required to include durable sidecar sessions after
  daemon restart.
- `format`: omit for full diagnostic records, use `json` for the
  OpenSeek-compatible minimal session-list array, or use `listing` for the
  richer MoonClaw diagnostic envelope suited to older Moondesk session lists.
  Other values return `400 Bad Request` instead of silently changing response
  shape.

`format=json` returns a raw array of `{id, title, updated_at_ms}` rows matching
OpenSeek's `--session-list --format=json` contract: `title` is only the
untruncated first line of the first stored user prompt, and remains empty when
that prompt is unavailable. `format=listing` preserves the same session ids and
stream URLs while projecting stable desktop fields such as `id`, `title`,
`updated_at_ms`, `workspace_root`, `status`, `model`, `last_message`,
command/event counts, `session_url`, and `stream_url`. The richer listing title
prefers the first stored user prompt; older sidecars that lack that field fall
back to the latest message, latest command id, then session id.
`updated_at_ms` is factual: live memory rows use their `last_updated` timestamp,
while durable sidecar rows use the newest mtime across `events.jsonl`,
`commands.jsonl`, `package-results.jsonl`, `runtime-dispatches.jsonl`, and
`session.json`.
Rows are sorted newest first by `updated_at_ms`; rows without a timestamp sort
last.

The endpoint and projection helpers live in `mooncode_session_listing.mbt`.
Live session/task binding and cold record resolution live in
`mooncode_session_binding.mbt`; durable sidecar paths and JSONL persistence live
in `mooncode_session_store.mbt`. The OpenSeek-compatible row contract is
covered by `mooncode_session_listing_wbtest.mbt`.

### `GET /v1/mooncode/sessions/{id}/serve-scheduler`

Returns the native OpenSeek-style serve scheduler projection for a selected
MoonBook session. Pass `book_root=<path>` to load the book-local sidecar. The
endpoint is read-only and does not spawn, claim, or dispatch work.

The response is built from `commands.jsonl` plus `runtime-dispatches.jsonl` and
reports one active turn, pending turn ids, lifecycle rows, and per-command
effects such as `start-turn`, `queue-turn`, `deliver-steer`, `queue-steer`,
`cancel-active`, `withdraw-pending`, `drop-steer`, and `drop-cancel`. This
mirrors OpenSeek serve-mode ordering while keeping MoonClaw responsible for the
runtime interpretation of durable MoonCode command logs.
The implementation lives in `mooncode_serve_scheduler.mbt`, with focused
white-box coverage in `mooncode_serve_scheduler_wbtest.mbt`, so scheduler
semantics stay separate from command ingestion and tool execution.

### `GET/POST /v1/mooncode/sessions/{id}/runtime-claim`

Projects and mutates the durable MoonCode command queue for a selected
MoonBook session. The claim state is built from book-local `commands.jsonl`
and `runtime-dispatches.jsonl`; it classifies commands as claimable, claimed,
delivered, invalid, or order-blocked. `POST` appends a
`runtime-claimed` receipt for the next unresolved command without executing it.

### `POST /v1/mooncode/sessions/{id}/runtime-dispatch`

Claims the next command when needed, forwards a claimed command through the
MoonClaw runtime boundary, and appends a terminal runtime-dispatch receipt such
as `runtime-delivered`, `runtime-failed`, or `runtime-cancelled`.

Runtime claim-state projection, claim receipt creation, dispatch receipt
creation, and the HTTP wrappers live in `mooncode_runtime_claims.mbt`, with
focused coverage in `mooncode_runtime_claims_wbtest.mbt`. This keeps queue
ownership separate from serve-scheduler projection, command ingestion, and
native runtime-turn tool execution.

### `GET /v1/mooncode/sessions/{id}/stream`

Replays the durable MoonCode event log for a selected MoonBook session. The
event source is book-local:
`.moonclaw/mooncode/sessions/{safe-session-id}/events.jsonl`.

Query parameters:

- `book_root`: required unless the daemon has a live binding for the session.
- `format`: `jsonl` by default, or `sse` for server-sent event envelopes.
- `since`: last seen 1-based sequence number. The response includes events with
  a higher sequence and returns `next_since` for resumable polling.

JSONL responses contain `meta`, `event`, and `done` records. SSE responses use
the same payloads as `event: meta`, `event: event`, and `event: done` chunks.
The transport and live task-event sync live in `mooncode_stream.mbt`, with
event projection and resumable replay coverage in `mooncode_stream_wbtest.mbt`.

### `GET /v1/mooncode/sessions/{id}/runtime-events`

Returns the native MoonCode runtime-event state for a selected MoonBook
session. Pass `book_root=<path>` to load the book-local sidecar after daemon
restart. Durable runtime events still live in
`.moonclaw/mooncode/sessions/{safe-session-id}/events.jsonl`.

The response also projects the native `moon_check` watcher sidecar at
`.moonclaw/mooncode/watchers/moon-check.json` into a synthetic
`runtime_update` event when the watcher belongs to the selected book. That
event carries `[moon_check update]` content, test-lane status, command line,
sequence, exit status when stopped, restart metadata, and capped output. The
`event_count` field includes projected watcher evidence, while
`durable_event_count` reports only the persisted `events.jsonl` rows.

### `GET /v1/mooncode/sessions/{id}/eval-report`

Reports native MoonCode eval/readiness evidence for a session. Pass
`book_root=<path>` to load evidence from the selected MoonBook's durable
`.moonclaw/mooncode/sessions/{safe-session-id}/` sidecar after daemon restart;
without `book_root`, the report only reflects the daemon's live binding. The
report also runs MoonClaw's first deterministic native eval harness over
`read`, `write`, `edit`, `shell`, `moon_ide`, `moon_cmd`, `moon_check`,
`finish`, and file-edit diff evidence, returning `ok`, `required_harnesses`,
`passed_count`, `failed_count`, and nested native harness results for
Moondesk's Eval Report panel.
The endpoint and readiness projection live in `mooncode_eval_report.mbt`, with
focused coverage in `mooncode_eval_report_wbtest.mbt`; native harness
collection stays in `mooncode_eval.mbt`.

### `POST /v1/mooncode/sessions/{id}/commands`

Accepts a MoonCode command from Moondesk or a standalone `mooncode` client,
validates the shared `mooncode.v1` envelope, and turns it into one of three
dispatch outcomes:

- `native_dispatch_mode=queue-only`: append the command and a
  `command.queued_for_runtime_turn` event to the book-local sidecar for native
  `runtime-turn` consumption.
- `command=cancel`: request cooperative cancellation for the bound legacy task,
  or persist `cancel.no_active_task` evidence when no task is active.
- all other commands: forward a prompt/steer message to the bound MoonClaw task
  while persisting the command and runtime accept event.

The command boundary lives in `mooncode_command_dispatch.mbt`, with validation,
control classification, task forwarding, cancellation, queue-only persistence,
and command id/book-root helpers kept together. The focused behavior tests live
in `mooncode_command_dispatch_wbtest.mbt`. Runtime-turn execution and tool
application remain separate, so MoonClaw can support both browser-hosted
Moondesk and a future standalone `mooncode` client over the same command
contract.

### `POST /v1/mooncode/sessions/{id}/runtime-turn`

Claims the next durable MoonCode command for the selected `book_root` and runs a
bounded native turn. Explicit `runtime_tool_calls` are executed directly; prompt
fallbacks can create MoonBook-owned tools or miniapps under `tools/` or `apps/`.
Those deterministic fallbacks live in `mooncode_runtime_prompt_fallback.mbt`,
keeping generated artifact planning separate from runtime-turn orchestration.
The response includes `serve_scheduler_state` and `serve_scheduler_decision`,
and the runtime uses that decision before planning or executing tools.
Steer commands now settle with `steer_applied` / `steer_dropped` runtime
events and do not start artifact generation unless explicit tool calls were
provided.
Idle steer and cancel controls are closed as scheduler-owned
`steer_dropped` / `cancel_dropped` evidence with no tool execution, so
`runtime-loop` can advance the queue without misclassifying stale controls as
new work.
Control decision and settlement event projection live in
`mooncode_runtime_controls.mbt`; runtime-turn only asks whether the current
claimed command should execute or settle as an idle control.
Accept and reject commands now settle as deterministic review decisions:
MoonClaw writes `mooncode-review-receipt` JSON under
`wiki/reviews/mooncode/{safe-session-id}/`, emits review-lane
`receipt.accept` / `receipt.reject` events, and avoids model planning unless
the command explicitly provides tool calls.
Review receipt construction and event projection live in
`mooncode_runtime_reviews.mbt`; runtime-turn only sequences that boundary after
tool execution.
Commit commands now settle as deterministic git proof: MoonClaw checks and
stages only book-local content, excluding `.moonclaw`, `.moontown`, and
`moonclaw-jobs` runtime sidecars, runs `git commit` inside the selected
MoonBook root, verifies `HEAD`, and emits `runtime.commit_created` with the
commit SHA only after the git operation succeeds.
Run-eval commands now run the native OpenSeek-style tool/file-edit harnesses
from runtime-turn, write `wiki/reviews/mooncode/{safe-session-id}/eval-report.json`
inside the selected MoonBook, and emit `eval_report.manifest` evidence with
`tool_harness` and `file_edit` results so Moondesk can gate review/package work
on MoonClaw-owned eval proof.
Run-tests commands now turn native `moon_check` execution into a first-class
command-scoped `test_result` event that carries pass/fail status, exit status,
capped output, and the original command packet. This gives Moondesk a durable
test proof event without asking the desktop shell to infer test state from a
generic tool result.
Test-result projection lives in `mooncode_runtime_test_results.mbt`, while
runtime-dispatch completion receipts live in `mooncode_runtime_turn_receipts.mbt`.
The native `moon_ide` and `moon_cmd` tools provide MoonBit-specific execution
paths before the generic shell fallback. `moon_ide` runs read-only semantic
navigation actions (`doc`, `outline`, `peek_def`, `hover`, and
`find_references`) inside the selected MoonBook root and emits a
`moon_ide.finished` proof event. `moon_cmd` runs selected structured `moon`
commands (`check`, `test`, `run`, `info`, `fmt`, and `build`) with bounded
output, snapshot-update guard metadata, test-lane events, and
`moon_cmd.finished` proof. Runtime `run_tests` and `run_eval` deterministic
plans run `moon_cmd` before `moon_check`, so MoonBit validation has a typed
path rather than depending on arbitrary shell commands.
These process-backed tools live in `mooncode_process_tools.mbt`, with focused
coverage in `mooncode_process_tools_wbtest.mbt`, while the generic tool
endpoint and patch/file tools stay in `mooncode_tools.mbt`.

The native `moon_check` tool also records an OpenSeek-style watcher snapshot
under `.moonclaw/mooncode/watchers/moon-check.json`. MoonClaw keys the snapshot
by the selected MoonBook root, returns `watcher=started|reused|replaced|restarted`,
keeps a monotonic `seq`, exposes human watcher `status` separately from numeric
`exit_status`, and increments `restart_count` when changed options replace the
previous watcher record. This gives Moondesk and future standalone `mooncode`
the same no-duplicate-watcher contract before live background `moon check
--watch` streaming is introduced.
When a command carries an explicit selected model, MoonClaw can ask that model
for bounded OpenSeek-style tool-call batches over `read`, `write`, `edit`,
`apply_patch`, `revert_patch`, `shell`, `moon_ide`, `moon_cmd`, `moon_check`,
and `finish`. Successful
tool results are fed back to the model until it calls `finish`, a tool fails,
the command is cancelled, or
the bounded `planner_max_steps` limit is reached. Planner
start/selection/failure events, `planner_steps`, `planner_step_count`, and
`model_step_limit` are included in the runtime result. Each planner step also
emits MoonCode `reasoning_delta` progress, optional assistant transcript deltas,
and pre-execution `tool_call` events before the matching `tool_result`, so
clients can render live-style OpenSeek/Codex progress from the native event log.
The explicit/model planner contract lives in
`mooncode_runtime_model_planner.mbt`; runtime-turn calls that boundary and owns
only execution sequencing around the selected tool calls.
Planner progress/failure event projection lives in
`mooncode_runtime_planner_events.mbt`, keeping live transcript shaping out of
the model contract and out of the runtime orchestration loop.
Native `apply_patch` and `revert_patch` execute bounded reviewed text
replacements plus single-file or multi-file unified-diff patchsets inside the
selected MoonBook root, infer target paths from diff headers when needed, and
emit `runtime.patch_applied` / `runtime.patch_reverted` proof events. They
also accept `hunk_index`/`hunk_id` or hunk targets such as
`tools/demo/main.mbt#hunk-2`, apply only that selected hunk, and report
`hunk_dispatch_scope`, `selected_hunk_index`, `available_hunk_count`, and
`file_path` metadata. Patch tool packets can request post-change verification
with `verification_command`,
`test_command`, `verify_after`, or `moon_check_target`; MoonClaw records the
command, status, capped output, and pass/fail result under the patch proof
metadata.
Unsupported or empty model plans fall back to deterministic planning.
Deterministic fallback planning lives in `mooncode_runtime_prompt_fallback.mbt`;
runtime-turn uses it only to obtain bounded tool calls before execution.
When a generated artifact verifies successfully, MoonClaw writes
`portable/app-tool/mooncode/{safe-session-id}/package-{safe-command-id}.json`,
refreshes `portable/app-tool/mooncode/{safe-session-id}/index.json`, appends
`package_built` and `package_verified` records to `package-results.jsonl`, and
adds artifact-lane events for Moondesk's package review UI. The package
result sink is `POST /v1/mooncode/sessions/{id}/package-result?book_root={path}`;
MoonClaw uses the query `book_root`, then body `book_root`, then any live
session binding so package proof can persist after restart. The package
manifest also promotes generated source files into
`portable/app-tool/mooncode/{safe-session-id}/sources/{safe-command-id}/...`
and records source hashes, promoted paths, and promotion status so the package
candidate is reviewable from a MoonBook-owned artifact root.
Runtime-built package manifest/index creation, source promotion, and package
proof records live in `mooncode_runtime_packages.mbt`; the runtime-turn
orchestrator calls that package boundary after tool execution.
Package-result ingestion, validation, artifact-lane event projection, and
`package-results.jsonl` persistence live in `mooncode_package_results.mbt`,
with focused coverage in `mooncode_package_results_wbtest.mbt`; runtime-turn
only calls that persistence boundary when it has produced package proof.

### `POST /v1/mooncode/sessions/{id}/runtime-loop`

Runs a bounded MoonCode queue supervisor for the selected `book_root`. The loop
reuses the native `runtime-turn` primitive, so each command still records normal
claim receipts, runtime events, tool results, package proof, and terminal
`runtime-completed` or `runtime-failed` receipts. It stops when the queue is
idle, a turn fails, a cancel command is processed, or `max_turns` is reached.

### `POST /v1/task/{id}/publish`

Run `moon publish` in the task's working directory.

```json
{
  "process": {
    "status": 0,
    "stdout": "Published successfully.",
    "stderr": ""
  }
}
```

### `GET /v1/task/{id}/moonbit/modules`

Returns the list of MoonBit modules in the task's working directory.

Returns the list of MoonBit modules in the server's working directory.

Response:

```json
{
  "modules": [
    {
      "path": "/path/to/moonbit/module",
      "name": "example-module",
      "version": "1.0.0",
      "description": "An example module."
    }
  ]
}
```

### `POST /v1/moonbit/publish`

Runs `moon publish` in the task's working directory.

```json
{
  "module": {
    "path": "/path/to/moonbit/module"
  }
}
```

If successful, returns 201 Created:

```json
{
  "module": {
    "name": "example-module",
    "version": "1.0.0",
    "description": "An example module.",
  },
  "process": {
    "status": 0,
    "stdout": "Published successfully.",
    "stderr": ""
  }
}
```

If failed, returns 500 Internal Server Error:

```json
{
  "error": {
    "code": -1,
    "message": "Failed to publish the module.",
    "metadata": {
      "module": {
        "name": "example-module",
        "version": "1.0.0",
        "description": "An example module.",
      },
      "process": {
        "status": 1,
        "stdout": "",
        "stderr": "Error: Failed to publish."
      }
    }
  },
}
```

### `POST /v1/shutdown`

Shuts down the daemon server gracefully.
