///|
/// Run a test body with a fixture-owned MoonFort protocol deployment. Each
/// capability is bound to one canonical executable before the grant is
/// created. The fake executor consumes grants exactly once and reports its
/// shared-kernel limitation as degraded; it is never a production fallback.
pub async fn[T] with_fixture_moonfort(
  workspace : String,
  capabilities : Map[String, String],
  body : async (@execution_sandbox.SandboxExecutorConfig) -> T,
) -> T {
  @fsx.with_temporary_directory("execution-sandbox-fixture-XXXXXX", async fn(
    infrastructure,
  ) {
    let canonical_workspace = @fsx.resolve(workspace)
    let pending = @pathx.join(infrastructure, "pending")
    let consumed = @pathx.join(infrastructure, "consumed")
    let receipts = @pathx.join(infrastructure, "receipts")
    @fsx.make_directory(pending)
    @fsx.make_directory(consumed)
    @fsx.make_directory(receipts)
    let executor_config = @pathx.join(infrastructure, "executor.json")
    @fsx.write_to_file(executor_config, "{}")
    let capability_file = @pathx.join(infrastructure, "capabilities.json")
    let capability_json : Map[String, Json] = Map([])
    for capability, executable in capabilities {
      guard !capability.is_blank() else {
        fail("fixture MoonFort capability must be non-empty")
      }
      let canonical_executable = @fsx.resolve(executable)
      guard @fsx.exists_as_file(canonical_executable) else {
        fail("fixture MoonFort executable must be a canonical regular file")
      }
      capability_json[capability] = canonical_executable.to_json()
    }
    @fsx.write_to_file(
      capability_file,
      Json::object(capability_json).stringify(),
    )
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
        #|capabilities = json.loads(pathlib.Path(sys.argv[5]).read_text())
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
        #|if grant["workspace_id"] != "fixture-workspace":
        #|    raise RuntimeError("fixture workspace binding mismatch")
        #|cwd = (workspace / grant["working_directory"]).resolve()
        #|if cwd != workspace and workspace not in cwd.parents:
        #|    raise RuntimeError("fixture working directory escaped workspace")
        #|command = grant["command"]
        #|if isinstance(command, list):
        #|    tag = command[0]
        #|    payload = command[1] if len(command) > 1 else {}
        #|else:
        #|    tag = command.get("$tag", command.get("tag", ""))
        #|    payload = command
        #|if tag != "Exec":
        #|    raise RuntimeError("fixture accepts typed Exec grants only")
        #|tool = payload["tool"]
        #|if grant["allowed_commands"] != [tool] or tool not in capabilities:
        #|    raise RuntimeError("fixture executable capability mismatch")
        #|executable = pathlib.Path(capabilities[tool]).resolve()
        #|if not executable.is_file():
        #|    raise RuntimeError("fixture capability executable is unavailable")
        #|argv = [str(executable)] + payload["args"]
        #|def workspace_snapshot():
        #|    snapshot = {}
        #|    for path in workspace.rglob("*"):
        #|        relative = path.relative_to(workspace)
        #|        if ".git" in relative.parts:
        #|            continue
        #|        if path.is_symlink():
        #|            snapshot[str(relative)] = "link:" + os.readlink(path)
        #|        elif path.is_file():
        #|            snapshot[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
        #|    return snapshot
        #|before = workspace_snapshot()
        #|environment = dict(os.environ)
        #|environment.update({
        #|    "GIT_AUTHOR_NAME": "MoonClaw Fixture",
        #|    "GIT_AUTHOR_EMAIL": "moonclaw-fixture@example.invalid",
        #|    "GIT_COMMITTER_NAME": "MoonClaw Fixture",
        #|    "GIT_COMMITTER_EMAIL": "moonclaw-fixture@example.invalid",
        #|})
        #|completed = subprocess.run(
        #|    argv,
        #|    cwd=cwd,
        #|    env=environment,
        #|    stdout=subprocess.PIPE,
        #|    stderr=subprocess.STDOUT,
        #|    text=True,
        #|    timeout=max(1.0, grant["limits"]["wall_clock_ms"] / 1000.0),
        #|)
        #|after = workspace_snapshot()
        #|changed_paths = sorted(
        #|    path for path in set(before) | set(after)
        #|    if before.get(path) != after.get(path)
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
        #|        "profile_digest": hashlib.sha256(b"fixture-profile").hexdigest(),
        #|        "exit_code": completed.returncode,
        #|        "output": output,
        #|        "output_truncated": truncated,
        #|        "unverified_limits": ["shared-kernel"],
        #|        "changed_paths": changed_paths,
        #|        "changes": [],
        #|        "artifacts": [],
        #|        "cleanup_verified": True,
        #|    },
        #|}))
        #|
      ),
    )
    let python = "/usr/bin/python3"
    guard @fsx.exists_as_file(python) else {
      fail("fixture MoonFort requires /usr/bin/python3")
    }
    let allowed_commands = capabilities.keys().to_array()
    allowed_commands.sort()
    let config = {
      ..@execution_sandbox.local_sandbox_executor_config(
        python,
        python,
        @fsx.resolve(executor_config),
        @fsx.resolve(receipts),
        "fixture-workspace",
        allow_degraded=true,
      ),
      allowed_commands,
      grant_publisher_args: [
        bridge, "publish", pending, consumed, canonical_workspace, capability_file,
      ],
      executor_args: [
        bridge, "execute", pending, consumed, canonical_workspace, capability_file,
      ],
    }
    body(config)
  })
}
