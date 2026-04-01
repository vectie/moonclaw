///|
pub enum ResourceKind {
  File
  Skill
  Worktree
  Provider
} derive(ToJson, FromJson, Show)

///|
pub struct ReadResourceResult {
  uri : String
  resolved_uri : String
  kind : ResourceKind
  text : String
  truncated : Bool
  content_type : String
  metadata : Json
} derive(ToJson, FromJson)

///|
pub impl Show for ReadResourceResult with output(
  result : ReadResourceResult,
  logger : &Logger,
) -> Unit {
  let lines = [
    "URI: \{result.uri}",
    "Resolved: \{result.resolved_uri}",
    "Kind: \{result.kind.to_json().stringify()}",
    "Content-Type: \{result.content_type}",
    "",
    result.text,
  ]
  if result.truncated {
    lines.push("")
    lines.push("[truncated]")
  }
  logger.write_string(lines.join("\n"))
}

///|
priv enum ResourceUri {
  File(String)
  Skill(String)
  Worktree(String)
  Provider(String)
}

///|
fn parse_resource_uri(uri : String) -> ResourceUri raise {
  if uri.has_prefix("file://") {
    let path = uri[7:].to_string()
    guard !path.trim().to_string().is_blank() else {
      fail("file:// URI must include a path")
    }
    return File(path)
  }
  if uri.has_prefix("skill://") {
    let name = uri[8:].trim().to_string()
    guard !name.is_blank() else {
      fail("skill:// URI must include a skill name")
    }
    return Skill(name)
  }
  if uri.has_prefix("worktree://") {
    let key = uri[11:].trim().to_string()
    guard !key.is_blank() else {
      fail("worktree:// URI must include a worktree key")
    }
    return Worktree(key)
  }
  if uri.has_prefix("provider://") {
    let name = uri[11:].trim().to_string()
    guard !name.is_blank() else {
      fail("provider:// URI must include a provider name")
    }
    return Provider(name)
  }
  fail(
    "Unsupported resource URI. Expected file://, skill://, worktree://, or provider://",
  )
}

///|
fn truncate_resource_text(text : String, max_chars : Int) -> (String, Bool) {
  if max_chars <= 0 {
    return ("", !text.is_empty())
  }
  if text.length() <= max_chars {
    return (text, false)
  }
  (text[:max_chars].trim().to_string(), true)
}

///|
fn resolve_file_resource(cwd : String, path : String) -> String raise {
  let resolved = if @pathx.is_absolute(path) {
    path.view()
  } else {
    @pathx.join(cwd, path)
  }
  @pathx.resolve(resolved)
}

///|
async fn read_file_resource(
  cwd : String,
  uri : String,
  path : String,
  max_chars : Int,
) -> ReadResourceResult {
  let resolved_path = resolve_file_resource(cwd, path) catch {
    error => fail("failed to resolve file resource: \{error}")
  }
  guard @fsx.exists(resolved_path) else {
    fail("File resource does not exist: \{resolved_path}")
  }
  let text = @fsx.read_file(resolved_path)
  let (text, truncated) = truncate_resource_text(text, max_chars)
  ReadResourceResult::{
    uri,
    resolved_uri: "file://\{resolved_path}",
    kind: File,
    text,
    truncated,
    content_type: "text/plain",
    metadata: { "path": resolved_path },
  }
}

///|
async fn read_skill_resource(
  cwd : String,
  home : String?,
  uri : String,
  skill_name : String,
  max_chars : Int,
) -> ReadResourceResult {
  let loader = @skills.Loader::new(
    home?,
    cwd~,
    logger=@pino.logger("read-resource", @pino.Transport::console()),
  ) catch {
    error => fail("failed to initialize skill loader: \{error}")
  }
  loader.load()
  let skill = match loader.skills().get(skill_name) {
    Some(skill) => skill
    None => fail("Skill resource not found: \{skill_name}")
  }
  let text = @fsx.read_file(skill.location)
  let (text, truncated) = truncate_resource_text(text, max_chars)
  ReadResourceResult::{
    uri,
    resolved_uri: "skill://\{skill.name}",
    kind: Skill,
    text,
    truncated,
    content_type: "text/markdown",
    metadata: {
      "name": skill.name,
      "description": skill.description,
      "location": skill.location,
      "allowed_tools": skill.allowed_tools,
      "metadata": skill.metadata,
    },
  }
}

///|
async fn read_worktree_resource(
  cwd : String,
  uri : String,
  worktree_key : String,
) -> ReadResourceResult {
  let result = @worktree.list_worktrees(cwd) catch {
    error => fail("failed to list worktrees: \{error}")
  }
  let mut matched : @worktree.WorktreeHandle? = None
  for handle in result.worktrees {
    if handle.task_key == worktree_key {
      matched = Some(handle)
      break
    }
  }
  let handle = match matched {
    Some(handle) => handle
    None => fail("Worktree resource not found: \{worktree_key}")
  }
  let text = [
    "Worktree: \{handle.task_key}",
    "Path: \{handle.path}",
    "Branch: \{handle.branch_name}",
    "Repo root: \{handle.repo_root}",
  ].join("\n")
  ReadResourceResult::{
    uri,
    resolved_uri: "worktree://\{handle.task_key}",
    kind: Worktree,
    text,
    truncated: false,
    content_type: "text/plain",
    metadata: {
      "repo_root": handle.repo_root,
      "path": handle.path,
      "branch_name": handle.branch_name,
      "task_key": handle.task_key,
    },
  }
}

///|
async fn read_provider_resource(
  cwd : String,
  home : String?,
  uri : String,
  provider_name : String,
) -> ReadResourceResult {
  let provider = match
    @resource_providers.find_resource_provider(cwd, provider_name, home~) {
    Some(provider) => provider
    None => fail("Provider resource not found: \{provider_name}")
  }
  let lines = [
    "Provider: \{provider.title}",
    "Name: \{provider.name}",
    "Kind: \{provider.kind}",
    "Description: \{provider.description}",
  ]
  let lines = match provider.endpoint {
    Some(endpoint) if !endpoint.is_blank() => [..lines, "Endpoint: \{endpoint}"]
    _ => lines
  }
  let lines = match provider.docs_uri {
    Some(docs_uri) if !docs_uri.is_blank() => [..lines, "Docs: \{docs_uri}"]
    _ => lines
  }
  let lines = if provider.capabilities.is_empty() {
    lines
  } else {
    let capabilities = provider.capabilities.join(", ")
    [..lines, "Capabilities: \{capabilities}"]
  }
  ReadResourceResult::{
    uri,
    resolved_uri: "provider://\{provider.name}",
    kind: Provider,
    text: lines.join("\n"),
    truncated: false,
    content_type: "application/json",
    metadata: {
      "name": provider.name,
      "title": provider.title,
      "description": provider.description,
      "kind": provider.kind,
      "endpoint": provider.endpoint,
      "docs_uri": provider.docs_uri,
      "capabilities": provider.capabilities,
      "metadata": provider.metadata,
    },
  }
}

///|
pub fn new(cwd : String, home? : String?) -> @tool.Tool[ReadResourceResult] {
  let resolved_home = home.unwrap_or(None)
  @tool.new(
    name="read_resource",
    description="Read a typed runtime resource by URI. Supported schemes: file://, skill://, worktree://, and provider://.",
    schema={
      "type": "object",
      "properties": {
        "uri": {
          "type": "string",
          "description": "Resource URI such as file://notes.txt, skill://job-planning, worktree://review-docs, or provider://slides-main",
        },
        "max_chars": {
          "type": "integer",
          "description": "Maximum number of characters to return",
          "minimum": 100,
        },
      },
      "required": ["uri"],
    },
    async fn(args) -> @tool.ToolResult[ReadResourceResult] noraise {
      guard args is { "uri": String(uri), .. } else {
        return @tool.error("Error: 'uri' parameter is required")
      }
      let max_chars = match args {
        { "max_chars": Number(value, ..), .. } => Int::max(100, value.to_int())
        _ => 20_000
      }
      let parsed_uri = parse_resource_uri(uri) catch {
        error => return @tool.error("Error reading resource: \{error}")
      }
      let result = match parsed_uri {
        File(path) =>
          read_file_resource(cwd, uri, path, max_chars) catch {
            error => return @tool.error("Error reading resource: \{error}")
          }
        Skill(name) =>
          read_skill_resource(cwd, resolved_home, uri, name, max_chars) catch {
            error => return @tool.error("Error reading resource: \{error}")
          }
        Worktree(key) =>
          read_worktree_resource(cwd, uri, key) catch {
            error => return @tool.error("Error reading resource: \{error}")
          }
        Provider(name) =>
          read_provider_resource(cwd, resolved_home, uri, name) catch {
            error => return @tool.error("Error reading resource: \{error}")
          }
      }
      @tool.ok(result)
    },
  )
}
