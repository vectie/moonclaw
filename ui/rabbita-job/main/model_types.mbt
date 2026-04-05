///|
enum Route {
  Overview
  Jobs
  Run(String)
  RunCanvas(String)
  Cowork
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
  SurfaceCowork
  SurfaceAcp
} derive(Eq, Compare, Show)

///|
enum CoworkPanel {
  CoworkPreview
  CoworkWorkspace
  CoworkArtifacts
  CoworkRun
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
struct LoadedArtifact {
  artifact : UiArtifact
  content : String?
} derive(FromJson, Show)

///|
struct CoworkSessionSummary {
  session_key : String
  session_id : String
  title : String
  updated_at : Int
  state : String
  last_message_preview : String?
  channel : String?
  cwd : String?
  model_override : String?
  provider_override : String?
  has_plan_mode : Bool
  linked_proposal_id : String?
  linked_run_id : String?
} derive(FromJson, Show)

///|
struct UiWorkspaceFile {
  name : String
  path : String
  content : String
} derive(FromJson, Show)

///|
struct UiWorkspaceSnapshot {
  root : String
  configured_from : String
  files : Array[UiWorkspaceFile]
  prompt_context : String
} derive(FromJson, Show)

///|
struct UiWorkspaceSnapshotPayload {
  workspace : UiWorkspaceSnapshot
} derive(FromJson, Show)

///|
struct CoworkProposalRef {
  id : String
  title : String
  summary : String
  status : String
  request_text : String
  updated_at : Int
} derive(FromJson, Show)

///|
struct CoworkRunRef {
  id : String
  job_id : String
  status : String
  summary : String?
  error : String?
  current_step_id : String?
  workspace_dir : String?
} derive(FromJson, Show)

///|
struct CoworkMessage {
  id : String
  role : String
  kind : String
  content : String
  timestamp : Int
  metadata : Json
} derive(FromJson, Show)

///|
struct CoworkSessionDetail {
  session : CoworkSessionSummary
  messages : Array[CoworkMessage]
  plan_preview : String?
  linked_proposal : CoworkProposalRef?
  linked_run : CoworkRunRef?
} derive(FromJson, Show)

///|
struct QueuedCoworkDraft {
  id : String
  action : String
  content : String
  quoted_message_id : String?
  quoted_preview : String?
} derive(Show)

///|
struct CoworkLocalUpload {
  id : String
  name : String
  media_type : String
  content : String
  source : String
} derive(FromJson, Show)

///|
struct CoworkContextChip {
  id : String
  label : String
  content : String
} derive(Show)

///|
struct CoworkSessionsPayload {
  sessions : Array[CoworkSessionSummary]
} derive(FromJson, Show)

///|
struct CoworkSessionPayload {
  session : CoworkSessionDetail
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
  artifact_modal_loading : Bool
  artifact_modal_error : String?
  artifact_modal : LoadedArtifact?
  artifact_editor_draft : String
  right_panel : RightPanel
  cowork_panel : CoworkPanel
  canvas_zoom : Int
  canvas_fullscreen : Bool
  cowork_sessions : Array[CoworkSessionSummary]
  cowork_sessions_loading : Bool
  cowork_sessions_error : String?
  selected_cowork_session_key : String?
  cowork_detail : CoworkSessionDetail?
  cowork_detail_loading : Bool
  cowork_detail_error : String?
  cowork_linked_snapshot : UiSnapshot?
  cowork_linked_snapshot_loading : Bool
  cowork_linked_snapshot_error : String?
  cowork_workspace_snapshot : UiWorkspaceSnapshot?
  cowork_workspace_loading : Bool
  cowork_workspace_error : String?
  cowork_composer : String
  cowork_title_override : String
  cowork_model_override : String
  cowork_provider_override : String
  cowork_cwd_override : String
  cowork_session_query : String
  cowork_pinned_session_keys : Array[String]
  cowork_reply_preview : String?
  cowork_local_uploads : Array[CoworkLocalUpload]
  cowork_context_chips : Array[CoworkContextChip]
  cowork_draft_queue : Array[QueuedCoworkDraft]
  cowork_queue_editing_id : String?
  cowork_queue_editing_content : String
  cowork_queue_paused : Bool
  cowork_input_history : Array[String]
  cowork_input_history_index : Int?
  cowork_notice : String?
  cowork_action_loading : Bool
  cowork_action_error : String?
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
  OpenArtifact(String)
  ArtifactLoaded(String, Result[LoadedArtifact, String])
  SetArtifactEditorDraft(String)
  CloseArtifactModal
  LoadCoworkSessions
  CoworkSessionsLoaded(Result[Array[CoworkSessionSummary], String])
  CreateCoworkSession
  CoworkSessionCreated(Result[CoworkSessionDetail, String])
  SelectCoworkSession(String)
  LoadCoworkSession(String)
  CoworkSessionLoaded(String, Result[CoworkSessionDetail, String])
  CoworkLinkedSnapshotLoaded(String, Result[UiSnapshot, String])
  CoworkWorkspaceLoaded(Result[UiWorkspaceSnapshot, String])
  SetCoworkComposer(String)
  SetCoworkTitleOverride(String)
  SetCoworkModelOverride(String)
  SetCoworkProviderOverride(String)
  SetCoworkCwdOverride(String)
  SetCoworkSessionQuery(String)
  TogglePinnedCoworkSession(String)
  SaveCoworkConfig
  OpenCoworkFilePicker
  PollCoworkDroppedFiles
  CoworkFilesPicked(Result[Array[CoworkLocalUpload], String])
  SendCoworkMessage
  StartCoworkPlan
  PreviewCoworkPlan
  PromoteCoworkPlan
  ConfirmCoworkProposal(String)
  ResumeCoworkRun(String)
  QueueCoworkDraft(String)
  RunQueuedCoworkDraft(String)
  RunAllQueuedCoworkDrafts
  RemoveQueuedCoworkDraft(String)
  MoveQueuedCoworkDraftUp(String)
  MoveQueuedCoworkDraftDown(String)
  EditQueuedCoworkDraft(String)
  SetQueuedCoworkDraftContent(String)
  SaveQueuedCoworkDraftEdit
  CancelQueuedCoworkDraftEdit
  ToggleCoworkQueuePaused
  QuoteCoworkMessage(String)
  ReuseCoworkMessage(String)
  CopyCoworkMessage(String)
  CoworkCopyFinished(Result[String, String])
  ClearCoworkReply
  RemoveCoworkLocalUpload(String)
  AttachCoworkContext(String, String, String)
  RemoveCoworkContext(String)
  RecallPreviousCoworkInput
  RecallNextCoworkInput
  CoworkActionFinished(Result[CoworkSessionDetail, String])
  SelectCoworkPanel(CoworkPanel)
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
  CanvasZoomIn
  CanvasZoomOut
  CanvasZoomReset
  ToggleCanvasFullscreen
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
    artifact_modal_loading: false,
    artifact_modal_error: None,
    artifact_modal: None,
    artifact_editor_draft: "",
    right_panel: Artifacts,
    cowork_panel: CoworkPreview,
    canvas_zoom: 100,
    canvas_fullscreen: false,
    cowork_sessions: [],
    cowork_sessions_loading: false,
    cowork_sessions_error: None,
    selected_cowork_session_key: None,
    cowork_detail: None,
    cowork_detail_loading: false,
    cowork_detail_error: None,
    cowork_linked_snapshot: None,
    cowork_linked_snapshot_loading: false,
    cowork_linked_snapshot_error: None,
    cowork_workspace_snapshot: None,
    cowork_workspace_loading: false,
    cowork_workspace_error: None,
    cowork_composer: "",
    cowork_title_override: "",
    cowork_model_override: "",
    cowork_provider_override: "",
    cowork_cwd_override: "",
    cowork_session_query: "",
    cowork_pinned_session_keys: [],
    cowork_reply_preview: None,
    cowork_local_uploads: [],
    cowork_context_chips: [],
    cowork_draft_queue: [],
    cowork_queue_editing_id: None,
    cowork_queue_editing_content: "",
    cowork_queue_paused: false,
    cowork_input_history: [],
    cowork_input_history_index: None,
    cowork_notice: None,
    cowork_action_loading: false,
    cowork_action_error: None,
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
