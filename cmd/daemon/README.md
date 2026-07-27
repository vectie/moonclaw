# Daemon Server

## Run

From the root directory of the repository, run:

```bash
moon run cmd/main -- daemon --port 8090 --serve cmd/daemon
```

It will first test if there is a running instance of the daemon server by
reading the `/path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/daemon.json` file. If there is no running instance, it
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

2. Read the port from the `/path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/daemon.json` file. Once the process
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
| `async fn detach(exec_path? : String, port? : Int, serve? : StringView) -> Int` | Spawns (or reuses) a detached daemon process, waits for it to write `/path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/daemon.json`, and returns the PID recorded in that file. |
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

Boundary note: the executable-book coding API is `/v1/code/*`; generic `/v1/task*` remains for background jobs. See [Executable Book Runtime Boundary](../../docs/executable_book_runtime_boundary.md).

- `mooncode/core` owns the MoonCode contract surface shared with
  MoonDesk: the `mooncode.v1` protocol marker, native capability contract id,
  required endpoint/tool lists, canonical required capability surface, and its
  SHA-256 surface fingerprint. It is currently mirrored per repo so both builds
  remain independent; the intended next step is replacing those mirrors with one
  physically shared MoonCode module. While mirrored, MoonDesk's
  `scripts/verify-mooncode-core-sync.sh` is the sync gate for this contract and
  compares the core source files plus normalized generated interfaces; MoonDesk's
  `scripts/validate-core-boundaries.sh` composes that gate with targeted
  MoonDesk, MoonClaw, MoonBook, and MoonTown checks.
- `mooncode_protocol.mbt` owns daemon-local MoonCode protocol constants such as
  runtime receipt/turn kinds, package proof events, planner modes, canonical
  tool/test/control event names, and optional daemon endpoints. Required native
  endpoint/tool/contract values come from `mooncode/core` through local wrapper
  functions for existing daemon call sites.
- `mooncode_capabilities.mbt` consumes that protocol-owned native capability
  surface through local wrapper helpers, so `/v1/code/capabilities`
  includes a canonical `capability_surface` object that MoonDesk validates
  before enabling native MoonCode runtime. The surface includes a SHA-256
  `capability_surface_fingerprint` over the required protocol, contract id,
  endpoints, and tools; the top-level endpoint, tool, contract, and fingerprint
  fields remain top-level mirrors of that surface.
- `mooncode_request_helpers.mbt` owns route/query parameter parsing.
- `mooncode_persistence.mbt` owns command, event, and session sidecar writes.
- `mooncode_stream.mbt` owns durable MoonCode event streaming and bounded
  long polling.
- `mooncode_json_helpers.mbt` owns small shared JSON field readers.
- `mooncode_tools.mbt` owns the generic native tool endpoint, shared tool
  result/event helpers, file read/write/edit tools, and patch application.
- `mooncode_process_tools.mbt` owns process-backed tools: `shell`,
  `moon_ide`, `moon_cmd`, and `moon_check` watcher state.
- `mooncode_runtime_turn.mbt` owns the native runtime-turn orchestration loop,
  command claiming, tool execution sequencing, package persistence handoff, and
  planner/tool/package/review/test/eval/commit boundary ordering.
- `mooncode_runtime_controls.mbt` owns runtime-control decisions for
  idle `steer` / `cancel` commands and their settlement events.
- `mooncode_runtime_turn_receipts.mbt` owns native runtime-turn completion
  events and queue settlement receipt projection.
- `mooncode_runtime_test_results.mbt` owns command-scoped test-result event
  projection from native `moon_check` tool output.
- `mooncode_runtime_model_planner.mbt` owns explicit/model tool-call planning,
  OpenAI tool schemas, model planner request/response decoding, bounded
  follow-up turns, and planner request/result contracts.
- `mooncode_runtime_horizon.mbt` owns compact task contracts, durable milestone
  checkpoints, evidence validation, and bounded follow-up context.
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
- Route-specific files such as `mooncode_runtime_control.mbt`,
  `mooncode_eval_report.mbt`, `mooncode_command_queue.mbt`,
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

### `GET /v1/code/sessions`

Lists MoonCode sessions for a selected MoonBook root. Pass
`book_root=<path>` to replay durable sidecars from the MoonClaw product home
derived from that book root:
`.moonsuite/products/moonclaw/mooncode/sessions/`. The default response returns
full `mooncode-session-record` entries for diagnostics and recovery.

Query parameters:

- `book_root`: optional, but required to include durable sidecar sessions after
  daemon restart.
- `format`: omit for full diagnostic records, use `json` for the
  minimal MoonCode session-list array, or use `listing` for the
  richer MoonClaw diagnostic envelope suited to older MoonDesk session lists.
  Other values return `400 Bad Request` instead of silently changing response
  shape.

`format=json` returns a raw array of `{id, title, updated_at_ms}` rows matching
the compact `format=json` session-list contract: `title` is only the
untruncated first line of the first stored user prompt, and remains empty when
that prompt is unavailable. `format=listing` preserves the same session ids and
stream URLs while projecting stable desktop fields such as `id`, `title`,
`updated_at_ms`, `workspace_root`, `status`, `model`, `last_message`,
command/event counts, `session_url`, and `stream_url`. The richer listing title
prefers the first stored user prompt; older sidecars that lack that field fall
back to the latest message, latest command id, then session id.
`updated_at_ms` is factual: live memory rows use their `last_updated` timestamp,
while durable sidecar rows use the newest mtime across authoritative
`journal.jsonl` and the replaceable `session.json` checkpoint.
Rows are sorted newest first by `updated_at_ms`; rows without a timestamp sort
last.

The endpoint and projection helpers live in `mooncode_session_listing.mbt`.
Live session/task binding and cold record resolution live in
`mooncode_session_binding.mbt`; durable sidecar paths and JSONL persistence live
in `mooncode_session_store.mbt`. The compact row contract is
covered by `mooncode_session_listing_wbtest.mbt`.

### `GET /v1/code/sessions/{id}/runtime-control`

Returns the native MoonCode runtime control projection for a selected
MoonBook session. Pass `book_root=<path>` to load the MoonClaw product-home
sidecar for that book. The endpoint is read-only and does not spawn, claim, or
execute work.

The response is projected from command and runtime-receipt records in the
single session journal and
reports one active turn, pending turn ids, lifecycle rows, and per-command
effects such as `start-turn`, `queue-turn`, `deliver-steer`, `queue-steer`,
`defer-steer`, `cancel-active`, `withdraw-pending`, and `drop-cancel`. Deferred
steering is persisted as runtime evidence and injected into the next turn. This
mirrors live coding-agent prompt/steer/cancel ordering while keeping MoonClaw
responsible for the runtime interpretation of durable MoonCode command logs.
During an active model-planned turn, runtime-turn reprojects the authoritative
control state at every planner boundary and immediately after each model
inference. A pending `deliver-steer` command receives one terminal
`moonclaw-native-runtime-live-steer` receipt, becomes an explicit user message,
and is recorded as one live `steer_applied` event. If the steer arrived while
the model was choosing tools, MoonClaw discards that not-yet-executed stale plan
and replans; this initial and follow-up stabilization is bounded to eight
replans and fails closed if steering never quiesces.
The implementation lives in `mooncode_runtime_control.mbt`, with focused
white-box coverage in `mooncode_runtime_control_wbtest.mbt`, so runtime-control
semantics stay separate from command ingestion and tool execution.

### `GET/POST /v1/code/sessions/{id}/runtime-claim`

Projects and mutates the durable MoonCode command queue for a selected
MoonBook session. The claim state is projected from book-local command and
runtime-receipt journal records; it classifies commands as claimable, claimed,
delivered, invalid, or order-blocked. `POST` appends a
`runtime-claimed` receipt for the next unresolved command without executing it.

Runtime claim-state projection, claim receipt creation, and the HTTP wrappers
live in `mooncode_runtime_claims.mbt`, with focused coverage in
`mooncode_runtime_claims_wbtest.mbt`. This keeps queue ownership separate from
runtime-control projection, command ingestion, and native runtime-turn tool
execution.

### `GET /v1/code/sessions/{id}/stream`

Replays the durable MoonCode event projection for a selected MoonBook session.
The source journal is in the MoonClaw product home derived from the selected book
root:
`.moonsuite/products/moonclaw/mooncode/sessions/{safe-session-id}/journal.jsonl`.

Query parameters:

- `book_root`: required unless the daemon has a MoonCode session for the id.
- `format`: `jsonl` by default, or `sse` for server-sent event envelopes.
- `since`: last seen 1-based sequence number. The response includes events with
  a higher sequence and returns `next_since` for resumable polling.
- `wait_ms`: optional bounded long-poll budget. The default `0` preserves
  immediate replay; positive values wait for a sequence newer than `since`.
- `poll_ms`: polling interval while `wait_ms` is active, clamped to a bounded
  runtime-safe range.

JSONL responses contain `meta`, `event`, and `done` records. SSE responses use
the same payloads as `event: meta`, `event: event`, and `event: done` chunks.
The meta and done records include wait metadata so MoonDesk can distinguish an
immediate replay from a live-tail wait that timed out with no new events.
The transport lives in `mooncode_stream.mbt`, with durable event projection and
resumable replay coverage in `mooncode_stream_wbtest.mbt`.

### `GET /v1/code/sessions/{id}/runtime-events`

Returns the native MoonCode runtime-event state for a selected MoonBook
session. Pass `book_root=<path>` to load the MoonClaw product-home sidecar
after daemon restart. Durable runtime events live in
`.moonsuite/products/moonclaw/mooncode/sessions/{safe-session-id}/journal.jsonl`
alongside the other totally ordered session records.

The response also projects the native `moon_check` watcher sidecar at
`.moonsuite/products/moonclaw/mooncode/watchers/moon-check.json` into a
synthetic `runtime_update` event when the watcher belongs to the selected book.
That event carries `[moon_check update]` content, test-lane status, command
line, sequence, exit status when stopped, restart metadata, and capped output.
The `event_count` field includes projected watcher evidence, while
`durable_event_count` reports only persisted event-kind journal records.

### `GET /v1/code/sessions/{id}/eval-report`

Reports native MoonCode eval/readiness evidence for a session. Pass
`book_root=<path>` to load evidence from the selected MoonBook's MoonClaw
product-home sidecar after daemon restart; without `book_root`, the report only
reflects the daemon's live binding. The
report also runs MoonClaw's first deterministic native eval harness over
`read`, `write`, `edit`, `shell`, `moon_ide`, `moon_cmd`, `moon_check`,
`finish`, and file-edit diff evidence, returning `ok`, `required_harnesses`,
`passed_count`, `failed_count`, and nested native harness results for
MoonDesk's Eval Report panel.
The endpoint and readiness projection live in `mooncode_eval_report.mbt`, with
focused coverage in `mooncode_eval_report_wbtest.mbt`; native harness
collection stays in `mooncode_eval.mbt`.

### `POST /v1/code/sessions/{id}/commands`

Accepts a MoonCode command from MoonDesk or a standalone `mooncode` client,
validates the shared `mooncode.v1` envelope, and appends the command plus a `command.queued_for_runtime_turn` event
to the book-local sidecar for native `runtime-turn` consumption. This endpoint
does not spawn or message a generic task.

The command queue boundary lives in `mooncode_command_queue.mbt`, with strict
packet validation, control classification, native queue persistence, and
command id/book-root helpers kept together. Top-level command envelope fields
come from `mooncode/core` so MoonDesk, MoonClaw, and a standalone `mooncode`
client validate the same contract. The focused behavior tests live in
`mooncode_command_queue_wbtest.mbt`.
Runtime-turn execution and tool application remain separate, so MoonClaw can
support both browser-hosted MoonDesk and a future standalone `mooncode` client
over the same command contract.

### `POST /v1/code/sessions/{id}/turns`

Atomically accepts one interactive MoonCode turn. MoonClaw validates and
durably appends the native command, starts the session's runtime service when
one is not already active, and returns the accepted command, runtime-service
state, and current canonical session record in one response.

This is the primary mutation endpoint for interactive clients such as
MoonDesk. Runtime execution is single-flight per session: a later accepted turn
reuses the active service instead of starting a competing queue consumer. The
durable command remains authoritative if the service exits before processing
it, so a subsequent runtime start can resume the queue without a second client
write.

Low-level clients may still use `/commands` plus the explicit runtime endpoints
for diagnostics and controlled orchestration. Interactive clients should not
reconstruct that transaction themselves.

### `POST /v1/code/sessions/{id}/runtime-turn`

Claims the next durable MoonCode command for the selected `book_root` and runs a
bounded native turn. Explicit `runtime_tool_calls` are executed directly; prompt
fallbacks can create MoonBook-owned tools or miniapps under `tools/` or `apps/`.
Those deterministic fallbacks live in `mooncode_runtime_prompt_fallback.mbt`,
keeping generated artifact planning separate from runtime-turn orchestration.
The response includes `runtime_control_state` and `runtime_control_decision`,
and the runtime uses that decision before planning or executing tools.
Steer commands now settle with `steer_applied`, `steer_deferred`, or
`steer_dropped` runtime events. Idle steer is persisted as deferred steering
context before planning and then injected into the next eligible MoonCode turn,
while delivered steer can run explicit or bounded model-planned tool batches
against the active MoonBook context.
Idle cancel controls are closed as runtime-control-owned `cancel_dropped` evidence
with no tool execution, so `runtime-loop` can advance the queue without
misclassifying stale controls as new work.
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
stages only book-local content, excluding the fresh internal `.moonsuite` and
`.tmp` lanes, runs `git commit` inside the selected MoonBook root, verifies
`HEAD`, and emits `runtime.commit_created` with the commit SHA only after the
git operation succeeds.
Run-eval commands now run the native MoonCode tool/file-edit harnesses
from runtime-turn, write `wiki/reviews/mooncode/{safe-session-id}/eval-report.json`
inside the selected MoonBook, and emit `eval_report.manifest` evidence with
`tool_harness` and `file_edit` results so MoonDesk can gate review/package work
on MoonClaw-owned eval proof.
Run-tests commands now turn native `moon_check` execution into a first-class
command-scoped `test_result` event that carries pass/fail status, exit status,
capped output, and the original command packet. This gives MoonDesk a durable
test proof event without asking the desktop shell to infer test state from a
generic tool result.
Test-result projection lives in `mooncode_runtime_test_results.mbt`, while
runtime-receipt completion receipts live in `mooncode_runtime_turn_receipts.mbt`.
The native `moon_ide` and `moon_cmd` tools provide MoonBit-specific execution
paths before the generic shell fallback. `moon_ide` runs read-only semantic
navigation actions (`doc`, `outline`, `peek_def`, `hover`, and
`find_references`) inside the selected MoonBook root and emits a
`moon_ide.finished` proof event. `moon_cmd` runs selected structured `moon`
commands (`check`, `test`, `run`, `info`, `fmt`, and `build`) with bounded
output, snapshot-update guard metadata, test-lane events, and
`moon_cmd.finished` proof. Runtime `run_tests`, `run_build`, and `run_eval`
deterministic plans run `moon_cmd` before `moon_check`; `run_build` defaults to
`moon build`, so MoonBit validation has a typed path rather than depending on
arbitrary shell commands.
These process-backed tools live in `mooncode_process_tools.mbt`, with focused
coverage in `mooncode_process_tools_wbtest.mbt`, while the generic tool
endpoint and patch/file tools stay in `mooncode_tools.mbt`.

The native `moon_check` tool also records a MoonCode watcher snapshot
under `.moonsuite/products/moonclaw/mooncode/watchers/moon-check.json`.
MoonClaw keys the snapshot by the selected MoonBook root, returns
`watcher=started|reused|replaced|restarted`, keeps a monotonic `seq`, exposes
human watcher `status` separately from numeric `exit_status`, and increments
`restart_count` when changed options replace the previous watcher record. This
gives MoonDesk and future standalone `mooncode` the same no-duplicate-watcher
contract before live background `moon check --watch` streaming is introduced.
When a command carries an explicit selected model, MoonClaw can ask that model
for bounded MoonCode tool-call batches over `checkpoint`, `read`, `write`,
`edit`, `apply_patch`, `revert_patch`, `shell`, `moon_ide`, `moon_cmd`,
`moon_check`, and `finish`. Coding turns carry a compact task contract and
evidence-backed milestone checkpoint instead of replaying their full prior
transcript. Successful tool results are fed back to the model until it calls
`finish`, a tool fails, the command is cancelled, or the bounded
`planner_max_steps` limit is reached. The last two opportunities are reserved
for completion: the penultimate message stops discovery and requests authored
repair plus typed verification, while the final batch must contain `finish` and
may contain only mutation recovery or structured check/test/build/info/fmt
tools plus the required all-done checkpoint. Runtime-turn validates that final
batch before execution and fails closed on exploratory, shell,
semantic-navigation, or finish-free plans. Planner
start/selection/failure events, `planner_steps`, `planner_step_count`, and
`model_step_limit` are included in the runtime result. Each planner step also
emits MoonCode `reasoning_delta` progress, optional assistant transcript deltas,
and pre-execution `tool_call` events before the matching `tool_result`, so
clients can render live live coding-agent progress from the native event log.
The explicit/model planner contract lives in
`mooncode_runtime_model_planner.mbt`; runtime-turn calls that boundary and owns
only execution sequencing around the selected tool calls.
Coding-intent prompt completion is evidence-gated for both model-planned and
explicit tool batches. The final result must be an accepted `finish`, an
accepted `write`, `edit`, `apply_patch`, or `revert_patch` must precede it, and
the accepted mutation sequence must leave at least one file in a different
content state when the turn finishes. Native mutation results record
before/after content fingerprints for single-file and multi-file changes, and
completion compares the first and final state of every touched path. A
speculative edit that is later fully reverted therefore cannot be reported as
completed implementation. A successful typed verification must also occur at
or after the final mutation and after every failed tool. `moon_check` and
`moon_cmd check|test|build` are typed verification. A patch may prove its own
mutation when its nested `metadata.verification.ok` is true. When the prompt
requests tests, only a successful `moon_cmd test` satisfies the gate. A later
read cannot recover a failed check or test. Explanation and other read-only
prompts still permit an accepted `finish` without inventing mutation work.

Runtime responses expose the structured `completion_verdict`; compact
projections preserve it; `runtime.turn_finished` includes the reason; and the
terminal receipt is `runtime-failed` when the gate rejects completion. This
gate is distinct from the replay proof policy for proof-sensitive command
actions: it protects ordinary coding prompts at native execution time.
Planner progress/failure event projection lives in
`mooncode_runtime_planner_events.mbt`, keeping live transcript shaping out of
the model contract and out of the runtime orchestration loop.
Native `apply_patch` and `revert_patch` execute bounded reviewed text
replacements plus single-file or multi-file unified-diff patchsets inside the
selected MoonBook root, infer target paths from diff headers when needed, and
emit `runtime.patch_applied` / `runtime.patch_reverted` proof events. They
also accept `hunk_index`/`hunk_id` or hunk targets such as
`tools/demo/main.mbt#hunk-2`, apply only that selected hunk, and report
`hunk_control_scope`, `selected_hunk_index`, `available_hunk_count`, and
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
`package_built` and `package_verified` records to the session journal, and
adds artifact-lane events for MoonDesk's package review UI. The package
result sink is `POST /v1/code/sessions/{id}/package-result?book_root={path}`;
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
journal persistence live in `mooncode_package_results.mbt`,
with focused coverage in `mooncode_package_results_wbtest.mbt`; runtime-turn
only calls that persistence boundary when it has produced package proof.

### `POST /v1/code/sessions/{id}/runtime-loop`

Runs a bounded MoonCode queue supervisor for the selected `book_root`. The loop
reuses the native `runtime-turn` primitive, so each command still records normal
claim receipts, runtime events, tool results, package proof, and terminal
`runtime-completed` or `runtime-failed` receipts. It stops when the queue is
idle, a turn fails, a cancel command is processed, or `max_turns` is reached.
By default it preserves immediate-idle behavior. Callers that need an
MoonCode live supervisor can pass `live_wait_ms` and `poll_ms` in the
JSON body; the loop then polls the authoritative session journal for newly
appended prompt, steer, or cancel commands before returning idle. The response
includes `live_wait_attempt_count`, `live_wait_elapsed_ms`, and per-iteration
`waits` records so MoonDesk can render whether the loop actually waited or
found work immediately.

### `POST /v1/code/sessions/{id}/runtime-service`

Starts the bounded runtime loop in the daemon task group instead of holding the
HTTP request open. The endpoint writes `runtime.service_started` immediately,
returns `202 Accepted`, then records `runtime.service_finished` or
`runtime.service_failed` in the selected book's session journal. It uses the
same durable queue, claim receipts, turn execution, and `max_turns` /
`live_wait_ms` / `poll_ms` limits as `runtime-loop`, with a default
`live_wait_ms` of 5000 ms for live steering.

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
