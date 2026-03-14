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
  inspect(compilation.compiler_notes.length() > 0, content="true")
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
  inspect(capability_available("workflow.delegate"), content="true")
  inspect(
    preferred_templates_for_capabilities([
      "workflow.delegate", "analysis.report",
    ]).join(","),
    content="generic.delegated,generic.analysis",
  )
  inspect(
    template_default_skills("research.topic_watch").join(","),
    content="research-paper-summary,research-novelty-review,research-report-writer",
  )
}

///|
test "compile_job_proposal selects delegated generic workflow for broad multi-step requests" {
  let proposal = draft_job_proposal(
    "proposal-compiler-3", "Collect market context, compare three options, break down risks, and produce an execution plan.",
    100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.family, content="generic")
  inspect(compilation.template, content="generic.delegated")
  inspect(
    compilation.compiler_notes.join("|").contains("Delegation enabled"),
    content="true",
  )
  inspect(compilation.workflow.steps[0].kind, content="job.delegate")
  inspect(compilation.workflow.steps.length() >= 4, content="true")
}

///|
test "compile_job_proposal selects delegated research workflow for broad research review requests" {
  let proposal = draft_job_proposal(
    "proposal-compiler-4", "Track yesterday's VLA arxiv papers, compare the strongest candidates, critique each paper, and produce a final digest.",
    100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.family, content="research")
  inspect(compilation.template, content="research.delegated_review")
  inspect(
    compilation.compiler_notes.join("|").contains("Detected comparison work"),
    content="true",
  )
  inspect(compilation.workflow.steps[0].kind, content="research.topic.sync")
  inspect(compilation.workflow.steps[1].kind, content="job.delegate")
}
