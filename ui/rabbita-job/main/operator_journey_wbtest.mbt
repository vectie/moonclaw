///|
test "operator journey chooses one goal action and a safe recovery" {
  let start = operator_next_step_for(false, 0, 0, 0, 0)
  assert_eq(start.position, 1)
  assert_eq(start.action, "cowork")
  let active = operator_next_step_for(false, 1, 1, 0, 0)
  assert_eq(active.position, 4)
  assert_eq(active.action, "jobs")
  let failed = operator_next_step_for(false, 1, 0, 1, 0)
  assert_true(failed.blocked)
  assert_eq(failed.action_label, "Review blocked run")
  let retry = operator_next_step_for(true, 1, 0, 0, 0)
  assert_true(retry.blocked)
  assert_eq(retry.action, "retry")
  let result = operator_next_step_for(false, 1, 0, 0, 1)
  assert_eq(result.position, 5)
  assert_eq(result.action_label, "Inspect result")
}

///|
fn operator_test_run(
  id : String,
  status : String,
  started? : Int? = Some(10),
  finished? : Int? = None,
) -> RunSummary {
  {
    id,
    job_id: "job-\{id}",
    status,
    depth: 0,
    started_at: started,
    finished_at: finished,
    summary: None,
  }
}

///|
fn operator_test_model(runs : Array[RunSummary]) -> Model {
  { ..init_model(), runs, runs_loading: false, }
}

///|
test "operator next step opens exact failed active and completed runs" {
  for
    (status, label, panel) in [
      ("Failed", "Review blocked run", "workspace"),
      ("Running", "Open active run", "workspace"),
      ("Pending", "Open active run", "workspace"),
      ("Completed", "Inspect result", "artifacts"),
    ] {
    let model = operator_test_model([operator_test_run("run-1", status)])
    let step = operator_next_step(model)
    assert_eq(step.action_label, label)
    assert_eq(step.target_url, "#/runs/run-1?panel=\{panel}")
    let url = @url.parse("http://localhost/ui\{step.target_url}")
    assert_true(route_from_url(url) == Run("run-1"))
    let next = artifact_test_update(model, UrlChanged(url))
    assert_true(next.route == Run("run-1"))
    assert_eq(next.selected_run_id, Some("run-1"))
    assert_eq(panel_query_value(next.right_panel), panel)
    assert_false(next.cowork_action_loading)
    assert_true(next.cowork_action_error is None)
  }
}

///|
test "operator next step prioritizes blocked then active then completed work" {
  let done = operator_test_run("done", "Completed", finished=Some(999))
  let active = operator_test_run("active", "Running", started=Some(998))
  let failed = operator_test_run("blocked", "Failed", finished=Some(2))
  inspect(
    operator_next_step(operator_test_model([done, active, failed])).target_url,
    content="#/runs/blocked?panel=workspace",
  )
  inspect(
    operator_next_step(operator_test_model([done, active])).target_url,
    content="#/runs/active?panel=workspace",
  )
  inspect(
    operator_next_step(operator_test_model([done])).target_url,
    content="#/runs/done?panel=artifacts",
  )
}

///|
test "operator next step chooses newest relevant timestamp and stable identity ties" {
  for status in ["Failed", "Completed", "Running"] {
    let old = operator_test_run(
      "old",
      status,
      started=Some(1),
      finished=Some(2),
    )
    let a = operator_test_run("a", status, started=Some(8), finished=Some(9))
    let z = operator_test_run("z", status, started=Some(8), finished=Some(9))
    for runs in [[old, z, a], [a, old, z], [z, a, old]] {
      let model = operator_test_model(runs)
      let step = operator_next_step(model)
      assert_eq(operator_next_run(model, step).unwrap().id, "a")
      assert_eq(model.runs[0].id, runs[0].id)
    }
  }
  let runs = [
    operator_test_run(
      "started-last",
      "Completed",
      started=Some(100),
      finished=Some(101),
    ),
    operator_test_run(
      "finished-last",
      "Completed",
      started=Some(1),
      finished=Some(200),
    ),
  ]
  inspect(
    operator_next_step(operator_test_model(runs)).target_url,
    content="#/runs/finished-last?panel=artifacts",
  )
  let missing = [
    operator_test_run("z", "Running", started=None),
    operator_test_run("a", "Running", started=None),
  ]
  inspect(
    operator_next_step(operator_test_model(missing)).target_url,
    content="#/runs/a?panel=workspace",
  )
}

///|
test "operator next step uses honest list fallback for missing or ambiguous identity" {
  for
    id in [
      "", " ", ".", "..", "run/other", "run?panel=memory", "run#x", "run%2Fother",
    ] {
    let step = operator_next_step(
      operator_test_model([operator_test_run(id, "Failed")]),
    )
    assert_eq(step.action_label, "View work")
    assert_eq(step.target_url, "#/jobs")
    assert_eq(step.title, "Choose work to inspect")
  }
  let duplicate = operator_test_run("duplicate", "Completed")
  let step = operator_next_step(operator_test_model([duplicate, duplicate]))
  inspect(step.action_label, content="View work")
  inspect(step.target_url, content="#/jobs")
  let valid = operator_test_run("run:1.2_3-4", "Failed")
  inspect(
    operator_next_step(operator_test_model([valid])).target_url,
    content="#/runs/run:1.2_3-4?panel=workspace",
  )
}

///|
test "operator next step does not promise stale run context during loading or errors" {
  let ready = operator_test_model([operator_test_run("old", "Failed")])
  let loading = { ..ready, runs_loading: true, }
  let step = operator_next_step(loading)
  inspect(step.action_label, content="View work")
  inspect(step.target_url, content="#/jobs")
  let failed = { ..ready, runs_error: Some("offline"), }
  let retry = operator_next_step(failed)
  inspect(retry.action_label, content="Retry status")
  inspect(retry.target_url, content="")
  let refreshed = artifact_test_update(
    loading,
    RunsLoaded(Ok([operator_test_run("new", "Running")])),
  )
  inspect(
    operator_next_step(refreshed).target_url,
    content="#/runs/new?panel=workspace",
  )
  inspect(
    operator_next_step(operator_test_model([])).target_url,
    content="#/cowork",
  )
}

///|
test "operator next step keeps selected run and ignores previous run result callbacks" {
  let initial = {
    ..operator_test_model([operator_test_run("next", "Completed")]),
    route: Run("old"),
    selected_run_id: Some("old"),
    selected_cowork_session_key: Some("request-owner"),
    cowork_composer: "retained request",
  }
  let pending = artifact_test_update(initial, OpenArtifact("old-result"))
  let step = operator_next_step(pending)
  let moved = artifact_test_update(
    pending,
    UrlChanged(@url.parse("http://localhost/ui\{step.target_url}")),
  )
  let stale = artifact_test_update(
    moved,
    ArtifactLoaded(
      "old-result",
      pending.artifact_request_generation,
      Ok(artifact_test_result("old-result", "late content")),
    ),
  )
  let old_snapshot = {
    ..test_canvas_snapshot([]),
    run: { ..test_ui_run(), id: "old", status: "Completed", },
  }
  let stale = artifact_test_update(
    stale,
    SnapshotLoaded("old", Ok(old_snapshot)),
  )
  let stale = artifact_test_update(
    stale,
    SnapshotLoaded("old", Err("late failure")),
  )
  inspect(stale.selected_run_id == Some("next"), content="true")
  inspect(stale.snapshot is None, content="true")
  inspect(stale.detail_error is None, content="true")
  inspect(stale.artifact_modal is None, content="true")
  inspect(stale.artifact_modal_loading, content="false")
  inspect(
    stale.selected_cowork_session_key == Some("request-owner"),
    content="true",
  )
  inspect(stale.cowork_composer, content="retained request")
  let snapshot = {
    ..test_canvas_snapshot([]),
    run: { ..test_ui_run(), id: "next", status: "Completed", },
  }
  let current = artifact_test_update(
    stale,
    SnapshotLoaded("next", Ok(snapshot)),
  )
  let repeated = artifact_test_update(
    current,
    UrlChanged(@url.parse("http://localhost/ui\{step.target_url}")),
  )
  inspect(repeated.snapshot.unwrap().run.id, content="next")
  inspect(repeated.right_panel == Artifacts, content="true")
}
