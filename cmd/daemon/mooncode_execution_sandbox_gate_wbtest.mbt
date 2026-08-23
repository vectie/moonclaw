///|
test "MoonCode route exists but missing deployment configuration fails closed" {
  assert_true(mooncode_execution_sandbox_route_available())
  for tool in ["shell", "moon_ide", "moon_cmd", "moon_check", "browser"] {
    let refusal = mooncode_execution_sandbox_refusal(tool)
    assert_false(mooncode_json_bool(refusal, "ok", default=true))
    assert_true(mooncode_json_bool(refusal, "is_error", default=false))
    let metadata = mooncode_json_object_field_or_empty(refusal, "metadata")
    assert_true(
      mooncode_json_bool(metadata, "execution_sandbox_required", default=false),
    )
    assert_false(
      mooncode_json_bool(metadata, "execution_sandbox_configured", default=true),
    )
    assert_eq(
      mooncode_json_string(metadata, "execution_sandbox_policy", default=""),
      "fail-closed",
    )
  }
}

///|
test "MoonCode patch verification fails closed without ExecutionSandbox" {
  let refusal = mooncode_patch_verification_sandbox_refusal()
  assert_false(mooncode_json_bool(refusal, "ok", default=true))
  assert_true(
    mooncode_json_bool(refusal, "execution_sandbox_required", default=false),
  )
  assert_false(
    mooncode_json_bool(refusal, "execution_sandbox_configured", default=true),
  )
}

///|
async fn[T] mooncode_with_fake_moonfort(
  body : async (@execution_sandbox.SandboxExecutorConfig, String) -> T,
) -> T {
  @fsx.with_temporary_directory("mooncode-fake-moonfort-XXXXXX", async fn(
    infrastructure,
  ) {
    let pending = @pathx.join(infrastructure, "pending")
    let consumed = @pathx.join(infrastructure, "consumed")
    let receipts = @pathx.join(infrastructure, "receipts")
    @fsx.make_directory(pending)
    @fsx.make_directory(consumed)
    @fsx.make_directory(receipts)
    let capture = @pathx.join(infrastructure, "capture.json")
    let executor_config = @pathx.join(infrastructure, "executor.json")
    @fsx.write_to_file(executor_config, "{}")
    let bridge = @pathx.join(infrastructure, "fake_moonfort.py")
    @fsx.write_to_file(
      bridge,
      (
        #|import hashlib
        #|import json
        #|import os
        #|import pathlib
        #|import sys
        #|
        #|mode = sys.argv[1]
        #|pending = pathlib.Path(sys.argv[2])
        #|capture = pathlib.Path(sys.argv[3])
        #|consumed = pathlib.Path(sys.argv[4])
        #|request = json.load(sys.stdin)
        #|if mode == "publish":
        #|    grant = request["grant"]
        #|    canonical = dict(grant)
        #|    canonical["allowed_egress"] = sorted(canonical["allowed_egress"])
        #|    canonical["allowed_commands"] = sorted(canonical["allowed_commands"])
        #|    encoded = json.dumps(canonical, separators=(",", ":"), ensure_ascii=False).encode()
        #|    digest = hashlib.sha256(encoded).hexdigest()
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
        #|else:
        #|    approval_id = request["approval_id"]
        #|    grant_path = pending / (approval_id + ".json")
        #|    spent_path = consumed / (approval_id + ".json")
        #|    grant_path.rename(spent_path)
        #|    grant = json.loads(spent_path.read_text())
        #|    canonical = dict(grant)
        #|    canonical["allowed_egress"] = sorted(canonical["allowed_egress"])
        #|    canonical["allowed_commands"] = sorted(canonical["allowed_commands"])
        #|    encoded = json.dumps(canonical, separators=(",", ":"), ensure_ascii=False).encode()
        #|    digest = hashlib.sha256(encoded).hexdigest()
        #|    capture.write_text(json.dumps({
        #|        "invocation": request,
        #|        "grant": grant,
        #|        "approval_digest": digest,
        #|        "executor_config": os.environ.get("MOONFORT_EXECUTOR_CONFIG"),
        #|    }))
        #|    print(json.dumps({
        #|        "protocol_version": 3,
        #|        "approval_id": approval_id,
        #|        "receipt": {
        #|            "run_id": grant["request_id"],
        #|            "approval_id": approval_id,
        #|            "approval_digest": digest,
        #|            "command_digest": "c" * 64,
        #|            "backend": grant["backend"],
        #|            "enforcement": "Enforced" if grant["enforcement_requirement"] == "RequireEnforced" else "Degraded",
        #|            "status": "Exited",
        #|            "profile_digest": "d" * 64,
        #|            "exit_code": 0,
        #|            "output": "configured MoonFort moon check passed",
        #|            "output_truncated": False,
        #|            "unverified_limits": [] if grant["enforcement_requirement"] == "RequireEnforced" else ["shared-kernel"],
        #|            "changed_paths": [],
        #|            "changes": [],
        #|            "artifacts": [],
        #|            "cleanup_verified": True,
        #|        },
        #|    }))
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
        "book",
        allow_degraded=true,
      ),
      allowed_commands: ["moon", "shell-compat"],
      grant_publisher_args: [bridge, "publish", pending, capture, consumed],
      executor_args: [bridge, "execute", pending, capture, consumed],
    }
    body(config, capture)
  })
}

///|
async test "MoonCode moon_check pairs missing-config refusal with configured grant success" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-moon-check-route-XXXXXX", async fn(
    book_root,
  ) {
    let refused = mooncode_tool_moon_check_with_config(book_root, {}, None)
    mooncode_assert_execution_sandbox_refusal(refused)
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let result = mooncode_tool_moon_check_with_config(
        book_root,
        { "target": "native", "timeout_ms": 5_000 },
        Some(config),
      )
      assert_true(mooncode_json_bool(result, "ok", default=false))
      assert_true(
        mooncode_json_string(result, "output", default="").contains(
          "configured MoonFort moon check passed",
        ),
      )
      let metadata = mooncode_json_object_field_or_empty(result, "metadata")
      assert_eq(
        mooncode_json_string(metadata, "execution_sandbox_policy", default=""),
        "grant-bound",
      )
      let capture = @json.parse(@fsx.read_file(capture_path))
      let digest = mooncode_json_string(capture, "approval_digest", default="")
      assert_eq(
        mooncode_json_string(metadata, "approval_plan_digest", default=""),
        digest,
      )
      assert_false(metadata.stringify().contains("audit_path"))
      let run_id = mooncode_json_string(metadata, "run_id", default="")
      assert_true(
        @fsx.exists(@pathx.join(config.receipt_root, "\{run_id}.json")),
      )
      let command = mooncode_json_array_items(
        mooncode_json_object_field_or_empty(capture, "grant"),
        "command",
      )
      assert_true(command.to_json().stringify().contains("moon"))
      assert_true(command.to_json().stringify().contains("check"))
      assert_false(@fsx.exists(@pathx.join(book_root, "host-fallback-marker")))
    })
  })
}

///|
async test "MoonCode typed moon_ide and moon_cmd grants preserve exact argv" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-typed-routes-XXXXXX", async fn(
    book_root,
  ) {
    @fsx.write_to_file(@pathx.join(book_root, "moon.mod"), "name = \"demo\"\n")
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let result = mooncode_tool_moon_ide(
        book_root,
        { "action": "doc", "query": "String", "timeout_ms": 5_000 },
        sandbox_config=config,
      )
      assert_true(mooncode_json_bool(result, "ok", default=false))
      let capture = @json.parse(@fsx.read_file(capture_path)).stringify()
      assert_true(capture.contains("Exec"))
      assert_true(capture.contains("moon"))
      assert_true(capture.contains("ide"))
      assert_true(capture.contains("String"))
    })
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let result = mooncode_tool_moon_cmd(
        book_root,
        { "command": "build", "target": "native", "timeout_ms": 5_000 },
        sandbox_config=config,
      )
      assert_true(mooncode_json_bool(result, "ok", default=false))
      let capture = @json.parse(@fsx.read_file(capture_path)).stringify()
      assert_true(capture.contains("Exec"))
      assert_true(capture.contains("build"))
      assert_true(capture.contains("native"))
    })
  })
}

///|
async test "MoonCode shell consumes exact approved grant once and exposes evidence" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-shell-route-XXXXXX", async fn(
    book_root,
  ) {
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let plan = @execution_sandbox.make_sandbox_plan(
        config, book_root, book_root, "printf exact", 5_000,
      )
      let result = mooncode_tool_shell_with_config(
        book_root,
        {
          "cmd": "printf exact",
          "timeout_ms": 5_000,
          "_execution_sandbox_plan": plan,
        },
        config,
      )
      assert_true(mooncode_json_bool(result, "ok", default=false))
      let evidence = mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(result, "metadata"),
        "sandbox_evidence",
      )
      assert_true(
        mooncode_json_bool(evidence, "cleanup_verified", default=false),
      )
      let profile_digest = mooncode_json_string(
        evidence,
        "profile_digest",
        default="",
      )
      assert_eq(profile_digest.length(), 64)
      assert_true(profile_digest.all(character => character == 'd'))
      let requested = mooncode_json_object_field_or_empty(
        evidence, "requested_policy",
      )
      assert_eq(mooncode_json_string(requested, "network", default=""), "Deny")
      let captured = @json.parse(@fsx.read_file(capture_path)).stringify()
      assert_true(captured.contains("Shell"))
      assert_true(captured.contains("printf exact"))
      let replay = mooncode_tool_shell_with_config(
        book_root,
        {
          "cmd": "printf exact",
          "timeout_ms": 5_000,
          "_execution_sandbox_plan": plan,
        },
        config,
      )
      assert_false(mooncode_json_bool(replay, "ok", default=true))
      assert_true(
        mooncode_json_string(replay, "message", default="").contains(
          "failed closed",
        ),
      )
    })
  })
}

///|
async test "MoonCode rejects shell command substitution before publication" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-shell-substitution-XXXXXX", async fn(
    book_root,
  ) {
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let plan = @execution_sandbox.make_sandbox_plan(
        config, book_root, book_root, "printf approved", 5_000,
      )
      let result = mooncode_tool_shell_with_config(
        book_root,
        {
          "cmd": "printf substituted",
          "timeout_ms": 5_000,
          "_execution_sandbox_plan": plan,
        },
        config,
      )
      assert_false(mooncode_json_bool(result, "ok", default=true))
      assert_true(
        mooncode_json_string(result, "message", default="").contains(
          "does not match",
        ),
      )
      assert_false(@fsx.exists(capture_path))
    })
  })
}

///|
async test "MoonCode rejects approved moon_cmd argv substitution" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-moon-cmd-substitution-XXXXXX", async fn(
    book_root,
  ) {
    @fsx.write_to_file(@pathx.join(book_root, "moon.mod"), "name = \"demo\"\n")
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let plan = @execution_sandbox.make_exec_plan(
        config,
        book_root,
        book_root,
        "moon",
        ["build", "--target", "native"],
        5_000,
      )
      let result = mooncode_tool_moon_cmd(
        book_root,
        {
          "command": "test",
          "target": "native",
          "timeout_ms": 5_000,
          "_execution_sandbox_plan": plan,
        },
        sandbox_config=config,
      )
      assert_false(mooncode_json_bool(result, "ok", default=true))
      assert_true(
        mooncode_json_string(result, "message", default="").contains(
          "does not match",
        ),
      )
      assert_false(@fsx.exists(capture_path))
    })
  })
}

///|
test "MoonCode approved shell event supplies the persisted plan only" {
  let call : Json = {
    "tool": "shell",
    "arguments": { "cmd": "printf original" },
  }
  let plan : Json = { "expected_approval_digest": "digest" }
  let authorized = mooncode_runtime_authorized_tool_call(call, {
    "state": "approved",
    "arguments": { "cmd": "printf original", "_execution_sandbox_plan": plan },
  })
  let arguments = mooncode_json_object_field_or_empty(authorized, "arguments")
  assert_eq(
    mooncode_json_string(arguments, "cmd", default=""),
    "printf original",
  )
  assert_true(arguments.stringify().contains("expected_approval_digest"))
}

///|
async test "MoonCode typed broker bounds argv before grant publication" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-argv-bound-XXXXXX", async fn(root) {
    mooncode_with_fake_moonfort(async fn(config, capture_path) {
      let args = [ for _ in 0..<257 => "arg" ]
      try
        @execution_sandbox.make_exec_plan(
          config, root, root, "moon", args, 5_000,
        )
      catch {
        error => assert_true("\{error}".contains("transport bound"))
      } noraise {
        _ => fail("expected oversized argv to be rejected")
      }
      assert_false(@fsx.exists(capture_path))
    })
  })
}

///|
async test "MoonCode process entry points refuse before host spawn" {
  let results = [
    mooncode_tool_shell("/", { "cmd": "true" }),
    mooncode_tool_shell_in_runtime(None, "/", { "cmd": "true" }),
    mooncode_tool_moon_ide("/", { "action": "outline", "path": "." }),
    mooncode_tool_moon_cmd("/", { "command": "check" }),
    mooncode_tool_moon_check("/", {}),
    mooncode_tool_browser("session", "/", { "action": "snapshot" }),
  ]
  for result in results {
    assert_false(mooncode_json_bool(result, "ok", default=true))
    assert_true(
      mooncode_json_string(result, "message", default="").contains(
        "ExecutionSandbox",
      ),
    )
  }
  let verification = mooncode_tool_run_patch_verification("/", {
    "verification_command": "true",
  })
  assert_false(mooncode_json_bool(verification, "ok", default=true))
  assert_true(
    mooncode_json_string(verification, "message", default="").contains(
      "ExecutionSandbox",
    ),
  )
}

///|
async test "MoonCode runtime dispatch rejects invalid or unconfigured process tools" (
  t : @test.Test,
) {
  ignore(t)
  @fsx.with_temporary_directory("mooncode-sandbox-dispatch-XXXXXX", async fn(
    book_root,
  ) {
    for tool in ["shell", "moon_ide", "moon_cmd", "moon_check"] {
      let execution = mooncode_execute_tool_call_in_runtime(
        None,
        "sandbox-dispatch",
        book_root,
        {
          "protocol": mooncode_protocol_version(),
          "session_id": "sandbox-dispatch",
          "book_root": book_root,
          "command_id": "cmd-\{tool}",
          "tool": tool,
          "arguments": {},
        },
        now=@clock.Timestamp::from_ms(1L),
      )
      assert_false(mooncode_json_bool(execution, "accepted", default=true))
      let result = mooncode_json_object_field_or_empty(execution, "result")
      assert_true(mooncode_json_bool(result, "is_error", default=false))
      let metadata = mooncode_json_object_field_or_empty(result, "metadata")
      if mooncode_json_string(result, "message", default="").contains(
          "ExecutionSandbox",
        ) {
        assert_true(
          mooncode_json_bool(
            metadata,
            "execution_sandbox_required",
            default=false,
          ),
        )
      }
    }
  })
}
