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
  match response {
    Err(e) => Err(e)
    Ok(res) =>
      if !res.ok {
        match res.error {
          Some(error) => Err(error.message)
          None => Err("Connection failed with unknown error")
        }
      } else {
        match res.payload {
          Some(payload) => {
            let hello = @json.from_json(payload) catch {
              e => return Err("Failed to parse hello response: \{e}")
            }
            self.connected = true
            Ok(hello)
          }
          None => Err("Missing hello response payload")
        }
      }
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
  match response {
    Err(e) => Err(e)
    Ok(res) =>
      if !res.ok {
        match res.error {
          Some(error) => Err(error.message)
          None => Err("Agent request failed with unknown error")
        }
      } else {
        match res.payload {
          Some(payload) => {
            let accepted = @json.from_json(payload) catch {
              e => return Err("Failed to parse agent accepted response: \{e}")
            }
            Ok(accepted)
          }
          None => Err("Missing agent accepted response payload")
        }
      }
  }
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
  match response {
    Err(e) => Err(e)
    Ok(res) =>
      if !res.ok {
        match res.error {
          Some(error) => Err(error.message)
          None => Err("Agent wait failed with unknown error")
        }
      } else {
        match res.payload {
          Some(payload) => Ok(payload)
          None => Err("Missing agent wait response payload")
        }
      }
  }
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
  match response {
    Err(e) => Err(e)
    Ok(res) =>
      if !res.ok {
        match res.error {
          Some(error) => Err(error.message)
          None => Err("Sessions list failed with unknown error")
        }
      } else {
        match res.payload {
          Some(payload) => {
            let sessions = @json.from_json(payload) catch {
              e => return Err("Failed to parse sessions response: \{e}")
            }
            Ok(sessions)
          }
          None => Err("Missing sessions response payload")
        }
      }
  }
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
  match response {
    Err(e) => Err(e)
    Ok(res) =>
      if !res.ok {
        match res.error {
          Some(error) => Err(error.message)
          None => Err("Health check failed with unknown error")
        }
      } else {
        match res.payload {
          Some(payload) => {
            let health = @json.from_json(payload) catch {
              e => return Err("Failed to parse health response: \{e}")
            }
            Ok(health)
          }
          None => Err("Missing health response payload")
        }
      }
  }
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
    frame.stringify().to_bytes(),
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
