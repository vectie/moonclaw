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
async test "plan_job_proposal includes decomposition guidance for land acquisition calculation" {
  let proposal = plan_job_proposal(
    "proposal-land-acquisition-1",
    "Land acquisition calculation",
    100,
    executor=AnalysisExecutor::new(run=fn(request) {
      let prompt = request.prompt
      let has_example = prompt.contains("Land acquisition calculation") &&
        prompt.contains("information collection") &&
        prompt.contains("risk assessment")
      Ok(AnalysisExecution::{
        model_name: "default",
        content: if has_example {
          "{\"title\":\"Land acquisition calculation\",\"summary\":\"Use a decomposed analytical plan.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Information collection\",\"prompt\":\"Collect the required data.\",\"kind\":\"job.analysis\"},{\"id\":\"design\",\"title\":\"Scheme design\",\"prompt\":\"Design the calculation scheme.\",\"kind\":\"job.analysis\"},{\"id\":\"estimate\",\"title\":\"Cost estimation\",\"prompt\":\"Estimate major costs.\",\"kind\":\"job.analysis\"},{\"id\":\"price\",\"title\":\"Marketing pricing\",\"prompt\":\"Estimate commercial pricing assumptions.\",\"kind\":\"job.analysis\"},{\"id\":\"finance\",\"title\":\"Financial analysis\",\"prompt\":\"Analyze the financial outcome.\",\"kind\":\"job.analysis\"},{\"id\":\"risk\",\"title\":\"Risk assessment\",\"prompt\":\"Review the main risks.\",\"kind\":\"job.analysis\"},{\"id\":\"report\",\"title\":\"Report generation\",\"prompt\":\"Generate the final report.\",\"kind\":\"job.analysis\"}]}"
        } else {
          "{\"title\":\"Missing guidance\",\"summary\":\"Prompt guidance missing.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"execute\",\"title\":\"Execute\",\"prompt\":\"Execute.\",\"kind\":\"job.analysis\"}]}"
        },
        conversation_id: None,
        usage: None,
        metadata: {},
      })
    }),
  )
  inspect(proposal.steps.length(), content="7")
  inspect(proposal.steps[0].title, content="Information collection")
  inspect(proposal.steps[5].title, content="Risk assessment")
  inspect(proposal.steps[6].title, content="Report generation")
}

///|
async test "plan_job_proposal loads skills/job-planning/SKILL.md when present" {
  @fsx.with_temporary_directory("job-proposal-planning-skill-XXXXXX", async fn(
    dir,
  ) {
    let skill_dir = @pathx.join(dir, "skills/job-planning")
    @fsx.make_directory(skill_dir, recursive=true)
    @fsx.write_to_file(
      @pathx.join(skill_dir, "SKILL.md"),
      [
        "---", "name: job-planning", "description: planning guidance", "---", "",
        "Planning skill marker: decompose analytical work into real phases.",
      ].join("\n"),
    )
    let proposal = plan_job_proposal(
      "proposal-planning-skill-1",
      "Land acquisition calculation",
      100,
      executor=AnalysisExecutor::new(run=fn(request) {
        let has_skill_name = request.preferred_skills
          .join(",")
          .contains("job-planning")
        let has_skill_content = request.prompt.contains(
          "Planning skill marker: decompose analytical work into real phases.",
        )
        Ok(AnalysisExecution::{
          model_name: "default",
          content: if has_skill_name && has_skill_content {
            "{\"title\":\"Skill-backed plan\",\"summary\":\"Planner loaded the planning skill.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Information collection\",\"prompt\":\"Collect the required inputs.\",\"kind\":\"job.analysis\"},{\"id\":\"report\",\"title\":\"Report generation\",\"prompt\":\"Generate the final report.\",\"kind\":\"job.analysis\"}]}"
          } else {
            "{\"title\":\"Missing skill\",\"summary\":\"Planner did not load the planning skill.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"execute\",\"title\":\"Execute\",\"prompt\":\"Execute.\",\"kind\":\"job.analysis\"}]}"
          },
          conversation_id: None,
          usage: None,
          metadata: {},
        })
      }),
      cwd=dir,
      home=Some(dir),
      workspace=Some(dir),
    )
    inspect(proposal.title, content="Skill-backed plan")
    inspect(proposal.steps.length(), content="2")
  })
}

///|
async test "plan_job_proposal reports invalid planner json in fallback summary" {
  let proposal = plan_job_proposal(
    "proposal-invalid-planner-json-1",
    "Land acquisition estimation",
    100,
    executor=fake_planner_executor(
      "Here is a plan:\n1. Collect inputs\n2. Analyze\n3. Report",
    ),
  )
  inspect(proposal.steps.length(), content="1")
  inspect(
    proposal.summary.contains(
      "Planner fallback used: model output was not valid proposal JSON.",
    ),
    content="true",
  )
  inspect(proposal.summary.contains("Collect inputs"), content="true")
}

///|
async test "plan_job_proposal accepts step details as prompt fallback" {
  let proposal = plan_job_proposal(
    "proposal-details-shape-1",
    "Land acquisition estimation",
    100,
    executor=fake_planner_executor(
      "{\"title\":\"Land acquisition estimation\",\"summary\":\"Use a decomposed plan.\",\"steps\":[{\"id\":\"scope\",\"title\":\"Clarify acquisition scope and assumptions\",\"details\":\"Define the target geography, parcel type, intended use, and time horizon.\"},{\"id\":\"inputs\",\"title\":\"Collect market and land inputs\",\"details\":\"Gather parcel, zoning, market, and comparable inputs.\"},{\"id\":\"finance\",\"title\":\"Estimate costs and financial outcome\",\"details\":\"Estimate acquisition costs, carrying costs, and expected financial outcome.\"},{\"id\":\"risk\",\"title\":\"Assess risks and produce report\",\"details\":\"Assess material risks and generate the final report.\"}]}",
    ),
  )
  inspect(proposal.steps.length(), content="4")
  inspect(
    proposal.steps[0].title,
    content="Clarify acquisition scope and assumptions",
  )
  inspect(
    proposal.steps[0].prompt,
    content="Define the target geography, parcel type, intended use, and time horizon.",
  )
}

///|
async test "plan_job_proposal accepts plan and step aliases from planner output" {
  let proposal = plan_job_proposal(
    "proposal-plan-alias-1",
    "Land acquisition estimation",
    100,
    executor=fake_planner_executor(
      "{\"title\":\"Land acquisition estimation\",\"overview\":\"Use a decomposed plan.\",\"plan\":[{\"step\":\"Clarify scope and assumptions for the land acquisition estimate\"},{\"step\":\"Collect market and parcel inputs\"},{\"step\":\"Estimate costs and financial outcome\"},{\"step\":\"Assess risks and prepare report\"}]}",
    ),
  )
  inspect(proposal.title, content="Land acquisition estimation")
  inspect(proposal.summary, content="Use a decomposed plan.")
  inspect(proposal.steps.length(), content="4")
  inspect(
    proposal.steps[0].title,
    content="Clarify scope and assumptions for the land acquisition estimate",
  )
  inspect(proposal.steps[3].prompt, content="Assess risks and prepare report")
}

///|
async test "plan_job_proposal accepts planner job field and details arrays" {
  let proposal = plan_job_proposal(
    "proposal-plan-array-details-1",
    "Land acquisition estimation",
    100,
    executor=fake_planner_executor(
      "{\"job\":\"Land acquisition estimation\",\"workspace_root\":\"/Users/kq/Workspace/moonclaw-workspace\",\"plan\":[{\"step\":1,\"title\":\"Clarify scope and assumptions\",\"details\":[\"Identify the target project geography.\",\"Confirm parcel type, intended use, and time horizon.\"]},{\"step\":2,\"title\":\"Collect market and parcel inputs\",\"details\":[\"Gather comparable sales and asking prices.\",\"Capture zoning, utilities, and legal constraints.\"]}]}",
    ),
  )
  inspect(proposal.title, content="Land acquisition estimation")
  inspect(proposal.steps.length(), content="2")
  inspect(proposal.steps[0].title, content="Clarify scope and assumptions")
  inspect(
    proposal.steps[0].prompt,
    content="Identify the target project geography.\nConfirm parcel type, intended use, and time horizon.",
  )
  inspect(proposal.steps[1].title, content="Collect market and parcel inputs")
}

///|
async test "plan_job_proposal retries under-decomposed analytical plan" {
  let calls : Ref[Int] = { val: 0 }
  let proposal = plan_job_proposal(
    "proposal-repair-1",
    "Land acquisition estimation",
    100,
    executor=AnalysisExecutor::new(run=fn(_request) {
      calls.val = calls.val + 1
      let content = if calls.val == 1 {
        "{\"title\":\"Land acquisition estimation\",\"summary\":\"Initial draft.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"execute\",\"title\":\"Execute requested work\",\"prompt\":\"Perform the requested job directly.\",\"kind\":\"job.analysis\"}]}"
      } else {
        "{\"title\":\"Land acquisition estimation\",\"summary\":\"Repaired draft.\",\"tags\":[\"job\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Information collection\",\"prompt\":\"Collect the required inputs.\",\"kind\":\"job.analysis\"},{\"id\":\"design\",\"title\":\"Scheme design\",\"prompt\":\"Design the estimation scheme.\",\"kind\":\"job.analysis\"},{\"id\":\"estimate\",\"title\":\"Cost estimation\",\"prompt\":\"Estimate costs.\",\"kind\":\"job.analysis\"},{\"id\":\"finance\",\"title\":\"Financial analysis\",\"prompt\":\"Analyze the financial outcome.\",\"kind\":\"job.analysis\"},{\"id\":\"risk\",\"title\":\"Risk assessment\",\"prompt\":\"Assess major risks.\",\"kind\":\"job.analysis\"},{\"id\":\"report\",\"title\":\"Report generation\",\"prompt\":\"Generate the final report.\",\"kind\":\"job.analysis\"}]}"
      }
      Ok(AnalysisExecution::{
        model_name: "default",
        content,
        conversation_id: None,
        usage: None,
        metadata: {},
      })
    }),
  )
  inspect(calls.val, content="2")
  inspect(proposal.steps.length(), content="6")
  inspect(proposal.steps[0].title, content="Information collection")
  inspect(proposal.steps[5].title, content="Report generation")
}

///|
async test "plan_job_proposal reports under-decomposed plan after repair" {
  let calls : Ref[Int] = { val: 0 }
  let proposal = plan_job_proposal(
    "proposal-repair-fail-1",
    "Land acquisition estimation",
    100,
    executor=AnalysisExecutor::new(run=fn(_request) {
      calls.val = calls.val + 1
      Ok(AnalysisExecution::{
        model_name: "default",
        content: "{\"title\":\"Land acquisition estimation\",\"steps\":[{\"id\":\"execute\",\"title\":\"Execute requested work\",\"prompt\":\"Perform the requested job directly.\",\"kind\":\"job.analysis\"}]}",
        conversation_id: None,
        usage: None,
        metadata: {},
      })
    }),
  )
  inspect(calls.val, content="2")
  inspect(proposal.steps.length(), content="1")
  inspect(
    proposal.summary.contains(
      "Planner fallback used: planner returned an under-decomposed plan even after repair.",
    ),
    content="true",
  )
  inspect(
    proposal.summary.contains("\"title\":\"Land acquisition estimation\""),
    content="true",
  )
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
