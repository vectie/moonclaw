///|
test "draft_job_proposal creates non-executing draft with steps" {
  let proposal = draft_job_proposal(
    "proposal-1",
    "Track arXiv papers about agent systems and summarize them.",
    100,
    channel_id=Some("feishu"),
    account_id=Some("default"),
    recipient=Some("oc_chat_123"),
  )
  inspect(proposal.status.to_json().stringify(), content="\"Draft\"")
  inspect(proposal.steps.length() > 0, content="true")
  inspect(proposal.tags.contains("monitoring"), content="true")
  inspect(proposal.suggested_family.unwrap_or(""), content="generic")
  inspect(proposal.job_id is None, content="true")
}

///|
async test "plan_job_proposal applies configured controller profile steps" {
  @fsx.with_temporary_directory("job-proposal-profile-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_profiles_json().stringify(),
    )
    let proposal = plan_job_proposal(
      "proposal-profile-1",
      "Research VLA papers and test new hypotheses.",
      100,
      executor=fake_planner_executor(
        "{\"title\":\"Research VLA papers\",\"summary\":\"Investigate papers and hypotheses.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"draft\",\"title\":\"Draft\",\"prompt\":\"Draft a plan.\",\"kind\":\"job.analysis\"}]}",
      ),
      cwd=dir,
      home=Some(dir),
      workspace=Some(dir),
    )
    inspect(
      proposal.suggested_family.unwrap_or(""),
      content="research_controller",
    )
    inspect(proposal.steps.length(), content="2")
    inspect(proposal.steps[0].kind, content="job.delegate")
    inspect(proposal.steps[1].kind, content="job.analysis")
  })
}

///|
test "proposal_as_workflow builds generic analysis workflow with notify config" {
  let proposal = draft_job_proposal(
    "proposal-2",
    "Prepare a code review job for a large repository.",
    100,
    channel_id=Some("feishu"),
    account_id=Some("default"),
    recipient=Some("oc_chat_123"),
    thread_id=Some("om_thread_1"),
  )
  let (definition, workflow) = proposal_as_workflow(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(definition.kind, content="job.proposal")
  inspect(workflow.steps.length(), content="1")
  inspect(workflow.steps[0].kind, content="job.analysis")
  inspect(definition.config.stringify().contains("\"notify\""), content="true")
}

///|
fn fake_planner_executor(content : String) -> AnalysisExecutor {
  AnalysisExecutor::new(run=fn(_request) {
    Ok(AnalysisExecution::{
      model_name: "default",
      content,
      conversation_id: None,
      usage: None,
      metadata: {},
    })
  })
}

///|
fn mapped_controller_profile_json() -> Json {
  {
    "jobs": {
      "profiles": {
        "generic_controller": {
          "family": "generic_controller",
          "role": "controller",
          "priority": 100,
          "match": { "any": ["controller", "evaluate", "hypothesis"] },
          "steps": [
            {
              "id": "evaluate",
              "title": "Evaluate outcome",
              "kind": "test.evaluate",
              "prompt_template": "Evaluate ${request}",
            },
          ],
          "metadata": {
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
      },
    },
  }
}

///|
async test "plan_job_proposal uses model JSON when available" {
  let proposal = plan_job_proposal(
    "proposal-3",
    "Create a weekly monitoring job.",
    100,
    executor=fake_planner_executor(
      "{\"title\":\"Weekly monitor\",\"summary\":\"Monitor and summarize new items weekly.\",\"tags\":[\"job\",\"weekly\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Collect items\",\"prompt\":\"Collect the newest items.\",\"kind\":\"job.analysis\"},{\"id\":\"summarize\",\"title\":\"Summarize findings\",\"prompt\":\"Summarize the collected items.\",\"kind\":\"job.analysis\"}]}",
    ),
    channel_id=Some("feishu"),
    account_id=Some("default"),
    recipient=Some("oc_chat_123"),
  )
  inspect(proposal.title, content="Weekly monitor")
  inspect(proposal.steps.length(), content="2")
  inspect(proposal.steps[0].id, content="collect")
  inspect(proposal.tags.join(","), content="job,weekly")
}

///|
async test "profile json drives controller policy through compilation into runtime" {
  @fsx.with_temporary_directory("job-proposal-controller-runtime-XXXXXX", async fn(
    dir,
  ) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      mapped_controller_profile_json().stringify(),
    )
    let proposal = plan_job_proposal(
      "proposal-controller-runtime-1",
      "Evaluate controller output and branch to a next hypothesis.",
      100,
      executor=fake_planner_executor(
        "{\"title\":\"Controller eval\",\"summary\":\"Use the controller profile.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"draft\",\"title\":\"Draft\",\"prompt\":\"Draft.\",\"kind\":\"job.analysis\"}]}",
      ),
      cwd=dir,
      home=Some(dir),
      workspace=Some(dir),
    )
    inspect(proposal.profile_role.unwrap_or(""), content="controller")
    inspect(
      proposal.profile_metadata.stringify().contains("next_iteration_fields"),
      content="true",
    )

    let compilation = compile_job_proposal(
      proposal,
      101,
      dir,
      dir,
      workspace_root=dir,
    )
    inspect(compilation.definition.kind, content="job.controller")

    let runtime = RuntimeManager::new(root=@pathx.join(dir, "jobs"))
    runtime.register_definition(compilation.definition)
    runtime.register_workflow(compilation.workflow)
    let run = match
      runtime.trigger_definition(
        "run-controller-runtime-1",
        compilation.definition.id,
        TriggerSource::Manual,
        200,
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
              "key": "iter-profile-mapped",
              "label": "Mapped from profile",
              "idea": "Use fields declared in profile metadata.",
              "relation": "refines",
              "extras": { "source": "profile-json" },
            },
          }),
        )
      }),
    )
    let result = match engine.execute_run(run.id, fn() { 300 }) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    inspect(result.run.status.to_json().stringify(), content="\"Succeeded\"")
    let next_iteration = match
      runtime.store().get_controller_iteration("iter-profile-mapped") {
      Some(iteration) => iteration
      None => fail("missing mapped iteration from profile")
    }
    inspect(next_iteration.title, content="Mapped from profile")
    inspect(
      next_iteration.hypothesis,
      content="Use fields declared in profile metadata.",
    )
  })
}

///|
async test "plan_job_proposal includes relevant memory context in planner prompt" {
  let proposal = plan_job_proposal(
    "proposal-memory-1",
    "Create a weekly monitoring job.",
    100,
    executor=AnalysisExecutor::new(run=fn(request) {
      let marker = request.prompt.contains("Relevant long-term memory")
      let note = request.prompt.contains(
        "Prefer VLA papers and weekday digests.",
      )
      Ok(AnalysisExecution::{
        model_name: "default",
        content: if marker && note {
          "{\"title\":\"Memory-aware plan\",\"summary\":\"Planner used memory context.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Collect\",\"prompt\":\"Collect.\",\"kind\":\"job.analysis\"}]}"
        } else {
          "{\"title\":\"Missing memory\",\"summary\":\"Planner missed memory context.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Collect\",\"prompt\":\"Collect.\",\"kind\":\"job.analysis\"}]}"
        },
        conversation_id: None,
        usage: None,
        metadata: {},
      })
    }),
    memory_context=Some(
      "Relevant long-term memory:\n- [memory-1] note\n  Prefer VLA papers and weekday digests.",
    ),
  )
  inspect(proposal.title, content="Memory-aware plan")
}

///|
async test "revise_job_proposal updates draft from model JSON" {
  let proposal = draft_job_proposal(
    "proposal-4", "Review a repository and produce findings.", 100,
  )
  let revised = revise_job_proposal(
    proposal,
    "Focus on security and deployment risks.",
    120,
    executor=fake_planner_executor(
      "{\"title\":\"Security-focused repo review\",\"summary\":\"Review with emphasis on security and deployment.\",\"tags\":[\"job\",\"review\",\"security\"],\"steps\":[{\"id\":\"inspect\",\"title\":\"Inspect code paths\",\"prompt\":\"Inspect risky paths.\",\"kind\":\"job.analysis\"},{\"id\":\"report\",\"title\":\"Report findings\",\"prompt\":\"Report security and deployment findings.\",\"kind\":\"job.analysis\"}]}",
    ),
  )
  inspect(revised.title, content="Security-focused repo review")
  inspect(revised.steps.length(), content="2")
  inspect(revised.summary.contains("security"), content="true")
  inspect(
    revised.revision_history.join("|"),
    content="Focus on security and deployment risks.",
  )
}

///|
async test "revise_job_proposal includes memory context in revise prompt" {
  let proposal = draft_job_proposal(
    "proposal-memory-2", "Review a repository and produce findings.", 100,
  )
  let revised = revise_job_proposal(
    proposal,
    "Focus on deployment risks.",
    120,
    executor=AnalysisExecutor::new(run=fn(request) {
      let marker = request.prompt.contains("Relevant long-term memory")
      let note = request.prompt.contains(
        "Deployment changes need rollback notes.",
      )
      Ok(AnalysisExecution::{
        model_name: "default",
        content: if marker && note {
          "{\"title\":\"Memory-aware revise\",\"summary\":\"Revision used memory context.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"inspect\",\"title\":\"Inspect\",\"prompt\":\"Inspect.\",\"kind\":\"job.analysis\"}]}"
        } else {
          "{\"title\":\"Missing revise memory\",\"summary\":\"Revision missed memory context.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"inspect\",\"title\":\"Inspect\",\"prompt\":\"Inspect.\",\"kind\":\"job.analysis\"}]}"
        },
        conversation_id: None,
        usage: None,
        metadata: {},
      })
    }),
    memory_context=Some(
      "Relevant long-term memory:\n- [memory-2] note\n  Deployment changes need rollback notes.",
    ),
  )
  inspect(revised.title, content="Memory-aware revise")
}

///|
async test "revise_job_proposal carries prior revision history into later revisions" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-5", "Review a repository.", 100),
    revision_history: ["focus on security"],
  }
  let revised = revise_job_proposal(
    proposal,
    "also cover deployment risks",
    120,
    executor=fake_planner_executor(
      "{\"title\":\"Security and deployment review\",\"summary\":\"Review with both security and deployment focus.\",\"tags\":[\"job\",\"review\"],\"steps\":[{\"id\":\"inspect\",\"title\":\"Inspect code\",\"prompt\":\"Inspect risky code.\",\"kind\":\"job.analysis\"}]}",
    ),
  )
  inspect(
    revised.revision_history.join("|"),
    content="focus on security|also cover deployment risks",
  )
}

///|
test "proposal_as_workflow preserves generic drafts as direct proposal workflows" {
  let proposal = draft_job_proposal(
    "proposal-6",
    "Review yesterday's VLA arxiv papers and send me a daily digest.",
    100,
    channel_id=Some("feishu"),
    account_id=Some("default"),
    recipient=Some("oc_chat_123"),
  )
  let (definition, workflow) = proposal_as_workflow(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(definition.kind, content="job.proposal")
  inspect(workflow.steps.length(), content="1")
  inspect(workflow.steps[0].kind, content="job.analysis")
  inspect(
    definition.config.stringify().contains("\"family\":\"generic\""),
    content="true",
  )
}

///|
test "render_job_proposal_for_chat includes proposal steps" {
  let proposal = draft_job_proposal(
    "proposal-7", "Compare each paper and break down subtasks.", 100,
  )
  let rendered = render_job_proposal_for_chat(proposal)
  inspect(rendered.contains("Planned steps:"), content="true")
  inspect(rendered.contains("execute"), content="true")
}

///|
test "ensure_draft_proposal rejects non-draft proposals" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-8", "Track papers.", 100),
    status: Confirmed,
  }
  inspect(
    ensure_draft_proposal(proposal, "proposal-8").unwrap_or(""),
    content="Proposal proposal-8 is already \"Confirmed\"",
  )
}

///|
async test "save_confirmed_job_proposal persists confirmed status and run id" {
  @fsx.with_temporary_directory("job-proposal-confirm-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let proposal = draft_job_proposal("proposal-9", "Track VLA papers.", 100)
    let compilation = compile_job_proposal(
      proposal, 101, "/tmp/workspace", "/tmp/home",
    )
    save_confirmed_job_proposal(store, proposal, compilation, "run-9", 200)
    let saved = store.get_job_proposal("proposal-9")
    inspect(
      saved.map(fn(p) { p.status.to_json().stringify() }).unwrap_or(""),
      content="\"Confirmed\"",
    )
    inspect(
      saved.map(fn(p) { p.last_run_id.unwrap_or("") }).unwrap_or(""),
      content="run-9",
    )
  })
}

///|
async test "save_rejected_job_proposal persists rejected status" {
  @fsx.with_temporary_directory("job-proposal-reject-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let proposal = draft_job_proposal("proposal-10", "Review repository.", 100)
    save_rejected_job_proposal(store, proposal, 200)
    inspect(
      store
      .get_job_proposal("proposal-10")
      .map(fn(p) { p.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Rejected\"",
    )
  })
}
