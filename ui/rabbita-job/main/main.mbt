///|
using @html {
  article,
  button,
  div,
  h1,
  h2,
  h3,
  header,
  input,
  main_,
  nothing,
  p,
  section,
  span,
}

///|
using @rabbita {type Cmd, type Dispatch, type Html, batch}

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
  AcpSnapshotLoaded(Result[AcpUiSnapshot, String])
  AcpEventsLoaded(Result[Array[AcpUiTimelineEntry], String])
  ExpandActiveBranches
  CollapseCompletedBranches
  ResetTree
  SelectRunsStatus(String?)
  SetRunsQuery(String)
  SelectRunsSort(RunSort)
  SelectRunsPage(Int)
  ToggleNode(String)
  FocusBranchPanel(String, RightPanel)
  FocusBranchEvents(String)
  ClearTimelineScope
  FocusNode(String)
  FocusTimeline(String)
  SelectAcpNode(String)
  SelectPanel(RightPanel)
  UrlChanged(@url.Url)
  UrlRequest(@url.UrlRequest)
}

///|
fn gateway_base_url() -> String {
  "http://localhost:4242"
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
  }
}

///|
fn status_class(status : String) -> String {
  let normalized = normalize_status(status)
  if normalized.contains("Running") {
    "status-badge running"
  } else if normalized.contains("Failed") {
    "status-badge failed"
  } else if normalized.contains("Pending") {
    "status-badge pending"
  } else {
    "status-badge"
  }
}

///|
fn run_status_is_live(status : String) -> Bool {
  let normalized = normalize_status(status)
  normalized.contains("Running") || normalized.contains("Pending")
}

///|
fn normalize_status(status : String) -> String {
  status.trim().replace(old="\"", new="").to_string()
}

///|
fn last_update_label(model : Model) -> String {
  match route_surface(model.route) {
    SurfaceJobs =>
      if model.timeline.is_empty() {
        "No events yet"
      } else {
        let entry = model.timeline[model.timeline.length() - 1]
        "Last event: \{entry.timestamp}"
      }
    SurfaceAcp =>
      if model.acp_timeline.is_empty() {
        "No events yet"
      } else {
        let entry = model.acp_timeline[model.acp_timeline.length() - 1]
        "Last event: \{entry.timestamp}"
      }
    SurfaceOverview => "Local + remote operator view"
  }
}

///|
fn acp_status_is_live(status : String) -> Bool {
  let normalized = normalize_status(status)
  normalized.contains("Running") ||
  normalized.contains("Pending") ||
  normalized.contains("Cancelling") ||
  normalized.contains("Resetting") ||
  normalized.contains("Detaching")
}

///|
fn acp_snapshot_is_live(snapshot : AcpUiSnapshot) -> Bool {
  snapshot.nodes.any(fn(node) { acp_status_is_live(node.status) })
}

///|
fn render_live_chip(model : Model) -> Html {
  match route_surface(model.route) {
    SurfaceJobs =>
      match model.snapshot {
        Some(snapshot) =>
          if model.detail_loading && run_status_is_live(snapshot.run.status) {
            span(class="status-badge pending", "Refreshing")
          } else if run_status_is_live(snapshot.run.status) {
            span(class="status-badge running", "Live")
          } else {
            span(class="status-badge", "Static")
          }
        None =>
          if model.runs_loading {
            span(class="status-badge pending", "Loading")
          } else {
            span(class="status-badge", "Idle")
          }
      }
    SurfaceAcp =>
      match model.acp_snapshot {
        Some(snapshot) =>
          if model.acp_loading && acp_snapshot_is_live(snapshot) {
            span(class="status-badge pending", "Refreshing")
          } else if acp_snapshot_is_live(snapshot) {
            span(class="status-badge running", "Live")
          } else {
            span(class="status-badge", "Static")
          }
        None =>
          if model.acp_loading {
            span(class="status-badge pending", "Loading")
          } else {
            span(class="status-badge", "Idle")
          }
      }
    SurfaceOverview =>
      if model.runs_loading || model.acp_loading {
        span(class="status-badge pending", "Loading")
      } else {
        span(class="status-badge", "Overview")
      }
  }
}

///|
fn route_from_url(url : @url.Url) -> Route {
  let path = url.path.trim().to_string()
  let parts = path
    .split("/")
    .filter(fn(part) { !part.is_empty() })
    .map(fn(part) { part.to_string() })
    .collect()
  if parts.is_empty() {
    return Overview
  }
  match parts {
    ["jobs"] => Jobs
    ["runs", run_id] => Run(run_id)
    ["acp"] => Acp
    _ => Overview
  }
}

///|
fn route_surface(route : Route) -> Surface {
  match route {
    Overview => SurfaceOverview
    Jobs => SurfaceJobs
    Run(_) => SurfaceJobs
    Acp => SurfaceAcp
  }
}

///|
fn query_value(url : @url.Url, key : String) -> String? {
  match url.query {
    Some(query) => {
      for pair in query.split("&") {
        match pair.split_once("=") {
          Some((k, value)) if k == key => return Some(value.to_string())
          _ => ()
        }
      }
      None
    }
    None => None
  }
}

///|
fn panel_query_value(panel : RightPanel) -> String {
  match panel {
    Workspace => "workspace"
    Artifacts => "artifacts"
    Memory => "memory"
  }
}

///|
fn run_sort_query_value(sort : RunSort) -> String {
  match sort {
    Newest => "newest"
    Oldest => "oldest"
    Depth => "depth"
  }
}

///|
fn run_sort_from_query(value : String?) -> RunSort {
  match value {
    Some("oldest") => Oldest
    Some("depth") => Depth
    _ => Newest
  }
}

///|
fn normalized_runs_query(query : String) -> String {
  query.trim().to_string()
}

///|
fn right_panel_from_query(value : String?) -> RightPanel? {
  match value {
    Some("workspace") => Some(Workspace)
    Some("artifacts") => Some(Artifacts)
    Some("memory") => Some(Memory)
    _ => None
  }
}

///|
fn run_url(
  run_id : String,
  runs_status_filter? : String? = None,
  runs_query? : String = "",
  runs_sort? : RunSort = Newest,
  runs_page? : Int = 0,
  focused_node_id? : String? = None,
  timeline_scope_node_id? : String? = None,
  timeline_scope_branch_only? : Bool = false,
  panel? : RightPanel? = None,
) -> String {
  let params : Array[String] = []
  match runs_status_filter {
    Some(status) => params.push("status=\{status}")
    None => ()
  }
  let query = normalized_runs_query(runs_query)
  if query != "" {
    params.push("q=\{query}")
  }
  if runs_sort != Newest {
    params.push("sort=\{run_sort_query_value(runs_sort)}")
  }
  if runs_page > 0 {
    params.push("page=\{runs_page}")
  }
  match focused_node_id {
    Some(node_id) => params.push("focus=\{node_id}")
    None => ()
  }
  match timeline_scope_node_id {
    Some(node_id) => params.push("scope=\{node_id}")
    None => ()
  }
  if timeline_scope_branch_only {
    params.push("branch=1")
  }
  match panel {
    Some(panel) => params.push("panel=\{panel_query_value(panel)}")
    None => ()
  }
  if params.is_empty() {
    "/runs/\{run_id}"
  } else {
    let query = params.join("&")
    "/runs/\{run_id}?\{query}"
  }
}

///|
fn jobs_url(
  runs_status_filter? : String? = None,
  runs_query? : String = "",
  runs_sort? : RunSort = Newest,
  runs_page? : Int = 0,
) -> String {
  let params : Array[String] = []
  match runs_status_filter {
    Some(status) => params.push("status=\{status}")
    None => ()
  }
  let query = normalized_runs_query(runs_query)
  if query != "" {
    params.push("q=\{query}")
  }
  if runs_sort != Newest {
    params.push("sort=\{run_sort_query_value(runs_sort)}")
  }
  if runs_page > 0 {
    params.push("page=\{runs_page}")
  }
  if params.is_empty() {
    "/jobs"
  } else {
    let query = params.join("&")
    "/jobs?\{query}"
  }
}

///|
fn acp_url(selected_node_id? : String? = None) -> String {
  match selected_node_id {
    Some(node_id) => "/acp?focus=\{node_id}"
    None => "/acp"
  }
}

///|
fn current_url_for_model(model : Model) -> String {
  match model.route {
    Overview => "/"
    Acp => acp_url(selected_node_id=model.selected_acp_node_id)
    Jobs =>
      jobs_url(
        runs_status_filter=model.runs_status_filter,
        runs_query=model.runs_query,
        runs_sort=model.runs_sort,
        runs_page=model.runs_page,
      )
    Run(run_id) =>
      run_url(
        run_id,
        runs_status_filter=model.runs_status_filter,
        runs_query=model.runs_query,
        runs_sort=model.runs_sort,
        runs_page=model.runs_page,
        focused_node_id=model.focused_node_id,
        timeline_scope_node_id=model.timeline_scope_node_id,
        timeline_scope_branch_only=model.timeline_scope_branch_only,
        panel=Some(model.right_panel),
      )
  }
}

///|
fn sync_url_cmd(model : Model) -> Cmd {
  @nav.replace_url(current_url_for_model(model))
}

///|
fn parse_runs_payload(json : Json) -> Result[Array[RunSummary], String] {
  let payload : Result[RunsPayload, Error] = try? @json.from_json(json)
  match payload {
    Ok(payload) => Ok(payload.runs)
    Err(error) => Err("Failed to parse runs payload: \{error}")
  }
}

///|
fn parse_snapshot_payload(json : Json) -> Result[UiSnapshot, String] {
  let payload : Result[UiSnapshotPayload, Error] = try? @json.from_json(json)
  match payload {
    Ok(payload) => Ok(payload.snapshot)
    Err(error) => Err("Failed to parse job snapshot: \{error}")
  }
}

///|
fn parse_events_payload(json : Json) -> Result[Array[UiTimelineEntry], String] {
  let payload : Result[UiEventsPayload, Error] = try? @json.from_json(json)
  match payload {
    Ok(payload) => Ok(payload.timeline)
    Err(error) => Err("Failed to parse job timeline: \{error}")
  }
}

///|
fn parse_acp_snapshot_payload(json : Json) -> Result[AcpUiSnapshot, String] {
  let payload : Result[AcpUiSnapshotPayload, Error] = try? @json.from_json(json)
  match payload {
    Ok(payload) => Ok(payload.snapshot)
    Err(error) => Err("Failed to parse ACP snapshot: \{error}")
  }
}

///|
fn parse_acp_events_payload(
  json : Json,
) -> Result[Array[AcpUiTimelineEntry], String] {
  let payload : Result[AcpUiEventsPayload, Error] = try? @json.from_json(json)
  match payload {
    Ok(payload) => Ok(payload.timeline)
    Err(error) => Err("Failed to parse ACP timeline: \{error}")
  }
}

///|
struct StreamDrainPayload {
  entries : Array[String]
  closed : Bool
  error : String?
} derive(FromJson, Show)

///|
fn parse_timeline_entry_payload(
  text : String,
) -> Result[UiTimelineEntry, String] {
  let json : Result[Json, Error] = try? @json.parse(text)
  match json {
    Ok(json) =>
      match (try? @json.from_json(json) : Result[UiTimelineEntry, Error]) {
        Ok(entry) => Ok(entry)
        Err(error) => Err("Failed to parse streamed timeline entry: \{error}")
      }
    Err(error) => Err("Failed to parse streamed timeline JSON: \{error}")
  }
}

///|
fn parse_stream_drain_payload(
  text : String,
) -> Result[(Array[UiTimelineEntry], Bool), String] {
  let json : Result[Json, Error] = try? @json.parse(text)
  let payload = match json {
    Ok(json) =>
      match (try? @json.from_json(json) : Result[StreamDrainPayload, Error]) {
        Ok(payload) => payload
        Err(error) => return Err("Failed to parse stream payload: \{error}")
      }
    Err(error) => return Err("Failed to parse stream drain JSON: \{error}")
  }
  let entries : Array[UiTimelineEntry] = []
  for raw in payload.entries {
    match parse_timeline_entry_payload(raw) {
      Ok(entry) => entries.push(entry)
      Err(error) => return Err(error)
    }
  }
  match payload.error {
    Some(error) => Err(error)
    None => Ok((entries, payload.closed))
  }
}

///|
fn fetch_runs(dispatch : Dispatch[Msg], gateway_base : String) -> Cmd {
  let expect : @http.Expecting[Cmd, Array[RunSummary]] = @http.Expecting::Json(
    fn(result) { dispatch(RunsLoaded(result)) },
    parse_runs_payload,
  )
  @http.get("\{gateway_base}/v1/jobs/runs", expect~)
}

///|
fn fetch_snapshot(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  run_id : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, UiSnapshot] = @http.Expecting::Json(
    fn(result) { dispatch(SnapshotLoaded(run_id, result)) },
    parse_snapshot_payload,
  )
  @http.get("\{gateway_base}/v1/jobs/runs/\{run_id}/ui", expect~)
}

///|
fn fetch_timeline(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  run_id : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, Array[UiTimelineEntry]] = @http.Expecting::Json(
    fn(result) { dispatch(EventsLoaded(run_id, result)) },
    parse_events_payload,
  )
  @http.get("\{gateway_base}/v1/jobs/runs/\{run_id}/events", expect~)
}

///|
fn fetch_acp_snapshot(dispatch : Dispatch[Msg], gateway_base : String) -> Cmd {
  let expect : @http.Expecting[Cmd, AcpUiSnapshot] = @http.Expecting::Json(
    fn(result) { dispatch(AcpSnapshotLoaded(result)) },
    parse_acp_snapshot_payload,
  )
  @http.get("\{gateway_base}/v1/acp/ui", expect~)
}

///|
fn fetch_acp_timeline(dispatch : Dispatch[Msg], gateway_base : String) -> Cmd {
  let expect : @http.Expecting[Cmd, Array[AcpUiTimelineEntry]] = @http.Expecting::Json(
    fn(result) { dispatch(AcpEventsLoaded(result)) },
    parse_acp_events_payload,
  )
  @http.get("\{gateway_base}/v1/acp/events", expect~)
}

///|
fn timeline_contains_entry(
  timeline : Array[UiTimelineEntry],
  target_id : String,
) -> Bool {
  for entry in timeline {
    if entry.id == target_id {
      return true
    }
  }
  false
}

///|
fn stream_entry_requires_snapshot(entry : UiTimelineEntry) -> Bool {
  let event_type = entry.event_type
  event_type == "step.succeeded" ||
  event_type == "step.failed" ||
  event_type == "step.cancelled" ||
  event_type == "job.completed" ||
  event_type == "job.failed" ||
  event_type == "job.cancelled" ||
  event_type.contains("artifact") ||
  event_type.contains("memory") ||
  event_type.contains("workspace") ||
  entry.detail.contains("child run") ||
  entry.detail.contains("spawned") ||
  entry.title.contains("ChildRun") ||
  entry.title.contains("child run")
}

///|
#cfg(target="js")
extern "js" fn start_job_ui_event_stream(url : String) =
  #| (url) => {
  #|   const key = "__moonclawJobUiStream";
  #|   const current = window[key];
  #|   if (current && current.es) current.es.close();
  #|   const state = { queue: [], closed: false, error: null, es: null };
  #|   const es = new EventSource(url);
  #|   state.es = es;
  #|   es.addEventListener("job_ui_event", (event) => { state.queue.push(event.data); });
  #|   es.addEventListener("job_ui_complete", () => {
  #|     state.closed = true;
  #|     es.close();
  #|   });
  #|   es.onerror = () => {
  #|     state.error = "stream_error";
  #|     state.closed = true;
  #|     es.close();
  #|   };
  #|   window[key] = state;
  #| }

///|
#cfg(target="js")
extern "js" fn stop_job_ui_event_stream() =
  #| () => {
  #|   const key = "__moonclawJobUiStream";
  #|   const state = window[key];
  #|   if (state && state.es) state.es.close();
  #|   window[key] = null;
  #| }

///|
#cfg(target="js")
extern "js" fn drain_job_ui_event_stream() -> String =
  #| () => {
  #|   const key = "__moonclawJobUiStream";
  #|   const state = window[key];
  #|   if (!state) return JSON.stringify({ entries: [], closed: true, error: null });
  #|   const payload = {
  #|     entries: state.queue.splice(0, state.queue.length),
  #|     closed: !!state.closed,
  #|     error: state.error,
  #|   };
  #|   if (state.closed && !state.error) window[key] = null;
  #|   return JSON.stringify(payload);
  #| }

///|
fn start_stream_cmd(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  run_id : String,
) -> Cmd {
  batch([
    @rabbita.effect(fn() noraise {
      start_job_ui_event_stream(
        "\{gateway_base}/v1/jobs/runs/\{run_id}/events/stream",
      )
    }),
    @rabbita.delay(dispatch(PumpStream(run_id)), 500),
  ])
}

///|
fn stop_stream_cmd() -> Cmd {
  @rabbita.effect(fn() noraise { stop_job_ui_event_stream() })
}

///|
fn drain_stream_cmd(dispatch : Dispatch[Msg], run_id : String) -> Cmd {
  @rabbita.perform(
    fn(raw) { dispatch(StreamDrained(run_id, parse_stream_drain_payload(raw))) },
    fn() noraise { drain_job_ui_event_stream() },
  )
}

///|
fn load_run_cmd(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  run_id : String,
) -> Cmd {
  batch([
    fetch_snapshot(dispatch, gateway_base, run_id),
    fetch_timeline(dispatch, gateway_base, run_id),
  ])
}

///|
fn contains_id(ids : Array[String], target : String) -> Bool {
  for id in ids {
    if id == target {
      return true
    }
  }
  false
}

///|
fn[T] fresh_ids_from(
  current : Array[T],
  previous_ids : Array[String],
  id_of : (T) -> String,
) -> Array[String] {
  let fresh : Array[String] = []
  for item in current {
    let id = id_of(item)
    if !contains_id(previous_ids, id) {
      fresh.push(id)
    }
  }
  fresh
}

///|
fn node_state_class(
  model : Model,
  snapshot : UiSnapshot,
  node : UiNode,
) -> String {
  let mut classes = "tree-node"
  if node.kind == "ChildRun" {
    classes = classes + " delegated"
  }
  if node.provisional {
    classes = classes + " provisional"
  }
  if snapshot.current_step_id == node.step_id {
    classes = classes + " active"
  }
  if normalize_status(node.status).contains("Failed") {
    classes = classes + " failed"
  }
  if contains_id(model.fresh_node_ids, node.id) {
    classes = classes + " fresh"
  }
  if model.focused_node_id == Some(node.id) {
    classes = classes + " focused"
  }
  classes
}

///|
fn render_status_badge(status : String) -> Html {
  span(class=status_class(status), normalize_status(status))
}

///|
fn render_meta_chip(label : String, value : String) -> Html {
  span(class="meta-chip", "\{label}: \{value}")
}

///|
fn render_action_chip(label : String, on_click : Cmd) -> Html {
  button(class="meta-chip meta-chip-button", on_click~, label)
}

///|
fn timeline_data_badges(entry : UiTimelineEntry) -> Array[Html] {
  let badges : Array[Html] = []
  match entry.data {
    { "attempt": Number(attempt, ..), .. } =>
      badges.push(render_meta_chip("attempt", attempt.to_string()))
    _ => ()
  }
  match entry.data {
    { "step_kind": String(step_kind), .. } =>
      badges.push(render_meta_chip("kind", step_kind))
    _ => ()
  }
  match entry.data {
    { "workflow_kind": String(workflow_kind), .. } =>
      badges.push(render_meta_chip("workflow", workflow_kind))
    _ => ()
  }
  match entry.data {
    { "step_count": Number(step_count, ..), .. } =>
      badges.push(render_meta_chip("steps", step_count.to_string()))
    _ => ()
  }
  match entry.data {
    { "metrics": Object(metrics), .. } if !metrics.is_empty() =>
      badges.push(render_meta_chip("metrics", metrics.length().to_string()))
    _ => ()
  }
  if entry.event_type.contains("artifact") {
    badges.push(render_meta_chip("output", "artifact"))
  }
  if entry.event_type.contains("memory") {
    badges.push(render_meta_chip("output", "memory"))
  }
  if entry.event_type.contains("workspace") {
    badges.push(render_meta_chip("output", "workspace"))
  }
  if entry.detail.contains("spawned") || entry.detail.contains("child run") {
    badges.push(render_meta_chip("branch", "child-run"))
  }
  badges
}

///|
fn preview_text(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else {
    text[:limit].to_string() + "..."
  }
}

///|
fn panel_for_node(model : Model, node : UiNode) -> RightPanel {
  if node.artifact_id is Some(_) {
    Artifacts
  } else if node.memory_id is Some(_) {
    Memory
  } else {
    model.right_panel
  }
}

///|
fn node_title_for_step(snapshot : UiSnapshot, step_id : String) -> String {
  for node in snapshot.nodes {
    if node.step_id == Some(step_id) {
      return node.title
    }
  }
  step_id
}

///|
fn node_for_id(snapshot : UiSnapshot, node_id : String) -> UiNode? {
  for node in snapshot.nodes {
    if node.id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn node_id_for_entry(snapshot : UiSnapshot, entry : UiTimelineEntry) -> String? {
  match entry.step_id {
    Some(step_id) => {
      for node in snapshot.nodes {
        if node.step_id == Some(step_id) {
          return Some(node.id)
        }
      }
      None
    }
    None => {
      for node in snapshot.nodes {
        if node.run_id == Some(entry.run_id) && node.kind == "ChildRun" {
          return Some(node.id)
        }
      }
      for node in snapshot.nodes {
        if node.run_id == Some(entry.run_id) && node.kind == "Workflow" {
          return Some(node.id)
        }
      }
      None
    }
  }
}

///|
fn current_step_title(snapshot : UiSnapshot) -> String {
  match snapshot.current_step_id {
    Some(step_id) => node_title_for_step(snapshot, step_id)
    None => "pending"
  }
}

///|
fn latest_fresh_title(
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  fresh_ids : Array[String],
) -> String? {
  for i = timeline.length() - 1; i >= 0; i = i - 1 {
    let entry = timeline[i]
    if contains_id(fresh_ids, entry.id) {
      return Some(entry.title)
    }
  }
  for node in snapshot.nodes {
    if contains_id(fresh_ids, node.id) {
      return Some(node.title)
    }
  }
  None
}

///|
fn fallback_focus_node_id(snapshot : UiSnapshot) -> String? {
  match snapshot.current_step_id {
    Some(step_id) => {
      for node in snapshot.nodes {
        if node.step_id == Some(step_id) {
          return Some(node.id)
        }
      }
      None
    }
    None => {
      for node in snapshot.nodes {
        if node.kind == "Workflow" {
          return Some(node.id)
        }
      }
      snapshot.nodes.get(0).map(fn(node) { node.id })
    }
  }
}

///|
fn resolved_focus_node_id(model : Model, snapshot : UiSnapshot) -> String? {
  match model.focused_node_id {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(_) => Some(node_id)
        None => fallback_focus_node_id(snapshot)
      }
    None => fallback_focus_node_id(snapshot)
  }
}

///|
fn group_title_for(entry : UiTimelineEntry) -> String {
  match entry.step_id {
    Some(step_id) => "Step · \{step_id}"
    None => "Run · \{entry.run_id}"
  }
}

///|
fn group_id_for(entry : UiTimelineEntry) -> String {
  match entry.step_id {
    Some(step_id) => "step:\{step_id}"
    None => "run:\{entry.run_id}"
  }
}

///|
fn timeline_groups(timeline : Array[UiTimelineEntry]) -> Array[TimelineGroup] {
  let groups : Array[TimelineGroup] = []
  for entry in timeline {
    let group_id = group_id_for(entry)
    let mut matched = false
    for i = 0; i < groups.length(); i = i + 1 {
      if groups[i].id == group_id {
        groups[i] = { ..groups[i], entries: groups[i].entries + [entry] }
        matched = true
        break
      }
    }
    if !matched {
      groups.push({
        id: group_id,
        title: group_title_for(entry),
        entries: [entry],
      })
    }
  }
  groups
}

///|
fn timeline_entry_class(
  model : Model,
  snapshot : UiSnapshot?,
  entry : UiTimelineEntry,
) -> String {
  let mut classes = "timeline-entry"
  if contains_id(model.fresh_timeline_ids, entry.id) {
    classes = classes + " fresh"
  }
  match snapshot {
    Some(snapshot) =>
      match model.focused_node_id {
        Some(focused_node_id) =>
          match node_id_for_entry(snapshot, entry) {
            Some(node_id) =>
              if node_id == focused_node_id {
                classes = classes + " focused"
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  classes
}

///|
fn view_run_card(
  dispatch : Dispatch[Msg],
  selected_run_id : String?,
  run : RunSummary,
) -> Html {
  let active = selected_run_id == Some(run.id)
  let card_class = if active { "run-card active" } else { "run-card" }
  button(class=card_class, on_click=dispatch(SelectRun(run.id)), [
    p(class="run-title", "\{run.job_id}"),
    div([render_status_badge(run.status)]),
    p(class="run-meta", "Run \{run.id} · depth \{run.depth}"),
    match run.summary {
      Some(summary) => p(class="run-meta", summary)
      None => nothing
    },
  ])
}

///|
fn filtered_runs(model : Model) -> Array[RunSummary] {
  let filtered = match model.runs_status_filter {
    Some(status) =>
      model.runs.filter(fn(run) {
        normalize_status(run.status).contains(status)
      })
    None => model.runs
  }
  let queried = if normalized_runs_query(model.runs_query) == "" {
    filtered
  } else {
    let query = normalized_runs_query(model.runs_query).to_lower()
    filtered.filter(fn(run) {
      run.id.to_lower().contains(query) ||
      run.job_id.to_lower().contains(query) ||
      run.status.to_lower().contains(query) ||
      run.summary.unwrap_or("").to_lower().contains(query)
    })
  }
  let sorted = queried.copy()
  match model.runs_sort {
    Newest =>
      sorted.sort_by(fn(left, right) {
        right.started_at.unwrap_or(0).compare(left.started_at.unwrap_or(0))
      })
    Oldest =>
      sorted.sort_by(fn(left, right) {
        left.started_at.unwrap_or(0).compare(right.started_at.unwrap_or(0))
      })
    Depth => sorted.sort_by(fn(left, right) { right.depth.compare(left.depth) })
  }
  sorted
}

///|
fn clamped_runs_page(model : Model, total_runs : Int) -> Int {
  if total_runs <= 0 {
    0
  } else {
    let last_page = (total_runs - 1) / runs_page_size()
    if model.runs_page < 0 {
      0
    } else if model.runs_page > last_page {
      last_page
    } else {
      model.runs_page
    }
  }
}

///|
fn paged_runs(model : Model, runs : Array[RunSummary]) -> Array[RunSummary] {
  let page = clamped_runs_page(model, runs.length())
  let start = page * runs_page_size()
  let page_runs : Array[RunSummary] = []
  for i = start; i < runs.length() && i < start + runs_page_size(); i = i + 1 {
    page_runs.push(runs[i])
  }
  page_runs
}

///|
fn render_runs_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  let runs = filtered_runs(model)
  let page = clamped_runs_page(model, runs.length())
  let visible_runs = paged_runs(model, runs)
  let total_pages = if runs.is_empty() {
    1
  } else {
    (runs.length() - 1) / runs_page_size() + 1
  }
  let status_button = fn(label : String, value : String?) {
    let active = model.runs_status_filter == value
    let cls = if active {
      "tree-control-button active-filter"
    } else {
      "tree-control-button"
    }
    button(class=cls, on_click=dispatch(SelectRunsStatus(value)), label)
  }
  let sort_button = fn(label : String, value : RunSort) {
    let active = model.runs_sort == value
    let cls = if active {
      "tree-control-button active-filter"
    } else {
      "tree-control-button"
    }
    button(class=cls, on_click=dispatch(SelectRunsSort(value)), label)
  }
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Runs")]),
    div(class="panel-body", [
      div(class="runs-controls", [
        div(class="tree-controls", [
          status_button("All", None),
          status_button("Running", Some("Running")),
          status_button("Pending", Some("Pending")),
          status_button("Failed", Some("Failed")),
          status_button("Completed", Some("Completed")),
        ]),
        div(class="runs-search-row", [
          input(
            class="runs-search-input",
            placeholder="Search run id, job id, or summary",
            value=model.runs_query,
            on_input=value => dispatch(SetRunsQuery(value)),
            nothing,
          ),
        ]),
        div(class="tree-controls", [
          sort_button("Newest", Newest),
          sort_button("Oldest", Oldest),
          sort_button("Depth", Depth),
        ]),
      ]),
      if model.runs_loading {
        p(class="empty", "Loading runs...")
      } else if model.runs_error is Some(error) {
        p(class="empty", error)
      } else if runs.is_empty() {
        p(class="empty", "No job runs available yet.")
      } else {
        div([
          div(
            class="runs-list",
            visible_runs.map(fn(run) {
              view_run_card(dispatch, model.selected_run_id, run)
            }),
          ),
          div(class="runs-pagination", [
            span(class="muted", "Page \{page + 1} of \{total_pages}"),
            div(class="tree-controls", [
              button(
                class="tree-control-button",
                disabled=page == 0,
                on_click=dispatch(SelectRunsPage(page - 1)),
                "Prev",
              ),
              button(
                class="tree-control-button",
                disabled=page + 1 >= total_pages,
                on_click=dispatch(SelectRunsPage(page + 1)),
                "Next",
              ),
            ]),
          ]),
        ])
      },
    ]),
  ])
}

///|
fn acp_node_for_id(snapshot : AcpUiSnapshot, node_id : String) -> AcpUiNode? {
  for node in snapshot.nodes {
    if node.id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn acp_kind_label(kind : AcpUiNodeKind) -> String {
  match kind {
    Target => "Target"
    Session => "Session"
    Run => "Run"
  }
}

///|
fn resolved_acp_node_id(model : Model, snapshot : AcpUiSnapshot) -> String? {
  match model.selected_acp_node_id {
    Some(node_id) =>
      match acp_node_for_id(snapshot, node_id) {
        Some(_) => Some(node_id)
        None => snapshot.nodes.get(0).map(fn(node) { node.id })
      }
    None => snapshot.nodes.get(0).map(fn(node) { node.id })
  }
}

///|
fn acp_timeline_for_node(
  node : AcpUiNode,
  timeline : Array[AcpUiTimelineEntry],
) -> Array[AcpUiTimelineEntry] {
  timeline.filter(fn(entry) {
    match node.kind {
      Target => entry.target_id == node.target_id
      Session => entry.session_id == node.session_id
      Run => entry.run_id == node.run_id
    }
  })
}

///|
fn acp_node_for_entry(
  snapshot : AcpUiSnapshot,
  entry : AcpUiTimelineEntry,
) -> AcpUiNode? {
  for node in snapshot.nodes {
    if !acp_timeline_for_node(node, [entry]).is_empty() {
      return Some(node)
    }
  }
  None
}

///|
fn acp_timeline_entry_class(
  model : Model,
  entry : AcpUiTimelineEntry,
) -> String {
  let mut classes = "timeline-entry"
  if contains_id(model.fresh_acp_timeline_ids, entry.id) {
    classes = classes + " fresh"
  }
  match model.selected_acp_node_id {
    Some(node_id) =>
      match model.acp_snapshot {
        Some(snapshot) =>
          match acp_node_for_id(snapshot, node_id) {
            Some(node) =>
              if acp_timeline_for_node(node, [entry]).length() > 0 {
                classes = classes + " focused"
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  classes
}

///|
fn render_acp_node_card(
  dispatch : Dispatch[Msg],
  model : Model,
  node : AcpUiNode,
) -> Html {
  let active = model.selected_acp_node_id == Some(node.id)
  let fresh = contains_id(model.fresh_acp_node_ids, node.id)
  let cls = if active {
    "run-card active"
  } else if fresh {
    "run-card fresh"
  } else {
    "run-card"
  }
  button(class=cls, on_click=dispatch(SelectAcpNode(node.id)), [
    p(class="node-kind", acp_kind_label(node.kind)),
    p(class="run-title", node.title),
    div([render_status_badge(node.status)]),
    match node.summary {
      Some(summary) => p(class="run-meta", preview_text(summary, 120))
      None => nothing
    },
    match node.detail {
      Some(detail) => p(class="run-meta mono", preview_text(detail, 120))
      None => nothing
    },
  ])
}

///|
fn render_acp_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "ACP Remote Agents")]),
    div(class="panel-body", [
      if model.acp_loading && model.acp_snapshot is None {
        p(class="empty", "Loading ACP targets, sessions, and runs...")
      } else if model.acp_error is Some(error) {
        p(class="empty", error)
      } else {
        match model.acp_snapshot {
          Some(snapshot) =>
            div(class="runs-list", [
              article(class="overview-stat", [
                p(class="kv-label", "Targets"),
                p(class="detail-title", "\{snapshot.targets.length()}"),
              ]),
              article(class="overview-stat", [
                p(class="kv-label", "Sessions"),
                p(class="detail-title", "\{snapshot.sessions.length()}"),
              ]),
              article(class="overview-stat", [
                p(class="kv-label", "Runs"),
                p(class="detail-title", "\{snapshot.runs.length()}"),
              ]),
              p(class="kv-label", "Targets"),
              div(
                class="runs-list",
                snapshot.nodes
                .filter(fn(node) { node.kind == Target })
                .map(fn(node) { render_acp_node_card(dispatch, model, node) }),
              ),
              p(class="kv-label", "Sessions"),
              div(
                class="runs-list",
                snapshot.nodes
                .filter(fn(node) { node.kind == Session })
                .map(fn(node) { render_acp_node_card(dispatch, model, node) }),
              ),
              p(class="kv-label", "Runs"),
              div(
                class="runs-list",
                snapshot.nodes
                .filter(fn(node) { node.kind == Run })
                .map(fn(node) { render_acp_node_card(dispatch, model, node) }),
              ),
            ])
          None => p(class="empty", "No ACP targets configured yet.")
        }
      },
    ]),
  ])
}

///|
fn render_acp_timeline(
  dispatch : Dispatch[Msg],
  model : Model,
  timeline : Array[AcpUiTimelineEntry],
) -> Html {
  if timeline.is_empty() {
    p(class="empty", "No ACP activity yet.")
  } else {
    div(
      class="timeline",
      timeline.map(fn(entry) {
        button(
          class=acp_timeline_entry_class(model, entry),
          on_click=match model.acp_snapshot {
            Some(snapshot) =>
              match acp_node_for_entry(snapshot, entry) {
                Some(node) => dispatch(SelectAcpNode(node.id))
                None => @rabbita.none
              }
            None => @rabbita.none
          },
          [
            p(class="timeline-title", entry.title),
            p(class="timeline-detail", preview_text(entry.detail, 220)),
            div([
              match entry.status {
                Some(status) => render_status_badge(status)
                None => nothing
              },
              span(class="muted mono", "\{entry.timestamp}"),
            ]),
          ],
        )
      }),
    )
  }
}

///|
fn render_stdio_preview(label : String, value : String?) -> Html {
  match value {
    Some(text) if !text.trim().is_blank() =>
      div(class="focus-block", [
        p(class="kv-label", label),
        article(class="artifact-card", [
          p(class="timeline-detail mono", preview_text(text, 320)),
        ]),
      ])
    _ => nothing
  }
}

///|
fn render_acp_detail(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.acp_snapshot {
    Some(snapshot) =>
      match resolved_acp_node_id(model, snapshot) {
        Some(node_id) =>
          match acp_node_for_id(snapshot, node_id) {
            Some(node) => {
              let related = acp_timeline_for_node(node, model.acp_timeline)
              section(class="panel", [
                header(class="panel-header", [
                  div(class="detail-header", [
                    div([
                      p(class="eyebrow", "Remote ACP Control"),
                      h2(class="detail-title", node.title),
                      p(
                        class="subline",
                        node.summary.unwrap_or(
                          "Attached ACP targets, sessions, and remote runs.",
                        ),
                      ),
                    ]),
                    render_status_badge(node.status),
                  ]),
                ]),
                div(class="panel-body", [
                  if model.acp_loading {
                    div(class="refresh-banner", [
                      p(class="kv-label", "ACP Refresh"),
                      p(
                        class="timeline-detail",
                        "Refreshing remote-agent state...",
                      ),
                    ])
                  } else {
                    nothing
                  },
                  div(class="detail-grid", [
                    section([
                      h3(class="section-title", "Remote Timeline"),
                      render_acp_timeline(dispatch, model, related),
                    ]),
                  ]),
                ]),
              ])
            }
            None =>
              section(class="panel", [
                header(class="panel-header", [
                  h2(class="panel-title", "ACP Detail"),
                ]),
                div(class="panel-body", [
                  p(class="empty", "Select an ACP node."),
                ]),
              ])
          }
        None =>
          section(class="panel", [
            header(class="panel-header", [h2(class="panel-title", "ACP Detail")]),
            div(class="panel-body", [
              p(class="empty", "No ACP state available yet."),
            ]),
          ])
      }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "ACP Detail")]),
        div(class="panel-body", [p(class="empty", "Loading ACP state...")]),
      ])
  }
}

///|
fn render_acp_inspector(model : Model) -> Html {
  match model.acp_snapshot {
    Some(snapshot) =>
      match resolved_acp_node_id(model, snapshot) {
        Some(node_id) =>
          match acp_node_for_id(snapshot, node_id) {
            Some(node) => {
              let related = acp_timeline_for_node(node, model.acp_timeline)
              let stdout_preview = match node.metadata {
                { "stdout_stderr": { "stdout": String(stdout), .. }, .. } =>
                  Some(stdout)
                _ => None
              }
              let stderr_preview = match node.metadata {
                { "stdout_stderr": { "stderr": String(stderr), .. }, .. } =>
                  Some(stderr)
                _ => None
              }
              section(class="panel", [
                header(class="panel-header", [
                  h2(class="panel-title", "ACP Inspector"),
                ]),
                div(class="panel-body", [
                  p(class="node-kind", acp_kind_label(node.kind)),
                  p(class="node-title", node.title),
                  div([render_status_badge(node.status)]),
                  match node.detail {
                    Some(detail) => p(class="mono", detail)
                    None => nothing
                  },
                  match node.summary {
                    Some(summary) => p(class="timeline-detail", summary)
                    None => nothing
                  },
                  div(class="inspector-stats", [
                    render_meta_chip("events", related.length().to_string()),
                    match node.target_id {
                      Some(target_id) => render_meta_chip("target", target_id)
                      None => nothing
                    },
                    match node.session_id {
                      Some(session_id) =>
                        render_meta_chip("session", session_id)
                      None => nothing
                    },
                    match node.run_id {
                      Some(run_id) => render_meta_chip("run", run_id)
                      None => nothing
                    },
                  ]),
                  render_stdio_preview("stdout", stdout_preview),
                  render_stdio_preview("stderr", stderr_preview),
                  if related.is_empty() {
                    p(class="empty", "No related ACP events yet.")
                  } else {
                    div(
                      class="focus-events",
                      preview_items(related, 6).map(fn(entry) {
                        article(class="focus-event", [
                          p(class="timeline-title", entry.title),
                          p(class="muted", preview_text(entry.detail, 180)),
                        ])
                      }),
                    )
                  },
                ]),
              ])
            }
            None =>
              section(class="panel", [
                header(class="panel-header", [
                  h2(class="panel-title", "ACP Inspector"),
                ]),
                div(class="panel-body", [
                  p(class="empty", "Select an ACP node."),
                ]),
              ])
          }
        None =>
          section(class="panel", [
            header(class="panel-header", [
              h2(class="panel-title", "ACP Inspector"),
            ]),
            div(class="panel-body", [p(class="empty", "No ACP node selected.")]),
          ])
      }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "ACP Inspector")]),
        div(class="panel-body", [p(class="empty", "Loading ACP state...")]),
      ])
  }
}

///|
fn render_overview(model : Model) -> Html {
  let local_running = model.runs
    .filter(fn(run) { run_status_is_live(run.status) })
    .length()
  let acp_live = match model.acp_snapshot {
    Some(snapshot) =>
      snapshot.nodes
      .filter(fn(node) { acp_status_is_live(node.status) })
      .length()
    None => 0
  }
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Operator Overview")]),
    div(class="panel-body", [
      div(class="overview-grid", [
        article(class="overview-stat", [
          p(class="kv-label", "Local Runs"),
          p(class="detail-title", "\{model.runs.length()}"),
          p(class="muted", "\{local_running} live in the local agent"),
        ]),
        article(class="overview-stat", [
          p(class="kv-label", "ACP Remote Nodes"),
          p(
            class="detail-title",
            match model.acp_snapshot {
              Some(snapshot) => "\{snapshot.nodes.length()}"
              None => "0"
            },
          ),
          p(
            class="muted",
            "\{acp_live} live across remote ACP sessions and runs",
          ),
        ]),
      ]),
      div(class="overview-grid", [
        section(class="panel nested-panel", [
          header(class="panel-header", [h2(class="panel-title", "Local Agent")]),
          div(class="panel-body", [
            if model.runs.is_empty() {
              p(class="empty", "No local jobs yet.")
            } else {
              div(
                class="runs-list",
                preview_items(filtered_runs(model), 4).map(fn(run) {
                  article(class="artifact-card", [
                    p(class="node-title", run.job_id),
                    div([render_status_badge(run.status)]),
                    p(
                      class="muted",
                      preview_text(run.summary.unwrap_or(run.id), 120),
                    ),
                  ])
                }),
              )
            },
          ]),
        ]),
        section(class="panel nested-panel", [
          header(class="panel-header", [h2(class="panel-title", "Remote ACP")]),
          div(class="panel-body", [
            match model.acp_snapshot {
              Some(snapshot) =>
                if snapshot.nodes.is_empty() {
                  p(class="empty", "No ACP state yet.")
                } else {
                  div(
                    class="runs-list",
                    preview_items(snapshot.nodes, 4).map(fn(node) {
                      article(class="artifact-card", [
                        p(class="node-title", node.title),
                        div([render_status_badge(node.status)]),
                        p(
                          class="muted",
                          preview_text(node.summary.unwrap_or(node.id), 120),
                        ),
                      ])
                    }),
                  )
                }
              None => p(class="empty", "Loading ACP state...")
            },
          ]),
        ]),
      ]),
    ]),
  ])
}

///|
fn node_is_root(snapshot : UiSnapshot, node : UiNode) -> Bool {
  match node.parent_id {
    None => true
    Some(parent_id) =>
      !snapshot.nodes.any(fn(candidate) { candidate.id == parent_id })
  }
}

///|
fn child_nodes(snapshot : UiSnapshot, parent_id : String) -> Array[UiNode] {
  snapshot.nodes.filter(fn(node) { node.parent_id == Some(parent_id) })
}

///|
fn descendant_nodes(snapshot : UiSnapshot, node : UiNode) -> Array[UiNode] {
  let descendants : Array[UiNode] = []
  let frontier = child_nodes(snapshot, node.id)
  while !frontier.is_empty() {
    match frontier.pop() {
      Some(current) => {
        descendants.push(current)
        for child in child_nodes(snapshot, current.id) {
          frontier.push(child)
        }
      }
      None => ()
    }
  }
  descendants
}

///|
fn parent_node(snapshot : UiSnapshot, node : UiNode) -> UiNode? {
  match node.parent_id {
    Some(parent_id) => node_for_id(snapshot, parent_id)
    None => None
  }
}

///|
fn node_has_collapsible_children(snapshot : UiSnapshot, node : UiNode) -> Bool {
  !child_nodes(snapshot, node.id).is_empty()
}

///|
fn auto_collapsible_node(snapshot : UiSnapshot, node : UiNode) -> Bool {
  node_has_collapsible_children(snapshot, node) &&
  !node.provisional &&
  !normalize_status(node.status).contains("Running") &&
  !normalize_status(node.status).contains("Pending") &&
  !normalize_status(node.status).contains("Failed")
}

///|
fn parent_chain_ids(snapshot : UiSnapshot, node_id : String) -> Array[String] {
  let ids : Array[String] = []
  let mut current = node_for_id(snapshot, node_id)
  while current is Some(_) {
    match current {
      Some(node) =>
        match node.parent_id {
          Some(parent_id) => {
            ids.push(parent_id)
            current = node_for_id(snapshot, parent_id)
          }
          None => current = None
        }
      None => ()
    }
  }
  ids
}

///|
fn auto_collapsed_ids(snapshot : UiSnapshot) -> Array[String] {
  snapshot.nodes
  .filter(fn(node) { auto_collapsible_node(snapshot, node) })
  .map(fn(node) { node.id })
}

///|
fn manual_tree_state_for_snapshot(
  model : Model,
  snapshot : UiSnapshot,
) -> (Array[String], Array[String]) {
  let node_ids = snapshot.nodes.map(fn(node) { node.id })
  let collapsed = model.collapsed_node_ids.filter(fn(id) {
    contains_id(node_ids, id)
  })
  let expanded = model.expanded_node_ids.filter(fn(id) {
    contains_id(node_ids, id)
  })
  (collapsed, expanded)
}

///|
fn keep_expanded_node(
  snapshot : UiSnapshot,
  model : Model,
  node : UiNode,
) -> Bool {
  contains_id(model.fresh_node_ids, node.id) ||
  model.focused_node_id == Some(node.id) ||
  snapshot.current_step_id == node.step_id ||
  contains_id(
    parent_chain_ids(snapshot, model.focused_node_id.unwrap_or("")),
    node.id,
  ) ||
  normalize_status(node.status).contains("Running") ||
  normalize_status(node.status).contains("Pending") ||
  normalize_status(node.status).contains("Failed")
}

///|
fn node_is_collapsed(
  model : Model,
  snapshot : UiSnapshot,
  node : UiNode,
) -> Bool {
  let focus_path = parent_chain_ids(
    snapshot,
    model.focused_node_id.unwrap_or(""),
  )
  if keep_expanded_node(snapshot, model, node) {
    false
  } else if contains_id(model.collapsed_node_ids, node.id) {
    true
  } else if contains_id(model.expanded_node_ids, node.id) {
    false
  } else {
    auto_collapsible_node(snapshot, node) &&
    !contains_id(model.fresh_node_ids, node.id) &&
    model.focused_node_id != Some(node.id) &&
    !contains_id(focus_path, node.id)
  }
}

///|
fn toggle_manual_tree_state(
  model : Model,
  snapshot : UiSnapshot,
  node_id : String,
) -> (Array[String], Array[String]) {
  match node_for_id(snapshot, node_id) {
    Some(node) if node_has_collapsible_children(snapshot, node) => {
      let collapsed = model.collapsed_node_ids
      let expanded = model.expanded_node_ids
      if node_is_collapsed(model, snapshot, node) {
        (
          collapsed.filter(fn(id) { id != node_id }),
          if contains_id(expanded, node_id) {
            expanded
          } else {
            expanded + [node_id]
          },
        )
      } else {
        (
          if contains_id(collapsed, node_id) {
            collapsed
          } else {
            collapsed + [node_id]
          },
          expanded.filter(fn(id) { id != node_id }),
        )
      }
    }
    _ => (model.collapsed_node_ids, model.expanded_node_ids)
  }
}

///|
fn collapsed_summary(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> String {
  let stats = lineage_event_stats(snapshot, node, timeline)
  let child_count = descendant_nodes(snapshot, node).length()
  let parts : Array[String] = ["\{child_count} nodes"]
  if stats.artifact_hits > 0 {
    parts.push("\{stats.artifact_hits} artifacts")
  }
  if stats.memory_hits > 0 {
    parts.push("\{stats.memory_hits} memories")
  }
  if stats.failed_events > 0 {
    parts.push("\{stats.failed_events} failures")
  }
  if stats.max_attempt > 1 {
    parts.push("retry x\{stats.max_attempt}")
  }
  let mut summary = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      summary = summary + " · "
    }
    summary = summary + parts[i]
  }
  summary
}

///|
fn render_collapsed_actions(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Html {
  let stats = lineage_event_stats(snapshot, node, timeline)
  let has_actions = stats.artifact_hits > 0 ||
    stats.memory_hits > 0 ||
    stats.failed_events > 0
  if !has_actions {
    nothing
  } else {
    div(class="timeline-meta", [
      if stats.artifact_hits > 0 {
        render_action_chip(
          "Open Artifacts",
          dispatch(FocusBranchPanel(node.id, Artifacts)),
        )
      } else {
        nothing
      },
      if stats.memory_hits > 0 {
        render_action_chip(
          "Open Memory",
          dispatch(FocusBranchPanel(node.id, Memory)),
        )
      } else {
        nothing
      },
      if stats.failed_events > 0 {
        render_action_chip(
          "Inspect Failures",
          dispatch(FocusBranchEvents(node.id)),
        )
      } else {
        nothing
      },
    ])
  }
}

///|
fn render_tree_node(
  model : Model,
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  node : UiNode,
  depth : Int,
) -> Html {
  let children = child_nodes(snapshot, node.id)
  let has_children = !children.is_empty()
  let collapsed = node_is_collapsed(model, snapshot, node)
  div(style=["margin-left: \{depth * 18}px;"], [
    div(class="tree-node-row", [
      if has_children {
        button(
          class="tree-toggle",
          on_click=dispatch(ToggleNode(node.id)),
          if collapsed {
            "Expand"
          } else {
            "Collapse"
          },
        )
      } else {
        nothing
      },
      button(
        class=node_state_class(model, snapshot, node) + " tree-node-body",
        on_click=dispatch(FocusNode(node.id)),
        [
          p(class="node-kind", node.kind),
          p(class="node-title", node.title),
          div([render_status_badge(node.status)]),
          div(class="node-meta", [
            render_meta_chip("node", node.id),
            match node.step_id {
              Some(step_id) => render_meta_chip("step", step_id)
              None => nothing
            },
            match node.run_id {
              Some(run_id) => render_meta_chip("run", run_id)
              None => nothing
            },
            if node.provisional {
              render_meta_chip("state", "provisional")
            } else if node.kind == "ChildRun" {
              render_meta_chip("state", "delegated")
            } else {
              nothing
            },
          ]),
          render_node_badges(snapshot, node, model.timeline),
          match node.summary {
            Some(summary) => p(class="muted", summary)
            None => nothing
          },
          match node.detail {
            Some(detail) => p(class="muted mono", detail)
            None => nothing
          },
          if collapsed {
            div([
              p(
                class="collapsed-summary",
                "Collapsed branch: \{collapsed_summary(snapshot, node, model.timeline)}",
              ),
              render_collapsed_actions(dispatch, snapshot, node, model.timeline),
            ])
          } else {
            nothing
          },
        ],
      ),
    ]),
    if children.is_empty() || collapsed {
      nothing
    } else {
      div(
        class="tree-children",
        children.map(fn(child) {
          render_tree_node(model, dispatch, snapshot, child, depth + 1)
        }),
      )
    },
  ])
}

///|
fn render_tree(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
) -> Html {
  let roots = snapshot.nodes.filter(fn(node) { node_is_root(snapshot, node) })
  div(
    class="tree",
    roots.map(fn(node) { render_tree_node(model, dispatch, snapshot, node, 0) }),
  )
}

///|
fn render_tree_controls(dispatch : Dispatch[Msg]) -> Html {
  div(class="tree-controls", [
    button(
      class="tree-control-button",
      on_click=dispatch(ExpandActiveBranches),
      "Expand Active",
    ),
    button(
      class="tree-control-button",
      on_click=dispatch(CollapseCompletedBranches),
      "Collapse Completed",
    ),
    button(
      class="tree-control-button",
      on_click=dispatch(ResetTree),
      "Reset Tree",
    ),
  ])
}

///|
fn scoped_timeline(
  model : Model,
  snapshot : UiSnapshot,
) -> Array[UiTimelineEntry] {
  match model.timeline_scope_node_id {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(node) =>
          if model.timeline_scope_branch_only {
            branch_only_timeline_for_node(snapshot, node, model.timeline)
          } else {
            lineage_timeline_for_node(snapshot, node, model.timeline)
          }
        None => model.timeline
      }
    None => model.timeline
  }
}

///|
fn timeline_scope_label(model : Model, snapshot : UiSnapshot) -> String? {
  match model.timeline_scope_node_id {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(node) =>
          Some(
            if model.timeline_scope_branch_only {
              "Branch timeline · \{node.title}"
            } else {
              "Scoped timeline · \{node.title}"
            },
          )
        None => None
      }
    None => None
  }
}

///|
fn render_active_strip(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  fresh_ids : Array[String],
) -> Html {
  let latest_title = latest_fresh_title(snapshot, timeline, fresh_ids).unwrap_or(
    current_step_title(snapshot),
  )
  section(class="active-strip", [
    p(class="active-strip-label", "Currently Expanding"),
    div(class="active-strip-body", [
      render_status_badge(snapshot.run.status),
      p(class="active-strip-title", latest_title),
      p(class="muted", "Current step: \{current_step_title(snapshot)}"),
      match timeline_scope_label(model, snapshot) {
        Some(label) =>
          div(class="timeline-scope-bar", [
            span(class="meta-chip", label),
            button(
              class="tree-control-button",
              on_click=dispatch(ClearTimelineScope),
              "Clear Scope",
            ),
          ])
        None => nothing
      },
    ]),
  ])
}

///|
fn render_timeline_group(
  dispatch : Dispatch[Msg],
  model : Model,
  group : TimelineGroup,
) -> Html {
  section(class="timeline-group", [
    p(class="timeline-group-title", group.title),
    div(
      class="timeline",
      group.entries.map(fn(entry) {
        let entry_class = timeline_entry_class(model, model.snapshot, entry)
        let badges = timeline_data_badges(entry)
        button(class=entry_class, on_click=dispatch(FocusTimeline(entry.id)), [
          p(class="timeline-title", entry.title),
          p(class="timeline-detail", entry.detail),
          if badges.is_empty() {
            nothing
          } else {
            div(class="timeline-meta", badges)
          },
          div([
            match entry.status {
              Some(status) => render_status_badge(status)
              None => nothing
            },
            span(class="muted mono", "\{entry.timestamp}"),
          ]),
        ])
      }),
    ),
  ])
}

///|
fn render_timeline(
  dispatch : Dispatch[Msg],
  model : Model,
  timeline : Array[UiTimelineEntry],
) -> Html {
  if timeline.is_empty() {
    p(class="empty", "No timeline events yet.")
  } else {
    div(
      class="timeline-groups",
      timeline_groups(timeline).map(fn(group) {
        render_timeline_group(dispatch, model, group)
      }),
    )
  }
}

///|
fn render_workspace_panel(snapshot : UiSnapshot) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Workspace")]),
    div(class="panel-body", [
      div(class="kv", [
        div(class="kv-row", [
          p(class="kv-label", "Run"),
          p(class="mono", snapshot.run.id),
        ]),
        div(class="kv-row", [
          p(class="kv-label", "Job"),
          p(class="mono", snapshot.run.job_id),
        ]),
        div(class="kv-row", [
          p(class="kv-label", "Workspace"),
          p(
            class="mono",
            snapshot.workspace_dir.unwrap_or("No dedicated workspace"),
          ),
        ]),
        div(class="kv-row", [
          p(class="kv-label", "Current step"),
          p(class="mono", snapshot.current_step_id.unwrap_or("pending")),
        ]),
      ]),
    ]),
  ])
}

///|
fn render_artifacts_panel(snapshot : UiSnapshot) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Artifacts")]),
    div(class="panel-body", [
      if snapshot.artifacts.is_empty() {
        p(class="empty", "No artifacts yet.")
      } else {
        div(
          class="artifact-list",
          snapshot.artifacts.map(fn(artifact) {
            article(class="artifact-card", [
              p(
                class="node-title",
                artifact.logical_key.unwrap_or(artifact.artifact_type),
              ),
              p(class="muted", artifact.artifact_type),
              p(class="mono", artifact.path),
            ])
          }),
        )
      },
    ]),
  ])
}

///|
fn render_memory_panel(snapshot : UiSnapshot) -> Html {
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Memory")]),
    div(class="panel-body", [
      if snapshot.memories.is_empty() {
        p(class="empty", "No captured memories yet.")
      } else {
        div(
          class="memory-list",
          snapshot.memories.map(fn(memory) {
            article(class="memory-card", [
              p(class="node-title", memory.title.unwrap_or(memory.kind)),
              p(class="muted", memory.kind),
              p(class="timeline-detail", memory.content),
            ])
          }),
        )
      },
    ]),
  ])
}

///|
fn[T] preview_items(items : Array[T], limit : Int) -> Array[T] {
  let preview : Array[T] = []
  let mut count = 0
  for item in items {
    if count >= limit {
      break
    }
    preview.push(item)
    count = count + 1
  }
  preview
}

///|
fn render_child_runs_panel(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
) -> Html {
  let child_runs = child_run_nodes(snapshot)
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Delegated Runs")]),
    div(class="panel-body", [
      if child_runs.is_empty() {
        p(class="empty", "No delegated runs yet.")
      } else {
        div(
          class="focus-links",
          child_runs.map(fn(node) {
            render_focus_node_button(
              dispatch,
              snapshot,
              snapshot.timeline,
              node,
            )
          }),
        )
      },
    ]),
  ])
}

///|
fn render_recent_changes_panel(
  dispatch : Dispatch[Msg],
  timeline : Array[UiTimelineEntry],
) -> Html {
  let recent = recent_change_entries(timeline)
  section(class="panel", [
    header(class="panel-header", [h2(class="panel-title", "Recent Changes")]),
    div(class="panel-body", [
      if recent.is_empty() {
        p(class="empty", "No recent output changes yet.")
      } else {
        div(
          class="focus-events",
          recent.map(fn(entry) { render_focus_timeline_button(dispatch, entry) }),
        )
      },
    ]),
  ])
}

///|
fn render_right_panel(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
) -> Html {
  let button_for = fn(panel : RightPanel, label : String) {
    let active = model.right_panel == panel
    let cls = if active { "run-card active" } else { "run-card" }
    button(class=cls, on_click=dispatch(SelectPanel(panel)), label)
  }
  div(class="side-stack", [
    render_focus_inspector(dispatch, model, snapshot),
    render_child_runs_panel(dispatch, snapshot),
    render_recent_changes_panel(dispatch, model.timeline),
    section(class="panel", [
      header(class="panel-header", [h2(class="panel-title", "Panels")]),
      div(class="panel-body", [
        div(class="runs-list", [
          button_for(Workspace, "Workspace"),
          button_for(Artifacts, "Artifacts"),
          button_for(Memory, "Memory"),
        ]),
      ]),
    ]),
    match model.right_panel {
      Workspace => render_workspace_panel(snapshot)
      Artifacts => render_artifacts_panel(snapshot)
      Memory => render_memory_panel(snapshot)
    },
  ])
}

///|
fn artifact_for_node(snapshot : UiSnapshot, node : UiNode) -> UiArtifact? {
  match node.artifact_id {
    Some(artifact_id) => {
      for artifact in snapshot.artifacts {
        if artifact.id == artifact_id {
          return Some(artifact)
        }
      }
      None
    }
    None => None
  }
}

///|
fn memory_for_node(snapshot : UiSnapshot, node : UiNode) -> UiMemory? {
  match node.memory_id {
    Some(memory_id) => {
      for memory in snapshot.memories {
        if memory.id == memory_id {
          return Some(memory)
        }
      }
      None
    }
    None => None
  }
}

///|
fn related_timeline_for_node(
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  timeline.filter(fn(entry) {
    match node.step_id {
      Some(step_id) => entry.step_id == Some(step_id)
      None =>
        match node.run_id {
          Some(run_id) => entry.run_id == run_id
          None => false
        }
    }
  })
}

///|
fn node_matches_entry(node : UiNode, entry : UiTimelineEntry) -> Bool {
  match node.step_id {
    Some(step_id) => entry.step_id == Some(step_id)
    None =>
      match node.run_id {
        Some(run_id) => entry.run_id == run_id
        None => false
      }
  }
}

///|
fn lineage_timeline_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  let nodes = [node] + descendant_nodes(snapshot, node)
  timeline.filter(fn(entry) {
    nodes.any(fn(candidate) { node_matches_entry(candidate, entry) })
  })
}

///|
fn branch_only_timeline_for_node(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  let descendants = descendant_nodes(snapshot, node)
  timeline.filter(fn(entry) {
    descendants.any(fn(candidate) { node_matches_entry(candidate, entry) })
  })
}

///|
fn collect_node_event_stats(
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> NodeEventStats {
  let mut stats = {
    event_count: 0,
    max_attempt: 0,
    metric_events: 0,
    artifact_hits: 0,
    memory_hits: 0,
    workspace_hits: 0,
    failed_events: 0,
  }
  for entry in related_timeline_for_node(node, timeline) {
    stats = { ..stats, event_count: stats.event_count + 1 }
    match entry.data {
      { "attempt": Number(attempt, ..), .. } =>
        if attempt.to_int() > stats.max_attempt {
          stats = { ..stats, max_attempt: attempt.to_int() }
        }
      _ => ()
    }
    match entry.data {
      { "metrics": Object(metrics), .. } if !metrics.is_empty() =>
        stats = { ..stats, metric_events: stats.metric_events + 1 }
      _ => ()
    }
    if entry.event_type.contains("artifact") {
      stats = { ..stats, artifact_hits: stats.artifact_hits + 1 }
    }
    if entry.event_type.contains("memory") {
      stats = { ..stats, memory_hits: stats.memory_hits + 1 }
    }
    if entry.event_type.contains("workspace") {
      stats = { ..stats, workspace_hits: stats.workspace_hits + 1 }
    }
    match entry.status {
      Some(status) if normalize_status(status).contains("Failed") =>
        stats = { ..stats, failed_events: stats.failed_events + 1 }
      _ => ()
    }
  }
  stats
}

///|
fn merge_node_event_stats(
  left : NodeEventStats,
  right : NodeEventStats,
) -> NodeEventStats {
  {
    event_count: left.event_count + right.event_count,
    max_attempt: if left.max_attempt > right.max_attempt {
      left.max_attempt
    } else {
      right.max_attempt
    },
    metric_events: left.metric_events + right.metric_events,
    artifact_hits: left.artifact_hits + right.artifact_hits,
    memory_hits: left.memory_hits + right.memory_hits,
    workspace_hits: left.workspace_hits + right.workspace_hits,
    failed_events: left.failed_events + right.failed_events,
  }
}

///|
fn lineage_event_stats(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> NodeEventStats {
  let mut stats = collect_node_event_stats(node, timeline)
  for descendant in descendant_nodes(snapshot, node) {
    stats = merge_node_event_stats(
      stats,
      collect_node_event_stats(descendant, timeline),
    )
  }
  stats
}

///|
fn node_event_badges(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Array[Html] {
  let direct = collect_node_event_stats(node, timeline)
  let lineage = lineage_event_stats(snapshot, node, timeline)
  let badges : Array[Html] = []
  if direct.max_attempt > 1 {
    badges.push(render_meta_chip("retry", direct.max_attempt.to_string()))
  }
  if normalize_status(node.status).contains("Failed") {
    badges.push(render_meta_chip("state", "failed"))
  }
  if direct.artifact_hits > 0 || node.artifact_id is Some(_) {
    badges.push(render_meta_chip("artifact", direct.artifact_hits.to_string()))
  }
  if direct.memory_hits > 0 || node.memory_id is Some(_) {
    badges.push(render_meta_chip("memory", direct.memory_hits.to_string()))
  }
  if direct.workspace_hits > 0 {
    badges.push(
      render_meta_chip("workspace", direct.workspace_hits.to_string()),
    )
  }
  if lineage.artifact_hits > direct.artifact_hits {
    badges.push(
      render_meta_chip(
        "branch-artifacts",
        (lineage.artifact_hits - direct.artifact_hits).to_string(),
      ),
    )
  }
  if lineage.memory_hits > direct.memory_hits {
    badges.push(
      render_meta_chip(
        "branch-memories",
        (lineage.memory_hits - direct.memory_hits).to_string(),
      ),
    )
  }
  if lineage.failed_events > direct.failed_events {
    badges.push(
      render_meta_chip(
        "branch-failures",
        (lineage.failed_events - direct.failed_events).to_string(),
      ),
    )
  }
  if lineage.max_attempt > direct.max_attempt && lineage.max_attempt > 1 {
    badges.push(
      render_meta_chip("branch-retry", lineage.max_attempt.to_string()),
    )
  }
  badges
}

///|
fn render_node_badges(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> Html {
  let badges = node_event_badges(snapshot, node, timeline)
  if badges.is_empty() {
    nothing
  } else {
    div(class="timeline-meta", badges)
  }
}

///|
fn render_focus_summary(
  snapshot : UiSnapshot,
  node : UiNode,
  related_events : Array[UiTimelineEntry],
) -> Html {
  let direct = collect_node_event_stats(node, related_events)
  let lineage = lineage_event_stats(snapshot, node, related_events)
  div(class="inspector-stats", [
    render_meta_chip("events", direct.event_count.to_string()),
    if direct.max_attempt > 1 {
      render_meta_chip("retry", direct.max_attempt.to_string())
    } else {
      nothing
    },
    if direct.metric_events > 0 {
      render_meta_chip("metric-events", direct.metric_events.to_string())
    } else {
      nothing
    },
    if direct.artifact_hits > 0 || node.artifact_id is Some(_) {
      render_meta_chip("artifacts", direct.artifact_hits.to_string())
    } else {
      nothing
    },
    if direct.memory_hits > 0 || node.memory_id is Some(_) {
      render_meta_chip("memories", direct.memory_hits.to_string())
    } else {
      nothing
    },
    if lineage.event_count > direct.event_count {
      render_meta_chip(
        "branch-events",
        (lineage.event_count - direct.event_count).to_string(),
      )
    } else {
      nothing
    },
    if lineage.artifact_hits > direct.artifact_hits {
      render_meta_chip(
        "branch-artifacts",
        (lineage.artifact_hits - direct.artifact_hits).to_string(),
      )
    } else {
      nothing
    },
    if lineage.memory_hits > direct.memory_hits {
      render_meta_chip(
        "branch-memories",
        (lineage.memory_hits - direct.memory_hits).to_string(),
      )
    } else {
      nothing
    },
    if lineage.failed_events > direct.failed_events {
      render_meta_chip(
        "branch-failures",
        (lineage.failed_events - direct.failed_events).to_string(),
      )
    } else {
      nothing
    },
  ])
}

///|
fn child_run_nodes(snapshot : UiSnapshot) -> Array[UiNode] {
  snapshot.nodes.filter(fn(node) { node.kind == "ChildRun" })
}

///|
fn descendant_artifacts(
  snapshot : UiSnapshot,
  node : UiNode,
) -> Array[UiArtifact] {
  let artifacts : Array[UiArtifact] = []
  for descendant in descendant_nodes(snapshot, node) {
    match artifact_for_node(snapshot, descendant) {
      Some(artifact) => artifacts.push(artifact)
      None => ()
    }
  }
  artifacts
}

///|
fn descendant_memories(snapshot : UiSnapshot, node : UiNode) -> Array[UiMemory] {
  let memories : Array[UiMemory] = []
  for descendant in descendant_nodes(snapshot, node) {
    match memory_for_node(snapshot, descendant) {
      Some(memory) => memories.push(memory)
      None => ()
    }
  }
  memories
}

///|
fn latest_descendant_artifact(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> UiArtifact? {
  let descendants = descendant_nodes(snapshot, node)
  for i = timeline.length() - 1; i >= 0; i = i - 1 {
    let entry = timeline[i]
    if entry.event_type.contains("artifact") {
      for descendant in descendants {
        if node_matches_entry(descendant, entry) {
          match artifact_for_node(snapshot, descendant) {
            Some(artifact) => return Some(artifact)
            None => ()
          }
        }
      }
    }
  }
  descendant_artifacts(snapshot, node).get(0)
}

///|
fn latest_descendant_memory(
  snapshot : UiSnapshot,
  node : UiNode,
  timeline : Array[UiTimelineEntry],
) -> UiMemory? {
  let descendants = descendant_nodes(snapshot, node)
  for i = timeline.length() - 1; i >= 0; i = i - 1 {
    let entry = timeline[i]
    if entry.event_type.contains("memory") {
      for descendant in descendants {
        if node_matches_entry(descendant, entry) {
          match memory_for_node(snapshot, descendant) {
            Some(memory) => return Some(memory)
            None => ()
          }
        }
      }
    }
  }
  descendant_memories(snapshot, node).get(0)
}

///|
fn recent_change_entries(
  timeline : Array[UiTimelineEntry],
) -> Array[UiTimelineEntry] {
  let recent : Array[UiTimelineEntry] = []
  for i = timeline.length() - 1; i >= 0 && recent.length() < 4; i = i - 1 {
    let entry = timeline[i]
    if entry.event_type.contains("artifact") ||
      entry.event_type.contains("memory") ||
      entry.event_type.contains("workspace") ||
      entry.event_type.contains("complete") ||
      entry.event_type.contains("spawn") {
      recent.push(entry)
    }
  }
  recent
}

///|
fn render_focus_node_button(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
  timeline : Array[UiTimelineEntry],
  node : UiNode,
) -> Html {
  let lineage = lineage_event_stats(snapshot, node, timeline)
  button(class="focus-link", on_click=dispatch(FocusNode(node.id)), [
    p(class="node-kind", node.kind),
    p(class="timeline-title", node.title),
    div([render_status_badge(node.status)]),
    div(class="timeline-meta", [
      if lineage.artifact_hits > 0 {
        render_meta_chip("artifacts", lineage.artifact_hits.to_string())
      } else {
        nothing
      },
      if lineage.memory_hits > 0 {
        render_meta_chip("memories", lineage.memory_hits.to_string())
      } else {
        nothing
      },
      if lineage.failed_events > 0 {
        render_meta_chip("failures", lineage.failed_events.to_string())
      } else {
        nothing
      },
      if lineage.max_attempt > 1 {
        render_meta_chip("retry", lineage.max_attempt.to_string())
      } else {
        nothing
      },
    ]),
  ])
}

///|
fn render_focus_timeline_button(
  dispatch : Dispatch[Msg],
  entry : UiTimelineEntry,
) -> Html {
  button(class="focus-event", on_click=dispatch(FocusTimeline(entry.id)), [
    p(class="timeline-title", entry.title),
    p(class="muted", preview_text(entry.detail, 180)),
    div([
      match entry.status {
        Some(status) => render_status_badge(status)
        None => nothing
      },
      span(class="muted mono", "\{entry.timestamp}"),
    ]),
  ])
}

///|
fn render_focus_inspector(
  dispatch : Dispatch[Msg],
  model : Model,
  snapshot : UiSnapshot,
) -> Html {
  match resolved_focus_node_id(model, snapshot) {
    Some(node_id) =>
      match node_for_id(snapshot, node_id) {
        Some(node) => {
          let related_events = related_timeline_for_node(node, model.timeline)
          let lineage_events = lineage_timeline_for_node(
            snapshot,
            node,
            model.timeline,
          )
          let branch_events = lineage_events.filter(fn(entry) {
            !node_matches_entry(node, entry)
          })
          let branch_stats = lineage_event_stats(snapshot, node, model.timeline)
          let artifact = artifact_for_node(snapshot, node)
          let memory = memory_for_node(snapshot, node)
          let branch_artifacts = descendant_artifacts(snapshot, node)
          let branch_memories = descendant_memories(snapshot, node)
          let latest_branch_artifact = latest_descendant_artifact(
            snapshot,
            node,
            model.timeline,
          )
          let latest_branch_memory = latest_descendant_memory(
            snapshot,
            node,
            model.timeline,
          )
          let parent = parent_node(snapshot, node)
          let children = child_nodes(snapshot, node.id)
          section(class="panel", [
            header(class="panel-header", [
              h2(class="panel-title", "Focused Node"),
            ]),
            div(class="panel-body", [
              p(class="node-kind", node.kind),
              p(class="node-title", node.title),
              div([render_status_badge(node.status)]),
              div(class="node-meta", [
                render_meta_chip("node", node.id),
                match node.step_id {
                  Some(step_id) => render_meta_chip("step", step_id)
                  None => nothing
                },
                match node.run_id {
                  Some(run_id) => render_meta_chip("run", run_id)
                  None => nothing
                },
              ]),
              if children.is_empty() {
                nothing
              } else {
                div(class="branch-health", [
                  render_meta_chip(
                    "branch-events",
                    branch_stats.event_count.to_string(),
                  ),
                  if branch_stats.artifact_hits > 0 {
                    render_meta_chip(
                      "artifacts",
                      branch_stats.artifact_hits.to_string(),
                    )
                  } else {
                    nothing
                  },
                  if branch_stats.memory_hits > 0 {
                    render_meta_chip(
                      "memories",
                      branch_stats.memory_hits.to_string(),
                    )
                  } else {
                    nothing
                  },
                  if branch_stats.failed_events > 0 {
                    render_meta_chip(
                      "failures",
                      branch_stats.failed_events.to_string(),
                    )
                  } else {
                    nothing
                  },
                  if branch_stats.max_attempt > 1 {
                    render_meta_chip(
                      "retry",
                      branch_stats.max_attempt.to_string(),
                    )
                  } else {
                    nothing
                  },
                ])
              },
              render_focus_summary(snapshot, node, related_events),
              div(class="inspector-stats", [
                render_meta_chip("children", children.length().to_string()),
                render_meta_chip(
                  "artifact",
                  if artifact is Some(_) {
                    "1"
                  } else {
                    "0"
                  },
                ),
                render_meta_chip(
                  "memory",
                  if memory is Some(_) {
                    "1"
                  } else {
                    "0"
                  },
                ),
              ]),
              match node.summary {
                Some(summary) => p(class="timeline-detail", summary)
                None => nothing
              },
              match node.detail {
                Some(detail) => p(class="muted mono", detail)
                None => nothing
              },
              if normalize_status(node.status).contains("Failed") {
                div(class="focus-block focus-failure", [
                  p(class="kv-label", "Failure"),
                  p(
                    class="timeline-detail",
                    "This node is in a failed state. Check related events below for the latest failure context.",
                  ),
                ])
              } else {
                nothing
              },
              match parent {
                Some(parent) =>
                  div(class="focus-block", [
                    p(class="kv-label", "Parent"),
                    render_focus_node_button(
                      dispatch,
                      snapshot,
                      model.timeline,
                      parent,
                    ),
                  ])
                None => nothing
              },
              if children.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Children"),
                  div(
                    class="focus-links",
                    children.map(fn(child) {
                      render_focus_node_button(
                        dispatch,
                        snapshot,
                        model.timeline,
                        child,
                      )
                    }),
                  ),
                ])
              },
              match artifact {
                Some(artifact) =>
                  div(class="focus-block", [
                    p(class="kv-label", "Artifact"),
                    p(
                      class="timeline-detail",
                      artifact.logical_key.unwrap_or(artifact.artifact_type),
                    ),
                    p(class="mono", artifact.path),
                    p(
                      class="muted",
                      "Preview: \{preview_text(artifact.path, 120)}",
                    ),
                  ])
                None => nothing
              },
              match memory {
                Some(memory) =>
                  div(class="focus-block", [
                    p(class="kv-label", "Memory"),
                    p(
                      class="timeline-detail",
                      memory.title.unwrap_or(memory.kind),
                    ),
                    p(class="muted", preview_text(memory.content, 220)),
                  ])
                None => nothing
              },
              if latest_branch_artifact is Some(_) ||
                latest_branch_memory is Some(_) {
                div(class="focus-block", [
                  p(class="kv-label", "Latest Branch Output"),
                  match latest_branch_artifact {
                    Some(artifact) =>
                      article(class="artifact-card", [
                        p(
                          class="node-title",
                          artifact.logical_key.unwrap_or(artifact.artifact_type),
                        ),
                        p(class="muted", "Latest artifact"),
                        p(class="mono", preview_text(artifact.path, 120)),
                      ])
                    None => nothing
                  },
                  match latest_branch_memory {
                    Some(memory) =>
                      article(class="memory-card", [
                        p(
                          class="node-title",
                          memory.title.unwrap_or(memory.kind),
                        ),
                        p(class="muted", "Latest memory"),
                        p(
                          class="timeline-detail",
                          preview_text(memory.content, 160),
                        ),
                      ])
                    None => nothing
                  },
                ])
              } else {
                nothing
              },
              if branch_artifacts.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Descendant Artifacts"),
                  div(
                    class="artifact-list",
                    preview_items(branch_artifacts, 3).map(fn(artifact) {
                      article(class="artifact-card", [
                        p(
                          class="node-title",
                          artifact.logical_key.unwrap_or(artifact.artifact_type),
                        ),
                        p(class="muted", artifact.artifact_type),
                        p(class="mono", preview_text(artifact.path, 120)),
                      ])
                    }),
                  ),
                ])
              },
              if branch_memories.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Descendant Memories"),
                  div(
                    class="memory-list",
                    preview_items(branch_memories, 3).map(fn(memory) {
                      article(class="memory-card", [
                        p(
                          class="node-title",
                          memory.title.unwrap_or(memory.kind),
                        ),
                        p(class="muted", memory.kind),
                        p(
                          class="timeline-detail",
                          preview_text(memory.content, 180),
                        ),
                      ])
                    }),
                  ),
                ])
              },
              if related_events.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Related Events"),
                  div(
                    class="focus-events",
                    related_events.map(fn(entry) {
                      render_focus_timeline_button(dispatch, entry)
                    }),
                  ),
                ])
              },
              if branch_events.is_empty() {
                nothing
              } else {
                div(class="focus-block", [
                  p(class="kv-label", "Branch Events"),
                  div(
                    class="focus-events",
                    preview_items(branch_events, 5).map(fn(entry) {
                      render_focus_timeline_button(dispatch, entry)
                    }),
                  ),
                ])
              },
            ]),
          ])
        }
        None =>
          section(class="panel", [
            header(class="panel-header", [
              h2(class="panel-title", "Focused Node"),
            ]),
            div(class="panel-body", [
              p(class="empty", "Select a node to inspect it."),
            ]),
          ])
      }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "Focused Node")]),
        div(class="panel-body", [
          p(class="empty", "Select a node to inspect it."),
        ]),
      ])
  }
}

///|
fn render_detail(dispatch : Dispatch[Msg], model : Model) -> Html {
  match model.snapshot {
    Some(snapshot) => {
      let timeline = scoped_timeline(model, snapshot)
      section(class="panel", [
        header(class="panel-header", [
          div(class="detail-header", [
            div([
              p(class="eyebrow", "Generative Expansion"),
              h2(class="detail-title", snapshot.run.job_id),
              p(
                class="subline",
                snapshot.run.summary.unwrap_or(
                  "Expansion tree, execution timeline, and outputs for the selected run.",
                ),
              ),
            ]),
            render_status_badge(snapshot.run.status),
          ]),
        ]),
        div(class="panel-body", [
          if model.detail_loading {
            div(class="refresh-banner", [
              p(class="kv-label", "Live Refresh"),
              p(
                class="timeline-detail",
                "Updating the run snapshot and timeline...",
              ),
            ])
          } else {
            nothing
          },
          match snapshot.run.error {
            Some(error) =>
              div(class="run-error-banner", [
                p(class="kv-label", "Run Error"),
                p(class="timeline-detail", error),
              ])
            None => nothing
          },
          div(class="detail-grid", [
            section([
              div(class="section-header", [
                h3(class="section-title", "Expansion Tree"),
                render_tree_controls(dispatch),
              ]),
              render_tree(dispatch, model, snapshot),
            ]),
            section([
              h3(class="section-title", "Timeline"),
              render_active_strip(
                dispatch,
                model,
                snapshot,
                timeline,
                model.fresh_timeline_ids,
              ),
              render_timeline(dispatch, model, timeline),
            ]),
          ]),
        ]),
      ])
    }
    None =>
      section(class="panel", [
        header(class="panel-header", [h2(class="panel-title", "Run Detail")]),
        div(class="panel-body", [
          if model.detail_loading {
            p(class="empty", "Loading run detail...")
          } else if model.detail_error is Some(error) {
            p(class="empty", error)
          } else {
            p(
              class="empty",
              "Select a run to inspect how the workflow expanded and executed.",
            )
          },
        ]),
      ])
  }
}

///|
fn render_surface_tabs(model : Model) -> Html {
  let tab = fn(label : String, route : Surface, url : String) {
    let active = route_surface(model.route) == route
    button(
      class=if active { "surface-tab active-filter" } else { "surface-tab" },
      on_click=@nav.push_url(url),
      label,
    )
  }
  div(class="surface-tabs", [
    tab("Overview", SurfaceOverview, "/"),
    tab("Jobs", SurfaceJobs, "/jobs"),
    tab("ACP", SurfaceAcp, "/acp"),
  ])
}

///|
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="shell", [
    header(class="topbar", [
      div([
        p(class="eyebrow", "MoonClaw + Rabbita"),
        h1(class="headline", "Local + Remote Agent Viewer"),
        p(
          class="subline",
          "A MoonBit-native operator surface for local job expansion and ACP-backed remote agent control.",
        ),
        render_surface_tabs(model),
      ]),
      div(class="topbar-side", [
        div(class="live-stack", [
          render_live_chip(model),
          span(class="gateway-chip", last_update_label(model)),
        ]),
        div(class="gateway-chip", "Gateway: \{model.gateway_base}"),
      ]),
    ]),
    main_(
      class=if route_surface(model.route) == SurfaceOverview {
        "layout overview-layout"
      } else {
        "layout"
      },
      match route_surface(model.route) {
        SurfaceOverview => [render_overview(model)]
        SurfaceJobs =>
          [
            render_runs_panel(dispatch, model),
            render_detail(dispatch, model),
            match model.snapshot {
              Some(snapshot) => render_right_panel(dispatch, model, snapshot)
              None =>
                section(class="panel", [
                  header(class="panel-header", [
                    h2(class="panel-title", "Outputs"),
                  ]),
                  div(class="panel-body", [
                    p(
                      class="empty",
                      "Artifacts, workspace, and memory appear here once a run is selected.",
                    ),
                  ]),
                ])
            },
          ]
        SurfaceAcp =>
          [
            render_acp_panel(dispatch, model),
            render_acp_detail(dispatch, model),
            render_acp_inspector(model),
          ]
      },
    ),
  ])
}

///|
fn update(dispatch : Dispatch[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    LoadRuns =>
      (
        fetch_runs(dispatch, model.gateway_base),
        { ..model, runs_loading: true, runs_error: None },
      )
    LoadAcp =>
      (
        batch([
          fetch_acp_snapshot(dispatch, model.gateway_base),
          fetch_acp_timeline(dispatch, model.gateway_base),
        ]),
        { ..model, acp_loading: true, acp_error: None },
      )
    RunsLoaded(Ok(runs)) => {
      let next_model = { ..model, runs, runs_loading: false, runs_error: None }
      match model.route {
        Run(run_id) =>
          (
            batch([
              load_run_cmd(dispatch, model.gateway_base, run_id),
              start_stream_cmd(dispatch, model.gateway_base, run_id),
            ]),
            {
              ..next_model,
              selected_run_id: Some(run_id),
              detail_loading: true,
              detail_error: None,
            },
          )
        _ => (@rabbita.none, next_model)
      }
    }
    RunsLoaded(Err(error)) =>
      (@rabbita.none, { ..model, runs_loading: false, runs_error: Some(error) })
    SelectRun(run_id) =>
      (
        @nav.push_url(
          run_url(
            run_id,
            runs_status_filter=model.runs_status_filter,
            runs_query=model.runs_query,
            runs_sort=model.runs_sort,
            runs_page=model.runs_page,
          ),
        ),
        {
          ..model,
          route: Run(run_id),
          selected_run_id: Some(run_id),
          detail_loading: true,
          detail_error: None,
        },
      )
    LoadRun(run_id) =>
      (
        batch([
          load_run_cmd(dispatch, model.gateway_base, run_id),
          start_stream_cmd(dispatch, model.gateway_base, run_id),
        ]),
        {
          ..model,
          route: Run(run_id),
          selected_run_id: Some(run_id),
          detail_loading: true,
          detail_error: None,
        },
      )
    PollRun(run_id) =>
      if model.selected_run_id == Some(run_id) {
        (
          batch([
            fetch_runs(dispatch, model.gateway_base),
            match model.snapshot {
              Some(snapshot) =>
                if run_status_is_live(snapshot.run.status) {
                  @rabbita.delay(
                    dispatch(PollRun(run_id)),
                    runs_poll_interval_ms(),
                  )
                } else {
                  @rabbita.none
                }
              None => @rabbita.none
            },
          ]),
          model,
        )
      } else {
        (@rabbita.none, model)
      }
    PollAcp =>
      (
        batch([
          fetch_acp_snapshot(dispatch, model.gateway_base),
          fetch_acp_timeline(dispatch, model.gateway_base),
          match model.acp_snapshot {
            Some(snapshot) =>
              if acp_snapshot_is_live(snapshot) {
                @rabbita.delay(dispatch(PollAcp), acp_poll_interval_ms())
              } else {
                @rabbita.none
              }
            None => @rabbita.none
          },
        ]),
        model,
      )
    PumpStream(run_id) =>
      if model.selected_run_id == Some(run_id) {
        (drain_stream_cmd(dispatch, run_id), model)
      } else {
        (@rabbita.none, model)
      }
    AcpSnapshotLoaded(Ok(snapshot)) => {
      let next_model = {
        ..model,
        acp_snapshot: Some(snapshot),
        acp_loading: false,
        acp_error: None,
        fresh_acp_node_ids: fresh_ids_from(
          snapshot.nodes,
          model.acp_snapshot
          .map(fn(item) { item.nodes.map(fn(node) { node.id }) })
          .unwrap_or([]),
          fn(node) { node.id },
        ),
        selected_acp_node_id: resolved_acp_node_id(
          { ..model, acp_snapshot: Some(snapshot) },
          snapshot,
        ),
      }
      (
        if acp_snapshot_is_live(snapshot) {
          @rabbita.delay(dispatch(PollAcp), acp_poll_interval_ms())
        } else {
          @rabbita.none
        },
        next_model,
      )
    }
    AcpSnapshotLoaded(Err(error)) =>
      (@rabbita.none, { ..model, acp_loading: false, acp_error: Some(error) })
    AcpEventsLoaded(Ok(timeline)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_timeline: timeline,
          fresh_acp_timeline_ids: fresh_ids_from(
            timeline,
            model.acp_timeline.map(fn(entry) { entry.id }),
            fn(entry) { entry.id },
          ),
        },
      )
    AcpEventsLoaded(Err(error)) =>
      (@rabbita.none, { ..model, acp_error: Some(error), acp_loading: false })
    SnapshotLoaded(run_id, Ok(snapshot)) =>
      if model.selected_run_id == Some(run_id) {
        let (collapsed_node_ids, expanded_node_ids) = manual_tree_state_for_snapshot(
          model, snapshot,
        )
        let fresh_node_ids = fresh_ids_from(
          snapshot.nodes,
          model.snapshot
          .map(fn(item) { item.nodes.map(fn(node) { node.id }) })
          .unwrap_or([]),
          fn(node) { node.id },
        )
        let focused_node_id = resolved_focus_node_id(model, snapshot)
        let next_model = {
          ..model,
          snapshot: Some(snapshot),
          fresh_node_ids,
          collapsed_node_ids,
          expanded_node_ids,
          focused_node_id,
          detail_loading: false,
          detail_error: None,
        }
        (
          if run_status_is_live(snapshot.run.status) {
            @rabbita.delay(dispatch(PollRun(run_id)), runs_poll_interval_ms())
          } else {
            @rabbita.none
          },
          { ..next_model },
        )
      } else {
        (@rabbita.none, model)
      }
    SnapshotLoaded(run_id, Err(error)) =>
      if model.selected_run_id == Some(run_id) {
        (
          @rabbita.none,
          {
            ..model,
            snapshot: None,
            timeline: [],
            fresh_node_ids: [],
            fresh_timeline_ids: [],
            collapsed_node_ids: [],
            expanded_node_ids: [],
            focused_node_id: None,
            detail_loading: false,
            detail_error: Some(error),
          },
        )
      } else {
        (@rabbita.none, model)
      }
    EventsLoaded(run_id, Ok(timeline)) =>
      if model.selected_run_id == Some(run_id) {
        (
          @rabbita.none,
          {
            ..model,
            timeline,
            fresh_timeline_ids: fresh_ids_from(
              timeline,
              model.timeline.map(fn(entry) { entry.id }),
              fn(entry) { entry.id },
            ),
          },
        )
      } else {
        (@rabbita.none, model)
      }
    EventsLoaded(run_id, Err(error)) =>
      if model.selected_run_id == Some(run_id) && model.detail_error is None {
        (@rabbita.none, { ..model, detail_error: Some(error) })
      } else {
        (@rabbita.none, model)
      }
    StreamDrained(run_id, Ok((entries, closed))) =>
      if model.selected_run_id == Some(run_id) {
        let merged : Array[UiTimelineEntry] = model.timeline.copy()
        let fresh : Array[String] = []
        let mut needs_snapshot = false
        for entry in entries {
          if !timeline_contains_entry(merged, entry.id) {
            merged.push(entry)
            fresh.push(entry.id)
            if stream_entry_requires_snapshot(entry) {
              needs_snapshot = true
            }
          }
        }
        let next_cmd = if closed {
          batch([
            fetch_snapshot(dispatch, model.gateway_base, run_id),
            fetch_runs(dispatch, model.gateway_base),
          ])
        } else if needs_snapshot {
          batch([
            fetch_snapshot(dispatch, model.gateway_base, run_id),
            @rabbita.delay(dispatch(PumpStream(run_id)), 500),
          ])
        } else {
          @rabbita.delay(dispatch(PumpStream(run_id)), 500)
        }
        (
          next_cmd,
          {
            ..model,
            timeline: merged,
            fresh_timeline_ids: if fresh.is_empty() {
              model.fresh_timeline_ids
            } else {
              fresh
            },
          },
        )
      } else {
        (@rabbita.none, model)
      }
    StreamDrained(run_id, Err(error)) =>
      if model.selected_run_id == Some(run_id) {
        (
          @rabbita.delay(dispatch(PumpStream(run_id)), 1000),
          { ..model, detail_error: Some(error) },
        )
      } else {
        (@rabbita.none, model)
      }
    ExpandActiveBranches =>
      match model.snapshot {
        Some(snapshot) =>
          (
            @rabbita.none,
            {
              ..model,
              collapsed_node_ids: snapshot.nodes
              .filter(fn(node) { !keep_expanded_node(snapshot, model, node) })
              .map(fn(node) { node.id }),
              expanded_node_ids: snapshot.nodes
              .filter(fn(node) {
                node_has_collapsible_children(snapshot, node) &&
                keep_expanded_node(snapshot, model, node)
              })
              .map(fn(node) { node.id }),
            },
          )
        None => (@rabbita.none, model)
      }
    CollapseCompletedBranches =>
      match model.snapshot {
        Some(snapshot) =>
          (
            @rabbita.none,
            {
              ..model,
              collapsed_node_ids: auto_collapsed_ids(snapshot),
              expanded_node_ids: [],
            },
          )
        None => (@rabbita.none, model)
      }
    ResetTree =>
      (
        sync_url_cmd({
          ..model,
          collapsed_node_ids: [],
          expanded_node_ids: [],
          timeline_scope_node_id: None,
          timeline_scope_branch_only: false,
        }),
        {
          ..model,
          collapsed_node_ids: [],
          expanded_node_ids: [],
          timeline_scope_node_id: None,
          timeline_scope_branch_only: false,
        },
      )
    SelectRunsStatus(status) => {
      let next_model = { ..model, runs_status_filter: status, runs_page: 0 }
      (sync_url_cmd(next_model), next_model)
    }
    SetRunsQuery(query) => {
      let next_model = { ..model, runs_query: query, runs_page: 0 }
      (sync_url_cmd(next_model), next_model)
    }
    SelectRunsSort(sort) => {
      let next_model = { ..model, runs_sort: sort, runs_page: 0 }
      (sync_url_cmd(next_model), next_model)
    }
    SelectRunsPage(page) => {
      let next_model = { ..model, runs_page: page }
      (sync_url_cmd(next_model), next_model)
    }
    ToggleNode(node_id) =>
      match model.snapshot {
        Some(snapshot) => {
          let (collapsed_node_ids, expanded_node_ids) = toggle_manual_tree_state(
            model, snapshot, node_id,
          )
          (@rabbita.none, { ..model, collapsed_node_ids, expanded_node_ids })
        }
        None => (@rabbita.none, model)
      }
    FocusBranchPanel(node_id, panel) =>
      match model.snapshot {
        Some(snapshot) =>
          match node_for_id(snapshot, node_id) {
            Some(_) => {
              let next_model = {
                ..model,
                focused_node_id: Some(node_id),
                timeline_scope_node_id: Some(node_id),
                timeline_scope_branch_only: true,
                right_panel: panel,
              }
              (sync_url_cmd(next_model), next_model)
            }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    FocusBranchEvents(node_id) =>
      match model.snapshot {
        Some(snapshot) =>
          match node_for_id(snapshot, node_id) {
            Some(_) => {
              let next_model = {
                ..model,
                focused_node_id: Some(node_id),
                timeline_scope_node_id: Some(node_id),
                timeline_scope_branch_only: true,
              }
              (sync_url_cmd(next_model), next_model)
            }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    ClearTimelineScope => {
      let next_model = {
        ..model,
        timeline_scope_node_id: None,
        timeline_scope_branch_only: false,
      }
      (sync_url_cmd(next_model), next_model)
    }
    FocusNode(node_id) =>
      match model.snapshot {
        Some(snapshot) =>
          match node_for_id(snapshot, node_id) {
            Some(node) => {
              let next_model = {
                ..model,
                focused_node_id: Some(node_id),
                timeline_scope_node_id: None,
                timeline_scope_branch_only: false,
                right_panel: panel_for_node(model, node),
              }
              (sync_url_cmd(next_model), next_model)
            }
            None => (@rabbita.none, { ..model, focused_node_id: Some(node_id) })
          }
        None => (@rabbita.none, { ..model, focused_node_id: Some(node_id) })
      }
    FocusTimeline(entry_id) =>
      match model.snapshot {
        Some(snapshot) => {
          for entry in model.timeline {
            if entry.id == entry_id {
              match node_id_for_entry(snapshot, entry) {
                Some(node_id) =>
                  match node_for_id(snapshot, node_id) {
                    Some(node) => {
                      let next_model = {
                        ..model,
                        focused_node_id: Some(node_id),
                        timeline_scope_node_id: None,
                        timeline_scope_branch_only: false,
                        right_panel: panel_for_node(model, node),
                      }
                      return (sync_url_cmd(next_model), next_model)
                    }
                    None =>
                      return (
                        @rabbita.none,
                        { ..model, focused_node_id: Some(node_id) },
                      )
                  }
                None => return (@rabbita.none, model)
              }
            }
          }
          (@rabbita.none, model)
        }
        None => (@rabbita.none, model)
      }
    SelectPanel(panel) => {
      let next_model = { ..model, right_panel: panel }
      (sync_url_cmd(next_model), next_model)
    }
    SelectAcpNode(node_id) => {
      let next_model = { ..model, selected_acp_node_id: Some(node_id) }
      (sync_url_cmd(next_model), next_model)
    }
    UrlRequest(request) =>
      match request {
        Internal(url) => (@nav.push_url(url.to_string()), model)
        External(url) => (@nav.load(url), model)
      }
    UrlChanged(url) => {
      let route = route_from_url(url)
      let runs_status_filter = query_value(url, "status")
      let runs_query = query_value(url, "q").unwrap_or("")
      let runs_sort = run_sort_from_query(query_value(url, "sort"))
      let runs_page = match query_value(url, "page") {
        Some(page) => @strconv.parse_int(page) catch { _ => 0 }
        None => 0
      }
      let focused_node_id = query_value(url, "focus")
      let selected_acp_node_id = query_value(url, "focus")
      let timeline_scope_node_id = query_value(url, "scope")
      let timeline_scope_branch_only = query_value(url, "branch") == Some("1")
      let right_panel = right_panel_from_query(query_value(url, "panel")).unwrap_or(
        model.right_panel,
      )
      match route {
        Overview =>
          (
            batch([@nav.scroll_to_top(), stop_stream_cmd()]),
            {
              ..model,
              route,
              selected_run_id: None,
              runs_status_filter,
              runs_query,
              runs_sort,
              runs_page,
              snapshot: None,
              timeline: [],
              fresh_node_ids: [],
              fresh_timeline_ids: [],
              focused_node_id: None,
              timeline_scope_node_id: None,
              timeline_scope_branch_only: false,
              collapsed_node_ids: [],
              expanded_node_ids: [],
              detail_loading: false,
              detail_error: None,
              selected_acp_node_id,
            },
          )
        Jobs =>
          (
            batch([@nav.scroll_to_top(), stop_stream_cmd()]),
            {
              ..model,
              route,
              selected_run_id: None,
              runs_status_filter,
              runs_query,
              runs_sort,
              runs_page,
              snapshot: None,
              timeline: [],
              fresh_node_ids: [],
              fresh_timeline_ids: [],
              focused_node_id: None,
              timeline_scope_node_id: None,
              timeline_scope_branch_only: false,
              collapsed_node_ids: [],
              expanded_node_ids: [],
              detail_loading: false,
              detail_error: None,
            },
          )
        Run(run_id) =>
          if model.selected_run_id == Some(run_id) && model.snapshot is Some(_) {
            (
              @rabbita.none,
              {
                ..model,
                route,
                runs_status_filter,
                runs_query,
                runs_sort,
                runs_page,
                focused_node_id,
                timeline_scope_node_id,
                timeline_scope_branch_only,
                right_panel,
              },
            )
          } else {
            (
              batch([@nav.scroll_to_top(), dispatch(LoadRun(run_id))]),
              {
                ..model,
                route,
                selected_run_id: Some(run_id),
                runs_status_filter,
                runs_query,
                runs_sort,
                runs_page,
                focused_node_id,
                timeline_scope_node_id,
                timeline_scope_branch_only,
                right_panel,
              },
            )
          }
        Acp =>
          (
            batch([@nav.scroll_to_top(), dispatch(LoadAcp), stop_stream_cmd()]),
            { ..model, route, selected_acp_node_id },
          )
      }
    }
  }
}

///|
fn main {
  let (dispatch, app) = @rabbita.cell_with_dispatch(
    model=init_model(),
    update~,
    view~,
  )
  @rabbita.new(app)
  ..with_route(url_changed=url => dispatch(UrlChanged(url)), url_request=req => {
    dispatch(UrlRequest(req))
  })
  ..with_init(batch([dispatch(LoadRuns), dispatch(LoadAcp)]))
  .mount("app")
}
