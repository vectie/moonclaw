///|
/// Install a protocol-complete, workspace-bound fake MoonFort deployment for
/// provider-task white-box tests. The fake accepts only provider target IDs as
/// typed executable capabilities and never evaluates shell text from a test.
async fn install_provider_task_fixture_moonfort(
  workspace_root : String,
) -> Unit {
  @fsx.with_temporary_directory("provider-task-moonfort-XXXXXX", async fn(
    infrastructure,
  ) {
    // The fixture infrastructure must outlive this callback. Moving it below
    // the test workspace gives the outer temporary-directory owner the same
    // lifetime and cleanup boundary.
    let durable = @pathx.join(
      workspace_root,
      ".provider-task-moonfort-\{@pathx.basename(infrastructure)}",
    )
    @fsx.make_directory(durable, recursive=true, exists_ok=true)
    let pending = @pathx.join(durable, "pending")
    let consumed = @pathx.join(durable, "consumed")
    let receipts = @pathx.join(durable, "receipts")
    @fsx.make_directory(pending, recursive=true, exists_ok=true)
    @fsx.make_directory(consumed, recursive=true, exists_ok=true)
    @fsx.make_directory(receipts, recursive=true, exists_ok=true)
    let executor_config = @pathx.join(durable, "executor.json")
    @fsx.write_to_file(executor_config, "{}")
    let bridge = @pathx.join(durable, "fixture_moonfort.py")
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
        #|if grant["workspace_id"] != "provider-task-fixture":
        #|    raise RuntimeError("fixture workspace registry mismatch")
        #|cwd = (workspace / grant["working_directory"]).resolve()
        #|if cwd != workspace and workspace not in cwd.parents:
        #|    raise RuntimeError("fixture working directory escaped workspace")
        #|command = grant["command"]
        #|if isinstance(command, list):
        #|    tag = command[0]
        #|    payload = command[1]
        #|else:
        #|    tag = command.get("$tag", command.get("tag", ""))
        #|    payload = command
        #|if tag != "Exec":
        #|    raise RuntimeError("fixture accepts only typed Exec grants")
        #|tool = payload["tool"]
        #|if tool not in ("wiki-main", "coding-main", "finance-main", "moonbook"):
        #|    raise RuntimeError("fixture provider capability is not registered")
        #|if grant["allowed_commands"] != [tool]:
        #|    raise RuntimeError("fixture provider capability mismatch")
        #|argv = ["/bin/sh"] + payload["args"]
        #|completed = subprocess.run(
        #|    argv,
        #|    cwd=cwd,
        #|    env=dict(os.environ),
        #|    stdout=subprocess.PIPE,
        #|    stderr=subprocess.STDOUT,
        #|    timeout=max(1.0, grant["limits"]["wall_clock_ms"] / 1000.0),
        #|)
        #|output = completed.stdout
        #|limit = grant["limits"]["output_bytes"]
        #|truncated = len(output) > limit
        #|if truncated:
        #|    output = output[:limit]
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
        #|        "profile_digest": hashlib.sha256(b"provider-task-fixture-profile").hexdigest(),
        #|        "exit_code": completed.returncode,
        #|        "output": output.decode(errors="replace"),
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
    let config = {
      ..@execution_sandbox.local_sandbox_executor_config(
        python,
        python,
        @fsx.resolve(executor_config),
        @fsx.resolve(receipts),
        "provider-task-fixture",
        allow_degraded=true,
      ),
      allowed_commands: ["wiki-main", "coding-main", "finance-main", "moonbook"],
      grant_publisher_args: [
        bridge, "publish", pending, consumed, workspace_root,
      ],
      executor_args: [bridge, "execute", pending, consumed, workspace_root],
    }
    install_provider_task_fixture_sandbox_config(workspace_root, config)
  })
}
