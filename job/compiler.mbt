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
fn metadata_string_array(metadata : Json, key : String) -> Array[String] {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(values)) => {
          let strings : Array[String] = []
          for value in values {
            match value {
              String(text) => strings.push(text)
              _ => ()
            }
          }
          strings
        }
        _ => []
      }
    _ => []
  }
}

///|
fn metadata_bool(metadata : Json, key : String, fallback : Bool) -> Bool {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => true
        Some(False) => false
        _ => fallback
      }
    _ => fallback
  }
}

///|
fn metadata_string(metadata : Json, key : String) -> String? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn metadata_json_value(metadata : Json, key : String) -> Json? {
  match metadata {
    Object(obj) => obj.get(key)
    _ => None
  }
}

///|
fn merge_json_objects(base : Json, extras : Array[(String, Json)]) -> Json {
  let merged : Map[String, Json] = {}
  match base {
    Object(obj) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  for extra in extras {
    let key = extra.0
    let value = extra.1
    merged.set(key, value)
  }
  Json::object(merged)
}

///|
fn workflow_step_definition_for_proposal_step(
  proposal : JobProposal,
  step : JobProposalStep,
  cwd : String,
  home : String,
  workspace_root : String,
  family : String,
) -> WorkflowStepDefinition {
  let kind = normalized_step_kind(step.kind)
  let base_metadata : Json = {
    "proposal_id": proposal.id,
    "proposal_step_id": step.id,
    "proposal_step_title": step.title,
    "family": family,
  }
  let board_extras : Array[(String, Json)] = []
  match metadata_json_value(step.metadata, "board_lane") {
    Some(value) => board_extras.push(("board_lane", value))
    None => ()
  }
  match metadata_json_value(step.metadata, "board_order") {
    Some(value) => board_extras.push(("board_order", value))
    None => ()
  }
  let config = if kind == "job.delegate" {
    merge_json_objects(
      SubjobStepConfig::new(
        request_text=step.prompt,
        cwd=Some(cwd),
        home=Some(home),
        child_profile=step.child_profile,
        execution_mode=step.execution_mode,
        execution_target=step.execution_target,
        include_parent_outputs=step.include_parent_outputs.unwrap_or(true),
        max_depth=step.max_depth.unwrap_or(2),
      ).to_json(),
      board_extras,
    )
  } else {
    let analysis_metadata = merge_json_objects(base_metadata, board_extras)
    merge_json_objects(
      AnalysisStepConfig::new(
        prompt=step.prompt,
        model=metadata_string(step.metadata, "model"),
        cwd=Some(cwd),
        home=Some(home),
        workspace=Some(workspace_root),
        execution_mode=step.execution_mode,
        execution_target=step.execution_target,
        system_prompt=metadata_string(step.metadata, "system_prompt"),
        preferred_skills=metadata_string_array(
          step.metadata,
          "preferred_skills",
        ),
        enable_tools=metadata_bool(step.metadata, "enable_tools", true),
        web_search=metadata_bool(step.metadata, "web_search", false),
        policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
        artifacts=AnalysisArtifactConfig::new(
          report_artifact_type="job.proposal.step.report",
          result_artifact_type="job.proposal.step.result",
          logical_key=Some("\{proposal.id}:\{step.id}"),
          scope=["jobs", "proposal:\{proposal.id}"],
          append_only=false,
        ),
        metadata=analysis_metadata,
      ).to_json(),
      board_extras,
    )
  }
  WorkflowStepDefinition::{ id: step.id, kind, config, retry_policy: None }
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
    workflow_step_definition_for_proposal_step(
      proposal, step, cwd, home, workspace_root, family,
    )
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
            "step_metadata": {},
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
