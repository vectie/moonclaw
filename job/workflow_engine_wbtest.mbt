///|
fn workflow_test_definition(workflow_id : String) -> JobDefinition {
  JobDefinition::{
    id: "job.workflow",
    kind: "job.workflow",
    enabled: true,
    config: {},
    schedule: None,
    retry_policy: None,
    workflow_id: Some(workflow_id),
    created_at: 1,
    updated_at: 1,
    tags: ["workflow"],
  }
}

///|
fn workflow_test_run() -> JobRun {
  JobRun::{
    id: "run-workflow-1",
    job_id: "job.workflow",
    trigger: TriggerSource::Manual,
    status: RunStatus::Pending,
    attempt: 1,
    retry_of: None,
    started_at: None,
    completed_at: None,
    summary: None,
    error: None,
  }
}

///|
async fn workflow_test_engine(
  root : String,
  workflow : WorkflowDefinition,
) -> WorkflowEngine {
  let runtime = RuntimeManager::new(root~)
  runtime.register_definition(workflow_test_definition(workflow.id))
  runtime.register_workflow(workflow)
  runtime.store().save_run(workflow_test_run())
  WorkflowEngine::new(runtime~)
}

///|
async test "WorkflowEngine executes steps in order and passes outputs" {
  @fsx.with_temporary_directory("job-workflow-engine-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workflow = WorkflowDefinition::{
      id: "workflow.progression",
      kind: "test",
      steps: [
        WorkflowStepDefinition::{
          id: "fetch",
          kind: "test.fetch",
          config: {},
          retry_policy: None,
        },
        WorkflowStepDefinition::{
          id: "parse",
          kind: "test.parse",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: ["parse"],
    }
    let engine = workflow_test_engine(root, workflow)
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.fetch", run=fn(_context) {
        Ok(
          WorkflowStepResult::new(
            output={ "value": 41 },
            summary=Some("fetched"),
            logs=["fetch ok"],
          ),
        )
      }),
    )
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.parse", run=fn(context) {
        let previous = context
          .output("fetch")
          .map(fn(output) {
            let data : Map[String, Int] = @json.from_json(output) catch {
              _ => {}
            }
            data.get("value").unwrap_or(0)
          })
          .unwrap_or(0)
        Ok(
          WorkflowStepResult::new(
            output={ "value": previous + 1 },
            summary=Some("parsed"),
            logs=["parse ok"],
          ),
        )
      }),
    )

    let result = match engine.execute_run("run-workflow-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("parse")
      .map(fn(output) { output.stringify() })
      .unwrap_or(""),
      content="{\"value\":42}",
    )
    inspect(
      result.steps
      .map(fn(step) { "\{step.step_id}:\{step.status.to_json().stringify()}" })
      .join(","),
      content="fetch:\"Succeeded\",parse:\"Succeeded\"",
    )
  })
}

///|
async test "WorkflowEngine retries a failing step and persists retry count" {
  @fsx.with_temporary_directory("job-workflow-retry-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workflow = WorkflowDefinition::{
      id: "workflow.retry",
      kind: "test",
      steps: [
        WorkflowStepDefinition::{
          id: "unstable",
          kind: "test.unstable",
          config: {},
          retry_policy: Some(RetryPolicy::{
            max_attempts: 2,
            backoff_ms: Some(0),
          }),
        },
      ],
      output_bindings: ["unstable"],
    }
    let engine = workflow_test_engine(root, workflow)
    let attempts : Ref[Int] = { val: 0 }
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.unstable", run=fn(_context) {
        attempts.val = attempts.val + 1
        if attempts.val == 1 {
          Err("first failure")
        } else {
          Ok(
            WorkflowStepResult::new(
              output={ "attempt": attempts.val },
              summary=Some("recovered"),
              logs=["recovered"],
            ),
          )
        }
      }),
    )

    let result = match engine.execute_run("run-workflow-1", fn() { 2000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(attempts.val, content="2")
    inspect(result.steps[0].retry_count, content="1")
    inspect(result.steps[0].summary.unwrap_or(""), content="recovered")
  })
}

///|
async test "WorkflowEngine fails the run when a step exhausts retries" {
  @fsx.with_temporary_directory("job-workflow-fail-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workflow = WorkflowDefinition::{
      id: "workflow.fail",
      kind: "test",
      steps: [
        WorkflowStepDefinition::{
          id: "broken",
          kind: "test.broken",
          config: {},
          retry_policy: Some(RetryPolicy::{
            max_attempts: 2,
            backoff_ms: Some(0),
          }),
        },
      ],
      output_bindings: [],
    }
    let engine = workflow_test_engine(root, workflow)
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.broken", run=fn(_context) {
        Err("still broken")
      }),
    )

    let result = engine.execute_run("run-workflow-1", fn() { 3000 })
    inspect(result is Err("still broken"), content="true")
    let failed_run = match engine.runtime.store().get_run("run-workflow-1") {
      Some(run) => run
      None => fail("missing failed run")
    }
    inspect(failed_run.status.to_json().stringify(), content="\"Failed\"")
    let failed_step = match
      engine.runtime.store().get_step_run("run-workflow-1", "broken") {
      Some(step) => step
      None => fail("missing failed step")
    }
    inspect(failed_step.retry_count, content="2")
    inspect(failed_step.status.to_json().stringify(), content="\"Failed\"")
  })
}

///|
async test "WorkflowEngine cancels before the next step when control requests stop" {
  @fsx.with_temporary_directory("job-workflow-cancel-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workflow = WorkflowDefinition::{
      id: "workflow.cancel",
      kind: "test",
      steps: [
        WorkflowStepDefinition::{
          id: "first",
          kind: "test.first",
          config: {},
          retry_policy: None,
        },
        WorkflowStepDefinition::{
          id: "second",
          kind: "test.second",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: [],
    }
    let engine = workflow_test_engine(root, workflow)
    let calls : Ref[Int] = { val: 0 }
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.first", run=fn(_context) {
        calls.val = calls.val + 1
        Ok(WorkflowStepResult::new(output={ "ok": true }))
      }),
    )
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.second", run=fn(_context) {
        calls.val = calls.val + 1
        Ok(WorkflowStepResult::new(output={ "ok": true }))
      }),
    )
    let control = WorkflowExecutionControl::new(should_cancel=fn() {
      calls.val >= 1
    })

    let result = engine.execute_run("run-workflow-1", fn() { 4000 }, control~)
    inspect(result is Err("Workflow cancelled"), content="true")
    let cancelled_run = match engine.runtime.store().get_run("run-workflow-1") {
      Some(run) => run
      None => fail("missing cancelled run")
    }
    inspect(cancelled_run.status.to_json().stringify(), content="\"Cancelled\"")
    inspect(calls.val, content="1")
  })
}
