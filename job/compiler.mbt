///|
pub(all) struct ProposalCompilation {
  family : String
  definition : JobDefinition
  workflow : WorkflowDefinition
  bindings : Array[ChatBinding]
}

///|
fn proposal_family(proposal : JobProposal) -> String {
  proposal.suggested_family.unwrap_or("generic")
}

///|
fn normalized_step_kind(kind : String) -> String {
  let trimmed = kind.trim().to_string()
  if trimmed.is_blank() {
    "job.analysis"
  } else {
    trimmed
  }
}

///|
fn workflow_steps_for_proposal(
  proposal : JobProposal,
  cwd : String,
  home : String,
  workspace_root : String,
  family : String,
) -> Array[WorkflowStepDefinition] {
  let steps = proposal.steps.map(fn(step) {
    WorkflowStepDefinition::{
      id: step.id,
      kind: normalized_step_kind(step.kind),
      config: AnalysisStepConfig::new(
        prompt=step.prompt,
        cwd=Some(cwd),
        home=Some(home),
        workspace=Some(workspace_root),
        preferred_skills=[],
        enable_tools=true,
        web_search=false,
        policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
        artifacts=AnalysisArtifactConfig::new(
          report_artifact_type="job.proposal.step.report",
          result_artifact_type="job.proposal.step.result",
          logical_key=Some("\{proposal.id}:\{step.id}"),
          scope=["jobs", "proposal:\{proposal.id}"],
          append_only=false,
        ),
        metadata={
          "proposal_id": proposal.id,
          "proposal_step_id": step.id,
          "proposal_step_title": step.title,
          "family": family,
        },
      ).to_json(),
      retry_policy: None,
    }
  })
  if steps.is_empty() {
    [
      WorkflowStepDefinition::{
        id: "execute",
        kind: "job.analysis",
        config: AnalysisStepConfig::new(
          prompt=proposal.request_text,
          cwd=Some(cwd),
          home=Some(home),
          workspace=Some(workspace_root),
          preferred_skills=[],
          enable_tools=true,
          web_search=false,
          policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
          artifacts=AnalysisArtifactConfig::new(
            report_artifact_type="job.proposal.step.report",
            result_artifact_type="job.proposal.step.result",
            logical_key=Some("\{proposal.id}:execute"),
            scope=["jobs", "proposal:\{proposal.id}"],
            append_only=false,
          ),
          metadata={
            "proposal_id": proposal.id,
            "proposal_step_id": "execute",
            "proposal_step_title": proposal.title,
            "family": family,
          },
        ).to_json(),
        retry_policy: None,
      },
    ]
  } else {
    steps
  }
}

///|
pub fn compile_job_proposal(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root? : String = cwd,
) -> ProposalCompilation {
  let family = proposal_family(proposal)
  let job_id = "job.proposal.\{proposal.id}"
  let workflow_id = "workflow.proposal.\{proposal.id}"
  let steps = workflow_steps_for_proposal(
    proposal, cwd, home, workspace_root, family,
  )
  let role = proposal.profile_role.unwrap_or("")
  let definition_kind = if role == "controller" {
    "job.controller"
  } else {
    "job.proposal"
  }
  let definition = JobDefinition::{
    id: job_id,
    kind: definition_kind,
    enabled: true,
    config: {
      "proposal_id": proposal.id,
      "title": proposal.title,
      "proposal_title": proposal.title,
      "workspace": workspace_root,
      "family": family,
      "profile_id": proposal.profile_id,
      "role": role,
      "profile_metadata": proposal.profile_metadata,
      "notify": {
        "channel": proposal.channel_id.unwrap_or(""),
        "account_id": proposal.account_id.unwrap_or(""),
        "to": proposal.recipient.unwrap_or(""),
        "thread_id": proposal.thread_id,
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: None,
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: proposal.tags,
  }
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: definition_kind,
    steps,
    output_bindings: steps.map(fn(step) { step.id }),
  }
  ProposalCompilation::{ family, definition, workflow, bindings: [] }
}
