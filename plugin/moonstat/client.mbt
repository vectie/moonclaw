///|
/// Optional moonstat client plugin for moonclaw.
///
/// This package is NOT imported by moonclaw's core. It is an opt-in
/// plugin that moonclaw can use when a moonstat instance is available.

pub const DEFAULT_PORT : Int = 15721
pub const DEFAULT_HOST : String = "127.0.0.1"

pub struct Client {
  base_url : String
}

pub async fn discover() -> Client {
  let home = try @os.home() catch { _ => "." }
  let status_path = home + "/.moonsuite/suite-status.json"
  let content = try @fsx.read_file(status_path) catch { _ => "" }
  if !content.is_empty() {
    let parsed = try @json.parse(content) catch { _ => Json::null() }
    match parsed {
      Object(obj) => {
        let base = match obj.get("base_url") {
          Some(String(url)) => url
          _ => "http://\{DEFAULT_HOST}:\{DEFAULT_PORT}"
        }
        return Client::{ base_url: base }
      }
      _ => ()
    }
  }
  Client::{ base_url: "http://\{DEFAULT_HOST}:\{DEFAULT_PORT}" }
}

pub async fn Client::health(self : Client) -> Result[Json, String] {
  self.get("/health")
}

pub async fn Client::status(self : Client) -> Result[Json, String] {
  self.get("/status")
}

pub async fn Client::get(self : Client, path : String) -> Result[Json, String] {
  let url = self.base_url + path
  let client = try @http.Client::new(url, headers={}) catch {
    err => return Err("client error: \{err}")
  }
  defer client.close()
  let response = try client.get("") catch {
    err => return Err("request error: \{err}")
  }
  if response.code == 200 {
    let body = try client.read_all().text() catch {
      err => return Err("read error: \{err}")
    }
    let parsed = try @json.parse(body) catch {
      _ => return Err("parse error")
    }
    Ok(parsed)
  } else {
    Err("HTTP \{response.code}")
  }
}

pub async fn Client::post(
  self : Client,
  path : String,
  body : Json,
) -> Result[Json, String] {
  let url = self.base_url + path
  let client = try @http.Client::new(url, headers={
    "Content-Type": "application/json",
  }) catch {
    err => return Err("client error: \{err}")
  }
  defer client.close()
  let response = try client.post("", body.stringify()) catch {
    err => return Err("request error: \{err}")
  }
  if response.code == 200 {
    let body = try client.read_all().text() catch {
      err => return Err("read error: \{err}")
    }
    let parsed = try @json.parse(body) catch {
      _ => return Err("parse error")
    }
    Ok(parsed)
  } else {
    Err("HTTP \{response.code}")
  }
}
