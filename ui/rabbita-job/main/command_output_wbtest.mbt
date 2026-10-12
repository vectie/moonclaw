///|
fn command_output_test_snapshot(
  status? : String = "available",
  output_limit? : Bool = false,
) -> UiSnapshot {
  let output = UiCommandOutput::{
    output_id: "run-fort-cross-product",
    run_id: "run-1",
    step_id: "step-1",
    status,
    size_bytes: 16L,
    sha256: "a".repeat(64),
    expires_at_ms: 9999999999999L,
    message: "Exact retained bytes",
    receipt_status: if output_limit {
      "killed"
    } else {
      "exited"
    },
    exit_code: if output_limit {
      None
    } else {
      Some(0)
    },
    output_truncated: output_limit,
    limit_reason: if output_limit {
      Some("output-limit")
    } else {
      None
    },
  }
  {
    ..test_canvas_snapshot([]),
    linked_remote: [
      {
        id: output.output_id,
        kind: "fort-command-output",
        title: "Command output · step-1",
        status,
        summary: Some(output.message),
        detail: None,
        metadata: output.to_json(),
      },
    ],
  }
}

///|
test "command output panel keeps readable actions and opaque details separate" {
  let dispatch = @cmd.Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_command_outputs(dispatch, command_output_test_snapshot()),
    ),
  )
  assert_true(html.contains("Download retained output"))
  assert_true(html.contains("Command exited · exit 0"))
  let limited = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_command_outputs(
        dispatch,
        command_output_test_snapshot(output_limit=true),
      ),
    ),
  )
  assert_true(limited.contains("Command killed"))
  assert_true(limited.contains("approved output ceiling"))
  assert_true(limited.contains("later output was not captured"))
  assert_true(html.contains("<details>"))
  assert_false(html.contains("signature"))
  for status in ["expired", "unavailable"] {
    let html = @rabbita.render_to_string(
      @rabbita.static_cell(
        render_command_outputs(dispatch, command_output_test_snapshot(status~)),
      ),
    )
    assert_false(html.contains("Download retained output"))
  }
}

///|
test "command output download owns run identity and cancel retry generations" {
  let initial = {
    ..init_model(),
    route: Run("run-1"),
    selected_run_id: Some("run-1"),
    snapshot: Some(command_output_test_snapshot()),
  }
  let pending = artifact_test_update(
    initial,
    DownloadCommandOutput("run-fort-cross-product"),
  )
  assert_true(pending.artifact_download_pending is Some(_))
  let duplicate = artifact_test_update(
    pending,
    DownloadCommandOutput("run-fort-cross-product"),
  )
  assert_eq(
    duplicate.artifact_download_generation,
    pending.artifact_download_generation,
  )
  let cancelled = artifact_test_update(pending, CancelArtifactDownload)
  let stale = artifact_test_update(
    cancelled,
    ArtifactDownloadFinished(pending.artifact_download_generation, Ok("late")),
  )
  assert_eq(stale.artifact_download_notice, cancelled.artifact_download_notice)
  let retry = artifact_test_update(
    cancelled,
    DownloadCommandOutput("run-fort-cross-product"),
  )
  assert_true(
    retry.artifact_download_generation > pending.artifact_download_generation,
  )
  let moved = artifact_test_update(retry, SelectRun("run-2"))
  assert_true(moved.artifact_download_pending is None)
  let stale_run = artifact_test_update(
    { ..initial, route: Run("run-2"), selected_run_id: Some("run-2"), },
    DownloadCommandOutput("run-fort-cross-product"),
  )
  assert_true(stale_run.artifact_download_pending is None)
  let missing = artifact_test_update(initial, DownloadCommandOutput("invented"))
  assert_true(missing.artifact_download_pending is None)
  let expired = artifact_test_update(
    {
      ..initial,
      snapshot: Some(command_output_test_snapshot(status="expired")),
    },
    DownloadCommandOutput("run-fort-cross-product"),
  )
  assert_true(expired.artifact_download_pending is None)
}

///|
test "command output projection refuses wrong run metadata and reload uses exact identity" {
  let snapshot = command_output_test_snapshot()
  assert_eq(
    selected_command_output(snapshot, "run-fort-cross-product").unwrap().run_id,
    "run-1",
  )
  let wrong = { ..snapshot, run: { ..snapshot.run, id: "run-2", }, }
  assert_true(selected_command_output(wrong, "run-fort-cross-product") is None)
  let original = selected_command_output(snapshot, "run-fort-cross-product").unwrap()
  let restored : UiCommandOutput = @json.from_json(original.to_json())
  assert_eq(restored.output_id, "run-fort-cross-product")
}
