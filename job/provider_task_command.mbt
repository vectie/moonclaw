///|
/// Provider-backed task target resolution and provider CLI loading.
///
/// This file deliberately contains only transport mechanics. Execution quality,
/// research semantics, and artifact ownership are handled elsewhere.
fn provider_execution_requested(mode : String?) -> Bool {
  match mode {
    Some(mode) => {
      let normalized = mode.trim().to_lower()
      normalized == "provider" ||
      normalized == "extension" ||
      normalized == "provider.task" ||
      normalized == "extension.task"
    }
    None => false
  }
}

///|
fn provider_metadata_string(metadata : Json, key : String) -> String? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) if !value.trim().to_owned().is_blank() =>
          Some(value.trim().to_owned())
        _ => None
      }
    _ => None
  }
}

///|
fn provider_metadata_string_array(
  metadata : Json,
  key : String,
) -> Array[String] {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(values)) => {
          let items : Array[String] = []
          for value in values {
            guard value is String(text) else { continue }
            let trimmed = text.trim().to_owned()
            if !trimmed.is_blank() {
              items.push(trimmed)
            }
          }
          items
        }
        _ => []
      }
    _ => []
  }
}

///|
fn provider_supports_extension_execution(
  provider : @resource_providers.RegisteredResourceProvider,
) -> Bool {
  provider.kind == "extension" ||
  provider.kind == "task-provider" ||
  provider.capabilities.contains("provider") ||
  provider.capabilities.contains("extension") ||
  provider.capabilities.contains("provider.task") ||
  provider.capabilities.contains("extension.task")
}

///|
fn provider_workspace_root(
  provider : @resource_providers.RegisteredResourceProvider,
) -> String? {
  provider_metadata_string(provider.metadata, "workspace_root").map(fn(root) {
    @pathx.normalize(root)
  })
}

///|
fn path_is_within(root : String, path : String) -> Bool {
  let normalized_root = @pathx.normalize(root)
  let normalized_path = @pathx.normalize(path)
  normalized_path == normalized_root ||
  normalized_path.has_prefix("\{normalized_root}/")
}

///|
fn select_provider_by_workspace_affinity(
  providers : Array[@resource_providers.RegisteredResourceProvider],
  cwd : String,
) -> @resource_providers.RegisteredResourceProvider? {
  let matches = providers
    .iter()
    .filter(fn(provider) {
      match provider_workspace_root(provider) {
        Some(root) => path_is_within(root, cwd)
        None => false
      }
    })
    .to_array()
  match matches {
    [provider] => Some(provider)
    _ => None
  }
}

///|
async fn resolve_provider_task_command(
  cwd : String,
  home : String?,
  target_id : String?,
  affinity_root : String,
) -> Result[ProviderTaskCommand, String] {
  let provider = match target_id {
    Some(target_id) if !target_id.trim().to_owned().is_blank() =>
      match @resource_providers.find_resource_provider(cwd, target_id, home~) {
        Some(provider) => provider
        None => return Err("Unknown provider task target: \{target_id}")
      }
    _ => {
      let providers = @resource_providers.load_resource_providers(cwd, home~)
        .iter()
        .filter(fn(provider) { provider_supports_extension_execution(provider) })
        .to_array()
      match providers {
        [provider] => provider
        _ =>
          match
            select_provider_by_workspace_affinity(providers, affinity_root) {
            Some(provider) => provider
            None =>
              match providers {
                [] =>
                  return Err(
                    "Extension task execution requires execution_target or exactly one registered provider target",
                  )
                _ =>
                  return Err(
                    "Extension task execution requires execution_target because multiple provider targets are registered",
                  )
              }
          }
      }
    }
  }
  guard provider_supports_extension_execution(provider) else {
    return Err(
      "Execution target \{provider.name} does not expose extension task capability",
    )
  }
  let command = provider_metadata_string(provider.metadata, "command").unwrap_or(
    "moon",
  )
  let args = provider_metadata_string_array(provider.metadata, "args")
  let command_cwd = provider_metadata_string(provider.metadata, "cwd")
  let workspace_root = match
    provider_metadata_string(provider.metadata, "workspace_root") {
    Some(root) => root
    None =>
      return Err(
        "Extension task target \{provider.name} is missing metadata.workspace_root",
      )
  }
  Ok({ provider, command, args, cwd: command_cwd, workspace_root })
}

///|
fn parse_provider_task_payload(
  text : String,
  context : String,
) -> Result[Json, String] {
  let trimmed = text.trim().to_owned()
  if trimmed.is_blank() {
    return Err("Provider task \{context} returned empty stdout")
  }
  let payload = extract_first_json_object(trimmed).unwrap_or(trimmed)
  let json = @json.parse(payload) catch {
    error =>
      return Err("Provider task \{context} returned invalid JSON: \{error}")
  }
  Ok(json)
}

///|
fn parse_provider_task_task_batch_json(
  text : String,
  context : String,
) -> Result[ProviderTaskBatch, String] {
  let json = match parse_provider_task_payload(text, context) {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskBatch = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task \{context} returned unexpected payload: \{error}",
      )
  }
  Ok(decoded)
}

///|
fn parse_provider_task_worker_context_json(
  text : String,
  context : String,
) -> Result[ProviderTaskWorkerContext, String] {
  let json = match parse_provider_task_payload(text, context) {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskWorkerContext = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task \{context} returned unexpected payload: \{error}",
      )
  }
  Ok(decoded)
}

///|
fn parse_provider_task_persist_outcome_json(
  text : String,
  context : String,
) -> Result[ProviderTaskPersistOutcome, String] {
  let json = match parse_provider_task_payload(text, context) {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskPersistOutcome = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task \{context} returned unexpected payload: \{error}",
      )
  }
  Ok(decoded)
}

///|
async fn run_provider_task_stdout(
  command : ProviderTaskCommand,
  subcommand : String,
  extra_args : Array[String],
  context : String,
) -> Result[String, String] {
  let arguments : Array[String] = [
    ..command.args,
    "wiki",
    "book",
    subcommand,
    command.workspace_root,
    ..extra_args,
  ]
  let process = @spawn.spawn(
    command.command,
    arguments.map(fn(arg) { arg }),
    cwd?=command.cwd.map(fn(value) { value }),
  ) catch {
    error => return Err("Failed to launch provider task \{context}: \{error}")
  }
  if process.status != 0 {
    let stderr = process.stderr.trim().to_owned()
    let stdout = process.stdout.trim().to_owned()
    let reason = if !stderr.is_blank() {
      stderr
    } else if !stdout.is_blank() {
      stdout
    } else {
      "exit status \{process.status}"
    }
    return Err("Provider task \{context} failed: \{reason}")
  }
  Ok(process.stdout)
}

///|
async fn load_provider_task_task_batch(
  cwd : String,
  home : String?,
  target_id : String?,
  goal : String,
  metadata? : Json = {},
) -> Result[(ProviderTaskCommand, ProviderTaskBatch), String] {
  let affinity_root = metadata_string_value(metadata, "workspace_root").unwrap_or(
    cwd,
  )
  let command = match
    resolve_provider_task_command(cwd, home, target_id, affinity_root) {
    Ok(command) => command
    Err(error) =>
      match embedded_provider_task_command(metadata, target_id) {
        Some(command) => command
        None => return Err(error)
      }
  }
  let stdout = match
    run_provider_task_stdout(command, "tasks", [goal], "tasks") {
    Ok(stdout) => stdout
    Err(error) => return Err(error)
  }
  let batch : ProviderTaskBatch = match
    parse_provider_task_task_batch_json(stdout, "tasks") {
    Ok(batch) => batch
    Err(error) => return Err(error)
  }
  Ok((command, batch))
}

///|
fn embedded_provider_task_command(
  metadata : Json,
  target_id : String?,
) -> ProviderTaskCommand? {
  guard metadata is Object(obj) else { return None }
  guard obj.get("provider_command") is Some(Object(command_obj)) else {
    return None
  }
  let provider_name = match command_obj.get("provider_name") {
    Some(String(value)) if !value.trim().to_owned().is_blank() =>
      value.trim().to_owned()
    _ => return None
  }
  match target_id {
    Some(target) if !target.trim().to_owned().is_blank() &&
      target.trim().to_owned() != provider_name => return None
    _ => ()
  }
  let command = match command_obj.get("command") {
    Some(String(value)) if !value.trim().to_owned().is_blank() =>
      value.trim().to_owned()
    _ => "moon"
  }
  let args = match command_obj.get("args") {
    Some(Array(values)) => {
      let items : Array[String] = []
      for value in values {
        guard value is String(text) else { continue }
        let trimmed = text.trim().to_owned()
        if !trimmed.is_blank() {
          items.push(trimmed)
        }
      }
      items
    }
    _ => []
  }
  let cwd = match command_obj.get("cwd") {
    Some(String(value)) if !value.trim().to_owned().is_blank() =>
      Some(value.trim().to_owned())
    _ => None
  }
  let workspace_root = match command_obj.get("workspace_root") {
    Some(String(value)) if !value.trim().to_owned().is_blank() =>
      value.trim().to_owned()
    _ => return None
  }
  Some({
    provider: @resource_providers.RegisteredResourceProvider::new(
      name=provider_name,
      title=provider_name,
      description="Embedded provider task command",
      kind="task-provider",
      capabilities=["provider.task"],
      metadata={
        "command": command,
        "args": args,
        "cwd": cwd,
        "workspace_root": workspace_root,
      },
    ),
    command,
    args,
    cwd,
    workspace_root,
  })
}

///|
async fn load_provider_task_context(
  command : ProviderTaskCommand,
  goal : String,
  task_id : String,
) -> Result[ProviderTaskWorkerContext, String] {
  let stdout = match
    run_provider_task_stdout(
      command,
      "context",
      [goal, "--task", task_id],
      "context",
    ) {
    Ok(stdout) => stdout
    Err(error) => return Err(error)
  }
  match parse_provider_task_worker_context_json(stdout, "context") {
    Ok(context) => Ok(context)
    Err(error) => Err(error)
  }
}

///|
fn select_provider_task_task(
  batch : ProviderTaskBatch,
  task_id : String?,
) -> Result[ProviderTaskSpec, String] {
  match task_id {
    Some(task_id) if !task_id.trim().to_owned().is_blank() =>
      match batch.tasks.iter().find_first(fn(task) { task.id == task_id }) {
        Some(task) => Ok(task)
        None => Err("Provider task task batch does not contain task \{task_id}")
      }
    _ =>
      if batch.tasks.is_empty() {
        Err("Provider task task batch is empty")
      } else {
        Ok(batch.tasks[0])
      }
  }
}
