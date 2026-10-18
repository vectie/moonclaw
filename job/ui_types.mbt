///|
pub(all) enum JobUiNodeKind {
  Proposal
  Workflow
  Split
  Merge
  Step
  ChildRun
  Artifact
  Memory
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct JobUiNode {
  id : String
  parent_id : String?
  kind : JobUiNodeKind
  title : String
  status : String
  summary : String?
  detail : String?
  run_id : String?
  step_id : String?
  artifact_id : String?
  memory_id : String?
  created_at : Int32?
  updated_at : Int32?
  provisional : Bool
  metadata : Json
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct JobUiTimelineEntry {
  id : String
  run_id : String
  event_type : String
  title : String
  detail : String
  timestamp : Int32
  step_id : String?
  status : String?
  data : Json
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct JobUiRemoteLink {
  id : String
  kind : String
  title : String
  status : String
  summary : String?
  detail : String?
  metadata : Json
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct JobUiHandoff {
  node_id : String
  step_id : String?
  remote : Array[JobUiRemoteLink]
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct JobUiSnapshot {
  run : JobRun
  definition : JobDefinition
  workflow : WorkflowDefinition?
  proposal : JobProposal?
  workspace_dir : String?
  current_step_id : String?
  child_runs : Array[JobRun]
  artifacts : Array[ArtifactRecord]
  memories : Array[MemoryRecord]
  linked_remote : Array[JobUiRemoteLink]
  handoffs : Array[JobUiHandoff]
  nodes : Array[JobUiNode]
  timeline : Array[JobUiTimelineEntry]
} derive(ToJson, FromJson, Debug)

///|
pub extend JobUiNodeKind with ToJson::{to_json}

///|
pub extend JobUiNodeKind with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JobUiNodeKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JobUiNode with ToJson::{to_json}

///|
pub extend JobUiNode with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JobUiNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JobUiTimelineEntry with ToJson::{to_json}

///|
pub extend JobUiTimelineEntry with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JobUiTimelineEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JobUiRemoteLink with ToJson::{to_json}

///|
pub extend JobUiRemoteLink with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JobUiRemoteLink with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JobUiHandoff with ToJson::{to_json}

///|
pub extend JobUiHandoff with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JobUiHandoff with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JobUiSnapshot with ToJson::{to_json}

///|
pub extend JobUiSnapshot with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend JobUiSnapshot with @moonbitlang/core/debug.Debug::{to_repr}
