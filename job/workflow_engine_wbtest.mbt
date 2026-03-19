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
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
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
async test "WorkflowEngine persists controller decisions from step output when policy allows it" {
  @fsx.with_temporary_directory("job-workflow-controller-decision-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let workflow = WorkflowDefinition::{
      id: "workflow.controller.decision",
      kind: "job.controller",
      steps: [
        WorkflowStepDefinition::{
          id: "evaluate",
          kind: "test.evaluate",
          config: { "prompt": "Evaluate the current result." },
          retry_policy: None,
        },
      ],
      output_bindings: ["evaluate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.workflow.controller",
      kind: "job.controller",
      enabled: true,
      config: {
        "family": "generic_controller",
        "role": "controller",
        "profile_metadata": {
          "controller_policy": {
            "acceptance_source": "step_output",
            "result_schema": "generic/controller_decision.v1",
          },
        },
      },
      schedule: None,
      retry_policy: None,
      workflow_id: Some(workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["controller"],
    })
    runtime.register_workflow(workflow)
    let run = match
      runtime.trigger_definition(
        "run-workflow-controller-1",
        "job.workflow.controller",
        TriggerSource::Manual,
        100,
      ) {
      Ok(run) => run
      Err(error) => fail(error)
    }
    let engine = WorkflowEngine::new(runtime~)
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.evaluate", run=fn(_context) {
        Ok(
          WorkflowStepResult::new(output={
            "summary": "accepted",
            "controller_decision": {
              "verdict": "accept",
              "reason": "The result meets the current bar.",
              "next_action": "branch",
              "next_iteration": {
                "title": "Explore follow-up",
                "hypothesis": "Try an adjacent strategy.",
                "edge_kind": "branches",
                "metadata": { "source": "analysis" },
              },
            },
          }),
        )
      }),
    )

    let result = match engine.execute_run(run.id, fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let decision = match
      runtime
      .store()
      .get_controller_decision("run-workflow-controller-1:decision:evaluate") {
      Some(decision) => decision
      None => fail("missing controller decision")
    }
    inspect(decision.verdict, content="accept")
    inspect(decision.next_action.unwrap_or(""), content="branch")
    inspect(
      decision.metadata.stringify().contains("generic/controller_decision.v1"),
      content="true",
    )
    let next_iteration = match
      runtime
      .store()
      .get_controller_iteration("run-workflow-controller-1:iter:evaluate:next") {
      Some(iteration) => iteration
      None => fail("missing next iteration")
    }
    inspect(next_iteration.status, content="pending")
    inspect(
      next_iteration.parent_iteration_id.unwrap_or(""),
      content="run-workflow-controller-1:iter:evaluate",
    )
    inspect(
      runtime
      .store()
      .list_controller_decisions(controller_run_id=Some(run.id))
      .length(),
      content="1",
    )
  })
}

///|
async test "WorkflowEngine accepts looser controller decision output shapes" {
  @fsx.with_temporary_directory(
    "job-workflow-controller-decision-loose-XXXXXX",
    dir => {
      let root = @pathx.join(dir, "jobs")
      let runtime = RuntimeManager::new(root~)
      let workflow = WorkflowDefinition::{
        id: "workflow.controller.decision.loose",
        kind: "job.controller",
        steps: [
          WorkflowStepDefinition::{
            id: "evaluate",
            kind: "test.evaluate",
            config: { "prompt": "Evaluate the current result." },
            retry_policy: None,
          },
        ],
        output_bindings: ["evaluate"],
      }
      runtime.register_definition(JobDefinition::{
        id: "job.workflow.controller.loose",
        kind: "job.controller",
        enabled: true,
        config: {
          "family": "generic_controller",
          "role": "controller",
          "profile_metadata": {
            "controller_policy": {
              "result_schema": "generic/controller_decision.v1",
            },
          },
        },
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: 1,
        updated_at: 1,
        tags: ["controller"],
      })
      runtime.register_workflow(workflow)
      let run = match
        runtime.trigger_definition(
          "run-workflow-controller-loose-1",
          "job.workflow.controller.loose",
          TriggerSource::Manual,
          100,
        ) {
        Ok(run) => run
        Err(error) => fail(error)
      }
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="test.evaluate", run=fn(_context) {
          Ok(
            WorkflowStepResult::new(output={
              "decision": "accept",
              "summary": "The result is good enough.",
              "next": {
                "title": "Loose follow-up",
                "objective": "Try another adjacent path.",
              },
            }),
          )
        }),
      )

      let result = match engine.execute_run(run.id, fn() { 1000 }) {
        Ok(result) => result
        Err(error) => fail(error)
      }
      inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
      let decision = match
        runtime
        .store()
        .get_controller_decision(
          "run-workflow-controller-loose-1:decision:evaluate",
        ) {
        Some(decision) => decision
        None => fail("missing loose controller decision")
      }
      inspect(decision.verdict, content="accept")
      inspect(
        decision.reason.unwrap_or(""),
        content="The result is good enough.",
      )
      let next_iteration = match
        runtime
        .store()
        .get_controller_iteration(
          "run-workflow-controller-loose-1:iter:evaluate:next",
        ) {
        Some(iteration) => iteration
        None => fail("missing loose next iteration")
      }
      inspect(next_iteration.hypothesis, content="Try another adjacent path.")
    },
  )
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

///|
async test "WorkflowEngine warns on unexpected verdicts but still persists them" {
  @fsx.with_temporary_directory(
    "job-workflow-controller-verdict-warning-XXXXXX",
    dir => {
      let root = @pathx.join(dir, "jobs")
      let runtime = RuntimeManager::new(root~)
      let workflow = WorkflowDefinition::{
        id: "workflow.controller.verdict.warning",
        kind: "job.controller",
        steps: [
          WorkflowStepDefinition::{
            id: "evaluate",
            kind: "test.evaluate",
            config: { "prompt": "Evaluate the current result." },
            retry_policy: None,
          },
        ],
        output_bindings: ["evaluate"],
      }
      runtime.register_definition(JobDefinition::{
        id: "job.workflow.controller.warning",
        kind: "job.controller",
        enabled: true,
        config: {
          "family": "generic_controller",
          "role": "controller",
          "profile_metadata": {
            "controller_policy": {
              "allowed_verdicts": ["accept", "reject"],
              "verdict_aliases": { "keep": "accept" },
            },
          },
        },
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: 1,
        updated_at: 1,
        tags: ["controller"],
      })
      runtime.register_workflow(workflow)
      let keep_run = match
        runtime.trigger_definition(
          "run-workflow-controller-keep-1",
          "job.workflow.controller.warning",
          TriggerSource::Manual,
          100,
        ) {
        Ok(run) => run
        Err(error) => fail(error)
      }
      let weird_run = match
        runtime.trigger_definition(
          "run-workflow-controller-weird-1",
          "job.workflow.controller.warning",
          TriggerSource::Manual,
          100,
        ) {
        Ok(run) => run
        Err(error) => fail(error)
      }
      let keep_engine = WorkflowEngine::new(runtime~)
      keep_engine.register_handler(
        WorkflowStepHandler::new(kind="test.evaluate", run=fn(_context) {
          Ok(WorkflowStepResult::new(output={ "decision": "keep" }))
        }),
      )
      let weird_engine = WorkflowEngine::new(runtime~)
      weird_engine.register_handler(
        WorkflowStepHandler::new(kind="test.evaluate", run=fn(_context) {
          Ok(
            WorkflowStepResult::new(output={
              "decision": "escalate",
              "summary": "Need operator review.",
            }),
          )
        }),
      )

      ignore(
        match keep_engine.execute_run(keep_run.id, fn() { 1000 }) {
          Ok(result) => result
          Err(error) => fail(error)
        },
      )
      ignore(
        match weird_engine.execute_run(weird_run.id, fn() { 1000 }) {
          Ok(result) => result
          Err(error) => fail(error)
        },
      )

      let keep_decision = match
        runtime
        .store()
        .get_controller_decision(
          "run-workflow-controller-keep-1:decision:evaluate",
        ) {
        Some(decision) => decision
        None => fail("missing keep decision")
      }
      inspect(keep_decision.verdict, content="accept")
      inspect(
        keep_decision.metadata.stringify().contains("\"warning\""),
        content="false",
      )

      let weird_decision = match
        runtime
        .store()
        .get_controller_decision(
          "run-workflow-controller-weird-1:decision:evaluate",
        ) {
        Some(decision) => decision
        None => fail("missing weird decision")
      }
      inspect(weird_decision.verdict, content="escalate")
      inspect(
        weird_decision.metadata.stringify().contains("allowed_verdicts"),
        content="true",
      )
    },
  )
}

///|
async test "WorkflowEngine uses configured next_iteration field mappings" {
  @fsx.with_temporary_directory("job-workflow-controller-next-mapping-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let workflow = WorkflowDefinition::{
      id: "workflow.controller.next.mapping",
      kind: "job.controller",
      steps: [
        WorkflowStepDefinition::{
          id: "evaluate",
          kind: "test.evaluate",
          config: { "prompt": "Evaluate the current result." },
          retry_policy: None,
        },
      ],
      output_bindings: ["evaluate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.workflow.controller.next.mapping",
      kind: "job.controller",
      enabled: true,
      config: {
        "family": "generic_controller",
        "role": "controller",
        "profile_metadata": {
          "controller_policy": {
            "next_iteration_fields": {
              "title": "label",
              "hypothesis": "idea",
              "id": "key",
              "edge_kind": "relation",
              "metadata": "extras",
            },
          },
        },
      },
      schedule: None,
      retry_policy: None,
      workflow_id: Some(workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["controller"],
    })
    runtime.register_workflow(workflow)
    let run = match
      runtime.trigger_definition(
        "run-workflow-controller-mapped-1",
        "job.workflow.controller.next.mapping",
        TriggerSource::Manual,
        100,
      ) {
      Ok(run) => run
      Err(error) => fail(error)
    }
    let engine = WorkflowEngine::new(runtime~)
    engine.register_handler(
      WorkflowStepHandler::new(kind="test.evaluate", run=fn(_context) {
        Ok(
          WorkflowStepResult::new(output={
            "decision": "accept",
            "next": {
              "key": "iter-custom",
              "label": "Mapped follow-up",
              "idea": "Use alternate mapped fields.",
              "relation": "refines",
              "extras": { "source": "mapped" },
            },
          }),
        )
      }),
    )

    let result = match engine.execute_run(run.id, fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let next_iteration = match
      runtime.store().get_controller_iteration("iter-custom") {
      Some(iteration) => iteration
      None => fail("missing mapped next iteration")
    }
    inspect(next_iteration.title, content="Mapped follow-up")
    inspect(next_iteration.hypothesis, content="Use alternate mapped fields.")
    inspect(
      runtime
      .store()
      .list_controller_lineage_edges(
        controller_job_id=Some("job.workflow.controller.next.mapping"),
      )
      .map(fn(edge) { edge.edge_kind })
      .join(","),
      content="step,refines",
    )
  })
}
