///|
enum Route {
  Overview
  Jobs
  Run(String)
  Acp
}

///|
enum RightPanel {
  Workspace
  Artifacts
  Memory
} derive(Eq, Compare, Show)

///|
enum RunSort {
  Newest
  Oldest
  Depth
} derive(Eq, Compare, Show)

///|
enum Surface {
  SurfaceOverview
  SurfaceJobs
  SurfaceAcp
} derive(Eq, Compare, Show)

///|
struct RunSummary {
  id : String
  job_id : String
  status : String
  depth : Int
  started_at : Int?
  completed_at : Int?
  summary : String?
} derive(FromJson, Show)

///|
struct RunsPayload {
  runs : Array[RunSummary]
} derive(FromJson, Show)

///|
struct UiNode {
  id : String
  parent_id : String?
  kind : String
  title : String
  status : String
  summary : String?
  detail : String?
  run_id : String?
  step_id : String?
  artifact_id : String?
  memory_id : String?
  metadata : Json
  provisional : Bool
} derive(FromJson, Show)

///|
struct UiTimelineEntry {
  id : String
  run_id : String
  event_type : String
  title : String
  detail : String
  timestamp : Int
  step_id : String?
  status : String?
  data : Json
} derive(FromJson, Show)

///|
struct UiArtifact {
  id : String
  artifact_type : String
  logical_key : String?
  path : String
  content_type : String
} derive(FromJson, Show)

///|
struct UiMemory {
  id : String
  kind : String
  title : String?
  content : String
  workspace : String?
} derive(FromJson, Show)

///|
struct UiRemoteLink {
  id : String
  kind : String
  title : String
  status : String
  summary : String?
  detail : String?
  metadata : Json
} derive(FromJson, Show)

///|
struct UiHandoff {
  node_id : String
  step_id : String?
  remote : Array[UiRemoteLink]
} derive(FromJson, Show)

///|
struct UiRun {
  id : String
  job_id : String
  status : String
  workspace_dir : String?
  summary : String?
  error : String?
} derive(FromJson, Show)

///|
struct UiSnapshot {
  run : UiRun
  workspace_dir : String?
  current_step_id : String?
  artifacts : Array[UiArtifact]
  memories : Array[UiMemory]
  linked_remote : Array[UiRemoteLink]
  handoffs : Array[UiHandoff]
  nodes : Array[UiNode]
  timeline : Array[UiTimelineEntry]
} derive(FromJson, Show)

///|
struct UiSnapshotPayload {
  snapshot : UiSnapshot
} derive(FromJson, Show)

///|
struct UiEventsPayload {
  timeline : Array[UiTimelineEntry]
} derive(FromJson, Show)

///|
enum AcpUiNodeKind {
  Target
  Session
  Run
} derive(Eq, Compare, FromJson, Show)

///|
struct AcpUiNode {
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
} derive(FromJson, Show)

///|
struct AcpUiTimelineEntry {
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
} derive(FromJson, Show)

///|
struct AcpUiSnapshot {
  targets : Array[Json]
  sessions : Array[Json]
  runs : Array[Json]
  nodes : Array[AcpUiNode]
  timeline : Array[AcpUiTimelineEntry]
} derive(FromJson, Show)

///|
struct AcpUiSnapshotPayload {
  snapshot : AcpUiSnapshot
} derive(FromJson, Show)

///|
struct AcpUiEventsPayload {
  timeline : Array[AcpUiTimelineEntry]
} derive(FromJson, Show)

///|
struct TimelineGroup {
  id : String
  title : String
  entries : Array[UiTimelineEntry]
}

///|
struct MixedHandoffGroup {
  key : String
  handoffs : Array[UiHandoff]
  remote : Array[UiRemoteLink]
}

///|
struct NodeEventStats {
  event_count : Int
  max_attempt : Int
  metric_events : Int
  artifact_hits : Int
  memory_hits : Int
  workspace_hits : Int
  failed_events : Int
}

///|
struct Model {
  gateway_base : String
  route : Route
  selected_mixed_handoff_key : String?
  runs : Array[RunSummary]
  runs_loading : Bool
  runs_error : String?
  selected_run_id : String?
  runs_status_filter : String?
  runs_query : String
  runs_sort : RunSort
  runs_page : Int
  snapshot : UiSnapshot?
  timeline : Array[UiTimelineEntry]
  fresh_node_ids : Array[String]
  fresh_timeline_ids : Array[String]
  collapsed_node_ids : Array[String]
  expanded_node_ids : Array[String]
  focused_node_id : String?
  timeline_scope_node_id : String?
  timeline_scope_branch_only : Bool
  detail_loading : Bool
  detail_error : String?
  right_panel : RightPanel
  acp_snapshot : AcpUiSnapshot?
  acp_timeline : Array[AcpUiTimelineEntry]
  acp_loading : Bool
  acp_error : String?
  selected_acp_node_id : String?
  fresh_acp_node_ids : Array[String]
  fresh_acp_timeline_ids : Array[String]
  expanded_acp_output_ids : Array[String]
  acp_run_message : String
  acp_action_notice : String?
}

///|
enum Msg {
  LoadRuns
  RunsLoaded(Result[Array[RunSummary], String])
  SelectRun(String)
  LoadRun(String)
  PollRun(String)
  PumpStream(String)
  SnapshotLoaded(String, Result[UiSnapshot, String])
  EventsLoaded(String, Result[Array[UiTimelineEntry], String])
  StreamDrained(String, Result[(Array[UiTimelineEntry], Bool), String])
  LoadAcp
  PollAcp
  PumpAcpStream
  AcpSnapshotLoaded(Result[AcpUiSnapshot, String])
  AcpEventsLoaded(Result[Array[AcpUiTimelineEntry], String])
  AcpStreamDrained(Result[(Array[AcpUiTimelineEntry], Bool), String])
  SetAcpRunMessage(String)
  AttachAcpTarget(String)
  DetachAcpSession(String)
  ResetAcpSession(String)
  StartAcpRun(String)
  CancelAcpRun(String)
  AcpActionFinished(Result[String, String])
  ExpandActiveBranches
  CollapseCompletedBranches
  ResetTree
  SelectRunsStatus(String?)
  SetRunsQuery(String)
  SelectRunsSort(RunSort)
  SelectRunsPage(Int)
  SelectMixedHandoff(String?)
  ExportMixedLineage(String)
  ExportMixedCase(String)
  ToggleNode(String)
  FocusBranchPanel(String, RightPanel)
  FocusBranchEvents(String)
  ClearTimelineScope
  FocusNode(String)
  FocusTimeline(String)
  SelectAcpNode(String)
  ToggleAcpOutput(String)
  CopyAcpOutput(String, String)
  AcpCopyFinished(Result[String, String])
  ExportAcpSession(String)
  ExportAcpSessionTimeline(String)
  ExportAcpRun(String)
  AcpExportFinished(Result[String, String])
  MixedExportFinished(Result[String, String])
  SelectPanel(RightPanel)
  UrlChanged(@url.Url)
  UrlRequest(@url.UrlRequest)
}

///|
fn gateway_base_url() -> String {
  "http://localhost:18123"
}

///|
fn runs_poll_interval_ms() -> Int {
  10000
}

///|
fn acp_poll_interval_ms() -> Int {
  5000
}

///|
fn runs_page_size() -> Int {
  12
}

///|
fn init_model() -> Model {
  {
    gateway_base: gateway_base_url(),
    route: Overview,
    selected_mixed_handoff_key: None,
    runs: [],
    runs_loading: true,
    runs_error: None,
    selected_run_id: None,
    runs_status_filter: None,
    runs_query: "",
    runs_sort: Newest,
    runs_page: 0,
    snapshot: None,
    timeline: [],
    fresh_node_ids: [],
    fresh_timeline_ids: [],
    collapsed_node_ids: [],
    expanded_node_ids: [],
    focused_node_id: None,
    timeline_scope_node_id: None,
    timeline_scope_branch_only: false,
    detail_loading: false,
    detail_error: None,
    right_panel: Artifacts,
    acp_snapshot: None,
    acp_timeline: [],
    acp_loading: true,
    acp_error: None,
    selected_acp_node_id: None,
    fresh_acp_node_ids: [],
    fresh_acp_timeline_ids: [],
    expanded_acp_output_ids: [],
    acp_run_message: "",
    acp_action_notice: None,
  }
}
