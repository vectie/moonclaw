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
  inspect(compilation.workflow.steps.length(), content="1")
  inspect(compilation.workflow.steps[0].kind, content="job.analysis")
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
        metadata: {},
        child_profile: Some("opc_impl_worker"),
        execution_mode: Some("acp"),
        execution_target: Some("codex-impl"),
        include_parent_outputs: Some(false),
        max_depth: Some(4),
      },
    ],
  }
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.workflow.steps.length(), content="1")
  inspect(compilation.workflow.steps[0].kind, content="job.delegate")
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"include_parent_outputs\":false"),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config.stringify().contains("\"max_depth\":4"),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"child_profile\":\"opc_impl_worker\""),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_mode\":\"acp\""),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_target\":\"codex-impl\""),
    content="true",
  )
}

///|
test "compile_job_proposal applies analysis metadata from proposal steps" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-compiler-4", "review and implement", 100),
    steps: [
      JobProposalStep::{
        id: "review",
        title: "Review",
        prompt: "Review the feature request.",
        kind: "job.analysis",
        metadata: {
          "preferred_skills": ["opc-ceo", "opc-eng"],
          "system_prompt": "Act like a focused executive reviewer.",
          "web_search": true,
          "enable_tools": false,
          "model": "codex/gpt-5.4",
        },
        child_profile: None,
        execution_mode: None,
        execution_target: None,
        include_parent_outputs: None,
        max_depth: None,
      },
    ],
  }
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.workflow.steps[0].kind, content="job.analysis")
  inspect(
    compilation.workflow.steps[0].config.stringify().contains("\"opc-ceo\""),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("Act like a focused executive reviewer."),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"web_search\":true"),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"enable_tools\":false"),
    content="true",
  )
}

///|
test "compile_job_proposal preserves analysis execution routing hints" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-compiler-5", "run analysis remotely", 100),
    steps: [
      JobProposalStep::{
        id: "scope",
        title: "Scope",
        prompt: "Scope the work.",
        kind: "job.analysis",
        metadata: {},
        child_profile: None,
        execution_mode: Some("acp"),
        execution_target: Some("codex-main"),
        include_parent_outputs: None,
        max_depth: None,
      },
    ],
  }
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_mode\":\"acp\""),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_target\":\"codex-main\""),
    content="true",
  )
}
