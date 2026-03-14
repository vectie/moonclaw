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
