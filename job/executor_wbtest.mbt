///|
async test "execute_run_lifecycle runs workflow and invokes hooks" {
  @fsx.with_temporary_directory("job-executor-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    runtime.register_definition({
      id: "job-1",
      kind: "generic.analysis",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some("workflow-1"),
      created_at: 1,
      updated_at: 1,
      tags: [],
    })
    runtime.register_workflow({
      id: "workflow-1",
      kind: "generic.analysis",
      steps: [
        { id: "step-1", kind: "job.analysis", config: {}, retry_policy: None },
      ],
      output_bindings: [],
    })
    ignore(runtime.create_run("run-1", "job-1", Manual, 10))
    let marks : Map[String, Int] = {}
    execute_run_lifecycle(
      runtime,
      "run-1",
      fn() { 100 },
      fn() {
        let engine = WorkflowEngine::new(runtime~)
        engine.register_handler(
          WorkflowStepHandler::new(kind="job.analysis", run=fn(_ctx) {
            Ok(WorkflowStepResult::new(output={ "ok": true }))
          }),
        )
        engine
      },
      hooks=RunExecutionHooks::new(
        on_started=fn(_definition, _run) { marks.set("started", 1) },
        on_finished=fn(_definition, _run) { marks.set("finished", 1) },
      ),
    )
    let run = match runtime.store().get_run("run-1") {
      Some(run) => run
      None => fail("expected run")
    }
    inspect(run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(marks.contains("started"), content="true")
    inspect(marks.contains("finished"), content="true")
  })
}

///|
async test "execute_run_lifecycle fails missing workflow_id runs" {
  @fsx.with_temporary_directory("job-executor-missing-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    runtime.register_definition({
      id: "job-1",
      kind: "generic.analysis",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: [],
    })
    ignore(runtime.create_run("run-1", "job-1", Manual, 10))
    execute_run_lifecycle(runtime, "run-1", fn() { 100 }, fn() {
      WorkflowEngine::new(runtime~)
    })
    let run = match runtime.store().get_run("run-1") {
      Some(run) => run
      None => fail("expected run")
    }
    inspect(run.status.to_json().stringify(), content="\"Failed\"")
    inspect(run.error.unwrap_or("").contains("no workflow_id"), content="true")
  })
}

///|
async test "execution_notification_hooks sends start and finish notifications" {
  @fsx.with_temporary_directory("job-executor-hooks-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let state = GatewayJobState::new(root~)
    let definition = JobDefinition::{
      id: "job-1",
      kind: "generic.analysis",
      enabled: true,
      config: {
        "notify": {
          "channel": "feishu",
          "account_id": "default",
          "to": "oc_chat_1",
        },
      },
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: [],
    }
    let run = JobRun::{
      id: "run-1",
      job_id: "job-1",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(10),
      finished_at: None,
      summary: None,
      error: None,
    }
    state.runtime().register_definition(definition)
    let sent : Array[String] = []
    let hooks = execution_notification_hooks(state, fn() { 100 }, fn(
      _target,
      content,
    ) {
      sent.push(content)
    })
    (hooks.on_started)(definition, run)
    inspect(sent.length().to_string(), content="1")
    inspect(sent[0].contains("Job started: job-1"), content="true")
    inspect(
      state.notification_runtime_state("run-1").last_sent_at.to_string(),
      content="100",
    )
    let finished = JobRun::{ ..run, status: Succeeded, finished_at: Some(120) }
    (hooks.on_finished)(definition, finished)
    inspect(sent.length().to_string(), content="2")
    inspect(sent[1].contains("Job completed: job-1"), content="true")
    inspect(
      state.notification_runtime_state("run-1").last_sent_at.to_string(),
      content="0",
    )
  })
}

///|
async test "execute_run_lifecycle does not send stale start notification when resuming waiting run" {
  @fsx.with_temporary_directory("job-executor-resume-hooks-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let definition = JobDefinition::{
      id: "job-1",
      kind: "generic.analysis",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some("workflow-1"),
      created_at: 1,
      updated_at: 1,
      tags: [],
    }
    runtime.register_definition(definition)
    runtime.register_workflow({
      id: "workflow-1",
      kind: "generic.analysis",
      steps: [
        { id: "step-1", kind: "job.analysis", config: {}, retry_policy: None },
      ],
      output_bindings: [],
    })
    runtime
    .store()
    .save_run({
      id: "run-1",
      job_id: "job-1",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: WaitingForInput,
      attempt: 1,
      retry_of: None,
      started_at: Some(10),
      finished_at: Some(20),
      summary: Some("waiting"),
      error: Some("Analysis requires input: parcel size"),
    })
    let marks : Map[String, Int] = {}
    execute_run_lifecycle(
      runtime,
      "run-1",
      fn() { 100 },
      fn() {
        let engine = WorkflowEngine::new(runtime~)
        engine.register_handler(
          WorkflowStepHandler::new(kind="job.analysis", run=fn(_ctx) {
            Ok(WorkflowStepResult::new(output={ "ok": true }))
          }),
        )
        engine
      },
      initial_input=Some({ "resume_content": "guess missing data" }),
      hooks=RunExecutionHooks::new(
        on_started=fn(_definition, _run) { marks.set("started", 1) },
        on_finished=fn(_definition, _run) { marks.set("finished", 1) },
      ),
    )
    let run = match runtime.store().get_run("run-1") {
      Some(run) => run
      None => fail("expected run")
    }
    inspect(run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(marks.contains("started"), content="false")
    inspect(marks.contains("finished"), content="true")
  })
}

///|
async test "execute_run_lifecycle cleans up auto-created worktrees on success" {
  @fsx.with_temporary_directory("job-executor-worktree-cleanup-XXXXXX", dir => {
    let repo = @pathx.join(dir, "repo")
    @fsx.make_directory(repo, recursive=true)
    @git.init_(repo)
    @fsx.write_to_file(repo |> @pathx.join("README.md"), "hello")
    @git.commit("init", ["README.md"], cwd=repo)
    let handle = @worktree.plan_worktree(repo, "cleanup candidate")
    ignore(@worktree.create_worktree(handle))
    inspect(@fsx.exists(handle.path), content="true")

    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    runtime.register_definition({
      id: "job-1",
      kind: "generic.analysis",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some("workflow-1"),
      created_at: 1,
      updated_at: 1,
      tags: [],
    })
    runtime.register_workflow({
      id: "workflow-1",
      kind: "generic.analysis",
      steps: [
        { id: "step-1", kind: "job.analysis", config: {}, retry_policy: None },
      ],
      output_bindings: [],
    })
    ignore(runtime.create_run("run-1", "job-1", Manual, 10))
    execute_run_lifecycle(runtime, "run-1", fn() { 100 }, fn() {
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="job.analysis", run=async fn(ctx) {
          let artifacts = ArtifactStore::new(store=runtime.store())
          ignore(
            artifacts.write(
              ArtifactWriteRequest::new(
                run_id=ctx.run.id,
                job_id=ctx.run.job_id,
                artifact_type="analysis.result",
                logical_key=Some("cleanup-check"),
                content="{}",
                content_type="application/json",
                metadata={
                  "execution_isolation": {
                    "mode": "git_worktree",
                    "cwd": handle.path,
                    "base_cwd": repo,
                    "repo_root": repo,
                    "task_key": "cleanup candidate",
                    "auto_created": true,
                    "cleanup_policy": "on_success",
                  },
                },
              ),
              "artifact-cleanup-1",
              100,
            ),
          )
          Ok(WorkflowStepResult::new(output={ "ok": true }))
        }),
      )
      engine
    })
    let run = match runtime.store().get_run("run-1") {
      Some(run) => run
      None => fail("expected run")
    }
    inspect(run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(@fsx.exists(handle.path), content="false")
    let cleanup_events = runtime
      .store()
      .list_run_events("run-1")
      .filter(fn(event) { event.event_type == "execution_isolation.cleaned" })
    inspect(cleanup_events.length(), content="1")
    inspect(cleanup_events[0].message, content="Removed 1 isolated worktree(s)")
  })
}
