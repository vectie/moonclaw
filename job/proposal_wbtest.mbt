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
}
