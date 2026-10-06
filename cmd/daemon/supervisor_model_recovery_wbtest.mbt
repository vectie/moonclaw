///|
async test "supervisor fresh and stopped recovery resolve the same persisted model" {
  let task : @job.SupervisorWorkerTaskV1 = {
    task_id: "task",
    conversation_id: "conversation",
    title: "Task",
    cwd: "/tmp/dummy-book",
    model: Some("moongate/configured/exact-id"),
    web_search: false,
    metadata: {},
  }
  let persisted : @job.SupervisorWorkerTaskV1 = @json.from_json(
    @json.parse(task.to_json().stringify()),
  )
  let selected : Array[String] = []
  for saved in [task, persisted] {
    let workspace = supervisor_model_workspace(
      supervisor_worker_model_selector(saved.model),
      saved.cwd,
    )
    assert_eq(workspace, Some("/tmp/dummy-book"))
    let arguments = @trusted_host_process.daemon_child_model_arguments(
      saved.model,
      workspace,
    )
    assert_eq(arguments, [
      "--model", "moongate/configured/exact-id", "--model-workspace", "/tmp/dummy-book",
    ])
    let model = resolve_supervisor_worker_model(saved.model, resolve=selector => {
      selected.push(selector)
      Some(
        @model.Model::new(
          api_key="",
          base_url="http://gate.invalid/openclaw/v1",
          name=selector,
          model_name="configured/exact-id",
          safe_zone_tokens=1000,
        ),
      )
    })
    assert_eq(model.selector(), "moongate/configured/exact-id")
    assert_eq(
      supervisor_worker_model_selector(
        saved.model,
        running_model=model.selector(),
      ),
      model.selector(),
    )
  }
  assert_eq(selected, [
    "moongate/configured/exact-id", "moongate/configured/exact-id",
  ])
  assert_true(
    supervisor_model_workspace("codex/gpt-5.4", "/tmp/dummy-book") is None,
  )
}

///|
test "supervisor running recovery rejects a changed route" {
  try
    supervisor_worker_model_selector(
      Some("moongate/chosen"),
      running_model="codex/gpt-5.6-sol",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected mismatched running route to fail")
  }
  for missing in [None, Some(""), Some(" ")] {
    try supervisor_worker_model_selector(missing) catch {
      _ => ()
    } noraise {
      _ => fail("expected missing route to fail")
    }
  }
  assert_eq(
    supervisor_worker_model_selector(Some("gpt-5.6-sol")),
    "codex/gpt-5.6-sol",
  )
  assert_eq(
    supervisor_worker_model_selector(Some("codex/gpt-5.4")),
    "codex/gpt-5.4",
  )
  assert_eq(
    supervisor_worker_model_selector(Some("qwen/qwen3-coder-plus")),
    "qwen/qwen3-coder-plus",
  )
  assert_eq(
    supervisor_worker_model_selector(
      Some("codex/gpt-5.4"),
      running_model="gpt-5.4",
    ),
    "codex/gpt-5.4",
  )
  assert_eq(
    supervisor_worker_model_selector(
      Some("qwen/qwen3-coder-plus"),
      running_model="qwen3-coder-plus",
    ),
    "qwen/qwen3-coder-plus",
  )
}

///|
async test "supervisor recovery cannot replace an unavailable selected model" {
  let requested : Array[String] = []
  try
    resolve_supervisor_worker_model(Some("moongate/chosen"), resolve=selector => {
      requested.push(selector)
      None
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("expected unavailable route to fail")
  }
  try
    resolve_supervisor_worker_model(Some("moongate/chosen"), resolve=_ => {
      Some(
        @model.Model::new(
          api_key="dummy",
          base_url="https://other.invalid",
          name="other/model",
          safe_zone_tokens=1000,
        ),
      )
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("expected replacement route to fail")
  }
  assert_eq(requested, ["moongate/chosen"])
}
