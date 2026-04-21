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
      finished_at: None,
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
    let parent_events = runtime.store().list_run_events("run-parent-1")
    inspect(
      parent_events.map(fn(event) { event.event_type }).join(","),
      content="job.started,step.started,child_run.started,child_run.succeeded,step.succeeded,job.completed",
    )
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
      finished_at: None,
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
    let captured_step_metadata : Ref[String] = { val: "" }
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
      captured_step_metadata.val = proposal.steps[0].metadata.stringify()
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
    inspect(captured_step_metadata.val.contains("git_worktree"), content="true")
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

///|
test "proposal execution override keeps resolved provider target for provider subjobs" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-provider-target-1", "run provider task", 100),
    profile_metadata: {
      "execution": { "mode": "provider", "target": "wiki-main" },
    },
  }
  let config = SubjobStepConfig::new(
    request_text="run provider task",
    execution_mode=Some("provider"),
    execution_target=Some("moonbook"),
  )
  let (mode, target) = proposal_execution_override(proposal, config)
  inspect(mode.unwrap_or(""), content="provider")
  inspect(target.unwrap_or(""), content="wiki-main")
}

///|
async test "subjob_step_handler propagates missing-input policy into child proposal" {
  @fsx.with_temporary_directory("job-subjob-policy-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      dir |> @pathx.join("moonclaw.jobs.json"),
      (
        #|{
        #|  "jobs": {
        #|    "profiles": {
        #|      "wiki_gather_worker": {
        #|        "family": "wiki_gather_worker",
        #|        "steps": [
        #|          {
        #|            "id": "gather_materials",
        #|            "title": "Gather source materials",
        #|            "kind": "job.analysis",
        #|            "prompt_template": "Gather for ${request}",
        #|            "metadata": {}
        #|          }
        #|        ],
        #|        "metadata": {}
        #|      }
        #|    }
        #|  }
        #|}
      ),
    )
    let runtime = RuntimeManager::new(root=dir)
    let parent_workflow = WorkflowDefinition::{
      id: "workflow.parent.policy",
      kind: "test.parent",
      steps: [
        WorkflowStepDefinition::{
          id: "delegate",
          kind: "job.delegate",
          config: SubjobStepConfig::new(
            request_text="collect source materials",
            cwd=Some(dir),
            home=Some(dir),
            child_profile=Some("wiki_gather_worker"),
          ).to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["delegate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.parent.policy",
      kind: "job.controller",
      enabled: true,
      config: {
        "profile_metadata": {
          "disable_waiting_for_input": true,
          "best_effort_on_missing_input": true,
        },
      },
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
      id: "run-parent-policy-1",
      job_id: "job.parent.policy",
      trigger: TriggerSource::Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some(dir),
      status: RunStatus::Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      finished_at: None,
      summary: None,
      error: None,
    })

    let planner = ProposalPlanner::new(run=fn(request_text, _cwd, _home) {
      draft_job_proposal("proposal-child-policy-1", request_text, 100)
    })
    let captured_profile_metadata : Ref[String] = { val: "" }
    let captured_step_metadata : Ref[String] = { val: "" }
    let compiler = ProposalCompiler::new(run=fn(proposal, now_ms, _cwd, _home) {
      captured_profile_metadata.val = proposal.profile_metadata.stringify()
      captured_step_metadata.val = proposal.steps[0].metadata.stringify()
      let workflow = WorkflowDefinition::{
        id: "workflow.child.policy",
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
        id: "job.child.policy",
        kind: "test.child",
        enabled: true,
        config: {},
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: "wiki_gather_worker",
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
        next_run_id=fn() { "run-child-policy-1" },
      ),
    )

    match engine.execute_run("run-parent-policy-1", fn() { 1000 }) {
      Ok(_) => ()
      Err(error) => fail(error)
    }
    inspect(
      captured_profile_metadata.val.contains(
        "\"disable_waiting_for_input\":true",
      ),
      content="true",
    )
    inspect(
      captured_profile_metadata.val.contains(
        "\"best_effort_on_missing_input\":true",
      ),
      content="true",
    )
    inspect(
      captured_step_metadata.val.contains("\"disable_waiting_for_input\":true"),
      content="true",
    )
    inspect(
      captured_step_metadata.val.contains(
        "\"best_effort_on_missing_input\":true",
      ),
      content="true",
    )
  })
}

///|
async test "subjob_step_handler fails when child run waits for input" {
  @fsx.with_temporary_directory("job-subjob-waiting-XXXXXX", async fn(dir) {
    let runtime = RuntimeManager::new(root=dir)
    let parent_workflow = WorkflowDefinition::{
      id: "workflow.parent.waiting",
      kind: "test.parent",
      steps: [
        WorkflowStepDefinition::{
          id: "delegate",
          kind: "job.delegate",
          config: SubjobStepConfig::new(
            request_text="run child gather",
            cwd=Some(dir),
            home=Some(dir),
          ).to_json(),
          retry_policy: None,
        },
      ],
      output_bindings: ["delegate"],
    }
    runtime.register_definition(JobDefinition::{
      id: "job.parent.waiting",
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
      id: "run-parent-waiting-1",
      job_id: "job.parent.waiting",
      trigger: TriggerSource::Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some(dir),
      status: RunStatus::Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      finished_at: None,
      summary: None,
      error: None,
    })

    let planner = ProposalPlanner::new(run=fn(request_text, _cwd, _home) {
      JobProposal::{
        ..draft_job_proposal("proposal-child-waiting-1", request_text, 100),
        suggested_family: Some("wiki_gather_worker"),
        steps: [
          JobProposalStep::{
            id: "gather_materials",
            title: "Gather source materials",
            prompt: request_text,
            kind: "needs.input",
            metadata: {},
            child_profile: None,
            execution_mode: None,
            execution_target: None,
            include_parent_outputs: None,
            max_depth: None,
          },
        ],
      }
    })
    let compiler = ProposalCompiler::new(run=fn(
      _proposal,
      now_ms,
      _cwd,
      _home,
    ) {
      let workflow = WorkflowDefinition::{
        id: "workflow.child.waiting",
        kind: "test.child",
        steps: [
          WorkflowStepDefinition::{
            id: "gather_materials",
            kind: "needs.input",
            config: {},
            retry_policy: None,
          },
        ],
        output_bindings: ["gather_materials"],
      }
      let definition = JobDefinition::{
        id: "job.child.waiting",
        kind: "test.child",
        enabled: true,
        config: {},
        schedule: None,
        retry_policy: None,
        workflow_id: Some(workflow.id),
        created_at: now_ms,
        updated_at: now_ms,
        tags: ["child"],
      }
      ProposalCompilation::{
        family: "wiki_gather_worker",
        definition,
        workflow,
        bindings: [],
      }
    })
    let child_engine_factory = fn() {
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="needs.input", run=fn(_context) {
          Err("Analysis requires input: missing raw sources")
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
        next_run_id=fn() { "run-child-waiting-1" },
      ),
    )

    let error = match
      engine.execute_run("run-parent-waiting-1", fn() { 1000 }) {
      Ok(_) => fail("expected waiting child run failure")
      Err(error) => error
    }
    inspect(error.contains("waiting for input"), content="true")
    inspect(error.contains("missing raw sources"), content="true")
  })
}
