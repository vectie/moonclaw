///|
pub suberror ExtensionError {
  ExtensionError(message~ : String)
}

///|
/// Logger functions for extensions
pub(all) struct LoggerFuncs {
  info : (String) -> Unit
  warn : (String) -> Unit
  error : (String) -> Unit
  debug : (String) -> Unit
}

///|
pub fn LoggerFuncs::new(
  info~ : (String) -> Unit,
  warn~ : (String) -> Unit,
  error~ : (String) -> Unit,
  debug~ : (String) -> Unit,
) -> LoggerFuncs {
  LoggerFuncs::{ info, warn, error, debug }
}

///|
/// Context provided to extensions when they are registered
pub(all) struct ExtensionContext {
  gateway_url : String
  gateway_token : String?
  home_dir : String
  cwd : String
  logger : LoggerFuncs?
  websocket_connector : WebSocketClientConnector?
  websocket_runtime : WebSocketClientRuntime?
}

///|
pub fn ExtensionContext::new(
  gateway_url~ : String,
  gateway_token? : String? = None,
  home_dir~ : String,
  cwd~ : String,
  logger? : LoggerFuncs? = None,
  websocket_connector? : WebSocketClientConnector? = None,
  websocket_runtime? : WebSocketClientRuntime? = None,
) -> ExtensionContext {
  ExtensionContext::{
    gateway_url,
    gateway_token,
    home_dir,
    cwd,
    logger,
    websocket_connector,
    websocket_runtime,
  }
}

///|
pub fn ExtensionContext::gateway_url(self : ExtensionContext) -> String {
  self.gateway_url
}

///|
pub fn ExtensionContext::gateway_token(self : ExtensionContext) -> String? {
  self.gateway_token
}

///|
pub fn ExtensionContext::home_dir(self : ExtensionContext) -> String {
  self.home_dir
}

///|
pub fn ExtensionContext::cwd(self : ExtensionContext) -> String {
  self.cwd
}

///|
pub fn ExtensionContext::logger(self : ExtensionContext) -> LoggerFuncs? {
  self.logger
}

///|
pub fn ExtensionContext::websocket_connector(
  self : ExtensionContext,
) -> WebSocketClientConnector? {
  self.websocket_connector
}

///|
pub fn ExtensionContext::websocket_runtime(
  self : ExtensionContext,
) -> WebSocketClientRuntime? {
  self.websocket_runtime
}

///|
/// Extension trait for channels that need to handle incoming requests
/// from external services (like Feishu, Slack, etc.)
pub(open) trait ChannelExtension: Channel {
  /// Returns the webhook path for this channel extension
  /// e.g., "/webhook/feishu" or "/webhook/slack"
  webhook_path(Self) -> String

  /// Handles incoming webhook requests from external services
  /// Returns a response to be sent back to the caller
  async handle_webhook(Self, request : ExtensionRequest) -> ExtensionResponse

  /// Returns true if this extension supports WebSocket connections
  supports_websocket(Self) -> Bool

  /// Handles WebSocket connections for real-time communication
  handle_websocket(Self, conn : WebSocketConnection) -> Unit

  /// Returns the list of HTTP methods supported by this extension's webhook
  allowed_methods(Self) -> Array[String]

  /// Returns the dock configuration for this channel
  /// This includes outbound, threading, mentions, streaming, and security settings
  dock_config(Self) -> ChannelDockConfig

  /// Called when the extension is registered with the gateway
  /// Allows the extension to initialize resources
  on_register(Self, context : ExtensionContext) -> Unit

  /// Called when the extension is unregistered from the gateway
  /// Allows the extension to cleanup resources
  on_unregister(Self) -> Unit
}

///|
/// Request structure for channel extensions
pub(all) struct ExtensionRequest {
  http_method : String
  path : String
  headers : Map[String, String]
  body : Bytes
  query_params : Map[String, String]
}

///|
pub fn ExtensionRequest::new(
  http_method~ : String,
  path~ : String,
  headers~ : Map[String, String],
  body~ : Bytes,
  query_params? : Map[String, String] = {},
) -> ExtensionRequest {
  ExtensionRequest::{ http_method, path, headers, body, query_params }
}

///|
pub fn ExtensionRequest::http_method(self : ExtensionRequest) -> String {
  self.http_method
}

///|
pub fn ExtensionRequest::path(self : ExtensionRequest) -> String {
  self.path
}

///|
pub fn ExtensionRequest::headers(
  self : ExtensionRequest,
) -> Map[String, String] {
  self.headers
}

///|
pub fn ExtensionRequest::body(self : ExtensionRequest) -> Bytes {
  self.body
}

///|
pub fn ExtensionRequest::query_params(
  self : ExtensionRequest,
) -> Map[String, String] {
  self.query_params
}

///|
pub fn ExtensionRequest::json(self : ExtensionRequest) -> Json raise {
  let body_str = @encoding/utf8.decode(self.body) catch {
    _ => raise ExtensionError(message="Invalid UTF-8 in request body")
  }
  @json.parse(body_str) catch {
    _ => raise ExtensionError(message="Invalid JSON in request body")
  }
}

///|
pub fn ExtensionRequest::query_param(
  self : ExtensionRequest,
  key : String,
) -> String? {
  self.query_params.get(key)
}

///|
pub fn ExtensionRequest::header(
  self : ExtensionRequest,
  key : String,
) -> String? {
  self.headers.get(key)
}

///|
/// Response structure for channel extensions
pub(all) struct ExtensionResponse {
  status_code : Int
  headers : Map[String, String]
  body : Bytes
}

///|
pub fn ExtensionResponse::new(
  status_code? : Int = 200,
  headers? : Map[String, String] = {},
  body? : Bytes = b"",
) -> ExtensionResponse {
  ExtensionResponse::{ status_code, headers, body }
}

///|
pub fn ExtensionResponse::status_code(self : ExtensionResponse) -> Int {
  self.status_code
}

///|
pub fn ExtensionResponse::headers(
  self : ExtensionResponse,
) -> Map[String, String] {
  self.headers
}

///|
pub fn ExtensionResponse::body(self : ExtensionResponse) -> Bytes {
  self.body
}

///|
pub fn ExtensionResponse::json(
  data : Json,
  status_code? : Int = 200,
) -> ExtensionResponse {
  let headers = { "Content-Type": "application/json" }
  ExtensionResponse::new(
    status_code~,
    headers~,
    body=@encoding/utf8.encode(data.stringify()),
  )
}

///|
pub fn ExtensionResponse::text(
  text : String,
  status_code? : Int = 200,
) -> ExtensionResponse {
  let headers = { "Content-Type": "text/plain" }
  ExtensionResponse::new(
    status_code~,
    headers~,
    body=@encoding/utf8.encode(text),
  )
}

///|
pub fn ExtensionResponse::ok() -> ExtensionResponse {
  ExtensionResponse::new(status_code=200, body=b"OK")
}

///|
pub fn ExtensionResponse::not_found() -> ExtensionResponse {
  ExtensionResponse::new(status_code=404, body=b"Not Found")
}

///|
pub fn ExtensionResponse::bad_request(
  message? : String = "Bad Request",
) -> ExtensionResponse {
  ExtensionResponse::new(status_code=400, body=@encoding/utf8.encode(message))
}

///|
pub fn ExtensionResponse::unauthorized(
  message? : String = "Unauthorized",
) -> ExtensionResponse {
  ExtensionResponse::new(status_code=401, body=@encoding/utf8.encode(message))
}

///|
pub fn ExtensionResponse::internal_error(
  message? : String = "Internal Server Error",
) -> ExtensionResponse {
  ExtensionResponse::new(status_code=500, body=@encoding/utf8.encode(message))
}

///|
pub fn ExtensionResponse::no_content() -> ExtensionResponse {
  ExtensionResponse::new(status_code=204, body=b"")
}

///|
/// WebSocket connection handle for real-time communication
pub(all) struct WebSocketConnection {
  id : String
  send : (Bytes) -> Unit
  close : () -> Unit
  on_message : (async (Bytes) -> Unit) -> Unit
  on_close : (() -> Unit) -> Unit
}

///|
pub fn WebSocketConnection::new(
  id~ : String,
  send~ : (Bytes) -> Unit,
  close~ : () -> Unit,
  on_message? : (async (Bytes) -> Unit) -> Unit = fn(_) {  },
  on_close? : (() -> Unit) -> Unit = fn(_) {  },
) -> WebSocketConnection {
  WebSocketConnection::{ id, send, close, on_message, on_close }
}

///|
pub fn WebSocketConnection::id(self : WebSocketConnection) -> String {
  self.id
}

///|
pub fn WebSocketConnection::send(
  self : WebSocketConnection,
  data : Bytes,
) -> Unit {
  (self.send)(data)
}

///|
pub fn WebSocketConnection::close(self : WebSocketConnection) -> Unit {
  (self.close)()
}

///|
pub fn WebSocketConnection::on_message(
  self : WebSocketConnection,
  handler : async (Bytes) -> Unit,
) -> Unit {
  (self.on_message)(handler)
}

///|
pub fn WebSocketConnection::on_close(
  self : WebSocketConnection,
  handler : () -> Unit,
) -> Unit {
  (self.on_close)(handler)
}

///|
pub(all) struct WebSocketDialRequest {
  client_id : String
  protocol : String
  metadata : Json
}

///|
pub fn WebSocketDialRequest::new(
  client_id~ : String,
  protocol~ : String,
  metadata? : Json = Json::object({}),
) -> WebSocketDialRequest {
  WebSocketDialRequest::{ client_id, protocol, metadata }
}

///|
pub fn WebSocketDialRequest::client_id(self : WebSocketDialRequest) -> String {
  self.client_id
}

///|
pub fn WebSocketDialRequest::protocol(self : WebSocketDialRequest) -> String {
  self.protocol
}

///|
pub fn WebSocketDialRequest::metadata(self : WebSocketDialRequest) -> Json {
  self.metadata
}

///|
pub(all) struct WebSocketClientConnector {
  connect : async (WebSocketDialRequest) -> Result[
    WebSocketManagedConnection,
    String,
  ]
}

///|
pub fn WebSocketClientConnector::new(
  connect~ : async (WebSocketDialRequest) -> Result[
    WebSocketManagedConnection,
    String,
  ],
) -> WebSocketClientConnector {
  WebSocketClientConnector::{ connect, }
}

///|
pub async fn WebSocketClientConnector::connect(
  self : WebSocketClientConnector,
  request : WebSocketDialRequest,
) -> Result[WebSocketManagedConnection, String] {
  (self.connect)(request)
}

///|
pub(all) struct WebSocketManagedConnection {
  connection : WebSocketConnection
  wait_until_closed : async () -> Unit
}

///|
pub fn WebSocketManagedConnection::new(
  connection~ : WebSocketConnection,
  wait_until_closed? : async () -> Unit = async fn() {
    for ;; {
      @async.sleep(100)
    }
  },
) -> WebSocketManagedConnection {
  WebSocketManagedConnection::{ connection, wait_until_closed }
}

///|
pub fn WebSocketManagedConnection::connection(
  self : WebSocketManagedConnection,
) -> WebSocketConnection {
  self.connection
}

///|
pub async fn WebSocketManagedConnection::wait_until_closed(
  self : WebSocketManagedConnection,
) -> Unit {
  (self.wait_until_closed)()
}

///|
pub(all) struct WebSocketClientSpec {
  client_id : String
  label : String
  reconnect_delay_ms : Int
}

///|
pub fn WebSocketClientSpec::new(
  client_id~ : String,
  label? : String = "",
  reconnect_delay_ms? : Int = 2_000,
) -> WebSocketClientSpec {
  WebSocketClientSpec::{
    client_id,
    label: if label.is_blank() {
      client_id
    } else {
      label
    },
    reconnect_delay_ms,
  }
}

///|
pub fn WebSocketClientSpec::client_id(self : WebSocketClientSpec) -> String {
  self.client_id
}

///|
pub fn WebSocketClientSpec::label(self : WebSocketClientSpec) -> String {
  self.label
}

///|
pub fn WebSocketClientSpec::reconnect_delay_ms(
  self : WebSocketClientSpec,
) -> Int {
  self.reconnect_delay_ms
}

///|
pub(all) struct WebSocketClientRegistration {
  spec : WebSocketClientSpec
  connect : async () -> Result[WebSocketManagedConnection, String]
  on_connect : (WebSocketConnection) -> Unit
  logger : LoggerFuncs?
}

///|
pub fn WebSocketClientRegistration::new(
  spec~ : WebSocketClientSpec,
  connect~ : async () -> Result[WebSocketManagedConnection, String],
  on_connect~ : (WebSocketConnection) -> Unit,
  logger? : LoggerFuncs? = None,
) -> WebSocketClientRegistration {
  WebSocketClientRegistration::{ spec, connect, on_connect, logger }
}

///|
enum WebSocketClientRuntimeCommand {
  Upsert(WebSocketClientRegistration)
  Remove(String)
  StopAll
}

///|
priv struct WebSocketClientRuntimeControl {
  mut stopped : Bool
  mut connection : WebSocketConnection?
}

///|
pub(all) struct WebSocketClientRuntimeManager {
  commands : @aqueue.Queue[WebSocketClientRuntimeCommand]
}

///|
pub fn WebSocketClientRuntimeManager::new() -> WebSocketClientRuntimeManager {
  WebSocketClientRuntimeManager::{
    commands: @aqueue.Queue::new(kind=Unbounded),
  }
}

///|
pub(all) struct WebSocketClientRuntime {
  commands : @aqueue.Queue[WebSocketClientRuntimeCommand]
}

///|
pub fn WebSocketClientRuntimeManager::controller(
  self : WebSocketClientRuntimeManager,
) -> WebSocketClientRuntime {
  WebSocketClientRuntime::{ commands: self.commands }
}

///|
pub fn WebSocketClientRuntime::upsert(
  self : WebSocketClientRuntime,
  registration : WebSocketClientRegistration,
) -> Unit {
  ignore(self.commands.try_put(Upsert(registration))) catch {
    _ => ()
  }
}

///|
pub fn WebSocketClientRuntime::remove(
  self : WebSocketClientRuntime,
  client_id : String,
) -> Unit {
  ignore(self.commands.try_put(Remove(client_id))) catch {
    _ => ()
  }
}

///|
pub fn WebSocketClientRuntime::stop_all(self : WebSocketClientRuntime) -> Unit {
  ignore(self.commands.try_put(StopAll)) catch {
    _ => ()
  }
}

///|
fn stop_websocket_client(control : WebSocketClientRuntimeControl) -> Unit {
  control.stopped = true
  match control.connection {
    Some(connection) => {
      connection.close()
      control.connection = None
    }
    None => ()
  }
}

///|
async fn run_websocket_client(
  control : WebSocketClientRuntimeControl,
  registration : WebSocketClientRegistration,
) -> Unit {
  let spec = registration.spec
  let logger = registration.logger
  while !control.stopped {
    match (registration.connect)() {
      Ok(managed) => {
        let connection = managed.connection()
        control.connection = Some(connection)
        let closed = Ref::new(false)
        connection.on_close(fn() {
          closed.val = true
          control.connection = None
        })
        (registration.on_connect)(connection)
        managed.wait_until_closed() catch {
          _ => ()
        }
        if control.stopped {
          connection.close()
          control.connection = None
          break
        }
        if !closed.val {
          closed.val = true
          control.connection = None
        }
      }
      Err(error) =>
        match logger {
          Some(logger) =>
            (logger.warn)(
              "WebSocket client \{spec.label()} connect failed: \{error}",
            )
          None => ()
        }
    }
    if control.stopped {
      break
    }
    @async.sleep(spec.reconnect_delay_ms())
  }
}

///|
pub async fn WebSocketClientRuntimeManager::start(
  self : WebSocketClientRuntimeManager,
) -> Unit {
  let active : Map[String, WebSocketClientRuntimeControl] = {}
  @async.with_task_group(group => {
    while true {
      match self.commands.get() {
        Upsert(registration) => {
          let client_id = registration.spec.client_id()
          match active.get(client_id) {
            Some(control) => stop_websocket_client(control)
            None => ()
          }
          let control = WebSocketClientRuntimeControl::{
            stopped: false,
            connection: None,
          }
          active[client_id] = control
          group.spawn_bg(
            () => run_websocket_client(control, registration),
            no_wait=true,
            allow_failure=true,
          )
        }
        Remove(client_id) =>
          match active.get(client_id) {
            Some(control) => {
              stop_websocket_client(control)
              active.remove(client_id)
            }
            None => ()
          }
        StopAll => {
          for _, control in active {
            stop_websocket_client(control)
          }
          active.clear()
        }
      }
    }
  })
}

///|
/// Extension metadata for discovery and documentation
pub(all) struct ExtensionMeta {
  name : String
  version : String
  description : String
  author : String?
  webhook_path : String
  supported_events : Array[String]
}

///|
pub fn ExtensionMeta::new(
  name~ : String,
  version~ : String,
  description~ : String,
  author? : String,
  webhook_path~ : String,
  supported_events? : Array[String] = [],
) -> ExtensionMeta {
  ExtensionMeta::{
    name,
    version,
    description,
    author,
    webhook_path,
    supported_events,
  }
}

///|
/// Message handler trait for processing incoming messages from channels
/// This allows the gateway to process messages and send responses
pub(open) trait MessageHandler {
  /// Process an incoming message from a channel
  /// Returns the response message to send back
  async handle_message(
    Self,
    channel_id : String,
    account_id : String,
    message : Message,
  ) -> Message

  /// Handle a message that doesn't need a response (fire-and-forget)
  async handle_event(
    Self,
    channel_id : String,
    account_id : String,
    event : ChannelEvent,
  ) -> Unit
}
