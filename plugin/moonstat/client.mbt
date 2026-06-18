///|
/// Optional moonstat client plugin for moonclaw.
///
/// This package is NOT imported by moonclaw's core. It is an opt-in
/// plugin that moonclaw can use when a moonstat instance is available.
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
pub fn Client::base_url(self : Client) -> String {
  self.base_url
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
pub async fn Client::usage_summary(self : Client) -> Result[Json, String] {
  self.get("/usage/summary")
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
