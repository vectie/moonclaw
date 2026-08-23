///|
priv suberror HttpError {
  HttpError(code~ : Int, reason~ : String, body~ : String)
}

///|
fn json_error(code : Int, reason : String, body : Json) -> HttpError {
  HttpError(code~, reason~, body=body.stringify())
}

///|
pub struct Gateway {
  clock : &@clock.Clock
  uuid : @uuid.Generator
  httpx : @httpx.Server
  port : Int
  events : @broadcast.Broadcast[GatewayEvent]
  auth : AuthConfig
  sessions : SessionManager
  dedupe : DedupeCache
  logger : @pino.Logger
  home : String
  cwd : String
  models : @model.Loader
  mut started_at : Int
  mut pending_requests : Int
  agent_runs : Map[String, AgentRun]
  active_channel_sessions : Map[String, @event.ExternalEventQueue]
  recent_thread_attachments : Map[String, Array[@job.E2EStarterAttachment]]
  shutdown_requested : Bool
  agent_events : @broadcast.Broadcast[@protocol.AgentEventPayload]
  channel_manager : ChannelManager
  extension_registry : @channel.ExtensionRegistry
  extension_websocket_runtime_manager : @channel.WebSocketClientRuntimeManager
  extension_websocket_runtime : @channel.WebSocketClientRuntime
  mailbox_manager : MailboxManager
  coordinator : Coordinator
  pipeline_manager : PipelineManager
  channel_state : ChannelStateStore
  job_app : @job.GatewayJobApp
  active_job_tasks : Map[String, @async.Task[Unit]]
  security_runtime : @security.SecurityRuntime
  workspace_runtime : @workspace.WorkspaceRuntime
  plugin_runtime : @plugin.PluginRuntime
  acp_runtime : @acp.AcpRuntime
  cancelled_acp_runs : Map[String, Bool]
}

///|
struct AgentRun {
  run_id : String
  session_key : String
  status : String
  created_at : Int
  completed_at : Int?
  result : Json?
  error : @protocol.ErrorShape?
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct AuthConfig {
  token : String?
  _password : String?
}

///|
struct SessionManager {
  sessions : Map[String, SessionEntry]
  session_dir : String
}

///|
pub struct SessionMessage {
  id : String
  role : String
  kind : String
  content : String
  timestamp : Int
  metadata : Json
} derive(ToJson, FromJson, Debug)

///|
struct SessionEntry {
  session_id : String
  title : String?
  updated_at : Int
  channel : String?
  model_override : String?
  provider_override : String?
  cwd : String?
  plan_mode : PlanModeState?
  messages : Array[SessionMessage]
  linked_proposal_id : String?
  linked_run_id : String?
} derive(ToJson, Debug)

///|
impl @json.FromJson for SessionEntry with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SessionEntry raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise JsonDecodeError((path, "SessionEntry: expected object"))
  }
  let session_id = match obj.get("session_id") {
    Some(String(value)) => value
    _ => raise JsonDecodeError((path, "SessionEntry: missing session_id"))
  }
  let title = match obj.get("title") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let updated_at = match obj.get("updated_at") {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
  let channel = match obj.get("channel") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let model_override = match obj.get("model_override") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let provider_override = match obj.get("provider_override") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let cwd = match obj.get("cwd") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let plan_mode = match obj.get("plan_mode") {
    Some(Null) | None => None
    Some(plan_json) =>
      Some(
        @json.from_json(plan_json, path~) catch {
          error =>
            raise JsonDecodeError((path, "SessionEntry.plan_mode: \{error}"))
        },
      )
  }
  let messages = match obj.get("messages") {
    Some(Array(items)) => {
      let parsed : Array[SessionMessage] = []
      for item in items {
        let message : SessionMessage = @json.from_json(item, path~) catch {
          error =>
            raise JsonDecodeError((path, "SessionEntry.messages: \{error}"))
        }
        parsed.push(message)
      }
      parsed
    }
    _ => []
  }
  let linked_proposal_id = match obj.get("linked_proposal_id") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let linked_run_id = match obj.get("linked_run_id") {
    Some(String(value)) => Some(value)
    _ => None
  }
  {
    session_id,
    title,
    updated_at,
    channel,
    model_override,
    provider_override,
    cwd,
    plan_mode,
    messages,
    linked_proposal_id,
    linked_run_id,
  }
}

///|
struct PlanModeState {
  request_text : String
  notes : Array[String]
  latest_candidate : @job.JobProposal
  updated_at : Int
} derive(ToJson, FromJson, Debug)

///|
struct DedupeCache {
  entries : Map[String, DedupeEntry]
  ttl_ms : Int
}

///|
struct DedupeEntry {
  ts : Int
  ok : Bool
  payload : Json?
  error : @protocol.ErrorShape?
}

///|
priv struct RemoteUiResolution {
  links : Array[@job.JobUiRemoteLink]
  handoffs : Array[@job.JobUiHandoff]
}

///|
struct PersistedChannelAccount {
  account_id : String
  config : Json
  auto_start : Bool
} derive(ToJson, FromJson, Debug)

///|
struct PersistedChannelState {
  channel_id : String
  config : @channel.ChannelConfig
  accounts : Array[PersistedChannelAccount]
} derive(ToJson, FromJson, Debug)

///|
struct ChannelStateStore {
  path : String
  states : Map[String, PersistedChannelState]
}

///|
enum GatewayEvent {
  Tick
  Shutdown
}

///|
pub fn Gateway::request_shutdown(self : Gateway) -> Unit {
  self.events.put(Shutdown)
}

///|
pub async fn Gateway::schedule_due_jobs(self : Gateway) -> Array[@job.JobRun] {
  let runs = self
    .job_runtime()
    .trigger_due_definitions(current_time_ms(), fn() {
      self.uuid.v4().to_string()
    })
  for run in runs {
    self.logger.info("Scheduled job run created: \{run.job_id} -> \{run.id}")
    self.launch_job_run(run.id)
  }
  runs
}

///|
fn Gateway::active_job_runs(self : Gateway) -> Array[@job.JobRun] {
  self
  .job_runtime()
  .store()
  .list_runs()
  .filter(fn(run) { run.status is Running || run.status is Pending })
}

///|
fn Gateway::job_runtime(self : Gateway) -> @job.RuntimeManager {
  self.job_app.runtime()
}

///|
fn Gateway::register_active_job_task(
  self : Gateway,
  run_id : String,
  task : @async.Task[Unit],
) -> Unit {
  self.active_job_tasks[run_id] = task
}

///|
fn Gateway::clear_active_job_task(self : Gateway, run_id : String) -> Unit {
  self.active_job_tasks.remove(run_id) |> ignore()
}

///|
fn Gateway::cancel_active_job_task(self : Gateway, run_id : String) -> Bool {
  match self.active_job_tasks.get(run_id) {
    Some(task) => {
      task.cancel()
      self.clear_active_job_task(run_id)
      true
    }
    None => false
  }
}

///|
pub fn Gateway::workspace_runtime(
  self : Gateway,
) -> @workspace.WorkspaceRuntime {
  self.workspace_runtime
}

///|
pub fn Gateway::security_runtime(self : Gateway) -> @security.SecurityRuntime {
  self.security_runtime
}

///|
pub fn Gateway::plugin_runtime(self : Gateway) -> @plugin.PluginRuntime {
  self.plugin_runtime
}

///|
pub fn Gateway::acp_runtime(self : Gateway) -> @acp.AcpRuntime {
  self.acp_runtime
}

///|
fn Gateway::cancel_active_acp_run(
  _self : Gateway,
  _run_id : String,
) -> Result[Bool, String] {
  // ACP host execution is fail-closed in execute_managed_acp_process, so this
  // process can never own a live ACP child.
  Ok(false)
}

///|
fn Gateway::active_acp_run_for_session(
  _self : Gateway,
  _session_id : String,
) -> @acp.AcpRun? {
  None
}

///|
fn Gateway::active_acp_stdio(_self : Gateway, _run_id : String) -> Json? {
  None
}

///|
fn linkage_matches_job_run(run : @job.JobRun, linkage : Json?) -> Bool {
  match linkage {
    Some({ "linked_job_run_id": String(linked_run_id), .. }) if linked_run_id ==
      run.id => true
    Some({ "linked_job_id": String(linked_job_id), .. }) if linked_job_id ==
      run.job_id => true
    Some({ "linked_workspace": String(linked_workspace), .. }) =>
      match run.workspace_dir {
        Some(workspace) => linked_workspace == workspace
        None => false
      }
    _ => false
  }
}

///|
fn session_linkage(session : @acp.AcpSession) -> Json? {
  if session.metadata == ({} : Json) {
    None
  } else {
    Some(session.metadata)
  }
}

///|
fn run_linkage(run : @acp.AcpRun) -> Json? {
  match run.request {
    { "metadata": metadata, .. } => Some(metadata)
    _ => None
  }
}

///|
fn json_object_copy(raw : Json?) -> Map[String, Json] {
  let copied : Map[String, Json] = Map([])
  match raw {
    Some(Object(obj)) =>
      for key in obj.keys().to_array() {
        match obj.get(key) {
          Some(value) => copied[key] = value
          None => ()
        }
      }
    _ => ()
  }
  copied
}

///|
fn merged_acp_linkage_metadata(
  session_metadata : Json,
  request_metadata : Json?,
) -> Json? {
  let merged = json_object_copy(request_metadata)
  let inherited = json_object_copy(Some(session_metadata))
  for key in inherited.keys().to_array() {
    if merged.get(key) is None {
      match inherited.get(key) {
        Some(value) => merged[key] = value
        None => ()
      }
    }
  }
  if merged.is_empty() {
    None
  } else {
    Some(merged.to_json())
  }
}

///|
fn merged_acp_run_metadata(
  session : @acp.AcpSession,
  request_metadata : Json?,
) -> Json? {
  merged_acp_linkage_metadata(session.metadata, request_metadata)
}

///|
fn run_result_summary(run : @acp.AcpRun) -> String? {
  match run.result {
    Some({ "content": String(content), .. }) if !content.trim().is_blank() =>
      Some(content.trim().to_owned())
    Some({ "stdout": String(stdout), .. }) if !stdout.trim().is_blank() =>
      Some(stdout.trim().to_owned())
    _ =>
      match run.error {
        Some(error) if !error.trim().is_blank() => Some(error.trim().to_owned())
        _ => None
      }
  }
}

///|
fn linkage_node_id(linkage : Json?) -> String? {
  match linkage {
    Some({ "linked_job_node_id": String(node_id), .. }) => Some(node_id)
    _ => None
  }
}

///|
fn linkage_step_id(linkage : Json?) -> String? {
  match linkage {
    Some({ "linked_job_step_id": String(step_id), .. }) => Some(step_id)
    _ => None
  }
}

///|
fn append_handoff(
  handoffs : Array[@job.JobUiHandoff],
  link : @job.JobUiRemoteLink,
) -> Unit {
  let linkage = match link.metadata {
    { "linkage": linkage, .. } => Some(linkage)
    _ => None
  }
  let node_id = match linkage_node_id(linkage) {
    Some(node_id) => node_id
    None => return
  }
  let step_id = linkage_step_id(linkage)
  for i = 0; i < handoffs.length(); i = i + 1 {
    if handoffs[i].node_id == node_id && handoffs[i].step_id == step_id {
      handoffs[i] = { ..handoffs[i], remote: handoffs[i].remote + [link] }
      return
    }
  }
  handoffs.push({ node_id, step_id, remote: [link] })
}

///|
fn Gateway::resolve_remote_ui_for_job_run(
  self : Gateway,
  run_id : String,
) -> RemoteUiResolution {
  let job_run = match self.job_runtime().store().get_run(run_id) {
    Some(run) => run
    None => return { links: [], handoffs: [] }
  }
  let links : Array[@job.JobUiRemoteLink] = []
  let handoffs : Array[@job.JobUiHandoff] = []
  for session in self.acp_runtime().list_sessions() {
    if linkage_matches_job_run(job_run, session_linkage(session)) {
      let link = @job.JobUiRemoteLink::{
        id: "acp-session:\{session.id}",
        kind: "acp_session",
        title: session.id,
        status: session.status,
        summary: Some(session.target_id),
        detail: match session.workspace {
          Some(workspace) => Some(workspace)
          None => session.cwd
        },
        metadata: {
          "target_id": session.target_id,
          "session_key": session.session_key,
          "linkage": session.metadata,
          "last_error": session.last_error,
          "created_at": session.created_at,
          "updated_at": session.updated_at,
        },
      }
      links.push(link)
      append_handoff(handoffs, link)
    }
  }
  for acp_run in self.acp_runtime().list_runs() {
    if linkage_matches_job_run(job_run, run_linkage(acp_run)) {
      let link = @job.JobUiRemoteLink::{
        id: "acp-run:\{acp_run.id}",
        kind: "acp_run",
        title: acp_run.id,
        status: acp_run.status,
        summary: run_result_summary(acp_run),
        detail: match acp_run.request {
          { "message": String(message), .. } => Some(message)
          _ => None
        },
        metadata: {
          "target_id": acp_run.target_id,
          "session_id": acp_run.session_id,
          "session_key": acp_run.session_key,
          "backend": acp_run.backend,
          "linkage": run_linkage(acp_run),
          "result": acp_run.result,
          "error": acp_run.error,
          "created_at": acp_run.created_at,
          "updated_at": acp_run.updated_at,
        },
      }
      links.push(link)
      append_handoff(handoffs, link)
    }
  }
  { links, handoffs }
}
