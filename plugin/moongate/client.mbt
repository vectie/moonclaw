///|
/// Optional moongate client plugin for moonclaw.
///
/// This package is used by gateway startup and remains a small optional bridge
/// for callers that want moongate health, routing, and usage data.
pub const DEFAULT_PORT : Int = 15721

///|
pub const DEFAULT_HOST : String = "127.0.0.1"

///|
const DEFAULT_BASE_URL : String = "http://127.0.0.1:15721"

///|
const SUITE_STATUS_CONTRACT : String = "moon.suite.status.v2"

///|
const SUITE_MANIFEST_CONTRACT : String = "moon.suite.service.v1"

///|
const SUITE_SERVICE_NAME : String = "moongate"

///|
const SUITE_STATUS_FILE : String = "suite-status.json"

///|
const MOONGATE_CONTROL_TOKEN_HEADER : String = "x-moongate-control-token"

///|
fn moongate_request_headers(
  content_type? : Bool = false,
) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  if content_type {
    headers["Content-Type"] = "application/json"
  }
  let configured = @os.getenv("MOONGATE_CONTROL_TOKEN") catch { _ => None }
  match configured {
    Some(token) if !token.trim().is_empty() =>
      headers[MOONGATE_CONTROL_TOKEN_HEADER] = token.trim().to_owned()
    _ => ()
  }
  headers
}

///|
pub struct Client {
  base_url : String
}

///|
pub struct MoonGateModel {
  id : String
  owner : String?
  context_window : Int?
}

///|
pub fn MoonGateModel::id(self : MoonGateModel) -> String {
  self.id
}

///|
pub fn MoonGateModel::owner(self : MoonGateModel) -> String? {
  self.owner
}

///|
pub fn MoonGateModel::context_window(self : MoonGateModel) -> Int? {
  self.context_window
}

///|
pub struct MoonGateUsageSummary {
  total_requests : Int
  total_cost : String
  total_input_tokens : Int64
  total_output_tokens : Int64
  total_cache_creation_tokens : Int64
  total_cache_read_tokens : Int64
  real_total_tokens : Int64
  success_rate : Double
  cache_hit_rate : Double
}

///|
pub async fn discover() -> Client {
  let status_path = moongate_suite_status_path_for_workspace_root(
    moongate_active_workspace_root(),
  )
  let content = @fsx.read_file(status_path) catch { _ => "" }
  if !content.is_empty() {
    let parsed = @json.parse(content) catch { _ => Json::null() }
    if moongate_base_url_from_status(parsed) is Some(base_url) {
      return { base_url, }
    }
  }
  { base_url: DEFAULT_BASE_URL }
}

///|
pub async fn discover_from_suite_status() -> Client? {
  discover_from_suite_status_for_workspace_root(
    moongate_active_workspace_root(),
  )
}

///|
pub async fn discover_from_suite_status_for_workspace_root(
  workspace_root : String,
) -> Client? {
  let status_path = moongate_suite_status_path_for_workspace_root(
    workspace_root,
  )
  let content = @fsx.read_file(status_path) catch { _ => "" }
  if content.is_empty() {
    return None
  }
  let parsed = @json.parse(content) catch { _ => Json::null() }
  moongate_base_url_from_status(parsed).map(fn(base_url) { { base_url, } })
}

///|
pub async fn configured_models_from_suite_status_for_workspace_root(
  workspace_root : String,
) -> Array[MoonGateModel] {
  let status_path = moongate_suite_status_path_for_workspace_root(
    workspace_root,
  )
  let content = @fsx.read_file(status_path) catch { _ => return [] }
  let parsed = @json.parse(content) catch { _ => return [] }
  moongate_default_models_from_status(parsed)
}

///|
fn moongate_default_models_from_status(status : Json) -> Array[MoonGateModel] {
  guard status is Object(obj) && moongate_status_contract_valid(obj) else {
    return []
  }
  guard obj.get("manifest") is Some(Object(manifest)) &&
    moongate_manifest_contract_valid(manifest) else {
    return []
  }
  guard moongate_json_string_field(manifest, "defaultModel") is Some(id) &&
    id != "" else {
    return []
  }
  [{ id, owner: None, context_window: Some(128_000) }]
}

///|
pub fn Client::base_url(self : Client) -> String {
  self.base_url
}

///|
fn moongate_active_workspace_root() -> String {
  @os.cwd() catch {
    _ => "."
  }
}

///|
fn moongate_suite_status_path_for_workspace_root(root : String) -> String {
  @pathx.join(
    @moonsuite.state_dir(@moonsuite.suite_root_for_workspace_root(root)),
    SUITE_STATUS_FILE,
  )
}

///|
pub fn Client::route_openclaw_chat_url(self : Client) -> String {
  self.base_url + "/openclaw/v1/chat/completions"
}

///|
pub async fn Client::health(self : Client) -> Result[Json, String] {
  self.get("/health")
}

///|
pub async fn Client::status(self : Client) -> Result[Json, String] {
  self.get("/status")
}

///|
pub async fn Client::stats(self : Client) -> Result[Json, String] {
  self.get("/stats")
}

///|
fn Client::models_path(_self : Client) -> String {
  "/openclaw/v1/models"
}

///|
pub async fn Client::models(self : Client) -> Result[Json, String] {
  self.get(self.models_path())
}

///|
pub async fn Client::model_catalog(
  self : Client,
) -> Result[Array[MoonGateModel], String] {
  match self.models() {
    Ok(json) => moongate_models_from_json(json)
    Err(err) => Err(err)
  }
}

///|
pub async fn Client::usage_summary(self : Client) -> Result[Json, String] {
  self.get("/usage/summary")
}

///|
pub async fn Client::usage_summary_typed(
  self : Client,
) -> Result[MoonGateUsageSummary, String] {
  match self.usage_summary() {
    Ok(json) => MoonGateUsageSummary::from_json(json)
    Err(err) => Err(err)
  }
}

///|
pub async fn Client::usage_trends(self : Client) -> Result[Json, String] {
  self.get("/usage/trends")
}

///|
pub async fn Client::provider_presets(self : Client) -> Result[Json, String] {
  self.get("/providers/presets")
}

///|
pub async fn Client::metrics(self : Client) -> Result[String, String] {
  self.get_text("/metrics")
}

///|
pub async fn Client::get(self : Client, path : String) -> Result[Json, String] {
  let body = match self.get_text(path) {
    Ok(body) => body
    Err(err) => return Err(err)
  }
  let parsed = @json.parse(body) catch { _ => return Err("parse error") }
  Ok(parsed)
}

///|
pub async fn Client::get_text(
  self : Client,
  path : String,
) -> Result[String, String] {
  let url = self.base_url + path
  let (origin, request_path) = match moongate_http_parts(url) {
    Ok(parts) => parts
    Err(error) => return Err(error)
  }
  let client = @http.Client::new(origin, headers=moongate_request_headers()) catch {
    err => return Err("client error: \{err}")
  }
  defer client.close()
  let response = client.get(request_path) catch {
    err => return Err("request error: \{err}")
  }
  if response.code == 200 {
    let body = client.read_all().text() catch {
        err => return Err("read error: \{err}")
      }
    Ok(body)
  } else {
    Err("HTTP \{response.code}")
  }
}

///|
pub async fn Client::post(
  self : Client,
  path : String,
  body : Json,
) -> Result[Json, String] {
  let url = self.base_url + path
  let (origin, request_path) = match moongate_http_parts(url) {
    Ok(parts) => parts
    Err(error) => return Err(error)
  }
  let client = @http.Client::new(
    origin,
    headers=moongate_request_headers(content_type=true),
  ) catch {
    err => return Err("client error: \{err}")
  }
  defer client.close()
  let response = client.post(request_path, body.stringify()) catch {
    err => return Err("request error: \{err}")
  }
  if response.code == 200 {
    let body = client.read_all().text() catch {
        err => return Err("read error: \{err}")
      }
    let parsed = @json.parse(body) catch { _ => return Err("parse error") }
    Ok(parsed)
  } else {
    Err("HTTP \{response.code}")
  }
}

///|
fn moongate_http_parts(url : String) -> Result[(String, String), String] {
  guard url.find("://") is Some(protocol_end) else {
    return Err("invalid URL: missing scheme")
  }
  let after_scheme = protocol_end + 3
  let rest = url[after_scheme:]
  let (authority, path) = match rest.find("/") {
    Some(path_start) =>
      (rest[:path_start].to_owned(), rest[path_start:].to_owned())
    None => (rest.to_owned(), "/")
  }
  if authority == "" {
    return Err("invalid URL: missing authority")
  }
  Ok((url[:after_scheme].to_owned() + authority, path))
}

///|
pub async fn Client::route_openclaw_chat(
  self : Client,
  body : Json,
) -> Result[Json, String] {
  self.post("/openclaw/v1/chat/completions", body)
}

///|
pub fn moongate_models_from_json(
  json : Json,
) -> Result[Array[MoonGateModel], String] {
  let rows = match json {
    Object(obj) =>
      match obj.get("models") {
        Some(Array(models)) => models
        Some(Object(models)) => models.values().to_array()
        Some(_) => return Err("moongate models field is not an array or object")
        None =>
          match obj.get("data") {
            Some(Array(models)) => models
            Some(_) => return Err("moongate data field is not an array")
            None => return Err("moongate models response has no models")
          }
      }
    Array(models) => models
    _ => return Err("moongate models response is not an object or array")
  }
  let parsed : Array[MoonGateModel] = []
  for row in rows {
    match MoonGateModel::from_json(row) {
      Ok(model) => parsed.push(model)
      Err(err) => return Err(err)
    }
  }
  Ok(parsed)
}

///|
pub fn MoonGateModel::from_json(json : Json) -> Result[MoonGateModel, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moongate model entry is not an object")
  }
  let id = match moongate_json_string_field(obj, "id") {
    Some(value) => value
    None =>
      match moongate_json_string_field(obj, "slug") {
        Some(value) => value
        None =>
          match moongate_json_string_field(obj, "name") {
            Some(value) => value
            None => return Err("moongate model entry has no id")
          }
      }
  }
  Ok({
    id,
    owner: moongate_json_string_field(obj, "owned_by"),
    context_window: moongate_json_int_field(obj, "context_window"),
  })
}

///|
pub fn MoonGateUsageSummary::from_json(
  json : Json,
) -> Result[MoonGateUsageSummary, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moongate usage summary is not an object")
  }
  Ok({
    total_requests: moongate_json_int_field(obj, "totalRequests").unwrap_or(0),
    total_cost: moongate_json_string_field(obj, "totalCost").unwrap_or("0"),
    total_input_tokens: moongate_json_int64_field(obj, "totalInputTokens").unwrap_or(
      0L,
    ),
    total_output_tokens: moongate_json_int64_field(obj, "totalOutputTokens").unwrap_or(
      0L,
    ),
    total_cache_creation_tokens: moongate_json_int64_field(
      obj, "totalCacheCreationTokens",
    ).unwrap_or(0L),
    total_cache_read_tokens: moongate_json_int64_field(
      obj, "totalCacheReadTokens",
    ).unwrap_or(0L),
    real_total_tokens: moongate_json_int64_field(obj, "realTotalTokens").unwrap_or(
      0L,
    ),
    success_rate: moongate_json_double_field(obj, "successRate").unwrap_or(0.0),
    cache_hit_rate: moongate_json_double_field(obj, "cacheHitRate").unwrap_or(
      0.0,
    ),
  })
}

///|
fn moongate_json_string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) if !value.trim().is_empty() => Some(value)
    _ => None
  }
}

///|
fn moongate_json_double_field(obj : Map[String, Json], key : String) -> Double? {
  match obj.get(key) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn moongate_json_int_field(obj : Map[String, Json], key : String) -> Int? {
  match moongate_json_double_field(obj, key) {
    Some(value) => Some(value.trunc().to_int())
    None => None
  }
}

///|
fn moongate_json_int64_field(obj : Map[String, Json], key : String) -> Int64? {
  match moongate_json_double_field(obj, key) {
    Some(value) => Some(value.trunc().to_int64())
    None => None
  }
}

///|
fn moongate_base_url_from_status(status : Json) -> String? {
  match status {
    Object(obj) if moongate_status_contract_valid(obj) =>
      match obj.get("manifest") {
        Some(Object(manifest)) if moongate_manifest_contract_valid(manifest) =>
          match manifest.get("baseUrl") {
            Some(String(url)) if !url.trim().is_empty() => Some(url)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn moongate_status_contract_valid(obj : Map[String, Json]) -> Bool {
  moongate_json_string_field(obj, "contract") == Some(SUITE_STATUS_CONTRACT) &&
  moongate_json_string_field(obj, "service") == Some(SUITE_SERVICE_NAME)
}

///|
fn moongate_manifest_contract_valid(obj : Map[String, Json]) -> Bool {
  moongate_json_string_field(obj, "contract") == Some(SUITE_MANIFEST_CONTRACT) &&
  moongate_json_string_field(obj, "service") == Some(SUITE_SERVICE_NAME)
}
