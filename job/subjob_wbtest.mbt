///|
async test "subjob_step_handler creates a child run with lineage and executes it" {
  @fsx.with_temporary_directory("job-subjob-handler-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let parent_workflow = WorkflowDefinition::{
      id: "workflow.parent",
      kind: "test",
      steps: [
        WorkflowStepDefinition::{
          id: "delegate",
          kind: "job.delegate",
          config: SubjobStepConfig::new(request_text="run child analysis").to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["delegate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.parent",
      kind: "test.parent",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some(parent_workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["test"],
    })
    runtime.register_workflow(parent_workflow)
    runtime
    .store()
    .save_run(JobRun::{
      id: "run-parent-1",
      job_id: "job.parent",
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
    })

    let planner = ProposalPlanner::new(run=fn(request_text, _cwd, _home) {
      draft_job_proposal("proposal-child-1", request_text, 100)
    })
    let compiler = ProposalCompiler::new(run=fn(
      _proposal,
      now_ms,
      _cwd,
      _home,
    ) {
      let workflow = WorkflowDefinition::{
        id: "workflow.child",
        kind: "test.child",
        steps: [
          WorkflowStepDefinition::{
            id: "child-step",
            kind: "test.child",
            config: {},
            retry_policy: None,
          },
        ],
        output_bindings: ["child-step"],
      }
      let definition = JobDefinition::{
        id: "job.child",
        kind: "test.child",
        enabled: true,
        config: { "family": "generic" },
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: "generic",
        definition,
        workflow,
        bindings: [],
      }
    })
    let child_engine_factory = fn() {
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="test.child", run=fn(_context) {
          Ok(WorkflowStepResult::new(output={ "value": 42 }))
        }),
      )
      engine
    }
    let engine = WorkflowEngine::new(runtime~)
    engine.register_handler(
      subjob_step_handler(
        runtime~,
        planner~,
        compiler~,
        engine_factory=child_engine_factory,
        next_run_id=fn() { "run-child-1" },
      ),
    )

    let result = match engine.execute_run("run-parent-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("delegate")
      .map(fn(output) {
        output.stringify().contains("\"child_run_id\":\"run-child-1\"")
      })
      .unwrap_or(false),
      content="true",
    )
    let child_run = match runtime.store().get_run("run-child-1") {
      Some(run) => run
      None => fail("missing child run")
    }
    inspect(child_run.parent_run_id.unwrap_or(""), content="run-parent-1")
    inspect(child_run.parent_step_id.unwrap_or(""), content="delegate")
    inspect(child_run.depth, content="1")
    inspect(child_run.status.to_json().stringify(), content="\"Succeeded\"")
  })
}

///|
async test "controller delegate step records iteration state and child lineage" {
  @fsx.with_temporary_directory("job-subjob-controller-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let parent_workflow = WorkflowDefinition::{
      id: "workflow.controller.parent",
      kind: "job.controller",
      steps: [
        WorkflowStepDefinition::{
          id: "delegate",
          kind: "job.delegate",
          config: SubjobStepConfig::new(request_text="run child analysis").to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["delegate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.controller.parent",
      kind: "job.controller",
      enabled: true,
      config: { "family": "generic_controller", "role": "controller" },
      schedule: None,
      retry_policy: None,
      workflow_id: Some(parent_workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["controller"],
    })
    runtime.register_workflow(parent_workflow)
    let parent_run = match
      runtime.trigger_definition(
        "run-controller-parent-1",
        "job.controller.parent",
        TriggerSource::Manual,
        100,
      ) {
      Ok(run) => run
      Err(error) => fail(error)
    }

    let planner = ProposalPlanner::new(run=fn(request_text, _cwd, _home) {
      draft_job_proposal("proposal-controller-child-1", request_text, 100)
    })
    let compiler = ProposalCompiler::new(run=fn(
      _proposal,
      now_ms,
      _cwd,
      _home,
    ) {
      let workflow = WorkflowDefinition::{
        id: "workflow.controller.child",
        kind: "test.child",
        steps: [
          WorkflowStepDefinition::{
            id: "child-step",
            kind: "test.child",
            config: {},
            retry_policy: None,
          },
        ],
        output_bindings: ["child-step"],
      }
      let definition = JobDefinition::{
        id: "job.controller.child",
        kind: "test.child",
        enabled: true,
        config: { "family": "generic" },
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: "generic",
        definition,
        workflow,
        bindings: [],
      }
    })
    let child_engine_factory = fn() {
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="test.child", run=fn(_context) {
          Ok(WorkflowStepResult::new(output={ "value": 42 }))
        }),
      )
      engine
    }
    let engine = WorkflowEngine::new(runtime~)
    engine.register_handler(
      subjob_step_handler(
        runtime~,
        planner~,
        compiler~,
        engine_factory=child_engine_factory,
        next_run_id=fn() { "run-controller-child-1" },
      ),
    )

    let result = match engine.execute_run(parent_run.id, fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let state = match runtime.store().get_controller_state(parent_run.id) {
      Some(state) => state
      None => fail("missing controller state")
    }
    inspect(
      state.accepted_iteration_ids.join(","),
      content="run-controller-parent-1:iter:delegate",
    )
    inspect(
      state.best_iteration_id.unwrap_or(""),
      content="run-controller-parent-1:iter:delegate",
    )
    let iteration = match
      runtime
      .store()
      .get_controller_iteration("run-controller-parent-1:iter:delegate") {
      Some(iteration) => iteration
      None => fail("missing delegate iteration")
    }
    inspect(iteration.status, content="completed")
    inspect(iteration.child_run_ids.join(","), content="run-controller-child-1")
    inspect(iteration.child_job_ids.join(","), content="job.controller.child")
    let root_iteration = match
      runtime
      .store()
      .get_controller_iteration("run-controller-parent-1:iter:root") {
      Some(iteration) => iteration
      None => fail("missing root iteration")
    }
    inspect(root_iteration.status, content="completed")
    inspect(
      runtime
      .store()
      .list_controller_lineage_edges(
        controller_job_id=Some("job.controller.parent"),
      )
      .length(),
      content="1",
    )
  })
}

///|
async test "subjob_step_handler applies explicit child profile to the planned child job" {
  @fsx.with_temporary_directory("job-subjob-child-profile-XXXXXX", dir => {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      (
        {
          "jobs": {
            "profiles": {
              "opc_impl_worker": {
                "family": "opc_impl_worker",
                "tags": ["opc", "worker", "implementation"],
                "steps": [
                  {
                    "id": "implement",
                    "title": "Implement requested change",
                    "kind": "job.analysis",
                    "prompt_template": "Implement worker request: ${request}",
                    "metadata": {
                      "preferred_skills": ["opc-eng"],
                      "enable_tools": true,
                    },
                  },
                ],
              },
            },
          },
        } : Json).stringify(),
    )
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let parent_workflow = WorkflowDefinition::{
      id: "workflow.parent",
      kind: "test",
      steps: [
        WorkflowStepDefinition::{
          id: "delegate",
          kind: "job.delegate",
          config: SubjobStepConfig::new(
            request_text="run child implementation",
            cwd=Some(dir),
            home=Some(dir),
            child_profile=Some("opc_impl_worker"),
            execution_mode=Some("acp"),
            execution_target=Some("codex-impl"),
          ).to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["delegate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.parent",
      kind: "test.parent",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some(parent_workflow.id),
      created_at: 1,
      updated_at: 1,
      tags: ["test"],
    })
    runtime.register_workflow(parent_workflow)
    runtime
    .store()
    .save_run(JobRun::{
      id: "run-parent-profile-1",
      job_id: "job.parent",
      trigger: TriggerSource::Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some(dir),
      status: RunStatus::Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      completed_at: None,
      summary: None,
      error: None,
    })

    let planner = ProposalPlanner::new(run=fn(request_text, _cwd, _home) {
      draft_job_proposal("proposal-child-profile-1", request_text, 100)
    })
    let captured_family : Ref[String] = { val: "" }
    let captured_profile_id : Ref[String] = { val: "" }
    let captured_step_count : Ref[Int] = { val: 0 }
    let captured_step_title : Ref[String] = { val: "" }
    let captured_skill_present : Ref[Bool] = { val: false }
    let captured_execution_mode : Ref[String] = { val: "" }
    let captured_execution_target : Ref[String] = { val: "" }
    let compiler = ProposalCompiler::new(run=fn(proposal, now_ms, _cwd, _home) {
      captured_family.val = proposal.suggested_family.unwrap_or("")
      captured_profile_id.val = proposal.profile_id.unwrap_or("")
      captured_step_count.val = proposal.steps.length()
      captured_step_title.val = proposal.steps[0].title
      captured_skill_present.val = proposal.steps[0].metadata
        .stringify()
        .contains("\"opc-eng\"")
      captured_execution_mode.val = match proposal.profile_metadata {
        { "execution": { "mode": String(mode), .. }, .. } => mode
        _ => ""
      }
      captured_execution_target.val = match proposal.profile_metadata {
        { "execution": { "target": String(target), .. }, .. } => target
        _ => ""
      }
      let workflow = WorkflowDefinition::{
        id: "workflow.child.profile",
        kind: "test.child",
        steps: [
          WorkflowStepDefinition::{
            id: "child-step",
            kind: "test.child",
            config: {},
            retry_policy: None,
          },
        ],
        output_bindings: ["child-step"],
      }
      let definition = JobDefinition::{
        id: "job.child.profile",
        kind: "test.child",
        enabled: true,
        config: { "family": proposal.suggested_family.unwrap_or("generic") },
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: proposal.suggested_family.unwrap_or("generic"),
        definition,
        workflow,
        bindings: [],
      }
    })
    let child_engine_factory = fn() {
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="test.child", run=fn(_context) {
          Ok(WorkflowStepResult::new(output={ "value": "ok" }))
        }),
      )
      engine
    }
    let engine = WorkflowEngine::new(runtime~)
    engine.register_handler(
      subjob_step_handler(
        runtime~,
        planner~,
        compiler~,
        engine_factory=child_engine_factory,
        next_run_id=fn() { "run-child-profile-1" },
      ),
    )

    let result = match
      engine.execute_run("run-parent-profile-1", fn() { 1000 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(captured_family.val, content="opc_impl_worker")
    inspect(captured_profile_id.val, content="opc_impl_worker")
    inspect(captured_step_count.val, content="1")
    inspect(captured_step_title.val, content="Implement requested change")
    inspect(captured_skill_present.val, content="true")
    inspect(captured_execution_mode.val, content="acp")
    inspect(captured_execution_target.val, content="codex-impl")
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    inspect(
      result.outputs
      .get("delegate")
      .map(fn(output) {
        output.stringify().contains("\"child_family\":\"opc_impl_worker\"")
      })
      .unwrap_or(false),
      content="true",
    )
  })
}
