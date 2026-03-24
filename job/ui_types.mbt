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
} derive(ToJson, FromJson, Show)

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
  created_at : Int?
  updated_at : Int?
  provisional : Bool
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobUiTimelineEntry {
  id : String
  run_id : String
  event_type : String
  title : String
  detail : String
  timestamp : Int
  step_id : String?
  status : String?
  data : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobUiRemoteLink {
  id : String
  kind : String
  title : String
  status : String
  summary : String?
  detail : String?
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobUiHandoff {
  node_id : String
  step_id : String?
  remote : Array[JobUiRemoteLink]
} derive(ToJson, FromJson, Show)

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
} derive(ToJson, FromJson, Show)
