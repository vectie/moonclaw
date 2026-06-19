///|
pub enum ResourceSummaryKind {
  File
  Skill
  Worktree
  Provider
} derive(ToJson, FromJson, Debug)

///|
pub struct ResourceSummary {
  uri : String
  kind : ResourceSummaryKind
  title : String
  description : String
  metadata : Json
} derive(ToJson, FromJson)

///|
pub struct ListResourcesResult {
  resources : Array[ResourceSummary]
  total_resources : Int
  truncated : Bool
} derive(ToJson, FromJson)

///|
pub impl Show for ListResourcesResult with fn output(
  result : ListResourcesResult,
  logger : &Logger,
) -> Unit {
  let lines = ["Resources: \{result.total_resources}", ""]
  if result.resources.is_empty() {
    lines.push("No resources found.")
    return logger.write_string(lines.join("\n"))
  }
  for resource in result.resources {
    lines.push("- \{resource.uri} :: \{resource.title}")
    if !resource.description.is_blank() {
      lines.push("  \{resource.description}")
    }
  }
  if result.truncated {
    lines.push("")
    lines.push("[truncated]")
  }
  logger.write_string(lines.join("\n"))
}

///|
fn file_resource_summary(path : String) -> ResourceSummary {
  {
    uri: "file://\{path}",
    kind: File,
    title: path,
    description: "Workspace file resource",
    metadata: { "path": path },
  }
}

///|
fn skill_resource_summary(skill : @skills.Skill) -> ResourceSummary {
  {
    uri: "skill://\{skill.name}",
    kind: Skill,
    title: skill.name,
    description: skill.description,
    metadata: {
      "location": skill.location,
      "allowed_tools": skill.allowed_tools,
      "metadata": skill.metadata,
    },
  }
}

///|
fn worktree_resource_summary(
  handle : @worktree.WorktreeHandle,
) -> ResourceSummary {
  {
    uri: "worktree://\{handle.task_key}",
    kind: Worktree,
    title: handle.task_key,
    description: "Managed git worktree",
    metadata: {
      "repo_root": handle.repo_root,
      "path": handle.path,
      "branch_name": handle.branch_name,
      "task_key": handle.task_key,
    },
  }
}

///|
fn provider_resource_summary(
  provider : @resource_providers.RegisteredResourceProvider,
) -> ResourceSummary {
  {
    uri: "provider://\{provider.name}",
    kind: Provider,
    title: provider.title,
    description: provider.description,
    metadata: {
      "name": provider.name,
      "kind": provider.kind,
      "endpoint": provider.endpoint,
      "docs_uri": provider.docs_uri,
      "capabilities": provider.capabilities,
      "metadata": provider.metadata,
    },
  }
}

///|
async fn list_file_resources(
  cwd : String,
  path : String,
  pattern : String,
  max_results : Int,
  include_hidden : Bool,
) -> ListResourcesResult {
  let result = @glob_files.new(cwd).call({
    "path": path,
    "pattern": pattern,
    "max_results": max_results,
    "respect_gitignore": true,
    "include_hidden": include_hidden,
  })
  let result = match result {
    Ok(result) => result
    Error(_, message) => fail(message)
  }
  let resources = result.matches.map(file_resource_summary)
  {
    resources,
    total_resources: result.total_matches,
    truncated: result.truncated,
  }
}

///|
async fn list_skill_resources(
  cwd : String,
  home : String?,
  max_results : Int,
) -> ListResourcesResult {
  let loader = @skills.Loader::new(
    home?,
    cwd~,
    logger=@pino.logger("list-resources", @pino.Transport::console()),
  ) catch {
    error => fail("failed to initialize skill loader: \{error}")
  }
  loader.load()
  let resources = []
  let skills = loader.skills().values().collect()
  for skill in skills {
    if resources.length() >= max_results {
      break
    }
    resources.push(skill_resource_summary(skill))
  }
  {
    resources,
    total_resources: skills.length(),
    truncated: skills.length() > resources.length(),
  }
}

///|
async fn list_worktree_resources(
  cwd : String,
  base_dir : String?,
  max_results : Int,
) -> ListResourcesResult {
  let result = @worktree.list_worktrees(cwd, base_dir~)
  let resources : Array[ResourceSummary] = []
  for handle in result.worktrees {
    if resources.length() >= max_results {
      break
    }
    resources.push(worktree_resource_summary(handle))
  }
  {
    resources,
    total_resources: result.worktrees.length(),
    truncated: result.worktrees.length() > resources.length(),
  }
}

///|
async fn list_provider_resources(
  cwd : String,
  home : String?,
  max_results : Int,
) -> ListResourcesResult {
  let providers = @resource_providers.load_resource_providers(cwd, home~)
  let resources : Array[ResourceSummary] = []
  for provider in providers {
    if resources.length() >= max_results {
      break
    }
    resources.push(provider_resource_summary(provider))
  }
  {
    resources,
    total_resources: providers.length(),
    truncated: providers.length() > resources.length(),
  }
}

///|
pub fn new(cwd : String, home? : String?) -> @tool.Tool[ListResourcesResult] {
  let resolved_home = home.unwrap_or(None)
  @tool.new(
    name="list_resources",
    description="List typed runtime resources. Supported kinds: files, skills, worktrees, and providers.",
    schema={
      "type": "object",
      "properties": {
        "kind": {
          "type": "string",
          "enum": ["file", "skill", "worktree", "provider"],
          "description": "Resource kind to list",
        },
        "path": {
          "type": "string",
          "description": "Base path for file resources",
        },
        "pattern": {
          "type": "string",
          "description": "Glob pattern for file resources",
        },
        "max_results": {
          "type": "integer",
          "description": "Maximum resources to return",
          "minimum": 1,
        },
        "include_hidden": {
          "type": "boolean",
          "description": "Whether hidden files should be included for file resources",
        },
        "base_dir": {
          "type": "string",
          "description": "Optional explicit worktree base directory",
        },
      },
      "required": ["kind"],
    },
    async fn(args) -> @tool.ToolResult[ListResourcesResult] noraise {
      guard args is { "kind": String(kind), .. } else {
        return @tool.error("Error: 'kind' parameter is required")
      }
      let max_results = match args {
        { "max_results": Number(value, ..), .. } => Int::max(1, value.to_int())
        _ => 100
      }
      let result = match kind {
        "file" => {
          let path = match args {
            { "path": String(path), .. } => path
            _ => "."
          }
          let pattern = match args {
            { "pattern": String(pattern), .. } => pattern
            _ => "**/*"
          }
          let include_hidden = match args {
            { "include_hidden": True, .. } => true
            _ => false
          }
          list_file_resources(cwd, path, pattern, max_results, include_hidden) catch {
            error => return @tool.error("Error listing resources: \{error}")
          }
        }
        "skill" =>
          list_skill_resources(cwd, resolved_home, max_results) catch {
            error => return @tool.error("Error listing resources: \{error}")
          }
        "worktree" => {
          let base_dir = match args {
            { "base_dir": String(base_dir), .. } => Some(base_dir)
            _ => None
          }
          list_worktree_resources(cwd, base_dir, max_results) catch {
            error => return @tool.error("Error listing resources: \{error}")
          }
        }
        "provider" =>
          list_provider_resources(cwd, resolved_home, max_results) catch {
            error => return @tool.error("Error listing resources: \{error}")
          }
        _ => return @tool.error("Error: unsupported resource kind '\{kind}'")
      }
      @tool.ok(result)
    },
  )
}
