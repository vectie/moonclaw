///|
const MOONCLAW_MOONGATE_ROUTE_CONTRACT : String = "moonclaw.moongate-route.v1"

///|
fn moonclaw_moongate_route_status_json(
  base_url : String,
  model_ids : Array[String],
  error : String,
  catalog? : Array[@moongate.MoonGateModel] = [],
) -> Json {
  let models : Array[Json] = []
  let names : Array[String] = []
  for model_id in model_ids {
    let id = model_id.trim().to_owned()
    let name = "moongate/" + id
    if id != "" && !names.contains(name) {
      names.push(name)
      let mut input_modalities : Array[String] = []
      for entry in catalog {
        if entry.id() == id {
          input_modalities = entry.input_modalities()
          break
        }
      }
      models.push({
        "name": name,
        "default": models.is_empty(),
        "input_modalities": Json::array(
          input_modalities.map(value => value.to_json()),
        ),
      })
    }
  }
  let ready = error == "" && !models.is_empty()
  {
    "contract": MOONCLAW_MOONGATE_ROUTE_CONTRACT,
    "ready": ready,
    "status": if ready {
      "ready"
    } else {
      "unavailable"
    },
    "required_for_moondesk": true,
    "traffic_path": ["moondesk", "moonclaw", "moongate"],
    "model_prefix": "moongate/",
    "base_url": base_url,
    "default_model": if names.is_empty() {
      ""
    } else {
      names[0]
    },
    "models": Json::array(models),
    "error": error,
  }
}

///|
async fn Daemon::moongate_route(
  self : Daemon,
  w : @httpx.ResponseWriter,
) -> Unit {
  let client = match
    @moongate.discover_from_suite_status_for_workspace_root(self.home) {
    Some(value) => value
    None => {
      w.header().set("Content-Type", "application/json")
      w.write_header(if hosted_model_alias() is Some(_) { 503 } else { 200 })
      w.write(
        moonclaw_moongate_route_status_json(
          "",
          [],
          "MoonGate suite status is unavailable",
        ).stringify(),
      )
      return
    }
  }
  let status = match client.model_catalog() {
    Ok(catalog) =>
      moonclaw_moongate_route_status_json(
        client.base_url(),
        catalog.map(model => model.id()),
        "",
        catalog~,
      )
    Err(error) =>
      moonclaw_moongate_route_status_json(client.base_url(), [], error)
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(
    if hosted_model_alias() is Some(_) && status is { "ready": False, .. } {
      503
    } else {
      200
    },
  )
  w.write(status.stringify())
}

///|
/// Kubernetes probes this loopback-only route without the private MoonDesk
/// control credential. It reports ready only after the configured hosted model
/// appears in this workspace's own MoonGate catalog.
async fn Daemon::hosted_ready(self : Daemon, w : @httpx.ResponseWriter) -> Unit {
  let expected = hosted_model_alias()
  let client = @moongate.discover_from_suite_status_for_workspace_root(
    self.home,
  )
  let ready = match (expected, client) {
    (Some(model), Some(client)) =>
      match client.model_catalog() {
        Ok(models) => models.any(entry => entry.id() == model)
        Err(_) => false
      }
    _ => false
  }
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.write_header(if ready { 200 } else { 503 })
  w.write({ "ready": ready }.to_json().stringify())
}
