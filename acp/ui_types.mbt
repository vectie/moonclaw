///|
pub(all) enum AcpUiNodeKind {
  Target
  Session
  Run
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpUiNode {
  id : String
  parent_id : String?
  kind : AcpUiNodeKind
  title : String
  status : String
  summary : String?
  detail : String?
  target_id : String?
  session_id : String?
  run_id : String?
  created_at : Int?
  updated_at : Int?
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpUiTimelineEntry {
  id : String
  event_type : String
  title : String
  detail : String
  timestamp : Int
  target_id : String?
  session_id : String?
  run_id : String?
  status : String?
  data : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpUiSnapshot {
  targets : Array[AcpTarget]
  sessions : Array[AcpSession]
  runs : Array[AcpRun]
  nodes : Array[AcpUiNode]
  timeline : Array[AcpUiTimelineEntry]
} derive(ToJson, FromJson, Show)
