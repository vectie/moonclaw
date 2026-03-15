///|
pub struct PluginRecord {
  id : String
  enabled : Bool
  status : String
  source : String?
  spec : String?
  version : String?
  install_path : String?
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub struct PluginRuntime {
  home : String
  cwd : String
  plugins : Map[String, PluginRecord]
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
fn config_paths(home : String, cwd : String) -> Array[String] {
  [
    root_config_path(home),
    nested_config_path(home),
    root_config_path(cwd),
    nested_config_path(cwd),
  ]
}

///|
async fn load_plugin_config(home : String, cwd : String) -> Json? {
  let mut loaded : Json? = None
  for path in config_paths(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    loaded = Some(json)
  }
  loaded
}

///|
fn plugin_entries_map(json : Json) -> Map[String, Json] {
  guard json is Object(root) else { return {} }
  guard root.get("plugins") is Some(Object(plugins)) else { return {} }
  guard plugins.get("entries") is Some(Object(entries)) else { return {} }
  entries
}

///|
fn plugin_installs_map(json : Json) -> Map[String, Json] {
  guard json is Object(root) else { return {} }
  guard root.get("plugins") is Some(Object(plugins)) else { return {} }
  guard plugins.get("installs") is Some(Object(installs)) else { return {} }
  installs
}

///|
fn plugin_enabled(value : Json?) -> Bool {
  match value {
    Some(Object(obj)) =>
      match obj.get("enabled") {
        Some(True) => true
        Some(False) => false
        _ => true
      }
    _ => true
  }
}

///|
fn plugin_string(value : Json?, field : String) -> String? {
  match value {
    Some(Object(obj)) =>
      match obj.get(field) {
        Some(String(text)) if !text.trim().is_empty() =>
          Some(text.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
async fn plugin_status(enabled : Bool, install_path : String?) -> String {
  if !enabled {
    "disabled"
  } else {
    match install_path {
      Some(path) => {
        let exists = @fsx.exists(path) catch { _ => false }
        if exists {
          "enabled"
        } else {
          "missing_install"
        }
      }
      None => "missing_install"
    }
  }
}

///|
async fn load_plugins_from_config(json : Json) -> Map[String, PluginRecord] {
  let entries = plugin_entries_map(json)
  let installs = plugin_installs_map(json)
  let plugin_ids : Array[String] = []
  for id, _ in entries {
    plugin_ids.push(id)
  }
  for id, _ in installs {
    if !plugin_ids.contains(id) {
      plugin_ids.push(id)
    }
  }
  let loaded : Map[String, PluginRecord] = {}
  for id in plugin_ids {
    let entry = entries.get(id)
    let install = installs.get(id)
    let enabled = plugin_enabled(entry)
    let install_path = plugin_string(install, "installPath")
    loaded[id] = PluginRecord::{
      id,
      enabled,
      status: plugin_status(enabled, install_path),
      source: plugin_string(install, "source"),
      spec: plugin_string(install, "spec"),
      version: match plugin_string(install, "resolvedVersion") {
        Some(version) => Some(version)
        None => plugin_string(install, "version")
      },
      install_path,
      metadata: { "entry": entry, "install": install },
    }
  }
  loaded
}

///|
pub async fn PluginRuntime::new(home~ : String, cwd~ : String) -> PluginRuntime {
  let runtime = PluginRuntime::{ home, cwd, plugins: {} }
  runtime.load()
  runtime
}

///|
pub async fn PluginRuntime::load(self : PluginRuntime) -> Unit {
  self.plugins.clear()
  match load_plugin_config(self.home, self.cwd) {
    Some(json) =>
      for id, record in load_plugins_from_config(json) {
        self.plugins[id] = record
      }
    None => ()
  }
}

///|
pub fn PluginRuntime::list(self : PluginRuntime) -> Array[PluginRecord] {
  let plugins = self.plugins.values().to_array()
  plugins.sort_by(fn(left, right) { left.id.compare(right.id) })
  plugins
}

///|
pub fn PluginRuntime::get(
  self : PluginRuntime,
  plugin_id : String,
) -> PluginRecord? {
  self.plugins.get(plugin_id)
}
