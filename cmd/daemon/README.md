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

### `GET /v1/mooncode/sessions/{id}/eval-report`

Reports native MoonCode eval/readiness evidence for a session. Pass
`book_root=<path>` to load evidence from the selected MoonBook's durable
`.moonclaw/mooncode/sessions/{safe-session-id}/` sidecar after daemon restart;
without `book_root`, the report only reflects the daemon's live binding. The
report also runs MoonClaw's first deterministic native eval harness over
`read`, `write`, `edit`, `shell`, `moon_check`, `finish`, and file-edit diff
evidence, returning `ok`, `required_harnesses`, `passed_count`,
`failed_count`, and nested native harness results for Moondesk's Eval Report
panel.

### `POST /v1/mooncode/sessions/{id}/runtime-turn`

Claims the next durable MoonCode command for the selected `book_root` and runs a
bounded native turn. Explicit `runtime_tool_calls` are executed directly; prompt
fallbacks can create MoonBook-owned tools or miniapps under `tools/` or `apps/`.
When a command carries an explicit selected model, MoonClaw can ask that model
for bounded OpenSeek-style tool-call batches over `read`, `write`, `edit`,
`apply_patch`, `revert_patch`, `shell`, `moon_check`, and `finish`. Successful
tool results are fed back to the model until it calls `finish`, a tool fails,
the command is cancelled, or
the bounded `planner_max_steps` limit is reached. Planner
start/selection/failure events, `planner_steps`, `planner_step_count`, and
`model_step_limit` are included in the runtime result. Each planner step also
emits MoonCode `reasoning_delta` progress, optional assistant transcript deltas,
and pre-execution `tool_call` events before the matching `tool_result`, so
clients can render live-style OpenSeek/Codex progress from the native event log.
Native `apply_patch` and `revert_patch` execute bounded reviewed text
replacements inside the selected MoonBook root and emit
`runtime.patch_applied` / `runtime.patch_reverted` proof events.
Unsupported or empty model plans fall back to deterministic planning.
When a generated artifact verifies successfully, MoonClaw writes
`portable/app-tool/mooncode/{safe-session-id}/package-{safe-command-id}.json`,
refreshes `portable/app-tool/mooncode/{safe-session-id}/index.json`, appends
`package_built` and `package_verified` records to `package-results.jsonl`, and
adds artifact-lane events for Moondesk's package review UI.

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
