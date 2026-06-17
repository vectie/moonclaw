///|
async fn mooncode_runtime_turn_package_results(
  session_id : String,
  book_root : String,
  command : Json,
  execution : Json,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let paths = mooncode_runtime_turn_package_paths(execution)
  if paths.length() == 0 {
    return []
  }
  let command_id = mooncode_command_id(command)
  let manifest = mooncode_runtime_turn_package_manifest(
    session_id,
    book_root,
    command,
    paths,
    now~,
  )
  let index = mooncode_runtime_turn_package_index(
    session_id,
    book_root,
    manifest,
    now~,
  )
  mooncode_runtime_turn_write_json_manifest(
    book_root,
    mooncode_json_string(manifest, "manifest_path", default=""),
    manifest,
  )
  mooncode_runtime_turn_write_json_manifest(
    book_root,
    mooncode_json_string(index, "manifest_path", default=""),
    index,
  )
  let entrypoint = mooncode_json_string(manifest, "context_path", default="")
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let built : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "event": mooncode_event_package_built(),
    "path": entrypoint,
    "detail": "MoonClaw native runtime built MoonBook package candidate `\{entrypoint}`.",
    "package_manifest": manifest,
    "package_index": index,
    "command_packet": packet,
  }
  if mooncode_runtime_turn_package_verified(execution) {
    [
      built,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command_id": command_id,
        "event": mooncode_event_package_verified(),
        "path": entrypoint,
        "detail": "MoonClaw native runtime verified MoonBook package candidate `\{entrypoint}`.",
        "package_manifest": manifest,
        "package_index": index,
        "command_packet": packet,
      },
    ]
  } else {
    [built]
  }
}

///|
fn mooncode_runtime_turn_package_paths(execution : Json) -> Array[String] {
  let paths : Array[String] = []
  for result in mooncode_json_array_items(execution, "tool_results") {
    if !mooncode_json_bool(result, "accepted", default=false) {
      continue
    }
    let tool = mooncode_json_string(result, "tool", default="")
    if tool != "write" && tool != "edit" {
      continue
    }
    let tool_result = mooncode_json_object_field_or_empty(result, "result")
    let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
    let path = mooncode_json_string(metadata, "path", default="")
    if mooncode_runtime_turn_is_package_path(path) &&
      !mooncode_runtime_turn_string_array_contains(paths, path) {
      paths.push(path)
    }
  }
  paths
}

///|
fn mooncode_runtime_turn_is_package_path(path : String) -> Bool {
  path.has_prefix("tools/") ||
  path.has_prefix("apps/") ||
  path.has_prefix("site/generated/") ||
  path.has_prefix("portable/app-tool/")
}

///|
fn mooncode_runtime_turn_package_verified(execution : Json) -> Bool {
  for result in mooncode_json_array_items(execution, "tool_results") {
    if !mooncode_json_bool(result, "accepted", default=false) {
      continue
    }
    let tool = mooncode_json_string(result, "tool", default="")
    if tool == "shell" || tool == "moon_check" {
      return true
    }
  }
  false
}

///|
async fn mooncode_runtime_turn_package_manifest(
  session_id : String,
  book_root : String,
  command : Json,
  paths : Array[String],
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_command_id(command)
  let entrypoint = mooncode_runtime_turn_package_entrypoint(paths)
  let safe_session = mooncode_safe_session_id(session_id)
  let safe_command = mooncode_safe_session_id(command_id)
  let package_root = "portable/app-tool/mooncode/\{safe_session}"
  let manifest_path = "\{package_root}/package-\{safe_command}.json"
  let absolute_manifest_path = @pathx.join(book_root, manifest_path)
  let source_inventory = mooncode_runtime_turn_source_inventory(
    book_root,
    paths,
    package_root~,
    safe_command~,
  )
  let source_present = mooncode_runtime_turn_source_present_count(
    source_inventory,
  )
  let source_promoted = mooncode_runtime_turn_source_promoted_count(
    source_inventory,
  )
  {
    "kind": "mooncode-package-manifest",
    "protocol": mooncode_protocol_version(),
    "status": "source-bound",
    "package_kind": mooncode_runtime_turn_package_kind(entrypoint),
    "session_id": session_id,
    "workspace_id": mooncode_json_string(command, "workspace_id", default=""),
    "workspace_name": mooncode_json_string(
      command,
      "workspace_name",
      default="",
    ),
    "task_id": "",
    "context_path": entrypoint,
    "candidate_paths": Json::array(
      mooncode_runtime_turn_string_json_array(paths),
    ),
    "source_inventory": Json::array(source_inventory),
    "promoted_sources": Json::array(source_inventory),
    "source_inventory_count": source_inventory.length(),
    "source_present_count": source_present,
    "promoted_source_count": source_promoted,
    "source_promotion_status": if source_promoted == paths.length() &&
      paths.length() > 0 {
      "promoted"
    } else if source_promoted > 0 {
      "partially-promoted"
    } else {
      "not-promoted"
    },
    "promoted_source_root": "\{package_root}/sources/\{safe_command}",
    "source_inventory_status": if source_present > 0 {
      "source-bound"
    } else {
      "no-source-yet"
    },
    "command_id": command_id,
    "command_created_at": mooncode_json_string(
      command,
      "created_at",
      default="",
    ),
    "recorded_at": now,
    "manifest_path": manifest_path,
    "absolute_manifest_path": absolute_manifest_path,
    "review_receipt_path": "",
    "detail": "MoonClaw native runtime created a packageable MoonBook artifact.",
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "owner": mooncode_runtime_turn_package_owner(),
    "next_runtime_step": "Moondesk can review this MoonClaw-built candidate through the MoonCode package panel; MoonClaw or standalone MoonCode owns follow-up rebuild and verification events.",
  }
}

///|
fn mooncode_runtime_turn_package_index(
  session_id : String,
  book_root : String,
  manifest : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let safe_session = mooncode_safe_session_id(session_id)
  let manifest_path = "portable/app-tool/mooncode/\{safe_session}/index.json"
  {
    "kind": "mooncode-package-index",
    "protocol": mooncode_protocol_version(),
    "status": "verified",
    "session_id": session_id,
    "workspace_id": mooncode_json_string(manifest, "workspace_id", default=""),
    "workspace_name": mooncode_json_string(
      manifest,
      "workspace_name",
      default="",
    ),
    "task_id": "",
    "recorded_at": now,
    "manifest_path": manifest_path,
    "absolute_manifest_path": @pathx.join(book_root, manifest_path),
    "package_root": "portable/app-tool/mooncode/\{safe_session}",
    "package_count": 1,
    "source_bound_package_count": 1,
    "missing_source_package_count": 0,
    "executable_ready_count": 1,
    "runtime_built_package_count": 1,
    "runtime_verified_package_count": 1,
    "runtime_package_proof_count": 2,
    "package_kinds": Json::array([
      mooncode_json_string(manifest, "package_kind", default="artifact").to_json(),
    ]),
    "entry_points": Json::array([
      mooncode_json_string(manifest, "context_path", default="").to_json(),
    ]),
    "packages": Json::array([manifest]),
    "latest_package_manifest": manifest,
    "descriptor_contract": {
      "owner": "moonbook",
      "consumer": "moonclaw-or-standalone-mooncode",
      "rule": "This index is the stable MoonBook package registry for a MoonCode session.",
    },
    "owner": mooncode_runtime_turn_package_owner(),
  }
}

///|
fn mooncode_runtime_turn_package_entrypoint(paths : Array[String]) -> String {
  for path in paths {
    if path.has_suffix("/run.sh") || path.has_suffix("/index.html") {
      return path
    }
  }
  if paths.length() == 0 {
    ""
  } else {
    paths[0]
  }
}

///|
fn mooncode_runtime_turn_package_kind(path : String) -> String {
  if path.has_prefix("tools/") {
    "tool"
  } else if path.has_prefix("apps/") {
    "miniapp"
  } else if path.has_prefix("site/generated/") {
    "generated-site"
  } else if path.has_prefix("portable/app-tool/") {
    "app-tool"
  } else {
    "artifact"
  }
}

///|
async fn mooncode_runtime_turn_source_inventory(
  book_root : String,
  paths : Array[String],
  package_root~ : String,
  safe_command~ : String,
) -> Array[Json] {
  let inventory : Array[Json] = []
  for path in paths {
    let absolute = @pathx.join(book_root, path)
    let content = @fsx.read_file(absolute) catch { _ => "" }
    let exists = @fsx.exists(absolute) catch { _ => false }
    let promoted = mooncode_runtime_turn_promote_source(
      book_root,
      package_root,
      safe_command,
      path,
      content,
      exists~,
    )
    inventory.push({
      "path": path,
      "absolute_path": absolute,
      "exists": exists,
      "kind": "file",
      "size_bytes": content.length(),
      "package_ready": exists && content.length() > 0,
      "sha256_base64": if exists {
        mooncode_runtime_turn_sha256_base64(content)
      } else {
        ""
      },
      "promotion": promoted,
      "promoted": mooncode_json_bool(promoted, "promoted", default=false),
      "promoted_path": mooncode_json_string(
        promoted,
        "promoted_path",
        default="",
      ),
      "promoted_absolute_path": mooncode_json_string(
        promoted,
        "promoted_absolute_path",
        default="",
      ),
    })
  }
  inventory
}

///|
fn mooncode_runtime_turn_sha256_base64(content : String) -> String {
  @base64.encode(
    Bytes::from_array(@crypto.sha256(@encoding/utf8.encode(content))),
    url_safe=false,
  )
}

///|
async fn mooncode_runtime_turn_promote_source(
  book_root : String,
  package_root : String,
  safe_command : String,
  path : String,
  content : String,
  exists~ : Bool,
) -> Json {
  let promoted_path = "\{package_root}/sources/\{safe_command}/\{path}"
  let promoted_absolute = @pathx.join(book_root, promoted_path)
  if !exists || content.length() == 0 {
    return {
      "promoted": false,
      "source_path": path,
      "promoted_path": promoted_path,
      "promoted_absolute_path": promoted_absolute,
      "status": "missing-source",
    }
  }
  @fsx.make_directory(
    @pathx.dirname(promoted_absolute),
    recursive=true,
    exists_ok=true,
  ) catch {
    error =>
      return {
        "promoted": false,
        "source_path": path,
        "promoted_path": promoted_path,
        "promoted_absolute_path": promoted_absolute,
        "status": "failed",
        "error": "\{error}",
      }
  }
  @fsx.write_to_file(promoted_absolute, content) catch {
    error =>
      return {
        "promoted": false,
        "source_path": path,
        "promoted_path": promoted_path,
        "promoted_absolute_path": promoted_absolute,
        "status": "failed",
        "error": "\{error}",
      }
  }
  {
    "promoted": true,
    "source_path": path,
    "promoted_path": promoted_path,
    "promoted_absolute_path": promoted_absolute,
    "status": "promoted",
    "size_bytes": content.length(),
    "sha256_base64": mooncode_runtime_turn_sha256_base64(content),
  }
}

///|
fn mooncode_runtime_turn_source_present_count(inventory : Array[Json]) -> Int {
  let mut count = 0
  for record in inventory {
    if mooncode_json_bool(record, "package_ready", default=false) {
      count += 1
    }
  }
  count
}

///|
fn mooncode_runtime_turn_source_promoted_count(inventory : Array[Json]) -> Int {
  let mut count = 0
  for record in inventory {
    if mooncode_json_bool(record, "promoted", default=false) {
      count += 1
    }
  }
  count
}

///|
fn mooncode_runtime_turn_package_owner() -> Json {
  {
    "ui": "moondesk",
    "runtime": "moonclaw",
    "artifact": "moonbook",
    "package": "moonbook",
    "extractable_component": "mooncode",
  }
}

///|
async fn mooncode_runtime_turn_write_json_manifest(
  book_root : String,
  relative_path : String,
  manifest : Json,
) -> Unit {
  if relative_path == "" {
    return
  }
  let absolute = @pathx.join(book_root, relative_path)
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  @fsx.write_to_file(absolute, manifest.stringify(indent=2))
}

///|
fn mooncode_runtime_turn_string_json_array(
  paths : Array[String],
) -> Array[Json] {
  let items : Array[Json] = []
  for path in paths {
    items.push(path.to_json())
  }
  items
}

///|
fn mooncode_runtime_turn_string_array_contains(
  values : Array[String],
  value : String,
) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}
