///|
/// Install a fixture-bound MoonFort deployment for legacy daemon tests. The
/// fake publisher and executor still exercise the complete grant/receipt
/// protocol; the executor is fixed to one temporary MoonBook and reports the
/// local-kernel boundary as degraded instead of pretending it is enforced.
async fn[T] mooncode_with_fixture_moonfort(
  book_root : String,
  body : async (@execution_sandbox.SandboxExecutorConfig) -> T,
) -> T {
  @fsx.with_temporary_directory("mooncode-fixture-moonfort-XXXXXX", async fn(
    infrastructure,
  ) {
    let pending = @pathx.join(infrastructure, "pending")
    let consumed = @pathx.join(infrastructure, "consumed")
    let receipts = @pathx.join(infrastructure, "receipts")
    @fsx.make_directory(pending)
    @fsx.make_directory(consumed)
    @fsx.make_directory(receipts)
    let executor_config = @pathx.join(infrastructure, "executor.json")
    @fsx.write_to_file(executor_config, "{}")
    let bridge = @pathx.join(infrastructure, "fixture_moonfort.py")
    @fsx.write_to_file(
      bridge,
      (
        #|import hashlib
        #|import json
        #|import os
        #|import pathlib
        #|import subprocess
        #|import sys
        #|
        #|mode = sys.argv[1]
        #|pending = pathlib.Path(sys.argv[2])
        #|consumed = pathlib.Path(sys.argv[3])
        #|workspace = pathlib.Path(sys.argv[4]).resolve()
        #|moon_path = sys.argv[5]
        #|fixture_path = sys.argv[6]
        #|request = json.load(sys.stdin)
        #|
        #|def canonical_digest(grant):
        #|    canonical = dict(grant)
        #|    canonical["allowed_egress"] = sorted(canonical["allowed_egress"])
        #|    canonical["allowed_commands"] = sorted(canonical["allowed_commands"])
        #|    encoded = json.dumps(canonical, separators=(",", ":"), ensure_ascii=False).encode()
        #|    return hashlib.sha256(encoded).hexdigest()
        #|
        #|if mode == "publish":
        #|    grant = request["grant"]
        #|    digest = canonical_digest(grant)
        #|    target = pending / (grant["approval_id"] + ".json")
        #|    spent = consumed / (grant["approval_id"] + ".json")
        #|    if target.exists() or spent.exists():
        #|        print(json.dumps({
        #|            "protocol_version": 3,
        #|            "approval_id": grant["approval_id"],
        #|            "approval_digest": digest,
        #|            "published": False,
        #|            "error": {"code": "replay", "message": "spent grant"},
        #|        }))
        #|        raise SystemExit(0)
        #|    target.write_text(json.dumps(grant))
        #|    print(json.dumps({
        #|        "protocol_version": 3,
        #|        "approval_id": grant["approval_id"],
        #|        "approval_digest": digest,
        #|        "published": True,
        #|    }))
        #|    raise SystemExit(0)
        #|
        #|approval_id = request["approval_id"]
        #|grant_path = pending / (approval_id + ".json")
        #|spent_path = consumed / (approval_id + ".json")
        #|grant_path.rename(spent_path)
        #|grant = json.loads(spent_path.read_text())
        #|if grant["workspace_id"] != "fixture-book":
        #|    raise RuntimeError("fixture workspace binding mismatch")
        #|cwd = (workspace / grant["working_directory"]).resolve()
        #|if cwd != workspace and workspace not in cwd.parents:
        #|    raise RuntimeError("fixture working directory escaped MoonBook")
        #|command = grant["command"]
        #|if isinstance(command, list):
        #|    tag = command[0]
        #|    payload = command[1] if len(command) > 1 else {}
        #|else:
        #|    tag = command.get("$tag", command.get("tag", ""))
        #|    payload = command
        #|if tag == "Shell":
        #|    if grant["allowed_commands"] != ["shell-compat"]:
        #|        raise RuntimeError("fixture shell capability mismatch")
        #|    script = payload["script"] if isinstance(payload, dict) else payload
        #|    argv = ["/bin/zsh", "-lc", script]
        #|elif tag == "Exec":
        #|    tool = payload["tool"]
        #|    if tool != "moon" or grant["allowed_commands"] != ["moon"]:
        #|        raise RuntimeError("fixture executable capability mismatch")
        #|    argv = [moon_path] + payload["args"]
        #|else:
        #|    raise RuntimeError("fixture command encoding is unsupported")
        #|environment = dict(os.environ)
        #|environment.update({
        #|    "GIT_AUTHOR_NAME": "MoonCode Fixture",
        #|    "GIT_AUTHOR_EMAIL": "mooncode-fixture@example.invalid",
        #|    "GIT_COMMITTER_NAME": "MoonCode Fixture",
        #|    "GIT_COMMITTER_EMAIL": "mooncode-fixture@example.invalid",
        #|})
        #|environment["PATH"] = fixture_path
        #|completed = subprocess.run(
        #|    argv,
        #|    cwd=cwd,
        #|    env=environment,
        #|    stdout=subprocess.PIPE,
        #|    stderr=subprocess.STDOUT,
        #|    text=True,
        #|    timeout=max(1.0, grant["limits"]["wall_clock_ms"] / 1000.0),
        #|)
        #|output_bytes = completed.stdout.encode()
        #|limit = grant["limits"]["output_bytes"]
        #|truncated = len(output_bytes) > limit
        #|if truncated:
        #|    output_bytes = output_bytes[:limit]
        #|output = output_bytes.decode(errors="replace")
        #|digest = canonical_digest(grant)
        #|print(json.dumps({
        #|    "protocol_version": 3,
        #|    "approval_id": approval_id,
        #|    "receipt": {
        #|        "run_id": grant["request_id"],
        #|        "approval_id": approval_id,
        #|        "approval_digest": digest,
        #|        "command_digest": hashlib.sha256(json.dumps(command, sort_keys=True).encode()).hexdigest(),
        #|        "backend": grant["backend"],
        #|        "enforcement": "Degraded",
        #|        "status": "Exited",
        #|        "profile_digest": hashlib.sha256(b"mooncode-fixture-profile").hexdigest(),
        #|        "exit_code": completed.returncode,
        #|        "output": output,
        #|        "output_truncated": truncated,
        #|        "unverified_limits": ["shared-kernel"],
        #|        "changed_paths": [],
        #|        "changes": [],
        #|        "artifacts": [],
        #|        "cleanup_verified": True,
        #|    },
        #|}))
        #|
      ),
    )
    let python = @fsx.resolve("/usr/bin/python3")
    let moon = mooncode_fixture_moon_executable()
    let fixture_path = @os.getenv("PATH").unwrap_or("")
    let config = {
      ..@execution_sandbox.local_sandbox_executor_config(
        python,
        python,
        @fsx.resolve(executor_config),
        @fsx.resolve(receipts),
        "fixture-book",
        allow_degraded=true,
      ),
      allowed_commands: ["moon", "shell-compat"],
      grant_publisher_args: [
        bridge, "publish", pending, consumed, book_root, moon, fixture_path,
      ],
      executor_args: [
        bridge, "execute", pending, consumed, book_root, moon, fixture_path,
      ],
    }
    mooncode_install_fixture_sandbox_config(book_root, config)
    try body(config) catch {
      error => {
        mooncode_remove_fixture_sandbox_config(book_root)
        raise error
      }
    } noraise {
      value => {
        mooncode_remove_fixture_sandbox_config(book_root)
        value
      }
    }
  })
}

///|
async fn mooncode_fixture_moon_executable() -> String {
  let path = @os.getenv("PATH").unwrap_or("")
  for directory in path.split(":") {
    let candidate = @pathx.join(directory, "moon")
    if @fsx.exists(candidate) {
      return @fsx.resolve(candidate)
    }
  }
  let moon_home = @os.getenv("MOON_HOME").unwrap_or("")
  if moon_home != "" {
    let candidate = @pathx.join(moon_home, "bin/moon")
    if @fsx.exists(candidate) {
      return @fsx.resolve(candidate)
    }
  }
  fail("MoonFort fixture requires a Moon executable on PATH")
}

///|
async fn mooncode_fixture_authorized_tool_body(
  config : @execution_sandbox.SandboxExecutorConfig,
  book_root : String,
  body : Json,
) -> Json {
  if mooncode_json_string(body, "tool", default="") != "shell" {
    return body
  }
  let arguments = mooncode_json_object_field_or_empty(body, "arguments")
  if arguments is { "_execution_sandbox_plan": _, .. } {
    return body
  }
  guard arguments is Object(fields) else { return body }
  let cwd = mooncode_tool_cwd(book_root, arguments)
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  let command = mooncode_json_string(arguments, "cmd", default="")
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=30000)
  let plan = @execution_sandbox.make_sandbox_plan(
    config, book_root, cwd_path, command, timeout,
  )
  fields["_execution_sandbox_plan"] = plan.to_json()
  body
}

///|
#warnings("-unused_value")
async fn mooncode_fixture_execute_tool_call(
  config : @execution_sandbox.SandboxExecutorConfig,
  session_id : String,
  book_root : String,
  body : Json,
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_execute_tool_call(
    session_id,
    book_root,
    mooncode_fixture_authorized_tool_body(config, book_root, body),
    now~,
  )
}

///|
#warnings("-unused_value")
async fn mooncode_fixture_execute_guarded_tool_call(
  config : @execution_sandbox.SandboxExecutorConfig,
  session_id : String,
  book_root : String,
  body : Json,
  prior_results : Array[Json],
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_execute_guarded_tool_call(
    session_id,
    book_root,
    mooncode_fixture_authorized_tool_body(config, book_root, body),
    prior_results,
    now~,
  )
}

///|
#warnings("-unused_value")
async fn mooncode_fixture_authorized_runtime_command(
  config : @execution_sandbox.SandboxExecutorConfig,
  book_root : String,
  command : Json,
) -> Json {
  guard command is Object(fields) else { return command }
  let calls = mooncode_json_array_items(command, "runtime_tool_calls")
  if calls.length() == 0 {
    return command
  }
  let authorized : Array[Json] = []
  for call in calls {
    authorized.push(
      mooncode_fixture_authorized_tool_body(config, book_root, call),
    )
  }
  fields["runtime_tool_calls"] = authorized.to_json()
  command
}

///|
/// Record fixture-owned operator decisions for any runtime calls whose normal
/// contract requires approval. The decision binds the exact MoonFort plan
/// already installed by `mooncode_fixture_authorized_runtime_command`.
#warnings("-unused_value")
async fn mooncode_fixture_approve_runtime_commands(
  book_root : String,
  command : Json,
) -> Unit {
  let session_id = mooncode_json_string(command, "session_id", default="")
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let command_id = mooncode_json_string(packet, "command_id", default="")
  for
    index, tool_call in mooncode_json_array_items(command, "runtime_tool_calls") {
    if mooncode_runtime_tool_requires_approval(tool_call) {
      let event = mooncode_runtime_tool_approval_event(
        session_id,
        command_id,
        tool_call,
        occurrence=index,
        state="approved",
        tool_call_id=mooncode_runtime_turn_tool_call_id(
          tool_call,
          step=1,
          index~,
        ),
        control_command_id="fixture-approval-\{index}",
        now=@clock.Timestamp::from_ms(3L + index.to_int64()),
      )
      ignore(
        mooncode_append_session_journal(
          book_root,
          session_id,
          mooncode_journal_event(),
          event,
        ),
      )
    }
  }
}
