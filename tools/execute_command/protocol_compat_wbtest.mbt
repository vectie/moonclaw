///|
test "MoonClaw canonical grant digest is stable for MoonFort v3" {
  let grant = @execution_sandbox.MoonFortExecutionGrant::{
    protocol_version: 3,
    approval_id: "approval-compat",
    request_id: "run-compat",
    workspace_id: "book",
    backend: LocalOs,
    enforcement_requirement: AllowDegraded,
    network: Deny,
    allowed_egress: [],
    allowed_commands: ["shell-compat"],
    limits: {
      wall_clock_ms: 5_000,
      cpu_seconds: 5,
      memory_mib: 128,
      disk_mib: 64,
      processes: 16,
      output_bytes: 4_096,
    },
    working_directory: "packages/app",
    command: Shell(script="printf hello"),
    backend_config_id: "local",
    expires_at_ms: 4_102_444_800_000L,
  }
  inspect(
    @execution_sandbox.moonfort_grant_digest(grant),
    content="274364655122683b82ceccb341ba8a2d86ff5b9efe831acef03fefae5d15bea9",
  )
}

///|
test "MoonFort v3 receipt decodes absent and present output artifacts" {
  let absent : @execution_sandbox.MoonFortReceipt = @json.from_json({
    "run_id": "run-compat",
    "approval_id": "approval-compat",
    "approval_digest": "a".repeat(64),
    "command_digest": "b".repeat(64),
    "backend": "LocalOs",
    "enforcement": "Degraded",
    "status": "Exited",
    "profile_digest": "c".repeat(64),
    "exit_code": 0,
    "output": "small complete output",
    "output_truncated": false,
    "unverified_limits": ["network"],
    "changed_paths": [],
    "changes": [],
    "artifacts": [],
    "cleanup_verified": true,
  })
  assert_true(absent.output_artifact is None)
  let present : @execution_sandbox.MoonFortReceipt = @json.from_json({
    "run_id": "run-compat",
    "approval_id": "approval-compat",
    "approval_digest": "a".repeat(64),
    "command_digest": "b".repeat(64),
    "backend": "LocalOs",
    "enforcement": "Degraded",
    "status": "Killed",
    "profile_digest": "c".repeat(64),
    "output": "bounded projection",
    "output_truncated": true,
    "output_artifact": {
      "artifact_id": "0123456789abcdef0123456789abcdef",
      "run_id": "run-compat",
      "sha256": "d".repeat(64),
      "size_bytes": "4096",
      "media_type": "text/plain; charset=utf-8",
      "expires_at_ms": "4102444800000",
      "key_id": "artifact-key-1",
      "signature": "e".repeat(64),
    },
    "limit_reason": "wall-clock-limit",
    "unverified_limits": ["network"],
    "changed_paths": [],
    "changes": [],
    "artifacts": [],
    "cleanup_verified": true,
  })
  guard present.output_artifact is Some(artifact) else {
    fail("present output_artifact decoded as absent")
  }
  assert_eq(artifact.run_id, "run-compat")
  assert_eq(artifact.size_bytes, 4_096L)
}
