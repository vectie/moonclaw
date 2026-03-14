///|
test "compile_job_proposal selects research topic template for paper monitoring requests" {
  let proposal = draft_job_proposal(
    "proposal-compiler-1", "Track yesterday's VLA arxiv papers and send me a daily review.",
    100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.family, content="research")
  inspect(compilation.template, content="research.topic_watch")
  inspect(compilation.missing_capabilities.length(), content="0")
  inspect(compilation.workflow.steps.length(), content="3")
  inspect(compilation.workflow.steps[0].kind, content="research.topic.sync")
  inspect(
    compilation.workflow.steps[1].config
    .stringify()
    .contains("\"research-paper-summary\""),
    content="true",
  )
}

///|
test "compile_job_proposal falls back to generic workflow for non-research requests" {
  let proposal = draft_job_proposal(
    "proposal-compiler-2", "Review a repository and produce a deployment risk report.",
    100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.family, content="generic")
  inspect(compilation.template, content="generic.tool_workflow")
  inspect(compilation.workflow.steps[0].kind, content="job.analysis")
}

///|
test "template and capability registries expose research defaults" {
  inspect(
    template_definition("research.topic_watch") is Some(_),
    content="true",
  )
  inspect(capability_available("research.arxiv_sync"), content="true")
  inspect(
    template_default_skills("research.topic_watch").join(","),
    content="research-paper-summary,research-novelty-review,research-report-writer",
  )
}
