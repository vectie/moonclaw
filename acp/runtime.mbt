///|
pub struct AcpTarget {
  id : String
  backend : String
  label : String?
  cwd : String?
  workspace : String?
  command : String?
  args : Array[String]
  model : String?
  status : String
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub struct AcpSession {
  id : String
  target_id : String
  session_key : String
  status : String
  cwd : String?
  workspace : String?
  created_at : Int
  updated_at : Int
  last_error : String?
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub struct AcpRun {
  id : String
  session_id : String
  session_key : String
  target_id : String
  backend : String
  status : String
  created_at : Int
  updated_at : Int
  request : Json
  plan : Json
  result : Json?
  error : String?
} derive(ToJson, FromJson, Show)

///|
struct PersistedAcpState {
  sessions : Array[AcpSession]
  runs : Array[AcpRun]?
} derive(ToJson, FromJson, Show)

///|
pub struct AcpRuntime {
  home : String
  cwd : String
  targets : Map[String, AcpTarget]
  sessions : Map[String, AcpSession]
  runs : Map[String, AcpRun]
}

///|
fn root_config_path(root : String) -> String {
  @path.Path(root).join(@path.Path("moonclaw.json")).to_string()
}

///|
fn nested_config_path(root : String) -> String {
  @path.Path(root)
  .join(@path.Path(".moonclaw"))
  .join(@path.Path("moonclaw.json"))
  .to_string()
}

///|
fn config_paths(home : String, cwd : String) -> Array[String] {
  [
    root_config_path(home),
    nested_config_path(home),
    root_config_path(cwd),
    nested_config_path(cwd),
  ]
}

///|
fn acp_state_path(home : String) -> String {
  @path.Path(home)
  .join(@path.Path(".moonclaw"))
  .join(@path.Path("acp_sessions.json"))
  .to_string()
}

///|
async fn ensure_acp_state_parent(home : String) -> Unit {
  @fsx.make_directory(
    @path.Path(home).join(@path.Path(".moonclaw")).to_string(),
    recursive=true,
  ) catch {
    _ => ()
  }
}

///|
async fn load_acp_config(home : String, cwd : String) -> Json? {
  let mut loaded : Json? = None
  for path in config_paths(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    loaded = Some(json)
  }
  loaded
}

///|
fn acp_targets_map(json : Json) -> Map[String, Json] {
  guard json is Object(root) else { return {} }
  guard root.get("acp") is Some(Object(acp)) else { return {} }
  guard acp.get("targets") is Some(Object(targets)) else { return {} }
  targets
}

///|
fn json_string(value : Json?, field : String) -> String? {
  match value {
    Some(Object(obj)) =>
      match obj.get(field) {
        Some(String(text)) if !text.trim().is_empty() =>
          Some(text.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn json_array_strings(value : Json?, field : String) -> Array[String] {
  match value {
    Some(Object(obj)) =>
      match obj.get(field) {
        Some(Array(items)) =>
          items.filter_map(fn(item) {
            match item {
              String(text) if !text.trim().is_empty() =>
                Some(text.trim().to_string())
              _ => None
            }
          })
        _ => []
      }
    _ => []
  }
}

///|
fn target_status(target : Json?) -> String {
  match json_string(target, "backend") {
    Some("codex") => "ready"
    Some(_) => "configured"
    None => "configured"
  }
}

///|
fn target_label(target_id : String, target : Json?) -> String? {
  match json_string(target, "label") {
    Some(label) => Some(label)
    None =>
      match json_string(target, "backend") {
        Some("codex") => Some("Codex \{target_id}")
        _ => None
      }
  }
}

///|
fn load_targets_from_config(json : Json) -> Map[String, AcpTarget] {
  let targets : Map[String, AcpTarget] = {}
  for target_id, raw in acp_targets_map(json) {
    let backend = match json_string(Some(raw), "backend") {
      Some(backend) => backend
      None => "codex"
    }
    targets[target_id] = AcpTarget::{
      id: target_id,
      backend,
      label: target_label(target_id, Some(raw)),
      cwd: json_string(Some(raw), "cwd"),
      workspace: json_string(Some(raw), "workspace"),
      command: json_string(Some(raw), "command"),
      args: json_array_strings(Some(raw), "args"),
      model: json_string(Some(raw), "model"),
      status: target_status(Some(raw)),
      metadata: raw,
    }
  }
  targets
}

///|
async fn load_persisted_sessions(home : String) -> Array[AcpSession] {
  let path = acp_state_path(home)
  let exists = @fsx.exists(path) catch { _ => false }
  guard exists else { return [] }
  let text = @fsx.read_file(path) catch { _ => return [] }
  let json = @json.parse(text) catch { _ => return [] }
  let state : PersistedAcpState = @json.from_json(json) catch { _ => return [] }
  state.sessions
}

///|
async fn load_persisted_runs(home : String) -> Array[AcpRun] {
  let path = acp_state_path(home)
  let exists = @fsx.exists(path) catch { _ => false }
  guard exists else { return [] }
  let text = @fsx.read_file(path) catch { _ => return [] }
  let json = @json.parse(text) catch { _ => return [] }
  let state : PersistedAcpState = @json.from_json(json) catch { _ => return [] }
  state.runs.unwrap_or([])
}

///|
async fn save_persisted_sessions(
  home : String,
  sessions : Array[AcpSession],
  runs : Array[AcpRun],
) -> Unit {
  ensure_acp_state_parent(home)
  @fsx.write_to_file(
    acp_state_path(home),
    PersistedAcpState::{ sessions, runs: Some(runs) }.to_json().stringify(),
  ) catch {
    _ => ()
  }
}

///|
fn session_identity_key(target_id : String, session_key : String) -> String {
  "\{target_id}::\{session_key}"
}

///|
pub async fn AcpRuntime::new(home~ : String, cwd~ : String) -> AcpRuntime {
  let runtime = AcpRuntime::{ home, cwd, targets: {}, sessions: {}, runs: {} }
  runtime.load()
  runtime
}

///|
pub async fn AcpRuntime::load(self : AcpRuntime) -> Unit {
  self.targets.clear()
  self.sessions.clear()
  self.runs.clear()
  match load_acp_config(self.home, self.cwd) {
    Some(json) =>
      for target_id, target in load_targets_from_config(json) {
        self.targets[target_id] = target
      }
    None => ()
  }
  for session in load_persisted_sessions(self.home) {
    self.sessions[session.id] = session
  }
  for run in load_persisted_runs(self.home) {
    self.runs[run.id] = run
  }
}

///|
async fn AcpRuntime::persist_sessions(self : AcpRuntime) -> Unit {
  save_persisted_sessions(
    self.home,
    self.sessions.values().to_array(),
    self.runs.values().to_array(),
  )
}

///|
pub fn AcpRuntime::list_targets(self : AcpRuntime) -> Array[AcpTarget] {
  let targets = self.targets.values().to_array()
  targets.sort_by(fn(left, right) { left.id.compare(right.id) })
  targets
}

///|
pub fn AcpRuntime::get_target(
  self : AcpRuntime,
  target_id : String,
) -> AcpTarget? {
  self.targets.get(target_id)
}

///|
pub fn AcpRuntime::list_sessions(self : AcpRuntime) -> Array[AcpSession] {
  let sessions = self.sessions.values().to_array()
  sessions.sort_by(fn(left, right) { right.updated_at.compare(left.updated_at) })
  sessions
}

///|
pub fn AcpRuntime::get_session(
  self : AcpRuntime,
  session_id : String,
) -> AcpSession? {
  self.sessions.get(session_id)
}

///|
pub fn AcpRuntime::list_sessions_for_key(
  self : AcpRuntime,
  session_key : String,
) -> Array[AcpSession] {
  let sessions = self.sessions
    .values()
    .filter(fn(session) { session.session_key == session_key })
    .to_array()
  sessions.sort_by(fn(left, right) { right.updated_at.compare(left.updated_at) })
  sessions
}

///|
pub fn AcpRuntime::list_runs(self : AcpRuntime) -> Array[AcpRun] {
  let runs = self.runs.values().to_array()
  runs.sort_by(fn(left, right) { right.updated_at.compare(left.updated_at) })
  runs
}

///|
pub fn AcpRuntime::get_run(self : AcpRuntime, run_id : String) -> AcpRun? {
  self.runs.get(run_id)
}

///|
pub fn AcpRuntime::list_runs_for_session(
  self : AcpRuntime,
  session_id : String,
) -> Array[AcpRun] {
  let runs = self.runs
    .values()
    .filter(fn(run) { run.session_id == session_id })
    .to_array()
  runs.sort_by(fn(left, right) { right.updated_at.compare(left.updated_at) })
  runs
}

///|
pub fn AcpRuntime::latest_run_for_session(
  self : AcpRuntime,
  session_id : String,
) -> AcpRun? {
  self.list_runs_for_session(session_id).get(0)
}

///|
pub async fn AcpRuntime::start_run(
  self : AcpRuntime,
  run_id : String,
  session : AcpSession,
  target : AcpTarget,
  request : Json,
  plan : Json,
  now : Int,
) -> AcpRun {
  let run = AcpRun::{
    id: run_id,
    session_id: session.id,
    session_key: session.session_key,
    target_id: target.id,
    backend: target.backend,
    status: "running",
    created_at: now,
    updated_at: now,
    request,
    plan,
    result: None,
    error: None,
  }
  self.runs[run.id] = run
  self.persist_sessions()
  run
}

///|
pub async fn AcpRuntime::finish_run(
  self : AcpRuntime,
  run_id : String,
  status : String,
  now : Int,
  result? : Json?,
  error? : String?,
) -> Result[AcpRun, String] {
  match self.runs.get(run_id) {
    Some(run) => {
      let updated = AcpRun::{
        ..run,
        status,
        updated_at: now,
        result: match result {
          Some(result) => result
          None => run.result
        },
        error: match error {
          Some(error) => error
          None => run.error
        },
      }
      self.runs[run_id] = updated
      self.persist_sessions()
      Ok(updated)
    }
    None => Err("Unknown ACP run: \{run_id}")
  }
}

///|
pub async fn AcpRuntime::delete_session(
  self : AcpRuntime,
  session_id : String,
) -> AcpSession? {
  let session = match self.sessions.get(session_id) {
    Some(session) => session
    None => return None
  }
  self.sessions.remove(session_id) |> ignore()
  self.persist_sessions()
  Some(session)
}

///|
pub async fn AcpRuntime::open_session(
  self : AcpRuntime,
  session_id : String,
  target_id : String,
  session_key : String,
  now : Int,
  metadata? : Json = {},
) -> Result[AcpSession, String] {
  let target = match self.targets.get(target_id) {
    Some(target) => target
    None => return Err("Unknown ACP target: \{target_id}")
  }
  for _, existing in self.sessions {
    if session_identity_key(existing.target_id, existing.session_key) ==
      session_identity_key(target_id, session_key) {
      let reused = AcpSession::{
        ..existing,
        updated_at: now,
        status: "attached",
        metadata: if metadata == ({} : Json) {
          existing.metadata
        } else {
          metadata
        },
      }
      self.sessions[existing.id] = reused
      self.persist_sessions()
      return Ok(reused)
    }
  }
  let session = AcpSession::{
    id: session_id,
    target_id,
    session_key,
    status: "attached",
    cwd: target.cwd,
    workspace: target.workspace,
    created_at: now,
    updated_at: now,
    last_error: None,
    metadata,
  }
  self.sessions[session.id] = session
  self.persist_sessions()
  Ok(session)
}

///|
pub async fn AcpRuntime::reset_session(
  self : AcpRuntime,
  session_id : String,
  now : Int,
) -> Result[AcpSession, String] {
  match self.sessions.get(session_id) {
    Some(session) => {
      let reset = AcpSession::{
        ..session,
        status: "reset",
        updated_at: now,
        last_error: None,
      }
      self.sessions[session_id] = reset
      self.persist_sessions()
      Ok(reset)
    }
    None => Err("Unknown ACP session: \{session_id}")
  }
}

///|
pub async fn AcpRuntime::set_session_status(
  self : AcpRuntime,
  session_id : String,
  status : String,
  now : Int,
  last_error? : String? = None,
) -> Result[AcpSession, String] {
  match self.sessions.get(session_id) {
    Some(session) => {
      let updated = AcpSession::{
        ..session,
        status,
        updated_at: now,
        last_error,
      }
      self.sessions[session_id] = updated
      self.persist_sessions()
      Ok(updated)
    }
    None => Err("Unknown ACP session: \{session_id}")
  }
}
