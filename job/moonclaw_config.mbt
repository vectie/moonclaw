///|
fn moonclaw_config_path_candidates(
  cwd : String,
  home : String?,
) -> Array[String] {
  let paths : Array[String] = [
    @moonsuite.product_artifact_for_workspace_root(
      cwd, "moonclaw", "moonclaw.json",
    ),
  ]
  match home {
    Some(home) =>
      paths.push(
        @moonsuite.product_artifact_for_workspace_root(
          home, "moonclaw", "moonclaw.json",
        ),
      )
    None => ()
  }
  paths
}

///|
fn configured_primary_model_from_json(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("model") {
                Some(Object(model)) =>
                  match model.get("primary") {
                    Some(String(primary)) if !primary.trim().is_empty() =>
                      Some(primary.trim().to_owned())
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
async fn configured_primary_model(cwd : String, home : String?) -> String? {
  for path in moonclaw_config_path_candidates(cwd, home) {
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    if configured_primary_model_from_json(Some(json)) is Some(primary) {
      return Some(primary)
    }
  }
  None
}

///|
fn configured_adaptive_subplan_max_depth_from_json(json : Json?) -> Int? {
  match json {
    Some(Object(root)) =>
      match root.get("jobs") {
        Some(Object(jobs)) =>
          match jobs.get("analysis") {
            Some(Object(analysis)) =>
              match analysis.get("adaptive") {
                Some(Object(adaptive)) =>
                  match adaptive.get("max_depth") {
                    Some(Number(value, ..)) => Some(value.to_int())
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
async fn configured_adaptive_subplan_max_depth(
  cwd : String,
  home : String?,
) -> Int? {
  for path in moonclaw_config_path_candidates(cwd, home) {
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    if configured_adaptive_subplan_max_depth_from_json(Some(json))
      is Some(max_depth) {
      return Some(max_depth)
    }
  }
  None
}
