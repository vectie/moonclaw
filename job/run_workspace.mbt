///|
fn configured_workspace_root(definition : JobDefinition) -> String? {
  match definition.config {
    { "workspace": String(workspace), .. } if !workspace.trim().is_blank() =>
      Some(workspace.trim().to_owned())
    _ => None
  }
}

///|
fn run_workspace_root_dir(root : String) -> String {
  root |> @pathx.join("moonclaw-jobs")
}

///|
fn child_workspace_root_dir(parent_workspace : String) -> String {
  parent_workspace |> @pathx.join("moonclaw-subjobs")
}

///|
fn run_workspace_meta_dir(workspace_dir : String) -> String {
  workspace_dir |> @pathx.join(".moonclaw")
}

///|
fn run_workspace_meta_file(workspace_dir : String) -> String {
  run_workspace_meta_dir(workspace_dir) |> @pathx.join("run.json")
}

///|
fn derived_workspace_dir(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
) -> String {
  match run.workspace_dir {
    Some(workspace_dir) if !workspace_dir.trim().is_blank() => workspace_dir
    _ =>
      match run.parent_run_id {
        Some(parent_run_id) =>
          match
            store
            .get_run(parent_run_id)
            .bind(fn(parent) { parent.workspace_dir }) {
            Some(parent_workspace) =>
              child_workspace_root_dir(parent_workspace) |> @pathx.join(run.id)
            None =>
              run_workspace_root_dir(
                configured_workspace_root(definition).unwrap_or("."),
              )
              |> @pathx.join(run.id)
          }
        None =>
          run_workspace_root_dir(
            configured_workspace_root(definition).unwrap_or("."),
          )
          |> @pathx.join(run.id)
      }
  }
}

///|
fn source_workspace_dir(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
) -> String {
  match run.parent_run_id {
    Some(parent_run_id) =>
      match
        store.get_run(parent_run_id).bind(fn(parent) { parent.workspace_dir }) {
        Some(parent_workspace) => parent_workspace
        None => configured_workspace_root(definition).unwrap_or(".")
      }
    None => configured_workspace_root(definition).unwrap_or(".")
  }
}

///|
async fn ensure_directory(path : String) -> Unit {
  @fsx.make_directory(path, recursive=true) catch {
    _ => ()
  }
}

///|
fn source_workspace_mount_names() -> Array[String] {
  [
    "wiki",
    "raw",
    "skills",
    "RESOLVER.md",
    "AGENTS.md",
    "moonclaw.jobs.json",
    source_hint_mount_dir_name(),
  ]
}

///|
fn source_hint_mount_dir_name() -> String {
  "mounted-sources"
}

///|
fn source_hint_mount_manifest_name() -> String {
  "MANIFEST.md"
}

///|
fn source_hint_mount_manifest_path(workspace_dir : String) -> String {
  workspace_dir
  |> @pathx.join(source_hint_mount_dir_name())
  |> @pathx.join(source_hint_mount_manifest_name())
}

///|
fn source_hint_mount_name(source_path : String) -> String {
  let base = @pathx.basename(source_path).to_owned()
  let safe_base = safe_step_file_segment(base)
  if safe_base.is_blank() {
    "source-\{source_path.hash()}"
  } else {
    "\{safe_base}-\{source_path.hash()}"
  }
}

///|
fn source_hint_mounted_relative_path(source_path : String) -> String {
  @pathx.join(source_hint_mount_dir_name(), source_hint_mount_name(source_path))
}

///|
fn source_hint_followup_paths_from_markdown(content : String) -> Array[String] {
  let paths : Array[String] = []
  let mut in_section = false
  for raw_line in content.split("\n") {
    let line = raw_line.trim().to_owned()
    if line.has_prefix("## ") {
      let normalized = line[3:].trim().to_lower()
      if in_section && normalized != "local repository follow-up" {
        break
      }
      in_section = normalized == "local repository follow-up"
      continue
    }
    if !in_section || !line.has_prefix("- ") {
      continue
    }
    let candidate = line[2:].trim().to_owned()
    if !candidate.is_blank() && !paths.contains(candidate) {
      paths.push(candidate)
    }
  }
  paths
}

///|
async fn source_hint_followup_paths(source_workspace : String) -> Array[String] {
  let path = source_workspace
    |> @pathx.join("raw")
    |> @pathx.join("bootstrap")
    |> @pathx.join("SOURCE_HINTS.md")
  let content = @fsx.read_file(path) catch { _ => return [] }
  source_hint_followup_paths_from_markdown(content)
}

///|
async fn create_source_workspace_mount(
  source_workspace : String,
  workspace_dir : String,
  name : String,
) -> Unit {
  let source_path = source_workspace |> @pathx.join(name)
  let destination_path = workspace_dir |> @pathx.join(name)
  if source_path == destination_path {
    return
  }
  let source_exists = @fsx.exists(source_path) catch { _ => false }
  if !source_exists {
    return
  }
  let destination_exists = @fsx.exists(destination_path) catch { _ => false }
  if destination_exists {
    return
  }
  let command = @spawn.spawn(
    "ln",
    ["-s", source_path, destination_path],
    cwd=workspace_dir,
  ) catch {
    _ => return
  }
  ignore(command)
}

///|
async fn create_external_source_mount(
  source_path : String,
  workspace_dir : String,
) -> Unit {
  let source_exists = @fsx.exists(source_path) catch { _ => false }
  if !source_exists {
    return
  }
  let relative = source_hint_mounted_relative_path(source_path)
  let destination_path = workspace_dir |> @pathx.join(relative)
  let parent_dir = @pathx.dirname(destination_path)
  @fsx.make_directory(parent_dir, recursive=true, exists_ok=true) catch {
    _ => return
  }
  let destination_exists = @fsx.exists(destination_path) catch { _ => false }
  if destination_exists {
    return
  }
  let command = @spawn.spawn(
    "ln",
    ["-s", source_path, destination_path],
    cwd=workspace_dir,
  ) catch {
    _ => return
  }
  ignore(command)
}

///|
async fn mount_source_hint_followup_entries(
  source_workspace : String,
  workspace_dir : String,
) -> Unit {
  if source_workspace == workspace_dir {
    return
  }
  let manifest_lines : Array[String] = [
    "# Mounted Source Hints", "", "MoonClaw mounts external source hints here so isolated run worktrees can inspect them without reading absolute paths directly.",
    "", "| Original path | Mounted path | Status |", "| --- | --- | --- |",
  ]
  for source_path in source_hint_followup_paths(source_workspace) {
    let relative = source_hint_mounted_relative_path(source_path)
    let exists = @fsx.exists(source_path) catch { _ => false }
    let status = if exists { "mounted" } else { "missing" }
    manifest_lines.push("| `\{source_path}` | `\{relative}` | \{status} |")
    create_external_source_mount(source_path, workspace_dir)
  }
  if manifest_lines.length() > 6 {
    let manifest_path = source_hint_mount_manifest_path(workspace_dir)
    @fsx.make_directory(
      @pathx.dirname(manifest_path),
      recursive=true,
      exists_ok=true,
    ) catch {
      _ => return
    }
    @fsx.write_to_file(manifest_path, manifest_lines.join("\n") + "\n") catch {
      _ => ()
    }
  }
}

///|
async fn mount_source_workspace_entries(
  source_workspace : String,
  workspace_dir : String,
) -> Unit {
  if source_workspace == workspace_dir {
    return
  }
  for name in source_workspace_mount_names() {
    create_source_workspace_mount(source_workspace, workspace_dir, name)
  }
  mount_source_hint_followup_entries(source_workspace, workspace_dir)
}

///|
fn manual_memory_content(current_content : String) -> String {
  let start_marker = "<!-- moonclaw:memory:start -->"
  let end_marker = "<!-- moonclaw:memory:end -->"
  match (current_content.find(start_marker), current_content.find(end_marker)) {
    (Some(start), Some(end)) if end >= start =>
      (current_content[:start].to_owned() +
      current_content[end + end_marker.length():].to_owned())
      .trim()
      .to_owned()
    _ => current_content.trim().to_owned()
  }
}

///|
async fn sync_manual_workspace_memory(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
  source_workspace : String,
  workspace_dir : String,
) -> Unit {
  let now_ms = run.finished_at.unwrap_or(run.started_at.unwrap_or(0))
  let memory_file = workspace_dir |> @pathx.join("MEMORY.md")
  let current_content = @fsx.read_file(memory_file) catch { _ => "" }
  let manual_content = manual_memory_content(current_content)
  let memory_id = "workspace-memory:\{run.id}"
  if manual_content.is_blank() {
    match store.get_memory(memory_id) {
      Some(existing) if existing.status is MemoryStatus::Active =>
        ignore(MemoryService::new(store~).archive(memory_id, now_ms))
      _ => ()
    }
    return
  }
  let created_at = store
    .get_memory(memory_id)
    .map(fn(record) { record.created_at })
    .unwrap_or(now_ms)
  ignore(
    MemoryService::new(store~).remember(
      MemoryWriteRequest::new(
        kind="workspace.note",
        title=Some("Workspace memory for \{run.id}"),
        content=manual_content,
        metadata={
          "job_id": definition.id,
          "run_id": run.id,
          "source_workspace": source_workspace,
        },
        tags=["workspace", "run", "memory"],
        scope=["run:\{run.id}", "job:\{definition.id}"],
        workspace=Some(workspace_dir),
      ),
      memory_id,
      created_at,
    ),
  )
}

///|
pub async fn refresh_run_workspace_memory(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
) -> Unit {
  let source_workspace = source_workspace_dir(store, definition, run)
  let workspace_dir = match run.workspace_dir {
    Some(workspace_dir) => workspace_dir
    None => return
  }
  sync_manual_workspace_memory(
    store, definition, run, source_workspace, workspace_dir,
  )
}

///|
async fn write_run_workspace_metadata(
  definition : JobDefinition,
  run : JobRun,
  workspace_dir : String,
  source_workspace : String,
) -> Unit {
  ensure_directory(run_workspace_meta_dir(workspace_dir))
  @fsx.write_to_file(
    run_workspace_meta_file(workspace_dir),
    (
      {
        "job_id": definition.id,
        "run_id": run.id,
        "parent_run_id": run.parent_run_id,
        "parent_step_id": run.parent_step_id,
        "workspace_dir": workspace_dir,
        "source_workspace": source_workspace,
        "depth": run.depth,
      } : Json).stringify(),
  ) catch {
    _ => ()
  }
}

///|
async fn git_with_local_identity(
  workspace_dir : String,
  args : Array[String],
) -> Result[@spawn.CompletedProcess, String] {
  let spawn_args : Array[StringView] = [
    "-c"[:],
    "user.name=MoonClaw"[:],
    "-c"[:],
    "user.email=moonclaw@local"[:],
    ..args.map(fn(arg) { arg[:] }),
  ]
  let command = @spawn.spawn("git", spawn_args, cwd=workspace_dir) catch {
    error => return Err("\{to_repr(error)}")
  }
  if command.status == 0 {
    Ok(command)
  } else {
    Err(command.stderr.trim().to_owned())
  }
}

///|
async fn git_stdout(workspace_dir : String, args : Array[String]) -> String {
  match git_with_local_identity(workspace_dir, args) {
    Ok(process) => process.stdout.trim().to_owned()
    Err(error) => error
  }
}

///|
async fn initialize_workspace_repo(workspace_dir : String) -> Unit {
  let git_dir = workspace_dir |> @pathx.join(".git")
  let exists = @fsx.exists(git_dir) catch { _ => false }
  if exists {
    return
  }
  ignore(git_with_local_identity(workspace_dir, ["init"]))
}

///|
async fn workspace_has_git_changes(workspace_dir : String) -> Bool {
  let result = git_with_local_identity(workspace_dir, ["status", "--porcelain"])
  match result {
    Ok(process) => !process.stdout.trim().is_blank()
    Err(_) => false
  }
}

///|
pub async fn checkpoint_run_workspace(
  store : SystemStore,
  run_id : String,
  message : String,
) -> Bool {
  let run = match store.get_run(run_id) {
    Some(run) => run
    None => return false
  }
  let workspace_dir = match run.workspace_dir {
    Some(workspace_dir) => workspace_dir
    None => return false
  }
  match store.get_definition(run.job_id) {
    Some(definition) => refresh_run_workspace_memory(store, definition, run)
    None => ()
  }
  if !workspace_has_git_changes(workspace_dir) {
    return false
  }
  ignore(git_with_local_identity(workspace_dir, ["add", "-A"]))
  ignore(git_with_local_identity(workspace_dir, ["commit", "-m", message]))
  true
}

///|
pub async fn render_run_workspace_status(
  _store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
) -> String {
  let workspace_dir = match run.workspace_dir {
    Some(workspace_dir) => workspace_dir
    None =>
      return "Job workspace: unavailable for `\{definition.id}` (`\{run.id}`)."
  }
  let status_output = git_stdout(workspace_dir, ["status", "--short"])
  let commits_output = git_stdout(workspace_dir, ["log", "--oneline", "-n", "3"])
  let status_text = if status_output.is_blank() {
    "clean"
  } else {
    status_output
  }
  let commits_text = if commits_output.is_blank() {
    "(no commits)"
  } else {
    commits_output
  }
  [
    "Job workspace: \{definition.id}",
    "Run: \{run.id}",
    "Path: \{workspace_dir}",
    "Git status:",
    status_text,
    "Recent commits:",
    commits_text,
  ].join("\n")
}

///|
pub async fn prepare_run_workspace(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
) -> JobRun {
  let source_workspace = source_workspace_dir(store, definition, run)
  let workspace_dir = derived_workspace_dir(store, definition, run)
  ensure_directory(workspace_dir)
  mount_source_workspace_entries(source_workspace, workspace_dir)
  write_run_workspace_metadata(definition, run, workspace_dir, source_workspace)
  initialize_workspace_repo(workspace_dir)
  let updated = JobRun::{ ..run, workspace_dir: Some(workspace_dir) }
  store.save_run(updated)
  ignore(
    checkpoint_run_workspace(
      store,
      updated.id,
      "moonclaw: initialize workspace",
    ),
  )
  updated
}
