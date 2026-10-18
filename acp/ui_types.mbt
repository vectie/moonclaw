///|
pub(all) enum AcpUiNodeKind {
  Target
  Session
  Run
} derive(ToJson, FromJson, Debug)

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
  created_at : Int32?
  updated_at : Int32?
  metadata : Json
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct AcpUiTimelineEntry {
  id : String
  event_type : String
  title : String
  detail : String
  timestamp : Int32
  target_id : String?
  session_id : String?
  run_id : String?
  status : String?
  data : Json
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct AcpUiSnapshot {
  targets : Array[AcpTarget]
  sessions : Array[AcpSession]
  runs : Array[AcpRun]
  nodes : Array[AcpUiNode]
  timeline : Array[AcpUiTimelineEntry]
} derive(ToJson, FromJson, Debug)

///|
pub extend AcpUiNodeKind with ToJson::{to_json}

///|
pub extend AcpUiNodeKind with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AcpUiNodeKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AcpUiNode with ToJson::{to_json}

///|
pub extend AcpUiNode with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AcpUiNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AcpUiTimelineEntry with ToJson::{to_json}

///|
pub extend AcpUiTimelineEntry with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AcpUiTimelineEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AcpUiSnapshot with ToJson::{to_json}

///|
pub extend AcpUiSnapshot with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AcpUiSnapshot with @moonbitlang/core/debug.Debug::{to_repr}
