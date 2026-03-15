///|
async test "execute_run_lifecycle runs workflow and invokes hooks" {
  @fsx.with_temporary_directory("job-executor-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    runtime.register_definition(JobDefinition::{
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
    runtime.register_workflow(WorkflowDefinition::{
      id: "workflow-1",
      kind: "generic.analysis",
      steps: [
        WorkflowStepDefinition::{
          id: "step-1",
          kind: "job.analysis",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: [],
    })
    ignore(runtime.create_run("run-1", "job-1", TriggerSource::Manual, 10))
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
    runtime.register_definition(JobDefinition::{
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
    ignore(runtime.create_run("run-1", "job-1", TriggerSource::Manual, 10))
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
      trigger: TriggerSource::Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: RunStatus::Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(10),
      completed_at: None,
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
    let finished = JobRun::{
      ..run,
      status: RunStatus::Succeeded,
      completed_at: Some(120),
    }
    (hooks.on_finished)(definition, finished)
    inspect(sent.length().to_string(), content="2")
    inspect(sent[1].contains("Job completed: job-1"), content="true")
    inspect(
      state.notification_runtime_state("run-1").last_sent_at.to_string(),
      content="0",
    )
  })
}
