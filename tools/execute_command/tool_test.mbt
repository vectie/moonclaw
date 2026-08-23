///|
async fn[T] with_fake_moonfort(
  mode : String,
  body : async (@execution_sandbox.SandboxExecutorConfig, String) -> T,
) -> T {
  @fsx.with_temporary_directory("moonclaw-fake-moonfort-XXXXXX", async fn(
    infrastructure,
  ) {
    let approval_root = @pathx.join(infrastructure, "approvals")
    let pending_root = @pathx.join(approval_root, "pending")
    let consumed_root = @pathx.join(approval_root, "consumed")
    let receipt_root = @pathx.join(infrastructure, "receipts")
    @fsx.make_directory(approval_root)
    @fsx.make_directory(pending_root)
    @fsx.make_directory(consumed_root)
    @fsx.make_directory(receipt_root)
    let capture_path = @pathx.join(infrastructure, "request.json")
    let executor_config_path = @pathx.join(infrastructure, "executor.json")
    @fsx.write_to_file(executor_config_path, "{}")
    let publisher_path = @pathx.join(infrastructure, "fake_publisher.py")
    let fake_publisher =
      #|import hashlib
      #|import json
      #|import pathlib
      #|import sys
      #|
      #|approval_root = pathlib.Path(sys.argv[1])
      #|mode = sys.argv[2]
      #|request = json.load(sys.stdin)
      #|grant = request["grant"]
      #|approval_id = grant["approval_id"]
      #|canonical = dict(grant)
      #|canonical["allowed_egress"] = sorted(canonical["allowed_egress"])
      #|canonical["allowed_commands"] = sorted(canonical["allowed_commands"])
      #|grant_bytes = json.dumps(
      #|    canonical, separators=(",", ":"), ensure_ascii=False
      #|).encode("utf-8")
      #|approval_digest = hashlib.sha256(grant_bytes).hexdigest()
      #|if mode == "publisher-mismatch":
      #|    print(json.dumps({
      #|        "protocol_version": 3,
      #|        "approval_id": "approval-wrong",
      #|        "approval_digest": "0" * 64,
      #|        "published": True,
      #|    }))
      #|    raise SystemExit(0)
      #|pending = approval_root / "pending" / (approval_id + ".json")
      #|pending.write_text(json.dumps(grant), encoding="utf-8")
      #|print(json.dumps({
      #|    "protocol_version": 3,
      #|    "approval_id": approval_id,
      #|    "approval_digest": approval_digest,
      #|    "published": True,
      #|}))
      #|
    @fsx.write_to_file(publisher_path, fake_publisher)
    let fake_path = @pathx.join(infrastructure, "fake_executor.py")
    let fake_executor =
      #|import hashlib
      #|import json
      #|import os
      #|import pathlib
      #|import sys
      #|
      #|capture_path = pathlib.Path(sys.argv[1])
      #|mode = sys.argv[2]
      #|approval_root = pathlib.Path(sys.argv[3])
      #|invocation = json.load(sys.stdin)
      #|approval_id = invocation["approval_id"]
      #|pending = approval_root / "pending" / (approval_id + ".json")
      #|consumed = approval_root / "consumed" / (approval_id + ".json")
      #|pending.rename(consumed)
      #|grant = json.loads(consumed.read_text(encoding="utf-8"))
      #|canonical = dict(grant)
      #|canonical["allowed_egress"] = sorted(canonical["allowed_egress"])
      #|canonical["allowed_commands"] = sorted(canonical["allowed_commands"])
      #|grant_bytes = json.dumps(
      #|    canonical, separators=(",", ":"), ensure_ascii=False
      #|).encode("utf-8")
      #|approval_digest = hashlib.sha256(grant_bytes).hexdigest()
      #|capture_path.write_text(json.dumps({
      #|    "invocation": invocation,
      #|    "grant": grant,
      #|    "executor_config_path": os.environ.get("MOONFORT_EXECUTOR_CONFIG"),
      #|}), encoding="utf-8")
      #|if mode == "protocol-error":
      #|    print(json.dumps({
      #|        "protocol_version": 3,
      #|        "approval_id": approval_id,
      #|        "error": {
      #|            "code": "fake-refused",
      #|            "message": "fake protocol failure",
      #|        },
      #|    }))
      #|    raise SystemExit(0)
      #|status = "Exited"
      #|enforcement = "Degraded"
      #|exit_code = 0
      #|output = "hello from MoonFort"
      #|truncated = False
      #|limit_reason = None
      #|denial_reason = None
      #|output_artifact = None
      #|unverified_limits = ["cpu"]
      #|changed_paths = ["generated.txt"]
      #|artifacts = ["generated.txt"]
      #|if mode == "timeout":
      #|    status = "Killed"
      #|    exit_code = None
      #|    output = "partial output"
      #|    truncated = True
      #|    limit_reason = "wall-clock-limit"
      #|    changed_paths = []
      #|    artifacts = []
      #|    output_artifact = {
      #|        "artifact_id": "f" * 32,
      #|        "run_id": grant["request_id"],
      #|        "sha256": "e" * 64,
      #|        "size_bytes": str(len(output.encode("utf-8"))),
      #|        "media_type": "text/plain; charset=utf-8",
      #|        "expires_at_ms": "4102444800000",
      #|        "key_id": "test-key",
      #|        "signature": "a" * 64,
      #|    }
      #|elif mode == "refused":
      #|    status = "Failed"
      #|    enforcement = "Refused"
      #|    exit_code = None
      #|    output = ""
      #|    denial_reason = "fake policy refusal"
      #|    changed_paths = []
      #|    artifacts = []
      #|    unverified_limits = []
      #|elif mode == "enforced":
      #|    enforcement = "Enforced"
      #|    unverified_limits = []
      #|receipt = {
      #|    "run_id": grant["request_id"],
      #|    "approval_id": approval_id,
      #|    "approval_digest": approval_digest,
      #|    "command_digest": "c" * 64,
      #|    "backend": grant["backend"],
      #|    "enforcement": enforcement,
      #|    "status": status,
      #|    "profile_digest": "d" * 64,
      #|    "output": output,
      #|    "output_truncated": truncated,
      #|    "unverified_limits": unverified_limits,
      #|    "changed_paths": changed_paths,
      #|    "changes": [],
      #|    "artifacts": artifacts,
      #|    "cleanup_verified": True,
      #|}
      #|if output_artifact is not None:
      #|    receipt["output_artifact"] = output_artifact
      #|if exit_code is not None:
      #|    receipt["exit_code"] = exit_code
      #|if limit_reason is not None:
      #|    receipt["limit_reason"] = limit_reason
      #|if denial_reason is not None:
      #|    receipt["denial_reason"] = denial_reason
      #|print(json.dumps({
      #|    "protocol_version": 3,
      #|    "approval_id": approval_id,
      #|    "receipt": receipt,
      #|}))
      #|
    @fsx.write_to_file(fake_path, fake_executor)
    let python = @fsx.resolve("/usr/bin/python3")
    let config = {
      ..@execution_sandbox.local_sandbox_executor_config(
        python,
        python,
        @fsx.resolve(executor_config_path),
        @fsx.resolve(receipt_root),
        "book",
        allow_degraded=true,
      ),
      executor_args: [
        fake_path,
        capture_path,
        mode,
        @fsx.resolve(approval_root),
      ],
      grant_publisher_args: [publisher_path, @fsx.resolve(approval_root), mode],
    }
    body(config, capture_path)
  })
}

///|
async test "missing sandbox configuration refuses without host fallback" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(mock.cwd.path(), home=mock.cwd.path())
    let result = tool.call({ "command": "printf unsafe > out.txt" })
    assert_true(
      result
      .to_string()
      .contains("MoonFort execution sandbox is not configured"),
    )
    inspect(
      @fsx.exists(@pathx.join(mock.cwd.path(), "out.txt")),
      content="false",
    )
  })
}

///|
async test "MoonFort v3 invocation is opaque and grant-bound receipt is persisted" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    with_fake_moonfort("exited", async fn(config, capture) {
      let nested = @pathx.join(mock.cwd.path(), "packages/app")
      @fsx.make_directory(@pathx.join(mock.cwd.path(), "packages"))
      @fsx.make_directory(nested)
      let tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let result = tool.call({
        "command": "printf hello",
        "working_directory": "packages/app",
        "timeout": 5_000,
      })
      guard result is Ok(Completed(status~, receipt~, audit_id~, ..)) else {
        fail("expected sandboxed completion, got \{result}")
      }
      inspect(status, content="0")
      inspect(receipt.enforcement is Degraded, content="true")
      json_inspect(receipt.changed_paths, content=["generated.txt"])
      assert_eq(audit_id, receipt.run_id)
      let audit_path = @pathx.join(config.receipt_root, "\{audit_id}.json")
      inspect(@fsx.exists(audit_path), content="true")
      let request = @json.parse(@fsx.read_file(capture))
      guard request
        is {
          "invocation": {
            "protocol_version": Number(3, ..),
            "approval_id": String(approval_id),
            ..
          },
          "grant": {
            "protocol_version": Number(3, ..),
            "approval_id": String(grant_approval_id),
            "request_id": String(run_id),
            "workspace_id": String("book"),
            "allowed_commands": Array(allowed),
            "working_directory": String("packages/app"),
            "command": Array(command),
            ..
          },
          "executor_config_path": String(executor_config_path),
          ..
        } else {
        fail("unexpected MoonFort request: \{Repr(request)}")
      }
      assert_eq(approval_id, grant_approval_id)
      assert_eq(approval_id, receipt.approval_id)
      assert_eq(run_id, receipt.run_id)
      assert_eq(executor_config_path, config.executor_config_path)
      assert_true(allowed.any(item => item is String("shell-compat")))
      assert_true(command.length() == 2)
      assert_false(command.to_json().stringify().contains("cd --"))
      let audit = @json.parse(@fsx.read_file(audit_path))
      assert_true(audit.stringify().contains(receipt.approval_digest))
      inspect(
        @fsx.exists(@pathx.join(mock.cwd.path(), "generated.txt")),
        content="false",
      )
    })
  })
}

///|
async test "MoonFort refusal is terminal and never retries through a shell" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    with_fake_moonfort("refused", async fn(config, _capture) {
      let tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let result = tool.call({ "command": "printf hello" })
      assert_true(result.to_string().contains("fake policy refusal"))
      inspect(
        @fsx.exists(@pathx.join(mock.cwd.path(), "generated.txt")),
        content="false",
      )
    })
  })
}

///|
async test "grant publisher identity mismatch fails closed before executor" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    with_fake_moonfort("publisher-mismatch", async fn(config, capture) {
      let tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let result = tool.call({ "command": "printf hello" })
      assert_true(
        result.to_string().contains("publisher refused or mismatched"),
      )
      inspect(@fsx.exists(capture), content="false")
    })
  })
}

///|
async test "high-risk approval persists and consumes the exact execution plan" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    with_fake_moonfort("exited", async fn(config, capture) {
      let first_tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let first = first_tool.call({ "command": "printf hello > out.txt" })
      guard first is Ok(ApprovalRequired(token~, ..)) else {
        fail("expected approval request, got \{first}")
      }
      let security = @security.SecurityRuntime::new(
        home=mock.cwd.path(),
        cwd=mock.cwd.path(),
      )
      let pending = security.list_pending_approvals("local:\{mock.cwd.path()}")
      guard pending is [record] && record.context is Some(context) else {
        fail("expected one profile-bound approval")
      }
      let approved_digest = match context {
        { "expected_approval_digest": String(value), .. } => value
        _ => fail("approval context omitted grant digest")
      }
      ignore(security.approve_token(token, 11))
      // Recreate the tool to prove the approved plan survives the in-memory
      // caller and is recovered atomically from the security journal.
      let resumed_tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let resumed = resumed_tool.call({ "command": "printf hello > out.txt" })
      guard resumed is Ok(Completed(receipt~, ..)) else {
        fail("expected approved sandbox execution, got \{resumed}")
      }
      assert_eq(receipt.approval_digest, approved_digest)
      let request = @json.parse(@fsx.read_file(capture))
      guard request
        is {
          "invocation": { "approval_id": String(invoked_approval), .. },
          "grant": { "approval_id": String(grant_approval), .. },
          ..
        } else {
        fail("captured request omitted approval identity")
      }
      assert_eq(invoked_approval, grant_approval)
      assert_eq(receipt.approval_id, grant_approval)
      inspect(
        @fsx.exists(@pathx.join(mock.cwd.path(), "out.txt")),
        content="false",
      )
    })
  })
}

///|
async test "operator configuration change invalidates a pending approval" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    with_fake_moonfort("exited", async fn(config, capture) {
      let first_tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let first = first_tool.call({ "command": "printf hello > out.txt" })
      guard first is Ok(ApprovalRequired(token~, ..)) else {
        fail("expected approval request, got \{first}")
      }
      let security = @security.SecurityRuntime::new(
        home=mock.cwd.path(),
        cwd=mock.cwd.path(),
      )
      ignore(security.approve_token(token, 11))
      let changed_config = { ..config, workspace_id: "changed" }
      let changed_tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=changed_config,
      )
      let result = changed_tool.call({ "command": "printf hello > out.txt" })
      assert_true(
        result
        .to_string()
        .contains("operator configuration changed after approval"),
      )
      inspect(@fsx.exists(capture), content="false")
    })
  })
}

///|
async test "wall-clock kill maps to timeout with a durable receipt" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    with_fake_moonfort("timeout", async fn(config, _capture) {
      let tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=config,
      )
      let result = tool.call({ "command": "sleep 5", "timeout": 1_000 })
      guard result is Ok(TimedOut(timeout~, receipt~, audit_id~, ..)) else {
        fail("expected sandbox timeout, got \{result}")
      }
      inspect(timeout, content="1000")
      debug_inspect(receipt.limit_reason, content="Some(\"wall-clock-limit\")")
      assert_eq(audit_id, receipt.run_id)
      inspect(
        @fsx.exists(@pathx.join(config.receipt_root, "\{audit_id}.json")),
        content="true",
      )
    })
  })
}

///|
async test "strict callers reject a degraded local receipt" (t : @test.Test) {
  @mock.run(t, mock => {
    with_fake_moonfort("exited", async fn(config, _capture) {
      let strict = { ..config, enforcement_requirement: RequireEnforced }
      let tool = @execute_command.new(
        mock.cwd.path(),
        home=mock.cwd.path(),
        sandbox_config=strict,
      )
      let result = tool.call({ "command": "printf hello" })
      assert_true(
        result
        .to_string()
        .contains("did not provide the required enforced boundary"),
      )
    })
  })
}
