///|
test "blocked recovery is connected only to the loaded linked work run" {
  let model = cowork_request_test_ready("work:fixture")
  let detail = model.cowork_detail.unwrap()
  let linked : CoworkRunRef = {
    id: "run-fixture",
    job_id: "job-fixture",
    status: "WaitingForInput",
    summary: None,
    error: None,
    current_step_id: Some("missing-date"),
    workspace_dir: None,
  }
  let ready = {
    ..model,
    cowork_detail: Some({ ..detail, linked_run: Some(linked), }),
  }
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_cowork_center(@cmd.Emit(_ => @rabbita.none), ready),
    ),
  )
  assert_true(html.contains("Continue blocked work"))
  assert_true(html.contains("Refresh retained checkpoint"))
  assert_true(html.contains("run-fixture"))
  assert_true(html.contains("Stop waiting for response"))
  for
    hidden in [
      model,
      { ..ready, cowork_detail_loading: true, },
      { ..ready, selected_cowork_session_key: Some("other"), },
    ] {
    assert_false(
      @rabbita.render_to_string(
        @rabbita.static_cell(render_cowork_blocked_recovery(hidden)),
      ).contains("claw-recovery-panel"),
    )
  }
}
