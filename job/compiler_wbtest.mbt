///|
test "compile_job_proposal preserves proposal step structure for generic requests" {
  let proposal = draft_job_proposal(
    "proposal-compiler-1", "Track yesterday's VLA arxiv papers and send me a daily review.",
    100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.family, content="generic")
  inspect(compilation.workflow.steps.length(), content="5")
  inspect(compilation.workflow.steps[0].kind, content="job.analysis")
  inspect(compilation.workflow.steps[1].kind, content="job.analysis")
  inspect(compilation.workflow.steps[4].kind, content="job.analysis")
}

///|
test "compile_job_proposal builds direct workflow for generic requests" {
  let proposal = draft_job_proposal(
    "proposal-compiler-2", "Review a repository and produce a deployment risk report.",
    100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.family, content="generic")
  inspect(compilation.workflow.steps[0].kind, content="job.analysis")
}

///|
test "compile_job_proposal preserves custom step kinds directly" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-compiler-3", "delegate this", 100),
    steps: [
      JobProposalStep::{
        id: "delegate",
        title: "Delegate",
        prompt: "Run a child job.",
        kind: "job.delegate",
      },
    ],
  }
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.workflow.steps.length(), content="1")
  inspect(compilation.workflow.steps[0].kind, content="job.delegate")
}
