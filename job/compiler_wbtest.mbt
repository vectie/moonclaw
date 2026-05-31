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
  inspect(
    compilation.workflow.steps[0].retry_policy
    .map(fn(policy) { policy.max_attempts })
    .unwrap_or(0),
    content="2",
  )
}

///|
test "compile_job_proposal applies default retry policy to generated analysis steps" {
  let proposal = draft_job_proposal(
    "proposal-compiler-retry-default", "Analyze the repo and summarize it.", 100,
  )
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(
    compilation.workflow.steps[0].retry_policy
    .map(fn(policy) { policy.max_attempts })
    .unwrap_or(0),
    content="2",
  )
  inspect(
    compilation.workflow.steps[0].retry_policy
    .bind(fn(policy) { policy.backoff_ms })
    .unwrap_or(0),
    content="2000",
  )
}

///|
test "compile_job_proposal honors retry metadata overrides" {
  let proposal = JobProposal::{
    ..draft_job_proposal(
      "proposal-compiler-retry-override", "Analyze once more", 100,
    ),
    steps: [
      JobProposalStep::{
        id: "scope",
        title: "Scope",
        prompt: "Inspect the workspace.",
        kind: "job.analysis",
        metadata: { "retry_max_attempts": 4, "retry_backoff_ms": 750 },
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
  inspect(
    compilation.workflow.steps[0].retry_policy
    .map(fn(policy) { policy.max_attempts })
    .unwrap_or(0),
    content="4",
  )
  inspect(
    compilation.workflow.steps[0].retry_policy
    .bind(fn(policy) { policy.backoff_ms })
    .unwrap_or(0),
    content="750",
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
test "compile_job_proposal maps timeout and token budget metadata into analysis policy" {
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-compiler-policy-1", "bounded analysis", 100),
    steps: [
      JobProposalStep::{
        id: "bounded",
        title: "Bounded",
        prompt: "Do bounded work.",
        kind: "job.analysis",
        metadata: { "timeout_ms": 12345, "max_total_tokens": 678 },
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
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"timeout_ms\":12345"),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"max_total_tokens\":678"),
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

///|
test "compile_job_proposal reads analysis execution routing from step metadata" {
  let proposal = JobProposal::{
    ..draft_job_proposal(
      "proposal-compiler-metadata-routing", "run analysis using metadata routing",
      100,
    ),
    steps: [
      JobProposalStep::{
        id: "scope",
        title: "Scope",
        prompt: "Scope the work.",
        kind: "job.analysis",
        metadata: { "execution_mode": "acp", "execution_target": "codex-main" },
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

///|
test "compile_job_proposal augments wiki ingest controller with provider delegate step" {
  let proposal = JobProposal::{
    ..draft_job_proposal(
      "proposal-compiler-wiki-ingest", "Ingest this source into the wiki.", 100,
    ),
    suggested_family: Some("wiki_ingest_controller"),
    profile_role: Some("controller"),
    steps: [
      JobProposalStep::{
        id: "inspect_source",
        title: "Inspect source",
        prompt: "Inspect the source.",
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
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.workflow.steps.length(), content="2")
  inspect(compilation.workflow.steps[0].id, content="extension_ingest")
  inspect(compilation.workflow.steps[1].kind, content="job.analysis")
  inspect(compilation.workflow.steps[1].id, content="inspect_source")
  inspect(compilation.workflow.steps[0].kind, content="job.delegate")
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_mode\":\"provider\""),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_target\""),
    content="false",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"include_parent_outputs\":false"),
    content="true",
  )
  inspect(
    compilation.workflow.steps[1].config
    .stringify()
    .contains("\"best_effort_on_missing_input\":true"),
    content="true",
  )
  inspect(
    compilation.workflow.steps[1].config
    .stringify()
    .contains("\"disable_waiting_for_input\":true"),
    content="true",
  )
}

///|
test "compile_job_proposal collapses imported wiki ingest controller to provider delegate only" {
  let proposal = JobProposal::{
    ..draft_job_proposal(
      "proposal-compiler-wiki-ingest-imported", "Ingest this source into the wiki.",
      100,
    ),
    suggested_family: Some("wiki_ingest_controller"),
    profile_role: Some("controller"),
    profile_metadata: {
      "external_packet": { "schema": "moonclaw.external_proposal_packet.v1" },
    },
    steps: [
      JobProposalStep::{
        id: "plan_gather_fanout",
        title: "Plan gather fanout",
        prompt: "Plan the gather lanes.",
        kind: "job.analysis",
        metadata: {},
        child_profile: None,
        execution_mode: None,
        execution_target: None,
        include_parent_outputs: None,
        max_depth: None,
      },
      JobProposalStep::{
        id: "gather_docs",
        title: "Gather docs",
        prompt: "Gather the docs.",
        kind: "job.delegate",
        metadata: {},
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
  inspect(compilation.workflow.steps.length(), content="1")
  inspect(compilation.workflow.steps[0].id, content="extension_ingest")
  inspect(compilation.workflow.steps[0].kind, content="job.delegate")
}

///|
test "compile_job_proposal lets wiki ingest controller override provider routing" {
  let proposal = JobProposal::{
    ..draft_job_proposal(
      "proposal-compiler-wiki-ingest-routing", "Ingest with custom provider.", 100,
    ),
    suggested_family: Some("wiki_ingest_controller"),
    profile_role: Some("controller"),
    profile_metadata: {
      "extension_target": "book-lead",
      "extension_mode": "extension",
    },
    steps: [],
  }
  let compilation = compile_job_proposal(
    proposal, 101, "/tmp/workspace", "/tmp/home",
  )
  inspect(compilation.workflow.steps.length(), content="2")
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_mode\":\"extension\""),
    content="true",
  )
  inspect(
    compilation.workflow.steps[0].config
    .stringify()
    .contains("\"execution_target\":\"book-lead\""),
    content="true",
  )
}
