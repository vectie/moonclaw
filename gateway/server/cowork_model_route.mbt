///|
// This projection belongs to Cowork, not to the separate native daemon.
// `cwd` is the same explicit workspace used by Cowork session execution.
struct CoworkModelRouteParams {
  cwd : String
} derive(FromJson)

///|
fn cowork_native_route_json(
  cwd : String,
  configured_default : String?,
  model_ids : Array[String],
  error : String,
) -> Json {
  let names : Array[String] = []
  if error.is_empty() {
    for id in model_ids {
      if !id.is_blank() &&
        id == id.trim().to_owned() &&
        !names.contains("moongate/" + id) {
        names.push("moongate/" + id)
      }
    }
  }
  let default_model = configured_default
    .map(id => "moongate/" + id)
    .unwrap_or("")
  let catalog_ready = error.is_empty() && !names.is_empty()
  let ready = catalog_ready && names.contains(default_model)
  let blocker = if !error.is_empty() {
    error
  } else if !catalog_ready {
    "MoonGate live model catalog is empty for this Cowork workspace."
  } else if configured_default is None || configured_default == Some("") {
    "MoonGate default model is not configured for this Cowork workspace."
  } else if !ready {
    "MoonGate configured default is absent from this Cowork workspace's live catalog."
  } else {
    ""
  }
  {
    "contract_id": "moonclaw.cowork-model-route.v1",
    "cwd": cwd,
    "catalog_ready": catalog_ready,
    "default_ready": ready,
    "default_model": if ready {
      default_model
    } else {
      ""
    },
    "models": names,
    "blocker": blocker,
  }
}

///|
// Preserve the existing manual Cowork protocol exactly. MoonFind prevents an
// automatic empty assignment at its own transport boundary.
fn cowork_config_model_override(
  current : String?,
  requested : String?,
) -> String? {
  match requested {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => current
  }
}

///|
async fn cowork_native_route(
  cwd : String,
  configured~ : async (String) -> String?,
  catalog~ : async (String) -> Result[Array[String], String],
) -> Json {
  guard !cwd.is_blank() && cwd == cwd.trim().to_owned() else {
    return cowork_native_route_json(
      cwd,
      None,
      [],
      "An exact Cowork workspace is required.",
    )
  }
  let configured_default = configured(cwd)
  match catalog(cwd) {
    Ok(ids) => cowork_native_route_json(cwd, configured_default, ids, "")
    Err(error) => cowork_native_route_json(cwd, configured_default, [], error)
  }
}

///|
async fn Gateway::handle_cowork_model_route(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : CoworkModelRouteParams = decode_request_body(
    r, "Cowork model route",
  )
  let route = cowork_native_route(
    params.cwd,
    configured=cwd => {
      @moongate.configured_models_from_suite_status_for_workspace_root(cwd)
      .get(0)
      .map(model => model.id())
    },
    catalog=cwd => {
      match @moongate.discover_from_suite_status_for_workspace_root(cwd) {
        None =>
          Err("MoonGate suite status is unavailable for this Cowork workspace.")
        Some(client) =>
          match client.model_catalog() {
            Ok(models) => Ok(models.map(model => model.id()))
            Err(_) =>
              Err(
                "MoonGate live model catalog is unavailable for this Cowork workspace.",
              )
          }
      }
    },
  )
  self.write_json(w, route)
}
