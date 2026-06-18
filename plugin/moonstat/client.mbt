///|
/// Optional moonstat client plugin for moonclaw.
///
/// This package is used by gateway startup and remains a small optional bridge
/// for callers that want moonstat health, routing, and usage data.
pub const DEFAULT_PORT : Int = 15721

///|
pub const DEFAULT_HOST : String = "127.0.0.1"

///|
const DEFAULT_BASE_URL : String = "http://127.0.0.1:15721"

///|
pub struct Client {
  base_url : String
}

///|
pub struct MoonstatModel {
  id : String
  owner : String?
  context_window : Int?
}

///|
pub struct MoonstatUsageSummary {
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
  let home = @os.home() catch { _ => "." }
  let status_path = home + "/.moonsuite/suite-status.json"
  let content = @fsx.read_file(status_path) catch { _ => "" }
  if !content.is_empty() {
    let parsed = @json.parse(content) catch { _ => Json::null() }
    if moonstat_base_url_from_status(parsed) is Some(base_url) {
      return Client::{ base_url, }
    }
  }
  Client::{ base_url: DEFAULT_BASE_URL }
}

///|
pub async fn discover_from_suite_status() -> Client? {
  let home = @os.home() catch { _ => "." }
  let status_path = home + "/.moonsuite/suite-status.json"
  let content = @fsx.read_file(status_path) catch { _ => "" }
  if content.is_empty() {
    return None
  }
  let parsed = @json.parse(content) catch { _ => Json::null() }
  moonstat_base_url_from_status(parsed).map(fn(base_url) {
    Client::{ base_url, }
  })
}

///|
pub fn Client::base_url(self : Client) -> String {
  self.base_url
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
pub async fn Client::models(self : Client) -> Result[Json, String] {
  self.get("/v1/models")
}

///|
pub async fn Client::model_catalog(
  self : Client,
) -> Result[Array[MoonstatModel], String] {
  match self.models() {
    Ok(json) => moonstat_models_from_json(json)
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
) -> Result[MoonstatUsageSummary, String] {
  match self.usage_summary() {
    Ok(json) => MoonstatUsageSummary::from_json(json)
    Err(err) => Err(err)
  }
}

///|
pub async fn Client::usage_trends(self : Client) -> Result[Json, String] {
  self.get("/usage/trends")
}

///|
pub async fn Client::provider_presets(self : Client) -> Result[Json, String] {
  self.get("/get_provider_presets")
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
  let client = @http.Client::new(url, headers={}) catch {
    err => return Err("client error: \{err}")
  }
  defer client.close()
  let response = client.get("") catch {
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
  let client = @http.Client::new(url, headers={
    "Content-Type": "application/json",
  }) catch {
    err => return Err("client error: \{err}")
  }
  defer client.close()
  let response = client.post("", body.stringify()) catch {
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
pub async fn Client::route_openclaw_chat(
  self : Client,
  body : Json,
) -> Result[Json, String] {
  self.post("/openclaw/v1/chat/completions", body)
}

///|
pub fn moonstat_models_from_json(
  json : Json,
) -> Result[Array[MoonstatModel], String] {
  let rows = match json {
    Object(obj) =>
      match obj.get("models") {
        Some(Array(models)) => models
        Some(Object(models)) => models.values().to_array()
        Some(_) => return Err("moonstat models field is not an array or object")
        None =>
          match obj.get("data") {
            Some(Array(models)) => models
            Some(_) => return Err("moonstat data field is not an array")
            None => return Err("moonstat models response has no models")
          }
      }
    Array(models) => models
    _ => return Err("moonstat models response is not an object or array")
  }
  let parsed : Array[MoonstatModel] = []
  for row in rows {
    match MoonstatModel::from_json(row) {
      Ok(model) => parsed.push(model)
      Err(err) => return Err(err)
    }
  }
  Ok(parsed)
}

///|
pub fn MoonstatModel::from_json(json : Json) -> Result[MoonstatModel, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moonstat model entry is not an object")
  }
  let id = match moonstat_json_string_field(obj, "id") {
    Some(value) => value
    None =>
      match moonstat_json_string_field(obj, "slug") {
        Some(value) => value
        None =>
          match moonstat_json_string_field(obj, "name") {
            Some(value) => value
            None => return Err("moonstat model entry has no id")
          }
      }
  }
  Ok({
    id,
    owner: moonstat_json_string_field(obj, "owned_by"),
    context_window: moonstat_json_int_field(obj, "context_window"),
  })
}

///|
pub fn MoonstatUsageSummary::from_json(
  json : Json,
) -> Result[MoonstatUsageSummary, String] {
  let obj = match json {
    Object(obj) => obj
    _ => return Err("moonstat usage summary is not an object")
  }
  Ok({
    total_requests: moonstat_json_int_field(obj, "totalRequests").unwrap_or(0),
    total_cost: moonstat_json_string_field(obj, "totalCost").unwrap_or("0"),
    total_input_tokens: moonstat_json_int64_field(obj, "totalInputTokens").unwrap_or(
      0L,
    ),
    total_output_tokens: moonstat_json_int64_field(obj, "totalOutputTokens").unwrap_or(
      0L,
    ),
    total_cache_creation_tokens: moonstat_json_int64_field(
      obj, "totalCacheCreationTokens",
    ).unwrap_or(0L),
    total_cache_read_tokens: moonstat_json_int64_field(
      obj, "totalCacheReadTokens",
    ).unwrap_or(0L),
    real_total_tokens: moonstat_json_int64_field(obj, "realTotalTokens").unwrap_or(
      0L,
    ),
    success_rate: moonstat_json_double_field(obj, "successRate").unwrap_or(0.0),
    cache_hit_rate: moonstat_json_double_field(obj, "cacheHitRate").unwrap_or(
      0.0,
    ),
  })
}

///|
fn moonstat_json_string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) if !value.trim().is_empty() => Some(value)
    _ => None
  }
}

///|
fn moonstat_json_double_field(obj : Map[String, Json], key : String) -> Double? {
  match obj.get(key) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn moonstat_json_int_field(obj : Map[String, Json], key : String) -> Int? {
  match moonstat_json_double_field(obj, key) {
    Some(value) => Some(value.trunc().to_int())
    None => None
  }
}

///|
fn moonstat_json_int64_field(obj : Map[String, Json], key : String) -> Int64? {
  match moonstat_json_double_field(obj, key) {
    Some(value) => Some(value.trunc().to_int64())
    None => None
  }
}

///|
fn moonstat_base_url_from_status(status : Json) -> String? {
  match status {
    Object(obj) => {
      match obj.get("manifest") {
        Some(Object(manifest)) =>
          match manifest.get("base_url") {
            Some(String(url)) if !url.is_empty() => return Some(url)
            _ => ()
          }
        _ => ()
      }
      match obj.get("base_url") {
        Some(String(url)) if !url.is_empty() => Some(url)
        _ =>
          match obj.get("health_url") {
            Some(String(url)) => moonstat_strip_suffix(url, "/health")
            _ => None
          }
      }
    }
    _ => None
  }
}

///|
fn moonstat_strip_suffix(value : String, suffix : String) -> String? {
  if value.has_suffix(suffix) {
    Some(value[:value.length() - suffix.length()].to_owned())
  } else {
    None
  }
}
