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
  inspect(proposal.tags.contains("research"), content="true")
  inspect(proposal.suggested_family.unwrap_or(""), content="research")
  inspect(proposal.job_id is None, content="true")
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
  inspect(workflow.steps.length(), content="5")
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
async test "plan_job_proposal uses model JSON when available" {
  let proposal = plan_job_proposal(
    "proposal-3",
    "Create a weekly research monitoring job.",
    100,
    executor=fake_planner_executor(
      "{\"title\":\"Weekly research monitor\",\"summary\":\"Monitor and summarize new papers weekly.\",\"tags\":[\"job\",\"research\",\"weekly\"],\"steps\":[{\"id\":\"collect\",\"title\":\"Collect papers\",\"prompt\":\"Collect the newest papers.\",\"kind\":\"job.analysis\"},{\"id\":\"summarize\",\"title\":\"Summarize findings\",\"prompt\":\"Summarize the collected papers.\",\"kind\":\"job.analysis\"}]}",
    ),
    channel_id=Some("feishu"),
    account_id=Some("default"),
    recipient=Some("oc_chat_123"),
  )
  inspect(proposal.title, content="Weekly research monitor")
  inspect(proposal.steps.length(), content="2")
  inspect(proposal.steps[0].id, content="collect")
  inspect(proposal.tags.join(","), content="job,research,weekly")
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
test "proposal_as_workflow compiles research drafts into research topic workflow" {
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
  inspect(definition.kind, content="job.proposal.research")
  inspect(workflow.steps.length(), content="3")
  inspect(workflow.steps[0].kind, content="research.topic.sync")
  inspect(workflow.steps[1].kind, content="job.analysis")
  inspect(
    definition.config.stringify().contains("\"family\":\"research\""),
    content="true",
  )
}

///|
test "render_job_proposal_for_chat includes compiler notes and missing capabilities" {
  let proposal = JobProposal::{
    ..draft_job_proposal(
      "proposal-7", "Compare each paper and break down subtasks.", 100,
    ),
    missing_capabilities: ["workflow.delegate"],
    compiler_notes: [
      "Delegation enabled because the request is broad or decomposable.",
    ],
  }
  let rendered = render_job_proposal_for_chat(proposal)
  inspect(
    rendered.contains("Missing capabilities: workflow.delegate"),
    content="true",
  )
  inspect(rendered.contains("Compiler notes:"), content="true")
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
async test "save_confirmed_job_proposal persists compilation metadata and run id" {
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
    inspect(
      saved.map(fn(p) { p.suggested_template.unwrap_or("") }).unwrap_or(""),
      content="research.topic_watch",
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
