///|
pub struct Client {
  base_url : String
  token : String?
  http : @http.Client
  uuid : @uuid.Generator
  logger : @pino.Logger
  mut connected : Bool
}

///|
pub(all) struct ClientConfig {
  base_url : String
  token : String?
  client_id : String?
  client_mode : @protocol.ClientMode
}

///|
pub(all) struct RunInfo {
  run_id : String
  session_key : String
  status : String
  created_at : Int
  completed_at : Int?
  result : Json?
  error : @protocol.ErrorShape?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct RunsListPayload {
  runs : Array[RunInfo]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobsListPayload {
  jobs : Array[@job.JobDefinition]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobRunsPayload {
  runs : Array[@job.JobRun]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct MemoriesListPayload {
  memories : Array[@job.MemoryRecord]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct WorkspacePayload {
  workspace : @workspace.WorkspaceSnapshot
} derive(ToJson, FromJson, Show)

///|
pub(all) struct PluginsListPayload {
  plugins : Array[@plugin.PluginRecord]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpTargetsPayload {
  targets : Array[@acp.AcpTarget]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpTargetPayload {
  target : @acp.AcpTarget
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpSessionsPayload {
  sessions : Array[@acp.AcpSession]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpSessionPayload {
  session : @acp.AcpSession
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpSessionMutationPayload {
  status : String
  session : @acp.AcpSession
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpRunsPayload {
  runs : Array[@acp.AcpRun]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpRunPayload {
  run : @acp.AcpRun
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpRunMutationPayload {
  status : String
  run : @acp.AcpRun
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpUiSnapshotPayload {
  snapshot : @acp.AcpUiSnapshot
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpUiEventsPayload {
  timeline : Array[@acp.AcpUiTimelineEntry]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AcpSessionRunPayload {
  status : String
  session : @acp.AcpSession
  run : @acp.AcpRun
  accepted : @protocol.AgentAcceptedPayload
  target : @acp.AcpTarget
  plan : @acp.AcpLaunchPlan
} derive(ToJson, FromJson, Show)

///|
pub(all) struct MemoryMutationPayload {
  status : String
  memory : @job.MemoryRecord
} derive(ToJson, FromJson, Show)

///|
pub(all) struct MemorySearchPayload {
  hits : Array[@job.MemorySearchHit]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobMutationPayload {
  status : String
  job : @job.JobDefinition?
  run : @job.JobRun?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobPayload {
  job : @job.JobDefinition
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobRunDetails {
  run : @job.JobRun
  steps : Array[@job.JobStepRun]
  artifacts : Array[@job.ArtifactRecord]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobUiSnapshotPayload {
  snapshot : @job.JobUiSnapshot
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobUiEventsPayload {
  timeline : Array[@job.JobUiTimelineEntry]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChannelsListPayload {
  channels : Array[@channel.ChannelDock]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChannelMutationPayload {
  status : String
  channel_id : String
  account_id : String?
} derive(ToJson, FromJson, Show)

///|
pub async fn Client::new(config : ClientConfig) -> Client {
  let uuid = @uuid.generator(@rand.chacha8())
  Client::{
    base_url: config.base_url,
    token: config.token,
    http: @http.Client::new(config.base_url),
    uuid,
    logger: @pino.logger("gateway-client", @pino.Transport::console()),
    connected: false,
  }
}

///|
pub async fn Client::connect(
  self : Client,
) -> Result[@protocol.HelloOk, String] {
  let connect_params = @protocol.ConnectParams::{
    min_protocol: @protocol.PROTOCOL_VERSION,
    max_protocol: @protocol.PROTOCOL_VERSION,
    client: @protocol.ClientInfo::{
      id: self.uuid.v4().to_string(),
      display_name: Some("moonclaw-client"),
      version: Some(@buildinfo.version.to_string()),
      platform: None,
      mode: @protocol.ClientMode::Cli,
    },
    auth: @protocol.AuthCredentials::{ token: self.token, password: None },
    role: @protocol.ClientRole::Operator,
    scopes: Some(["operator.admin"]),
  }
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "connect",
    params: Some(connect_params.to_json()),
  }
  let response = self.send_rpc(request)
  let hello : Result[@protocol.HelloOk, String] = decode_ok_payload(
    response, "Connection failed with unknown error", "Missing hello response payload",
    "Failed to parse hello response",
  )
  match hello {
    Ok(hello) => {
      self.connected = true
      Ok(hello)
    }
    Err(error) => Err(error)
  }
}

///|
pub async fn Client::agent(
  self : Client,
  message~ : String,
  session_key? : String,
  cwd? : String,
  model? : String,
  run_id? : String,
) -> Result[@protocol.AgentAcceptedPayload, String] {
  let params = @protocol.AgentParams::{
    message,
    session_key,
    cwd,
    model,
    provider: None,
    run_id,
    idempotency_key: None,
  }
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "agent",
    params: Some(params.to_json()),
  }
  let response = self.send_rpc(request)
  decode_ok_payload(
    response, "Agent request failed with unknown error", "Missing agent accepted response payload",
    "Failed to parse agent accepted response",
  )
}

///|
pub async fn Client::wait_agent(
  self : Client,
  run_id~ : String,
  timeout_ms? : Int = 60000,
) -> Result[Json, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "agent.wait",
    params: Some({ "run_id": run_id, "timeout_ms": timeout_ms }),
  }
  let response = self.send_rpc(request)
  decode_ok_payload(
    response, "Agent wait failed with unknown error", "Missing agent wait response payload",
    "Failed to parse agent wait response",
  )
}

///|
pub async fn Client::list_sessions(
  self : Client,
) -> Result[@protocol.SessionsListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "sessions.list",
    params: None,
  }
  let response = self.send_rpc(request)
  decode_ok_payload(
    response, "Sessions list failed with unknown error", "Missing sessions response payload",
    "Failed to parse sessions response",
  )
}

///|
pub async fn Client::health(
  self : Client,
) -> Result[@protocol.HealthPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "health",
    params: None,
  }
  let response = self.send_rpc(request)
  decode_ok_payload(
    response, "Health check failed with unknown error", "Missing health response payload",
    "Failed to parse health response",
  )
}

///|
pub async fn Client::list_runs(
  self : Client,
) -> Result[RunsListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "runs.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Runs list failed with unknown error",
    "Missing runs response payload",
    "Failed to parse runs response",
  )
}

///|
pub async fn Client::get_run(
  self : Client,
  run_id~ : String,
) -> Result[RunInfo, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "runs.get",
    params: Some({ "run_id": run_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Run lookup failed with unknown error",
    "Missing run response payload",
    "Failed to parse run response",
  )
}

///|
pub async fn Client::list_channels(
  self : Client,
) -> Result[ChannelsListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "channels.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Channels list failed with unknown error",
    "Missing channels response payload",
    "Failed to parse channels response",
  )
}

///|
pub async fn Client::get_channel(
  self : Client,
  channel_id~ : String,
) -> Result[@channel.ChannelDock, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "channels.get",
    params: Some({ "channel_id": channel_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Channel lookup failed with unknown error",
    "Missing channel response payload",
    "Failed to parse channel response",
  )
}

///|
pub async fn Client::configure_channel(
  self : Client,
  channel_id~ : String,
  config : @channel.ChannelConfig,
) -> Result[ChannelMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "channels.configure",
    params: Some({ "channel_id": channel_id, "config": config.to_json() }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Channel configure failed with unknown error",
    "Missing channel configure payload",
    "Failed to parse channel configure response",
  )
}

///|
pub async fn Client::start_channel(
  self : Client,
  channel_id~ : String,
  account_id~ : String,
  config : Json,
) -> Result[ChannelMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "channels.start",
    params: Some({
      "channel_id": channel_id,
      "account_id": account_id,
      "config": config,
    }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Channel start failed with unknown error",
    "Missing channel start payload",
    "Failed to parse channel start response",
  )
}

///|
pub async fn Client::stop_channel(
  self : Client,
  channel_id~ : String,
  account_id~ : String,
) -> Result[ChannelMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "channels.stop",
    params: Some({ "channel_id": channel_id, "account_id": account_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Channel stop failed with unknown error",
    "Missing channel stop payload",
    "Failed to parse channel stop response",
  )
}

///|
pub async fn Client::ask_job(
  self : Client,
  params : @job.JobAskParams,
) -> Result[@job.ChatAnswer, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.ask",
    params: Some(params.to_json()),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job ask failed with unknown error",
    "Missing job ask payload",
    "Failed to parse job ask response",
  )
}

///|
pub async fn Client::get_workspace(
  self : Client,
) -> Result[WorkspacePayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "workspace.get",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Workspace lookup failed with unknown error",
    "Missing workspace payload",
    "Failed to parse workspace payload",
  )
}

///|
pub async fn Client::list_plugins(
  self : Client,
) -> Result[PluginsListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "plugins.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Plugin list failed with unknown error",
    "Missing plugins payload",
    "Failed to parse plugins payload",
  )
}

///|
pub async fn Client::get_plugin(
  self : Client,
  plugin_id~ : String,
) -> Result[@plugin.PluginRecord, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "plugins.get",
    params: Some({ "plugin_id": plugin_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Plugin lookup failed with unknown error",
    "Missing plugin payload",
    "Failed to parse plugin payload",
  )
}

///|
pub async fn Client::list_acp_targets(
  self : Client,
) -> Result[AcpTargetsPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.targets.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP target list failed with unknown error",
    "Missing ACP targets payload",
    "Failed to parse ACP targets payload",
  )
}

///|
pub async fn Client::get_acp_target(
  self : Client,
  target_id~ : String,
) -> Result[AcpTargetPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.targets.get",
    params: Some({ "target_id": target_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP target lookup failed with unknown error",
    "Missing ACP target payload",
    "Failed to parse ACP target payload",
  )
}

///|
pub async fn Client::list_acp_sessions(
  self : Client,
) -> Result[AcpSessionsPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.sessions.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP session list failed with unknown error",
    "Missing ACP sessions payload",
    "Failed to parse ACP sessions payload",
  )
}

///|
pub async fn Client::get_acp_session(
  self : Client,
  session_id~ : String,
) -> Result[AcpSessionPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.sessions.get",
    params: Some({ "session_id": session_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP session lookup failed with unknown error",
    "Missing ACP session payload",
    "Failed to parse ACP session payload",
  )
}

///|
pub async fn Client::create_acp_session(
  self : Client,
  target_id~ : String,
  session_key~ : String,
  session_id? : String,
  metadata? : Json = {},
) -> Result[AcpSessionMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.sessions.create",
    params: Some({
      "target_id": target_id,
      "session_key": session_key,
      "session_id": session_id,
      "metadata": metadata,
    }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP session create failed with unknown error",
    "Missing ACP session mutation payload",
    "Failed to parse ACP session mutation payload",
  )
}

///|
pub async fn Client::reset_acp_session(
  self : Client,
  session_id~ : String,
) -> Result[AcpSessionMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.sessions.reset",
    params: Some({ "session_id": session_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP session reset failed with unknown error",
    "Missing ACP session reset payload",
    "Failed to parse ACP session reset payload",
  )
}

///|
pub async fn Client::list_acp_runs(
  self : Client,
) -> Result[AcpRunsPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.runs.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP run list failed with unknown error",
    "Missing ACP runs payload",
    "Failed to parse ACP runs payload",
  )
}

///|
pub async fn Client::get_acp_run(
  self : Client,
  run_id~ : String,
) -> Result[AcpRunPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.runs.get",
    params: Some({ "run_id": run_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP run lookup failed with unknown error",
    "Missing ACP run payload",
    "Failed to parse ACP run payload",
  )
}

///|
pub async fn Client::cancel_acp_run(
  self : Client,
  run_id~ : String,
) -> Result[AcpRunMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.runs.cancel",
    params: Some({ "run_id": run_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP run cancel failed with unknown error",
    "Missing ACP run cancel payload",
    "Failed to parse ACP run cancel payload",
  )
}

///|
pub async fn Client::get_acp_ui_snapshot(
  self : Client,
) -> Result[AcpUiSnapshotPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.ui.get",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP UI snapshot failed with unknown error",
    "Missing ACP UI snapshot payload",
    "Failed to parse ACP UI snapshot payload",
  )
}

///|
pub async fn Client::get_acp_ui_events(
  self : Client,
) -> Result[AcpUiEventsPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.ui.events",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP UI events failed with unknown error",
    "Missing ACP UI events payload",
    "Failed to parse ACP UI events payload",
  )
}

///|
pub async fn Client::run_acp_session(
  self : Client,
  session_id~ : String,
  message~ : String,
  run_id? : String,
  model? : String,
  cwd? : String,
  idempotency_key? : String,
) -> Result[AcpSessionRunPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "acp.sessions.run",
    params: Some({
      "session_id": session_id,
      "message": message,
      "run_id": run_id,
      "model": model,
      "cwd": cwd,
      "idempotency_key": idempotency_key,
    }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "ACP session run failed with unknown error",
    "Missing ACP session run payload",
    "Failed to parse ACP session run payload",
  )
}

///|
pub async fn Client::list_memories(
  self : Client,
  query? : @job.MemoryQuery,
) -> Result[MemoriesListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "memories.list",
    params: query.map(fn(query) { query.to_json() }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Memories list failed with unknown error",
    "Missing memories payload",
    "Failed to parse memories payload",
  )
}

///|
pub async fn Client::get_memory(
  self : Client,
  memory_id~ : String,
) -> Result[@job.MemoryRecord, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "memories.get",
    params: Some({ "memory_id": memory_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Memory lookup failed with unknown error",
    "Missing memory payload",
    "Failed to parse memory payload",
  )
}

///|
pub async fn Client::create_memory(
  self : Client,
  params : @job.MemoryWriteRequest,
) -> Result[MemoryMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "memories.create",
    params: Some(params.to_json()),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Memory create failed with unknown error",
    "Missing memory create payload",
    "Failed to parse memory create payload",
  )
}

///|
pub async fn Client::search_memories(
  self : Client,
  question~ : String,
  query? : @job.MemoryQuery,
  max_hits? : Int = 5,
) -> Result[MemorySearchPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "memories.search",
    params: Some({
      "question": question,
      "query": query.map(fn(query) { query.to_json() }),
      "max_hits": max_hits,
    }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Memory search failed with unknown error",
    "Missing memory search payload",
    "Failed to parse memory search payload",
  )
}

///|
pub async fn Client::list_jobs(
  self : Client,
) -> Result[JobsListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Jobs list failed with unknown error",
    "Missing jobs payload",
    "Failed to parse jobs payload",
  )
}

///|
pub async fn Client::get_job(
  self : Client,
  job_id~ : String,
) -> Result[JobPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.get",
    params: Some({ "job_id": job_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job lookup failed with unknown error",
    "Missing job payload",
    "Failed to parse job payload",
  )
}

///|
pub async fn Client::create_job(
  self : Client,
  definition : @job.JobDefinition,
) -> Result[JobMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.create",
    params: Some(definition.to_json()),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job create failed with unknown error",
    "Missing job create payload",
    "Failed to parse job create response",
  )
}

///|
pub async fn Client::update_job(
  self : Client,
  definition : @job.JobDefinition,
) -> Result[JobMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.update",
    params: Some(definition.to_json()),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job update failed with unknown error",
    "Missing job update payload",
    "Failed to parse job update response",
  )
}

///|
pub async fn Client::run_job(
  self : Client,
  job_id~ : String,
) -> Result[JobMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.run",
    params: Some({ "job_id": job_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job run failed with unknown error",
    "Missing job run payload",
    "Failed to parse job run response",
  )
}

///|
pub async fn Client::cancel_job(
  self : Client,
  job_id~ : String,
) -> Result[JobMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.cancel",
    params: Some({ "job_id": job_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job cancel failed with unknown error",
    "Missing job cancel payload",
    "Failed to parse job cancel response",
  )
}

///|
pub async fn Client::force_cancel_job(
  self : Client,
  job_id~ : String,
) -> Result[JobMutationPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.force_cancel",
    params: Some({ "job_id": job_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job force-cancel failed with unknown error",
    "Missing job force-cancel payload",
    "Failed to parse job force-cancel response",
  )
}

///|
pub async fn Client::list_job_runs(
  self : Client,
) -> Result[JobRunsPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.runs.list",
    params: None,
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job runs list failed with unknown error",
    "Missing job runs payload",
    "Failed to parse job runs response",
  )
}

///|
pub async fn Client::get_job_run(
  self : Client,
  run_id~ : String,
) -> Result[JobRunDetails, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.runs.get",
    params: Some({ "run_id": run_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job run lookup failed with unknown error",
    "Missing job run payload",
    "Failed to parse job run response",
  )
}

///|
pub async fn Client::get_job_ui_snapshot(
  self : Client,
  run_id~ : String,
) -> Result[JobUiSnapshotPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.ui.get",
    params: Some({ "run_id": run_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job UI snapshot lookup failed with unknown error",
    "Missing job UI snapshot payload",
    "Failed to parse job UI snapshot response",
  )
}

///|
pub async fn Client::get_job_ui_events(
  self : Client,
  run_id~ : String,
) -> Result[JobUiEventsPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    rpc_method: "jobs.ui.events",
    params: Some({ "run_id": run_id }),
  }
  decode_ok_payload(
    self.send_rpc(request),
    "Job UI events lookup failed with unknown error",
    "Missing job UI events payload",
    "Failed to parse job UI events response",
  )
}

///|
async fn Client::send_rpc(
  self : Client,
  request : @protocol.Request,
) -> Result[@protocol.Response, String] {
  let frame : Json = {
    "type": "req",
    "id": request.id,
    "method": request.rpc_method,
    "params": request.params,
  }
  let extra_headers : Map[String, String] = {
    "Content-Type": "application/json",
  }
  let _ = self.http.post(
    "/v1/rpc",
    @encoding/utf8.encode(frame.stringify()),
    extra_headers~,
  )
  let body = self.http.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ => return Err("Failed to decode response as UTF-8")
  }
  let json = @json.parse(text) catch {
    e => return Err("Failed to parse response: \{e}")
  }
  guard json is Object(obj) else { return Err("Response is not a JSON object") }
  let ok = match obj.get("ok") {
    Some(True) => true
    Some(False) => false
    _ => false
  }
  let error = match obj.get("error") {
    Some(error_json) => {
      let e = @json.from_json(error_json) catch {
        _ => return Err("Failed to parse error")
      }
      Some(e)
    }
    None => None
  }
  Ok(@protocol.Response::{
    id: request.id,
    ok,
    payload: obj.get("payload"),
    error,
  })
}

///|
fn[T : @json.FromJson] decode_ok_payload(
  response : Result[@protocol.Response, String],
  default_error : String,
  missing_payload_error : String,
  parse_error_prefix : String,
) -> Result[T, String] {
  match response {
    Err(error) => Err(error)
    Ok(res) =>
      if !res.ok {
        match res.error {
          Some(error) => Err(error.message)
          None => Err(default_error)
        }
      } else {
        match res.payload {
          Some(payload) => {
            let parsed : T = @json.from_json(payload) catch {
              error => return Err("\{parse_error_prefix}: \{error}")
            }
            Ok(parsed)
          }
          None => Err(missing_payload_error)
        }
      }
  }
}
