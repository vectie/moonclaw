///|
async test "GatewayJobApp::revise_draft_proposal rejects non-draft proposals" {
  @fsx.with_temporary_directory("job-app-revise-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workspace = @workspace.WorkspaceRuntime::new(
      home="/tmp/home",
      cwd="/tmp/workspace",
    )
    let app = GatewayJobApp::new(
      root~,
      cwd="/tmp/workspace",
      home="/tmp/home",
      workspace~,
      next_id=fn() { "proposal-next" },
      now=fn() { 200 },
    )
    let proposal = JobProposal::{
      ..draft_job_proposal("proposal-1", "Track papers.", 100),
      status: Confirmed,
    }
    let result = app.revise_draft_proposal(
      proposal, "proposal-1", "add filtering",
    )
    inspect(
      match result {
        Ok(_) => ""
        Err(error) => error
      },
      content="Proposal proposal-1 is already \"Confirmed\"",
    )
  })
}

///|
async test "GatewayJobApp::confirm_proposal registers workflow and persists proposal state" {
  @fsx.with_temporary_directory("job-app-confirm-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workspace = @workspace.WorkspaceRuntime::new(
      home="/tmp/home",
      cwd="/tmp/workspace",
    )
    let app = GatewayJobApp::new(
      root~,
      cwd="/tmp/workspace",
      home="/tmp/home",
      workspace~,
      next_id=fn() { "proposal-next" },
      now=fn() { 200 },
    )
    let proposal = draft_job_proposal(
      "proposal-2",
      "Review yesterday's VLA arxiv papers and send me a daily digest.",
      100,
      channel_id=Some("feishu"),
      account_id=Some("default"),
      recipient=Some("oc_chat_123"),
    )
    app.runtime().store().save_job_proposal(proposal)
    let result = app.confirm_proposal(proposal, "proposal-2", async fn(job_id) {
      app
      .runtime()
      .trigger_definition("run-2", job_id, TriggerSource::Manual, 200)
    })
    let confirmed = match result {
      Ok(confirmed) => confirmed
      Err(error) => fail(error)
    }
    inspect(confirmed.compilation.family, content="generic")
    inspect(confirmed.run.id, content="run-2")
    inspect(
      app.runtime().store().get_definition(confirmed.compilation.definition.id)
      is Some(_),
      content="true",
    )
    inspect(
      app
      .runtime()
      .store()
      .get_job_proposal("proposal-2")
      .map(fn(saved) { saved.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Confirmed\"",
    )
    inspect(
      app
      .runtime()
      .store()
      .get_job_proposal("proposal-2")
      .map(fn(saved) { saved.last_run_id.unwrap_or("") })
      .unwrap_or(""),
      content="run-2",
    )
  })
}

///|
async test "GatewayJobApp::confirm_proposal initializes generic controller records" {
  @fsx.with_temporary_directory("job-app-controller-confirm-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let workspace = @workspace.WorkspaceRuntime::new(home=dir, cwd=dir)
    let app = GatewayJobApp::new(
      root~,
      cwd=dir,
      home=dir,
      workspace~,
      next_id=fn() { "proposal-controller-next" },
      now=fn() { 200 },
    )
    let proposal = JobProposal::{
      ..draft_job_proposal(
        "proposal-controller", "Research VLA papers and evaluate hypotheses.", 100,
      ),
      suggested_family: Some("research_controller"),
      profile_id: Some("research_controller"),
      profile_role: Some("controller"),
      profile_metadata: { "domain": "research" },
      steps: [
        JobProposalStep::{
          id: "collect",
          title: "Collect evidence",
          prompt: "Collect evidence for ${request}",
          kind: "job.delegate",
          metadata: {},
          child_profile: None,
          execution_mode: None,
          execution_target: None,
          include_parent_outputs: None,
          max_depth: None,
        },
        JobProposalStep::{
          id: "evaluate",
          title: "Evaluate",
          prompt: "Evaluate outputs.",
          kind: "job.analysis",
          metadata: {},
          child_profile: None,
          execution_mode: None,
          execution_target: None,
          include_parent_outputs: None,
          max_depth: None,
        },
      ],
    }
    app.runtime().store().save_job_proposal(proposal)
    let result = app.confirm_proposal(proposal, "proposal-controller", async fn(
      job_id,
    ) {
      app
      .runtime()
      .trigger_definition("run-controller", job_id, TriggerSource::Manual, 200)
    })
    let confirmed = match result {
      Ok(confirmed) => confirmed
      Err(error) => fail(error)
    }
    inspect(confirmed.compilation.definition.kind, content="job.controller")
    inspect(confirmed.compilation.workflow.kind, content="job.controller")
    inspect(
      app.runtime().store().get_controller_state("run-controller") is Some(_),
      content="true",
    )
    inspect(
      app.runtime().store().get_controller_iteration("run-controller:iter:root")
      is Some(_),
      content="true",
    )
  })
}
