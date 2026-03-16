///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  match arr[:] {
    ["add", "codex", ..] => add_codex_target(arr)
    ["help"] | ["--help"] | ["-h"] => print_help()
    ["version"] | ["--version"] | ["-v"] => println(@buildinfo.version)
    _ => print_help()
  }
}

///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  start(args)
}

///|
fn print_help() -> Unit {
  println("MoonClaw ACP")
  println("")
  println("Usage: moonclaw acp <command> [options]")
  println("")
  println("Commands:")
  println("  add codex     Add or update a Codex ACP target")
  println("  version       Show version")
  println("  help          Show this help message")
  println("")
  println("Options for `add codex`:")
  println("  --home <dir>       Home config directory (default: ~/.moonclaw)")
  println(
    "  --cwd <dir>        Working directory for config discovery (default: current)",
  )
  println("  --id <target>      Target id (default: codex-main)")
  println("  --label <text>     Target label (default: Codex <id>)")
  println(
    "  --workspace <dir>  ACP workspace path (default: config workspace or <home>/workspace)",
  )
  println(
    "  --target-cwd <dir> ACP target cwd (default: config cwd or workspace)",
  )
  println("  --model <model>    Codex model (default: gpt-5)")
  println("  --command <cmd>    Command to launch (default: codex)")
  println("")
  println("Example:")
  println(
    "  moonclaw acp add codex --home ~/.moonclaw --workspace ~/.moonclaw/workspace",
  )
}

///|
fn parse_string_arg(args : Array[String], flag : String) -> String? {
  for i in 0..<args.length() {
    if args[i] == flag && i + 1 < args.length() {
      return Some(args[i + 1])
    }
  }
  None
}

///|
fn resolve_home(args : Array[String]) -> String {
  match parse_string_arg(args, "--home") {
    Some(home) => home
    None => @pathx.join(@os.home() catch { _ => "." }, ".moonclaw")
  }
}

///|
fn resolve_cwd(args : Array[String]) -> String {
  match parse_string_arg(args, "--cwd") {
    Some(cwd) => cwd
    None => @os.cwd() catch { _ => "." }
  }
}

///|
fn root_config_path(root : String) -> String {
  root |> @pathx.join("moonclaw.json")
}

///|
fn nested_config_path(root : String) -> String {
  root |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json")
}

///|
fn config_candidates(home : String, cwd : String) -> Array[String] {
  [
    root_config_path(home),
    nested_config_path(home),
    root_config_path(cwd),
    nested_config_path(cwd),
  ]
}

///|
fn preferred_config_path(home : String) -> String {
  root_config_path(home)
}

///|
async fn load_config(home : String, cwd : String) -> (String, Json?) {
  for path in config_candidates(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    return (path, Some(json))
  }
  (preferred_config_path(home), None)
}

///|
fn json_object_copy(value : Json?) -> Map[String, Json] {
  let copied : Map[String, Json] = {}
  match value {
    Some(Object(obj)) =>
      for key, entry in obj {
        copied[key] = entry
      }
    _ => ()
  }
  copied
}

///|
fn configured_workspace_root(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("workspace") {
                Some(String(workspace)) if !workspace.trim().is_empty() =>
                  Some(workspace.trim().to_string())
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
fn configured_agent_cwd(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("cwd") {
                Some(String(cwd)) if !cwd.trim().is_empty() =>
                  Some(cwd.trim().to_string())
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
fn json_set_path(json : Json, path : Array[String], value : Json) -> Json {
  if path.is_empty() {
    return value
  }
  let current = json_object_copy(Some(json))
  let head = path[0]
  let tail = path[1:].to_array()
  current[head] = match current.get(head) {
    Some(existing) => json_set_path(existing, tail, value)
    None => json_set_path(Json::object({}), tail, value)
  }
  Json::object(current)
}

///|
fn merge_missing(existing : Json, defaults : Json) -> Json {
  match (existing, defaults) {
    (Object(existing_obj), Object(default_obj)) => {
      let merged : Map[String, Json] = {}
      for key, value in default_obj {
        match existing_obj.get(key) {
          Some(existing_value) =>
            merged[key] = merge_missing(existing_value, value)
          None => merged[key] = value
        }
      }
      for key, value in existing_obj {
        if !merged.contains(key) {
          merged[key] = value
        }
      }
      Json::object(merged)
    }
    (existing, _) => existing
  }
}

///|
fn default_config(home : String) -> Json {
  let workspace_root = home |> @pathx.join("workspace")
  {
    "models": { "providers": {} },
    "agents": {
      "defaults": { "model": { "primary": "" }, "workspace": workspace_root },
    },
    "commands": {
      "native": "auto",
      "nativeSkills": "auto",
      "restart": true,
      "ownerDisplay": "raw",
    },
    "session": { "dmScope": "per-channel-peer" },
    "gateway": { "port": 18123, "auth": { "mode": "token", "token": "" } },
    "plugins": { "entries": {} },
  }
}

///|
fn config_dir(path : String) -> String {
  @pathx.dirname(path).to_string()
}

///|
fn codex_target_json(
  label : String,
  workspace : String,
  cwd : String,
  model : String,
  command : String,
) -> Json {
  {
    "backend": "codex",
    "label": label,
    "cwd": cwd,
    "workspace": workspace,
    "command": command,
    "args": ["exec"],
    "model": model,
  }
}

///|
async fn add_codex_target(args : Array[String]) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let (config_path, existing) = load_config(home, cwd)
  let base = match existing {
    Some(existing) => merge_missing(existing, default_config(home))
    None => default_config(home)
  }
  let target_id = parse_string_arg(args, "--id").unwrap_or("codex-main")
  let workspace = match parse_string_arg(args, "--workspace") {
    Some(workspace) => workspace
    None =>
      configured_workspace_root(existing).unwrap_or(
        home |> @pathx.join("workspace"),
      )
  }
  let target_cwd = match parse_string_arg(args, "--target-cwd") {
    Some(target_cwd) => target_cwd
    None => configured_agent_cwd(existing).unwrap_or(workspace)
  }
  let model = parse_string_arg(args, "--model").unwrap_or("gpt-5")
  let command = parse_string_arg(args, "--command").unwrap_or("codex")
  let label = parse_string_arg(args, "--label").unwrap_or("Codex \{target_id}")
  let configured = json_set_path(
    base,
    ["acp", "targets", target_id],
    codex_target_json(label, workspace, target_cwd, model, command),
  )
  @fsx.make_directory(config_dir(config_path), recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(config_path, configured.stringify(indent=2)) catch {
    err => {
      println("Failed to write ACP config: \{err}")
      return
    }
  }
  println("Configured ACP target `\{target_id}` in \{config_path}")
  println("Backend: codex")
  println("Workspace: \{workspace}")
  println("CWD: \{target_cwd}")
  println("Command: \{command} exec")
  println("Model: \{model}")
  if @codex.credentials_exist() {
    println("Codex credentials: ready")
  } else {
    println(
      "Codex credentials: missing. Run `moon run cmd/main -- onboard auth codex --home \{home}`.",
    )
  }
}
