///|
fn output_artifact_test_reference(
  run_id? : String = "run-output-artifact",
  artifact_id? : String = "0123456789abcdef0123456789abcdef",
  sha256? : String = "d".repeat(64),
  size_bytes? : Int64 = 128L,
  media_type? : String = "text/plain; charset=utf-8",
  expires_at_ms? : Int64 = 4_102_444_800_000L,
  key_id? : String = "artifact-key-1",
  signature? : String = "e".repeat(64),
) -> @execution_sandbox.MoonFortCommandOutputArtifactRef {
  {
    artifact_id,
    run_id,
    sha256,
    size_bytes,
    media_type,
    expires_at_ms,
    key_id,
    signature,
  }
}

///|
fn output_artifact_test_receipt(
  status? : @execution_sandbox.MoonFortRunStatus = Exited,
  output? : String = "bounded inline output",
  output_truncated? : Bool = false,
  output_artifact? : @execution_sandbox.MoonFortCommandOutputArtifactRef,
) -> @execution_sandbox.MoonFortReceipt {
  {
    run_id: "run-output-artifact",
    approval_id: "approval-output-artifact",
    approval_digest: "a".repeat(64),
    command_digest: "b".repeat(64),
    backend: LocalOs,
    enforcement: Degraded,
    status,
    profile_digest: "c".repeat(64),
    exit_code: Some(0),
    output,
    output_truncated,
    output_artifact,
    limit_reason: None,
    unverified_limits: ["network"],
    changed_paths: [],
    changes: [],
    artifacts: [],
    denial_reason: None,
    cleanup_verified: true,
    retention_id: None,
  }
}

///|
fn live_output_test_reference(
  run_id? : String = "run-output-artifact",
  status? : String = "exited",
  size_bytes? : Int64 = 128L,
  expires_at_ms? : Int64 = 4_102_444_800_000L,
) -> @execution_sandbox.MoonFortLiveOutputReference {
  {
    stream_id: "0123456789abcdef0123456789abcdef",
    run_id,
    status,
    size_bytes,
    sha256: "a".repeat(64),
    expires_at_ms,
    key_id: "live-output-key-1",
    signature: "b".repeat(64),
  }
}

///|
test "MoonFort output artifact accepts the signed opaque metadata shape" {
  assert_true(
    @execution_sandbox.moonfort_output_artifact_valid(
      output_artifact_test_receipt(
        output_artifact=output_artifact_test_reference(),
      ),
      4_096,
      1_000L,
    ),
  )
  // Older small-output receipts may omit the optional field.
  assert_true(
    @execution_sandbox.moonfort_output_artifact_valid(
      output_artifact_test_receipt(),
      4_096,
      1_000L,
    ),
  )
}

///|
test "truncated terminal output requires a complete-output artifact" {
  assert_false(
    @execution_sandbox.moonfort_output_artifact_valid(
      output_artifact_test_receipt(output_truncated=true),
      4_096,
      1_000L,
    ),
  )
  assert_true(
    @execution_sandbox.moonfort_output_artifact_valid(
      output_artifact_test_receipt(
        output_truncated=true,
        output_artifact=output_artifact_test_reference(),
      ),
      4_096,
      1_000L,
    ),
  )
}

///|
test "MoonFort output artifact metadata is adversarially bounded and run-bound" {
  let invalid = [
    output_artifact_test_reference(run_id="another-run"),
    output_artifact_test_reference(artifact_id="/private/tmp/leak"),
    output_artifact_test_reference(artifact_id="../../leak"),
    output_artifact_test_reference(sha256="not-a-digest"),
    output_artifact_test_reference(size_bytes=4_097L),
    output_artifact_test_reference(size_bytes=1L),
    output_artifact_test_reference(media_type="application/octet-stream"),
    output_artifact_test_reference(expires_at_ms=999L),
    output_artifact_test_reference(key_id="../../host-key"),
    output_artifact_test_reference(signature="not-a-signature"),
  ]
  for artifact in invalid {
    assert_false(
      @execution_sandbox.moonfort_output_artifact_valid(
        output_artifact_test_receipt(output_artifact=artifact),
        4_096,
        1_000L,
      ),
    )
  }
  assert_false(
    @execution_sandbox.moonfort_output_artifact_valid(
      output_artifact_test_receipt(
        status=Failed,
        output_artifact=output_artifact_test_reference(),
      ),
      4_096,
      1_000L,
    ),
  )
}

///|
test "MoonFort live output metadata is terminal, bounded, and run-bound" {
  let receipt = output_artifact_test_receipt()
  assert_true(
    @execution_sandbox.moonfort_live_output_reference_valid(
      live_output_test_reference(),
      receipt,
      4_096,
      1_000L,
    ),
  )
  let invalid = [
    live_output_test_reference(run_id="another-run"),
    live_output_test_reference(status="running"),
    live_output_test_reference(size_bytes=1L),
    live_output_test_reference(size_bytes=4_097L),
    live_output_test_reference(expires_at_ms=999L),
  ]
  for reference in invalid {
    assert_false(
      @execution_sandbox.moonfort_live_output_reference_valid(
        reference, receipt, 4_096, 1_000L,
      ),
    )
  }
}

///|
test "rendered process output exposes metadata but no host receipt path or secret" {
  let artifact = output_artifact_test_reference(
    key_id="private-key-name",
    signature="f".repeat(64),
  )
  let receipt = output_artifact_test_receipt(output_artifact=artifact)
  let result = Completed(
    command="printf hello",
    status=0,
    stdout=receipt.output,
    stderr="",
    max_output_lines=100,
    receipt~,
    audit_id="run-output-artifact",
  )
  let rendered = result.to_string()
  assert_true(rendered.contains("artifact_id=" + artifact.artifact_id))
  assert_true(rendered.contains("sha256=" + artifact.sha256))
  assert_true(rendered.contains("size_bytes=128"))
  assert_false(rendered.contains("/private/var"))
  assert_false(rendered.contains("private-key-name"))
  assert_false(rendered.contains(artifact.signature))
  let encoded = result.to_json().stringify()
  assert_false(encoded.contains("audit_path"))
  assert_false(encoded.contains("/private/"))
}
