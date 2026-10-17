///|
fn recovery_test_run() -> @job.JobRun {
  {
    id: "recovery-run",
    job_id: "recovery-job",
    trigger: Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
    status: WaitingForInput,
    attempt: 1,
    retry_of: None,
    started_at: Some(100),
    finished_at: None,
    summary: None,
    error: None,
  }
}

///|
fn recovery_test_step(id : String, status : @job.RunStatus) -> @job.JobStepRun {
  {
    id: "record-" + id,
    run_id: "recovery-run",
    step_id: id,
    status,
    started_at: Some(100),
    finished_at: None,
    metrics: {},
    logs: ["private log"],
    retry_count: 0,
    summary: Some("Retained evidence " + id),
    output: Some({ "private_output": "not a recovery field" }),
    error: None,
  }
}

///|
fn recovery_test_project(
  run~ : @job.JobRun = recovery_test_run(),
  steps~ : Array[@job.JobStepRun] = [
    recovery_test_step("done", Succeeded),
    recovery_test_step("input", WaitingForInput),
  ],
  messages~ : Int32 = 2,
  events~ : Int32 = 3,
  observed~ : Int32 = 1000,
) -> Json {
  cowork_recovery_projection(
    "work:fixture",
    "/fixture",
    messages,
    Json::null(),
    false,
    run,
    steps,
    [],
    events,
    observed,
  )
}

///|
test "blocked recovery shows completed and waiting work without raw payloads" {
  let value = recovery_test_project()
  assert_true(
    value is { "can_resume": True, "status": String("WaitingForInput"), .. },
  )
  assert_false(value.stringify().contains("private log"))
  assert_false(value.stringify().contains("private_output"))
  assert_true(value.stringify().contains("Retained evidence done"))
}

///|
test "recovery checkpoint changes on a newer wait, accepted input and journal change but not observation time" {
  let original = recovery_test_project()
  guard original is { "checkpoint": String(checkpoint), .. } else {
    fail("checkpoint")
  }
  assert_true(
    recovery_test_project(observed=2000) is { "checkpoint": String(value), .. } &&
    value == checkpoint,
  )
  for
    changed in [
      recovery_test_project(messages=3),
      recovery_test_project(events=4),
      recovery_test_project(steps=[
        recovery_test_step("new-input", WaitingForInput),
      ]),
      recovery_test_project(steps=[
        { ..recovery_test_step("input", WaitingForInput), retry_count: 1, },
      ]),
      recovery_test_project(run={ ..recovery_test_run(), status: Running, }),
    ] {
    assert_true(
      changed is { "checkpoint": String(value), .. } && value != checkpoint,
    )
  }
}

///|
test "recovery fails closed for mixed failed running cancelled absent and multiple waits" {
  for
    steps in [
      [],
      [
        recovery_test_step("a", WaitingForInput),
        recovery_test_step("b", WaitingForInput),
      ],
      [
        recovery_test_step("a", WaitingForInput),
        recovery_test_step("b", Running),
      ],
      [
        recovery_test_step("a", WaitingForInput),
        recovery_test_step("b", Failed),
      ],
      [
        recovery_test_step("a", WaitingForInput),
        recovery_test_step("b", Cancelled),
      ],
    ] {
    assert_true(recovery_test_project(steps~) is { "can_resume": False, .. })
  }
  for status in [@job.RunStatus::Pending, Running, Succeeded, Failed, Cancelled] {
    assert_true(
      recovery_test_project(run={ ..recovery_test_run(), status, })
      is { "can_resume": False, .. },
    )
  }
}

///|
test "resume checkpoint body is optional for legacy callers and exact for recovery" {
  let legacy : CoworkResumeParams = @json.from_json({ "content": "input" })
  assert_eq(legacy.expected_checkpoint, None)
  let current : CoworkResumeParams = @json.from_json({
    "content": "input",
    "expected_checkpoint": "sha256:fixture",
  })
  assert_eq(current.expected_checkpoint, Some("sha256:fixture"))
}

///|
async test "recovery HTTP reads exact linked checkpoint and refuses stale unrelated inactive submissions without effects" {
  @fsx.with_temporary_directory("claw-recovery-http-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only"),
      _password: None,
    })
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    store.save_run(recovery_test_run())
    store.save_step_run(recovery_test_step("done", Succeeded))
    store.save_step_run(recovery_test_step("input", WaitingForInput))
    let session = gateway.sessions.get_or_create(
      session_key="work:fixture",
      cwd=dir.to_string(),
    )
    gateway.sessions.save_entry("work:fixture", {
      ..session,
      linked_run_id: Some("recovery-run"),
    })
    let base = "http://127.0.0.1:\{gateway.httpx.port()}"
    let path = base + "/v1/cowork/sessions/work%3Afixture/runs/recovery-run"
    let headers = { "authorization": "Bearer fixture-only" }
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          gateway.httpx.serve(
            @httpx.Handler((r, w) => gateway.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      let (denied, _) = @http.get(path + "/recovery")
      assert_eq(denied.code, 401)
      let (response, body) = @http.get(path + "/recovery", headers~)
      assert_eq(response.code, 200)
      assert_eq(response.headers.get("cache-control"), Some("no-store"))
      guard @json.parse(body.text())
        is { "checkpoint": String(checkpoint), "can_resume": True, .. } else {
        fail("checkpoint response")
      }
      let payload : Json = {
        "content": "Use only supplied dates",
        "expected_checkpoint": checkpoint,
      }
      let (inactive, _) = @http.post(
        path + "/resume",
        payload.stringify(),
        headers~,
      )
      assert_eq(inactive.code, 503)
      assert_eq(
        gateway.sessions.get("work:fixture").unwrap().messages.length(),
        0,
      )
      store.save_step_run({
        ..recovery_test_step("input", WaitingForInput),
        retry_count: 1,
      })
      let (stale, _) = @http.post(
        path + "/resume",
        payload.stringify(),
        headers~,
      )
      assert_eq(stale.code, 409)
      let (unrelated, _) = @http.get(
        base + "/v1/cowork/sessions/work%3Afixture/runs/other/recovery",
        headers~,
      )
      assert_eq(unrelated.code, 409)
      gateway.recovery_resume_pending["recovery-run"] = true
      let (duplicate, _) = @http.post(
        path + "/resume",
        payload.stringify(),
        headers~,
      )
      assert_eq(duplicate.code, 409)
      gateway.recovery_resume_pending.remove("recovery-run") |> ignore()
      let pending = group.spawn(no_wait=true, allow_failure=true, () => {
        @async.sleep(60000)
      })
      gateway.register_active_job_task("recovery-run", pending)
      let (launching, launching_body) = @http.get(path + "/recovery", headers~)
      assert_eq(launching.code, 200)
      assert_true(
        @json.parse(launching_body.text())
        is { "can_resume": False, "launch_pending": True, .. },
      )
      let (during_launch, _) = @http.post(
        path + "/resume",
        payload.stringify(),
        headers~,
      )
      assert_eq(during_launch.code, 409)
      gateway.clear_active_job_task("recovery-run")
      assert_eq(store.list_runs().length(), 1)
      assert_eq(
        gateway.sessions.get("work:fixture").unwrap().messages.length(),
        0,
      )
      assert_eq(
        store.get_step_run("recovery-run", "done").unwrap().status.to_json(),
        "Succeeded",
      )
      group.return_immediately(())
    })
  })
}

///|
async test "historical resume lookup binds the exact answer after later resumes and detects cancelled post-save state" {
  @fsx.with_temporary_directory("claw-recovery-receipt-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only"),
      _password: None,
    })
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    store.save_run(recovery_test_run())
    store.save_step_run(recovery_test_step("input", WaitingForInput))
    let entry = gateway.sessions.get_or_create(
      session_key="work:fixture",
      cwd=dir.to_string(),
    )
    let first = gateway.append_session_message(
      { ..entry, linked_run_id: Some("recovery-run"), },
      "user",
      "resume",
      "Original exact answer",
      metadata={
        "run_id": "recovery-run",
        "recovery_checkpoint": "checkpoint-a",
      },
    )
    let second = gateway.append_session_message(
      first,
      "user",
      "resume",
      "Later different answer",
      metadata={
        "run_id": "recovery-run",
        "recovery_checkpoint": "checkpoint-b",
      },
    )
    gateway.sessions.save_entry("work:fixture", second)
    let snapshot = gateway.cowork_recovery_snapshot(
      "work:fixture",
      "recovery-run",
      lookup_checkpoint=Some("checkpoint-a"),
    )
    guard snapshot
      is {
        "resume_receipt": {
          "content_digest": String(digest),
          "message_id": String(message_id),
          ..
        },
        "checkpoint": String(before),
        ..
      } else {
      fail("original receipt")
    }
    assert_eq(
      digest,
      @book_learning.digest(@encoding/utf8.encode("Original exact answer")),
    )
    assert_eq(message_id, first.messages[0].id)
    assert_true(
      gateway.cowork_recovery_snapshot(
        "work:fixture",
        "recovery-run",
        lookup_checkpoint=Some("missing"),
      )
      is { "resume_receipt": Null, .. },
    )
    store.save_run({ ..recovery_test_run(), status: Cancelled, })
    let changed = gateway.cowork_recovery_snapshot(
      "work:fixture", "recovery-run",
    )
    assert_true(
      changed is { "checkpoint": String(after), "can_resume": False, .. } &&
      before != after,
    )
  })
}

///|
async test "conditional resume records exact input and launches only the original fixture run" {
  @fsx.with_temporary_directory("claw-recovery-submit-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only"),
      _password: None,
    })
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    // Deliberately no workflow: exercises admission, persistence and actual
    // launch, then the existing honest missing-workflow failure. No provider.
    store.save_definition({
      id: "recovery-job",
      kind: "fixture.recovery",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: [],
    })
    store.save_run(recovery_test_run())
    store.save_step_run(recovery_test_step("done", Succeeded))
    store.save_step_run(recovery_test_step("input", WaitingForInput))
    let entry = gateway.sessions.get_or_create(
      session_key="work:fixture",
      cwd=dir.to_string(),
    )
    gateway.sessions.save_entry("work:fixture", {
      ..entry,
      linked_run_id: Some("recovery-run"),
    })
    let path = "http://127.0.0.1:\{gateway.httpx.port()}/v1/cowork/sessions/work%3Afixture/runs/recovery-run"
    let headers = { "authorization": "Bearer fixture-only" }
    @async.with_task_group(group => {
      gateway_root_groups[gateway.port] = group
      defer gateway_root_groups.remove(gateway.port) |> ignore()
      group.spawn_bg(
        () => {
          gateway.httpx.serve(
            @httpx.Handler((r, w) => gateway.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      let (_, snapshot_body) = @http.get(path + "/recovery", headers~)
      guard @json.parse(snapshot_body.text())
        is { "checkpoint": String(checkpoint), .. } else {
        fail("checkpoint")
      }
      let payload : Json = {
        "content": "Exact 世界\nanswer",
        "expected_checkpoint": checkpoint,
      }
      let (response, _) = @http.post(
        path + "/resume",
        payload.stringify(),
        headers~,
      )
      assert_eq(response.code, 200)
      let saved = gateway.sessions.get("work:fixture").unwrap()
      assert_eq(
        saved.messages.filter(message => message.kind == "resume").length(),
        1,
      )
      assert_eq(saved.messages[0].content, "Exact 世界\nanswer")
      let (duplicate, _) = @http.post(
        path + "/resume",
        payload.stringify(),
        headers~,
      )
      assert_eq(duplicate.code, 409)
      for _ in 0..<100 {
        if store.get_run("recovery-run").unwrap().status is Failed &&
          !gateway.active_job_tasks.contains("recovery-run") {
          break
        }
        @async.sleep(10)
      }
      assert_true(store.get_run("recovery-run").unwrap().status is Failed)
      assert_eq(store.list_runs().length(), 1)
      assert_true(
        store.get_step_run("recovery-run", "done").unwrap().status is Succeeded,
      )
      let receipt = gateway.cowork_recovery_snapshot(
        "work:fixture",
        "recovery-run",
        lookup_checkpoint=Some(checkpoint),
      )
      assert_true(
        receipt
        is {
          "can_resume": False,
          "resume_receipt": { "content_digest": String(digest), .. },
          ..
        } &&
        digest ==
        @book_learning.digest(@encoding/utf8.encode("Exact 世界\nanswer")),
      )
      group.return_immediately(())
    })
  })
}
