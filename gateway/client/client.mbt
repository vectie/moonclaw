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
    method: "connect",
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
    method: "agent",
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
    method: "agent.wait",
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
    method: "sessions.list",
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
    method: "health",
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
    method: "runs.list",
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
    method: "runs.get",
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
    method: "channels.list",
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
    method: "channels.get",
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
    method: "channels.configure",
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
    method: "channels.start",
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
    method: "channels.stop",
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
    method: "jobs.ask",
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
pub async fn Client::list_jobs(
  self : Client,
) -> Result[JobsListPayload, String] {
  let request = @protocol.Request::{
    id: self.uuid.v4().to_string(),
    method: "jobs.list",
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
    method: "jobs.get",
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
    method: "jobs.create",
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
    method: "jobs.update",
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
    method: "jobs.run",
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
    method: "jobs.cancel",
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
    method: "jobs.force_cancel",
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
    method: "jobs.runs.list",
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
    method: "jobs.runs.get",
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
async fn Client::send_rpc(
  self : Client,
  request : @protocol.Request,
) -> Result[@protocol.Response, String] {
  let frame : Json = {
    "type": "req",
    "id": request.id,
    "method": request.method,
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
