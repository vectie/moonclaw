///|
fn configured_workspace_root(definition : JobDefinition) -> String? {
  match definition.config {
    { "workspace": String(workspace), .. } if !workspace.trim().is_blank() =>
      Some(workspace.trim().to_string())
    _ => None
  }
}

///|
fn run_workspace_root_dir(root : String) -> String {
  root |> @pathx.join(".moonclaw") |> @pathx.join("job-workspaces")
}

///|
fn child_workspace_root_dir(parent_workspace : String) -> String {
  parent_workspace |> @pathx.join(".moonclaw") |> @pathx.join("subjobs")
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
async fn copy_workspace_files_if_missing(
  source_workspace : String,
  workspace_dir : String,
) -> Unit {
  for name in @workspace.managed_workspace_file_names() {
    let source_file = source_workspace |> @pathx.join(name)
    let target_file = workspace_dir |> @pathx.join(name)
    let target_exists = @fsx.exists(target_file) catch { _ => false }
    if target_exists {
      continue
    }
    let content = @fsx.read_file(source_file) catch { _ => "" }
    @fsx.write_to_file(target_file, content) catch {
      _ => ()
    }
  }
}

///|
fn scoped_workspace_memories(
  store : SystemStore,
  workspace_root : String,
) -> Array[MemoryRecord] {
  MemoryService::new(store~).list(
    query=MemoryQuery::new(
      workspace=Some(workspace_root),
      status=Some(MemoryStatus::Active),
    ),
  )
}

///|
fn file_with_generated_section(
  current_content : String,
  start_marker : String,
  end_marker : String,
  generated_content : String,
) -> String {
  let section = [start_marker, generated_content, end_marker].join("\n")
  match (current_content.find(start_marker), current_content.find(end_marker)) {
    (Some(start), Some(end)) if end >= start =>
      current_content[:start].to_string() +
      section +
      current_content[end + end_marker.length():].to_string()
    _ if current_content.trim().is_blank() => section + "\n"
    _ => current_content.trim_end().to_string() + "\n\n" + section + "\n"
  }
}

///|
fn memory_file_with_generated_section(
  current_content : String,
  generated_content : String,
) -> String {
  file_with_generated_section(
    current_content, "<!-- moonclaw:memory:start -->", "<!-- moonclaw:memory:end -->",
    generated_content,
  )
}

///|
fn manual_memory_content(current_content : String) -> String {
  let start_marker = "<!-- moonclaw:memory:start -->"
  let end_marker = "<!-- moonclaw:memory:end -->"
  match (current_content.find(start_marker), current_content.find(end_marker)) {
    (Some(start), Some(end)) if end >= start =>
      (current_content[:start].to_string() +
      current_content[end + end_marker.length():].to_string())
      .trim()
      .to_string()
    _ => current_content.trim().to_string()
  }
}

///|
fn memory_matches_materialized_role(
  memory : MemoryRecord,
  role : String,
) -> Bool {
  if memory.tags.contains(role) || memory.tags.contains("workspace.\{role}") {
    return true
  }
  match (role, memory.kind) {
    ("identity", kind) if kind == "identity.note" ||
      kind == "workspace.identity" => true
    ("routine", kind) if kind == "routine.note" || kind == "workspace.routine" =>
      true
    _ => false
  }
}

///|
fn materialized_workspace_memories(
  store : SystemStore,
  workspace_root : String,
  role : String,
) -> Array[MemoryRecord] {
  scoped_workspace_memories(store, workspace_root).filter(fn(memory) {
    memory_matches_materialized_role(memory, role)
  })
}

///|
async fn sync_manual_workspace_memory(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
  source_workspace : String,
  workspace_dir : String,
) -> Unit {
  let now_ms = run.completed_at.unwrap_or(run.started_at.unwrap_or(0))
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
async fn sync_workspace_memory_file(
  store : SystemStore,
  source_workspace : String,
  workspace_dir : String,
) -> Unit {
  let memory_file = workspace_dir |> @pathx.join("MEMORY.md")
  let current_content = @fsx.read_file(memory_file) catch { _ => "" }
  let generated = render_memory_records_prompt(
    scoped_workspace_memories(store, source_workspace),
    header="Inherited workspace memory",
  )
  let next_content = memory_file_with_generated_section(
    current_content,
    if generated.is_blank() {
      "No inherited workspace memories yet."
    } else {
      generated
    },
  )
  @fsx.write_to_file(memory_file, next_content) catch {
    _ => ()
  }
}

///|
async fn sync_materialized_workspace_file(
  store : SystemStore,
  source_workspace : String,
  workspace_dir : String,
  file_name : String,
  role : String,
  header : String,
) -> Unit {
  let file_path = workspace_dir |> @pathx.join(file_name)
  let current_content = @fsx.read_file(file_path) catch { _ => "" }
  let generated = render_memory_records_prompt(
    materialized_workspace_memories(store, source_workspace, role),
    header~,
  )
  let next_content = file_with_generated_section(
    current_content,
    "<!-- moonclaw:\{role}:start -->",
    "<!-- moonclaw:\{role}:end -->",
    if generated.is_blank() {
      "No materialized \{role} memories yet."
    } else {
      generated
    },
  )
  @fsx.write_to_file(file_path, next_content) catch {
    _ => ()
  }
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
  sync_workspace_memory_file(store, source_workspace, workspace_dir)
  sync_materialized_workspace_file(
    store, source_workspace, workspace_dir, "IDENTITY.md", "identity", "Materialized identity memory",
  )
  sync_materialized_workspace_file(
    store, source_workspace, workspace_dir, "ROUTINES.md", "routine", "Materialized routine memory",
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
    error => return Err(error.to_string())
  }
  if command.status == 0 {
    Ok(command)
  } else {
    Err(command.stderr.trim().to_string())
  }
}

///|
async fn git_stdout(workspace_dir : String, args : Array[String]) -> String {
  match git_with_local_identity(workspace_dir, args) {
    Ok(process) => process.stdout.trim().to_string()
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
  copy_workspace_files_if_missing(source_workspace, workspace_dir)
  sync_workspace_memory_file(store, source_workspace, workspace_dir)
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
