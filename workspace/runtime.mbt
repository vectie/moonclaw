///|
pub struct WorkspaceFile {
  name : String
  path : String
  content : String
} derive(ToJson, FromJson, Debug)

///|
pub struct WorkspaceSnapshot {
  root : String
  configured_from : String
  files : Array[WorkspaceFile]
  prompt_context : String
} derive(ToJson, FromJson, Debug)

///|
pub struct WorkspaceRuntime {
  home : String
  cwd : String
  mut snapshot : WorkspaceSnapshot
}

///|
pub fn managed_workspace_file_names() -> Array[String] {
  ["IDENTITY.md", "AGENTS.md", "USER.md", "ROUTINES.md", "MEMORY.md"]
}

///|
fn preferred_config_path(home : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    home, "moonclaw", "moonclaw.json",
  )
}

///|
fn config_paths(home : String, cwd : String) -> Array[String] {
  let paths = [preferred_config_path(cwd)]
  if cwd != home {
    paths.push(preferred_config_path(home))
  }
  paths
}

///|
fn workspace_path_from_json(json : Json) -> String? {
  guard json is Object(root) else { return None }
  guard root.get("agents") is Some(Object(agents)) else { return None }
  guard agents.get("defaults") is Some(Object(defaults)) else { return None }
  match defaults.get("workspace") {
    Some(String(path)) if !path.trim().is_empty() =>
      Some(path.trim().to_owned())
    _ => None
  }
}

///|
async fn configured_workspace(home : String, cwd : String) -> (String, String) {
  for path in config_paths(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    match workspace_path_from_json(json) {
      Some(root) => return (root, path)
      None => ()
    }
  }
  (cwd, "cwd")
}

///|
fn workspace_file_path(root : String, name : String) -> String {
  root |> @pathx.join(name)
}

///|
fn default_workspace_file_content(root : String, name : String) -> String {
  match name {
    "IDENTITY.md" =>
      [
        "# Identity",
        "",
        "This workspace is managed by MoonClaw.",
        "Workspace root: \{root}",
      ].join("\n")
    "AGENTS.md" =>
      [
        "# Agents", "", "Document the roles, constraints, and defaults for this workspace.",
      ].join("\n")
    "USER.md" =>
      [
        "# User", "", "Record durable user preferences and collaboration expectations here.",
      ].join("\n")
    "ROUTINES.md" =>
      [
        "# Routines", "", "Describe recurring workflows, operating rules, and checklists here.",
      ].join("\n")
    "MEMORY.md" =>
      [
        "# Memory", "", "Capture durable long-term notes that should shape planning and execution.",
      ].join("\n")
    _ => ""
  }
}

///|
async fn ensure_workspace_files(root : String) -> Unit {
  @fsx.make_directory(root, recursive=true) catch {
    _ => ()
  }
  for name in managed_workspace_file_names() {
    let path = workspace_file_path(root, name)
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      @fsx.write_to_file(path, default_workspace_file_content(root, name)) catch {
        _ => ()
      }
    }
  }
}

///|
async fn load_workspace_files(root : String) -> Array[WorkspaceFile] {
  let files : Array[WorkspaceFile] = []
  for name in managed_workspace_file_names() {
    let path = workspace_file_path(root, name)
    let content = @fsx.read_file(path) catch { _ => "" }
    files.push({ name, path, content })
  }
  files
}

///|
fn excerpt_workspace_text(content : String, max_lines : Int) -> String {
  let lines : Array[String] = []
  for line in content.split("\n") {
    let trimmed = line.trim_end().to_owned()
    if !trimmed.is_blank() {
      lines.push(trimmed)
    }
  }
  if lines.length() <= max_lines {
    lines.join("\n")
  } else {
    [..lines[:max_lines], "..."].join("\n")
  }
}

///|
async fn render_extension_workspace_prompt_context(root : String) -> String {
  let raw_dir = root |> @pathx.join("raw")
  let wiki_dir = root |> @pathx.join("wiki")
  let has_raw_dir = @fsx.exists(raw_dir) catch { _ => false }
  let has_wiki_dir = @fsx.exists(wiki_dir) catch { _ => false }
  if !has_raw_dir && !has_wiki_dir {
    return ""
  }
  let sections : Array[String] = []
  let summary_lines : Array[String] = []
  if has_raw_dir {
    summary_lines.push("- raw source directory: \{raw_dir}")
  }
  if has_wiki_dir {
    summary_lines.push("- maintained wiki directory: \{wiki_dir}")
  }
  let index_path = wiki_dir |> @pathx.join("index.md")
  let log_path = wiki_dir |> @pathx.join("log.md")
  let has_index = @fsx.exists(index_path) catch { _ => false }
  if has_index {
    summary_lines.push("- wiki index file: \{index_path}")
    let content = @fsx.read_file(index_path) catch { _ => "" }
    if !content.trim().is_empty() {
      sections.push(
        ["Wiki index excerpt", excerpt_workspace_text(content, 18)].join("\n\n"),
      )
    }
  }
  let has_log = @fsx.exists(log_path) catch { _ => false }
  if has_log {
    summary_lines.push("- wiki log file: \{log_path}")
    let content = @fsx.read_file(log_path) catch { _ => "" }
    if !content.trim().is_empty() {
      sections.push(
        ["Wiki log excerpt", excerpt_workspace_text(content, 12)].join("\n\n"),
      )
    }
  }
  for dir_name in ["entities", "concepts", "synthesis", "queries", "sources"] {
    let path = wiki_dir |> @pathx.join(dir_name)
    let exists = @fsx.exists(path) catch { _ => false }
    if exists {
      summary_lines.push("- wiki/\{dir_name}/ available at: \{path}")
    }
  }
  if !summary_lines.is_empty() {
    let summary = ["Extension workspace detected:", summary_lines.join("\n")].join(
      "\n\n",
    )
    return [summary, ..sections].join("\n\n---\n\n")
  }
  sections.join("\n\n---\n\n")
}

///|
async fn render_workspace_prompt_context(
  root : String,
  files : Array[WorkspaceFile],
) -> String {
  let sections : Array[String] = []
  for file in files {
    if file.content.trim().is_empty() {
      continue
    }
    sections.push(["Workspace file `\{file.name}`", file.content].join("\n\n"))
  }
  let extension_context = render_extension_workspace_prompt_context(root)
  if !extension_context.is_blank() {
    sections.push(extension_context)
  }
  if sections.is_empty() {
    ""
  } else {
    ["Workspace context:", sections.join("\n\n---\n\n")].join("\n\n")
  }
}

///|
pub async fn load_workspace_snapshot_from_root(
  root : String,
  configured_from? : String = "explicit",
) -> WorkspaceSnapshot {
  ensure_workspace_files(root)
  let files = load_workspace_files(root)
  {
    root,
    configured_from,
    files,
    prompt_context: render_workspace_prompt_context(root, files),
  }
}

///|
pub async fn WorkspaceRuntime::new(
  home~ : String,
  cwd~ : String,
) -> WorkspaceRuntime {
  let (root, configured_from) = configured_workspace(home, cwd)
  let runtime = WorkspaceRuntime::{
    home,
    cwd,
    snapshot: { root, configured_from, files: [], prompt_context: "" },
  }
  runtime.load()
  runtime
}

///|
pub async fn WorkspaceRuntime::load(self : WorkspaceRuntime) -> Unit {
  let (root, configured_from) = configured_workspace(self.home, self.cwd)
  self.snapshot = load_workspace_snapshot_from_root(root, configured_from~)
}

///|
pub fn WorkspaceRuntime::root(self : WorkspaceRuntime) -> String {
  self.snapshot.root
}

///|
pub fn WorkspaceRuntime::prompt_context(self : WorkspaceRuntime) -> String {
  self.snapshot.prompt_context
}

///|
pub fn WorkspaceRuntime::snapshot(self : WorkspaceRuntime) -> WorkspaceSnapshot {
  self.snapshot
}
