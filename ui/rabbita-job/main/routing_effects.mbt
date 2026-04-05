///|
fn route_fragment(url : @url.Url) -> String? {
  match url.fragment {
    Some(fragment) => {
      let trimmed = fragment.trim().to_string()
      if trimmed == "" {
        None
      } else if trimmed.has_prefix("/") {
        Some(trimmed)
      } else {
        Some("/\{trimmed}")
      }
    }
    None => None
  }
}

///|
fn route_query_string(url : @url.Url) -> String? {
  match route_fragment(url) {
    Some(fragment) =>
      match fragment.split_once("?") {
        Some((_, query)) => Some(query.to_string())
        None => None
      }
    None => url.query
  }
}

///|
fn route_from_url(url : @url.Url) -> Route {
  let path = match route_fragment(url) {
    Some(fragment) =>
      match fragment.split_once("?") {
        Some((fragment_path, _)) => fragment_path.to_string()
        None => fragment
      }
    None => url.path.trim().to_string()
  }
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
    ["runs", run_id, "canvas"] => RunCanvas(run_id)
    ["cowork"] => Cowork
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
    RunCanvas(_) => SurfaceJobs
    Cowork => SurfaceCowork
    Acp => SurfaceAcp
  }
}

///|
fn query_value(url : @url.Url, key : String) -> String? {
  match route_query_string(url) {
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
fn hash_route_url(path : String) -> String {
  if path.has_prefix("/") {
    "#\{path}"
  } else {
    "#/\{path}"
  }
}

///|
fn cowork_panel_query_value(panel : CoworkPanel) -> String {
  match panel {
    CoworkPreview => "preview"
    CoworkWorkspace => "workspace"
    CoworkArtifacts => "artifacts"
    CoworkRun => "run"
  }
}

///|
fn cowork_panel_from_query(value : String?) -> CoworkPanel {
  match value {
    Some("workspace") => CoworkWorkspace
    Some("artifacts") => CoworkArtifacts
    Some("run") => CoworkRun
    _ => CoworkPreview
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
    hash_route_url("/runs/\{run_id}")
  } else {
    let query = params.join("&")
    hash_route_url("/runs/\{run_id}?\{query}")
  }
}

///|
fn run_canvas_url(
  run_id : String,
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
    hash_route_url("/runs/\{run_id}/canvas")
  } else {
    let query = params.join("&")
    hash_route_url("/runs/\{run_id}/canvas?\{query}")
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
    hash_route_url("/jobs")
  } else {
    let query = params.join("&")
    hash_route_url("/jobs?\{query}")
  }
}

///|
fn acp_url(selected_node_id? : String? = None) -> String {
  match selected_node_id {
    Some(node_id) => hash_route_url("/acp?focus=\{node_id}")
    None => hash_route_url("/acp")
  }
}

///|
fn cowork_url(
  selected_session_key? : String? = None,
  panel? : CoworkPanel = CoworkPreview,
) -> String {
  let params : Array[String] = []
  match selected_session_key {
    Some(session_key) => params.push("session=\{session_key}")
    None => ()
  }
  if panel != CoworkPreview {
    params.push("panel=\{cowork_panel_query_value(panel)}")
  }
  if params.is_empty() {
    hash_route_url("/cowork")
  } else {
    let query = params.join("&")
    hash_route_url("/cowork?\{query}")
  }
}

///|
fn overview_url(selected_mixed_handoff_key? : String? = None) -> String {
  match selected_mixed_handoff_key {
    Some(key) => hash_route_url("/?mixed=\{key}")
    None => hash_route_url("/")
  }
}

///|
fn acp_focus_id_for_remote_link(link : UiRemoteLink) -> String? {
  if link.id.has_prefix("acp-session:") {
    match link.id.split_once(":") {
      Some((_, suffix)) => Some("session:\{suffix}")
      None => None
    }
  } else if link.id.has_prefix("acp-run:") {
    match link.id.split_once(":") {
      Some((_, suffix)) => Some("run:\{suffix}")
      None => None
    }
  } else {
    None
  }
}

///|
fn acp_url_for_remote_link(link : UiRemoteLink) -> String {
  match acp_focus_id_for_remote_link(link) {
    Some(focus_id) => acp_url(selected_node_id=Some(focus_id))
    None => acp_url()
  }
}

///|
fn current_url_for_model(model : Model) -> String {
  match model.route {
    Overview =>
      overview_url(selected_mixed_handoff_key=model.selected_mixed_handoff_key)
    Acp => acp_url(selected_node_id=model.selected_acp_node_id)
    Cowork =>
      cowork_url(
        selected_session_key=model.selected_cowork_session_key,
        panel=model.cowork_panel,
      )
    Jobs =>
      jobs_url(
        runs_status_filter=model.runs_status_filter,
        runs_query=model.runs_query,
        runs_sort=model.runs_sort,
        runs_page=model.runs_page,
      )
    RunCanvas(run_id) =>
      run_canvas_url(
        run_id,
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
fn parse_loaded_artifact_payload(json : Json) -> Result[LoadedArtifact, String] {
  match json {
    { "artifact": artifact_json, "content": content_json, .. } =>
      match (try? @json.from_json(artifact_json) : Result[UiArtifact, Error]) {
        Ok(artifact) => {
          let content = match content_json {
            Null => None
            String(text) => Some(text)
            value => Some(value.stringify())
          }
          Ok(LoadedArtifact::{ artifact, content })
        }
        Err(error) => Err("Failed to parse artifact payload: \{error}")
      }
    _ => Err("Failed to parse artifact payload: expected object")
  }
}

///|
fn parse_cowork_sessions_payload(
  json : Json,
) -> Result[Array[CoworkSessionSummary], String] {
  let payload : Result[CoworkSessionsPayload, Error] = try? @json.from_json(
    json,
  )
  match payload {
    Ok(payload) => Ok(payload.sessions)
    Err(error) => Err("Failed to parse Cowork sessions: \{error}")
  }
}

///|
fn parse_cowork_session_payload(
  json : Json,
) -> Result[CoworkSessionDetail, String] {
  let payload : Result[CoworkSessionPayload, Error] = try? @json.from_json(json)
  match payload {
    Ok(payload) => Ok(payload.session)
    Err(error) => Err("Failed to parse Cowork session: \{error}")
  }
}

///|
fn parse_workspace_snapshot_payload(
  json : Json,
) -> Result[UiWorkspaceSnapshot, String] {
  let payload : Result[UiWorkspaceSnapshotPayload, Error] = try? @json.from_json(
    json,
  )
  match payload {
    Ok(payload) => Ok(payload.workspace)
    Err(error) => Err("Failed to parse workspace snapshot: \{error}")
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
fn parse_acp_timeline_entry_payload(
  text : String,
) -> Result[AcpUiTimelineEntry, String] {
  let json : Result[Json, Error] = try? @json.parse(text)
  match json {
    Ok(json) =>
      match (try? @json.from_json(json) : Result[AcpUiTimelineEntry, Error]) {
        Ok(entry) => Ok(entry)
        Err(error) =>
          Err("Failed to parse streamed ACP timeline entry: \{error}")
      }
    Err(error) => Err("Failed to parse streamed ACP timeline JSON: \{error}")
  }
}

///|
fn parse_action_status_payload(text : String) -> Result[String, String] {
  let json : Result[Json, Error] = try? @json.parse(text)
  match json {
    Ok({ "status": String(status), .. }) => Ok(status)
    Ok({ "error": { "message": String(message), .. }, .. }) => Err(message)
    Ok({ "error": String(message), .. }) => Err(message)
    Ok(_) => Ok("ok")
    Err(error) => Err("Failed to parse ACP action response: \{error}")
  }
}

///|
#cfg(target="js")
extern "js" fn browser_copy_text(text : String) -> String =
  #| async (text) => {
  #|   try {
  #|     await navigator.clipboard.writeText(text);
  #|     return JSON.stringify({ ok: true, value: "copied", error: null });
  #|   } catch (error) {
  #|     return JSON.stringify({ ok: false, value: "", error: String(error) });
  #|   }
  #| }

///|
struct BrowserCopyResult {
  ok : Bool
  value : String
  error : String?
} derive(FromJson, Show)

///|
struct BrowserLocalUploadBatch {
  ok : Bool
  files : Array[CoworkLocalUpload]
  error : String?
} derive(FromJson, Show)

///|
fn parse_browser_copy_result(text : String) -> Result[String, String] {
  let json : Result[Json, Error] = try? @json.parse(text)
  let payload = match json {
    Ok(json) =>
      match (try? @json.from_json(json) : Result[BrowserCopyResult, Error]) {
        Ok(payload) => payload
        Err(error) => return Err("Failed to parse clipboard result: \{error}")
      }
    Err(error) => return Err("Failed to parse clipboard wrapper: \{error}")
  }
  match payload.error {
    Some(error) => Err(error)
    None =>
      if payload.ok {
        Ok(payload.value)
      } else {
        Err("Clipboard write failed")
      }
  }
}

///|
#cfg(target="js")
extern "js" fn browser_pick_local_files() -> String =
  #| async () => {
  #|   const readFile = async (file, source) => {
  #|     const textLike =
  #|       file.type.startsWith("text/") ||
  #|       /\.(md|txt|json|mbt|js|ts|tsx|jsx|css|html|xml|yaml|yml|toml|csv)$/i.test(file.name);
  #|     const content = textLike
  #|       ? await file.text()
  #|       : await new Promise((resolve, reject) => {
  #|           const reader = new FileReader();
  #|           reader.onerror = () => reject(reader.error ?? new Error("Failed to read file"));
  #|           reader.onload = () => resolve(String(reader.result ?? ""));
  #|           reader.readAsDataURL(file);
  #|         });
  #|     return {
  #|       id: `${source}:${file.name}:${file.size}:${file.lastModified}`,
  #|       name: file.name,
  #|       media_type: file.type || "application/octet-stream",
  #|       content,
  #|       source,
  #|     };
  #|   };
  #|   try {
  #|     const input = document.createElement("input");
  #|     input.type = "file";
  #|     input.multiple = true;
  #|     const files = await new Promise((resolve) => {
  #|       input.onchange = () => resolve(Array.from(input.files || []));
  #|       input.click();
  #|     });
  #|     const loaded = await Promise.all(files.map((file) => readFile(file, "picker")));
  #|     return JSON.stringify({ ok: true, files: loaded, error: null });
  #|   } catch (error) {
  #|     return JSON.stringify({ ok: false, files: [], error: String(error) });
  #|   }
  #| }

///|
#cfg(target="js")
extern "js" fn browser_take_dropped_files() -> String =
  #| async () => {
  #|   const state =
  #|     (window.__moonclawCoworkDropState ||= { installed: false, queue: [] });
  #|   const readFile = async (file, source) => {
  #|     const textLike =
  #|       file.type.startsWith("text/") ||
  #|       /\.(md|txt|json|mbt|js|ts|tsx|jsx|css|html|xml|yaml|yml|toml|csv)$/i.test(file.name);
  #|     const content = textLike
  #|       ? await file.text()
  #|       : await new Promise((resolve, reject) => {
  #|           const reader = new FileReader();
  #|           reader.onerror = () => reject(reader.error ?? new Error("Failed to read dropped file"));
  #|           reader.onload = () => resolve(String(reader.result ?? ""));
  #|           reader.readAsDataURL(file);
  #|         });
  #|     return {
  #|       id: `${source}:${file.name}:${file.size}:${file.lastModified}`,
  #|       name: file.name,
  #|       media_type: file.type || "application/octet-stream",
  #|       content,
  #|       source,
  #|     };
  #|   };
  #|   if (!state.installed) {
  #|     const stop = (event) => {
  #|       event.preventDefault();
  #|       event.stopPropagation();
  #|     };
  #|     window.addEventListener("dragover", stop);
  #|     window.addEventListener("drop", (event) => {
  #|       stop(event);
  #|       const files = Array.from(event.dataTransfer?.files || []);
  #|       Promise.all(files.map((file) => readFile(file, "drop")))
  #|         .then((loaded) => {
  #|           state.queue.push(...loaded);
  #|         })
  #|         .catch((error) => {
  #|           state.queue.push({
  #|             id: `drop-error:${Date.now()}`,
  #|             name: "drop-error.txt",
  #|             media_type: "text/plain",
  #|             content: String(error),
  #|             source: "drop",
  #|           });
  #|         });
  #|     });
  #|     state.installed = true;
  #|   }
  #|   const files = state.queue.splice(0, state.queue.length);
  #|   return JSON.stringify({ ok: true, files, error: null });
  #| }

///|
fn parse_browser_local_upload_batch(
  text : String,
) -> Result[Array[CoworkLocalUpload], String] {
  if text.trim().to_string().is_blank() {
    return Ok([])
  }
  let json : Result[Json, Error] = try? @json.parse(text)
  let payload = match json {
    Ok(json) =>
      match
        (try? @json.from_json(json) : Result[BrowserLocalUploadBatch, Error]) {
        Ok(payload) => payload
        Err(error) => return Err("Failed to parse local upload batch: \{error}")
      }
    Err(error) => return Err("Failed to parse local upload wrapper: \{error}")
  }
  match payload.error {
    Some(error) => Err(error)
    None =>
      if payload.ok {
        Ok(payload.files)
      } else {
        Err("Local file import failed")
      }
  }
}

///|
fn copy_to_clipboard(dispatch : Dispatch[Msg], text : String) -> Cmd {
  @rabbita.perform(fn(result) { dispatch(AcpCopyFinished(result)) }, fn() noraise {
    parse_browser_copy_result(browser_copy_text(text))
  })
}

///|
fn copy_cowork_text(dispatch : Dispatch[Msg], text : String) -> Cmd {
  @rabbita.perform(fn(result) { dispatch(CoworkCopyFinished(result)) }, fn() noraise {
    parse_browser_copy_result(browser_copy_text(text))
  })
}

///|
fn pick_cowork_local_files(dispatch : Dispatch[Msg]) -> Cmd {
  @rabbita.perform(fn(result) { dispatch(CoworkFilesPicked(result)) }, fn() noraise {
    parse_browser_local_upload_batch(browser_pick_local_files())
  })
}

///|
fn take_cowork_dropped_files(dispatch : Dispatch[Msg]) -> Cmd {
  @rabbita.perform(fn(result) { dispatch(CoworkFilesPicked(result)) }, fn() noraise {
    parse_browser_local_upload_batch(browser_take_dropped_files())
  })
}

///|
fn schedule_cowork_drop_poll(dispatch : Dispatch[Msg]) -> Cmd {
  @rabbita.delay(dispatch(PollCoworkDroppedFiles), 1200)
}

///|
#cfg(target="js")
extern "js" fn browser_download_text(
  filename : String,
  content : String,
) -> String =
  #| async (filename, content) => {
  #|   try {
  #|     const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
  #|     const url = URL.createObjectURL(blob);
  #|     const link = document.createElement("a");
  #|     link.href = url;
  #|     link.download = filename;
  #|     document.body.appendChild(link);
  #|     link.click();
  #|     link.remove();
  #|     URL.revokeObjectURL(url);
  #|     return JSON.stringify({ ok: true, value: "downloaded", error: null });
  #|   } catch (error) {
  #|     return JSON.stringify({ ok: false, value: "", error: String(error) });
  #|   }
  #| }

///|
fn download_text_file(
  dispatch : Dispatch[Msg],
  filename : String,
  content : String,
) -> Cmd {
  @rabbita.perform(fn(result) { dispatch(AcpExportFinished(result)) }, fn() noraise {
    parse_browser_copy_result(browser_download_text(filename, content))
  })
}

///|
fn download_mixed_text_file(
  dispatch : Dispatch[Msg],
  filename : String,
  content : String,
) -> Cmd {
  @rabbita.perform(fn(result) { dispatch(MixedExportFinished(result)) }, fn() noraise {
    parse_browser_copy_result(browser_download_text(filename, content))
  })
}

///|
struct StreamDrainPayload {
  entries : Array[String]
  closed : Bool
  error : String?
} derive(FromJson, Show)

///|
fn stream_drain_error_message(json : Json) -> String? {
  match json {
    Null => None
    String(message) => Some(message)
    Object(obj) =>
      match obj.get("message") {
        Some(String(message)) => Some(message)
        _ => Some(json.stringify())
      }
    _ => Some(json.stringify())
  }
}

///|
fn parse_stream_drain_payload_json(
  json : Json,
) -> Result[StreamDrainPayload, String] {
  match json {
    Object(obj) => {
      let entries = match obj.get("entries") {
        Some(Array(items)) => {
          let collected : Array[String] = []
          for item in items {
            match item {
              String(text) => collected.push(text)
              _ =>
                return Err(
                  "Failed to parse stream payload: entries must contain only strings",
                )
            }
          }
          collected
        }
        Some(_) =>
          return Err(
            "Failed to parse stream payload: entries must be an array of strings",
          )
        None => []
      }
      let closed = match obj.get("closed") {
        Some(True) => true
        Some(False) => false
        Some(_) =>
          return Err("Failed to parse stream payload: closed must be a boolean")
        None => false
      }
      let error = match obj.get("error") {
        Some(value) => stream_drain_error_message(value)
        None => None
      }
      Ok({ entries, closed, error })
    }
    _ => Err("Failed to parse stream payload: expected object")
  }
}

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
      match parse_stream_drain_payload_json(json) {
        Ok(payload) => payload
        Err(error) => return Err(error)
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
fn parse_acp_stream_drain_payload(
  text : String,
) -> Result[(Array[AcpUiTimelineEntry], Bool), String] {
  let json : Result[Json, Error] = try? @json.parse(text)
  let payload = match json {
    Ok(json) =>
      match parse_stream_drain_payload_json(json) {
        Ok(payload) => payload
        Err(error) => return Err("Failed to parse ACP stream payload: \{error}")
      }
    Err(error) => return Err("Failed to parse ACP stream drain JSON: \{error}")
  }
  let entries : Array[AcpUiTimelineEntry] = []
  for raw in payload.entries {
    match parse_acp_timeline_entry_payload(raw) {
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
fn fetch_artifact(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  artifact_id : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, LoadedArtifact] = @http.Expecting::Json(
    fn(result) { dispatch(ArtifactLoaded(artifact_id, result)) },
    parse_loaded_artifact_payload,
  )
  @http.get("\{gateway_base}/v1/artifacts/\{artifact_id}", expect~)
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
fn fetch_cowork_linked_snapshot(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  run_id : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, UiSnapshot] = @http.Expecting::Json(
    fn(result) { dispatch(CoworkLinkedSnapshotLoaded(run_id, result)) },
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
fn fetch_cowork_sessions(
  dispatch : Dispatch[Msg],
  gateway_base : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, Array[CoworkSessionSummary]] = @http.Expecting::Json(
    fn(result) { dispatch(CoworkSessionsLoaded(result)) },
    parse_cowork_sessions_payload,
  )
  @http.get("\{gateway_base}/v1/cowork/sessions", expect~)
}

///|
fn fetch_cowork_session(
  dispatch : Dispatch[Msg],
  gateway_base : String,
  session_key : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, CoworkSessionDetail] = @http.Expecting::Json(
    fn(result) { dispatch(CoworkSessionLoaded(session_key, result)) },
    parse_cowork_session_payload,
  )
  @http.get("\{gateway_base}/v1/cowork/sessions/\{session_key}", expect~)
}

///|
fn fetch_cowork_workspace(
  dispatch : Dispatch[Msg],
  gateway_base : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, UiWorkspaceSnapshot] = @http.Expecting::Json(
    fn(result) { dispatch(CoworkWorkspaceLoaded(result)) },
    parse_workspace_snapshot_payload,
  )
  @http.get("\{gateway_base}/v1/workspace", expect~)
}

///|
fn create_cowork_session(
  dispatch : Dispatch[Msg],
  gateway_base : String,
) -> Cmd {
  let expect : @http.Expecting[Cmd, CoworkSessionDetail] = @http.Expecting::Json(
    fn(result) { dispatch(CoworkSessionCreated(result)) },
    parse_cowork_session_payload,
  )
  @http.post(
    "\{gateway_base}/v1/cowork/sessions",
    @http.Body::Json({}),
    expect~,
  )
}

///|
fn post_cowork_action(
  dispatch : Dispatch[Msg],
  url : String,
  body? : Json = {},
) -> Cmd {
  let expect : @http.Expecting[Cmd, CoworkSessionDetail] = @http.Expecting::Json(
    fn(result) { dispatch(CoworkActionFinished(result)) },
    parse_cowork_session_payload,
  )
  @http.post(url, @http.Body::Json(body), expect~)
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
fn acp_timeline_contains_entry(
  timeline : Array[AcpUiTimelineEntry],
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
fn acp_stream_entry_requires_snapshot(entry : AcpUiTimelineEntry) -> Bool {
  entry.event_type != "run.output"
}

///|
fn post_action(
  dispatch : Dispatch[Msg],
  url : String,
  body? : Json = {},
) -> Cmd {
  let expect : @http.Expecting[Cmd, String] = @http.Expecting::Text(fn(result) {
    dispatch(
      AcpActionFinished(
        match result {
          Ok(text) => parse_action_status_payload(text)
          Err(error) => Err(error)
        },
      ),
    )
  })
  @http.post(url, @http.Body::Json(body), expect~)
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
#cfg(target="js")
extern "js" fn start_acp_ui_event_stream(url : String) =
  #| (url) => {
  #|   const key = "__moonclawAcpUiStream";
  #|   const current = window[key];
  #|   if (current && current.es) current.es.close();
  #|   const state = { queue: [], closed: false, error: null, es: null };
  #|   const es = new EventSource(url);
  #|   state.es = es;
  #|   es.addEventListener("acp_ui_event", (event) => { state.queue.push(event.data); });
  #|   es.addEventListener("acp_ui_complete", () => {
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
extern "js" fn stop_acp_ui_event_stream() =
  #| () => {
  #|   const key = "__moonclawAcpUiStream";
  #|   const state = window[key];
  #|   if (state && state.es) state.es.close();
  #|   window[key] = null;
  #| }

///|
#cfg(target="js")
extern "js" fn drain_acp_ui_event_stream() -> String =
  #| () => {
  #|   const key = "__moonclawAcpUiStream";
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
fn start_acp_stream_cmd(dispatch : Dispatch[Msg], gateway_base : String) -> Cmd {
  batch([
    @rabbita.effect(fn() noraise {
      start_acp_ui_event_stream("\{gateway_base}/v1/acp/events/stream")
    }),
    @rabbita.delay(dispatch(PumpAcpStream), 500),
  ])
}

///|
fn stop_acp_stream_cmd() -> Cmd {
  @rabbita.effect(fn() noraise { stop_acp_ui_event_stream() })
}

///|
fn drain_acp_stream_cmd(dispatch : Dispatch[Msg]) -> Cmd {
  @rabbita.perform(
    fn(raw) { dispatch(AcpStreamDrained(parse_acp_stream_drain_payload(raw))) },
    fn() noraise { drain_acp_ui_event_stream() },
  )
}
