///|
/// Provider-task runtime artifact paths and workspace artifact harvesting.
///
/// Keep filesystem naming and result sanitization here so provider execution
/// code does not reintroduce long prompt-derived filenames or unsafe paths.
fn provider_task_runtime_artifact_root(
  request : AnalysisRequest,
  workspace_root : String,
) -> String {
  let provider_root = workspace_root.trim().to_owned()
  if !provider_root.is_blank() {
    provider_root
  } else {
    request.cwd
  }
}

///|
fn provider_task_runtime_artifact_dir(
  request : AnalysisRequest,
  workspace_root : String,
) -> String {
  @pathx.join(
    provider_task_runtime_artifact_root(request, workspace_root),
    ".moonclaw/provider-task",
  )
}

///|
async fn provider_task_runtime_artifact_path(
  request : AnalysisRequest,
  workspace_root : String,
  artifact_kind : String,
) -> Result[String, String] {
  let step_key = safe_step_file_segment(request.step_id)
  let artifact_dir = provider_task_runtime_artifact_dir(request, workspace_root)
  @fsx.make_directory(artifact_dir, recursive=true, exists_ok=true) catch {
    error =>
      return Err(
        "Failed to prepare provider task artifact directory \{artifact_dir}: \{error}",
      )
  }
  Ok(
    @pathx.join(
      artifact_dir,
      ".moonclaw-provider-\{artifact_kind}-\{request.run_id}-\{step_key}.json",
    ),
  )
}

///|
async fn provider_task_failure_debug_path(
  request : AnalysisRequest,
  workspace_root : String,
) -> Result[String, String] {
  provider_task_runtime_artifact_path(request, workspace_root, "failure")
}

///|
fn is_provider_result_artifact_path(path : String) -> Bool {
  let normalized = path.trim().to_owned()
  !normalized.is_blank() &&
  !normalized.has_prefix("/") &&
  !normalized.contains("://") &&
  !normalized.has_suffix("/") &&
  @pathx.basename(normalized).contains(".")
}

///|
fn is_provider_result_workspace_artifact(path : String) -> Bool {
  let normalized = path.trim().to_owned()
  normalized.has_prefix("wiki/") ||
  normalized.has_prefix("raw/") ||
  normalized.has_prefix("keeper/")
}

///|
async fn provider_task_existing_workspace_artifacts(
  workspace_root : String,
  artifacts : Array[String],
) -> Array[String] {
  let sanitized : Array[String] = []
  for artifact in artifacts {
    let normalized = artifact.trim().to_owned()
    if !is_provider_result_artifact_path(normalized) ||
      !is_provider_result_workspace_artifact(normalized) {
      continue
    }
    let absolute = @pathx.join(workspace_root, normalized)
    if !(@fsx.exists(absolute) catch { _ => false }) {
      continue
    }
    if !sanitized.contains(normalized) {
      sanitized.push(normalized)
    }
  }
  sanitized
}

///|
async fn align_provider_task_result(
  workspace_root : String,
  task : ProviderTaskSpec,
  result : ProviderTaskResult,
) -> ProviderTaskResult {
  ProviderTaskResult::{
    ..result,
    task_id: provider_task_result_task_id(task),
    artifacts: provider_task_existing_workspace_artifacts(
      workspace_root,
      result.artifacts,
    ),
  }
}

///|
fn provider_task_artifact_paths_from_line(line : String) -> Array[String] {
  let paths : Array[String] = []
  let normalized = line
    .replace_all(old="`", new=" ")
    .replace_all(old=",", new=" ")
    .replace_all(old=":", new=" ")
    .replace_all(old=";", new=" ")
    .replace_all(old="(", new=" ")
    .replace_all(old=")", new=" ")
    .replace_all(old="[", new=" ")
    .replace_all(old="]", new=" ")
    .replace_all(old="{", new=" ")
    .replace_all(old="}", new=" ")
  for token in normalized.split(" ") {
    let candidate = token.trim().trim(chars=".'\"").to_owned()
    if candidate.is_blank() {
      continue
    }
    if is_provider_result_artifact_path(candidate) && !paths.contains(candidate) {
      paths.push(candidate)
    }
  }
  paths
}

///|
fn provider_task_collect_artifacts_from_json(
  value : Json,
  artifacts : Array[String],
) -> Unit {
  match value {
    String(text) =>
      for raw_line in text.split("\n") {
        for path in provider_task_artifact_paths_from_line(raw_line.to_owned()) {
          if !artifacts.contains(path) {
            artifacts.push(path)
          }
        }
      }
    Array(items) =>
      for item in items {
        provider_task_collect_artifacts_from_json(item, artifacts)
      }
    Object(obj) =>
      for _, item in obj {
        provider_task_collect_artifacts_from_json(item, artifacts)
      }
    _ => ()
  }
}

///|
async fn provider_task_target_artifacts(
  workspace_root : String,
  task : ProviderTaskSpec,
) -> Array[String] {
  let artifacts : Array[String] = []
  for path in task.target_pages {
    let normalized = path.trim().to_owned()
    if normalized.is_blank() {
      continue
    }
    if normalized.has_suffix("/") {
      let absolute_dir = @pathx.join(workspace_root, normalized)
      let entries = @fsx.list_directory(absolute_dir) catch { _ => continue }
      for entry in entries {
        guard entry.kind is Regular else { continue }
        let relative = "\{normalized}\{entry.name}"
        if is_provider_result_artifact_path(relative) &&
          !artifacts.contains(relative) {
          artifacts.push(relative)
        }
      }
      continue
    }
    let absolute = @pathx.join(workspace_root, normalized)
    if (@fsx.exists(absolute) catch { _ => false }) &&
      is_provider_result_artifact_path(normalized) &&
      !artifacts.contains(normalized) {
      artifacts.push(normalized)
    }
  }
  artifacts
}
