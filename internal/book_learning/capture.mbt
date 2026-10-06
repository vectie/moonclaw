///|
priv struct Inventory {
  paths : Array[String]
  mut count : Int
  mut admitted : Int
  mut excluded : Int
}

///|
/// Bounds iteration before materializing directory names; never follows links.
async fn inventory(
  root : String,
  relative : String,
  result : Inventory,
) -> Unit {
  let path = root + "/" + relative
  if !@fs.exists(path) {
    return
  }
  guard @fs.kind(path, follow_symlink=false) == Directory else {
    fail("unsafe_memory_directory")
  }
  let directory = @fs.opendir(path)
  defer directory.close()
  while directory.next(include_hidden=true) is Some(entry) {
    result.count += 1
    if result.count > 256 {
      fail("scan_entry_budget")
    }
    let relative = relative + "/" + entry.name
    if entry.name.contains("\\") || entry.name == "." || entry.name == ".." {
      fail("unsafe_memory_entry")
    }
    let path = root + "/" + relative
    match @fs.kind(path, follow_symlink=false) {
      Directory => inventory(root, relative, result)
      Regular => result.paths.push(relative)
      _ => fail("unsafe_memory_entry")
    }
  }
}

///|
async fn inventory_all(
  root : String,
  result? : Inventory = { paths: [], count: 0, admitted: 0, excluded: 0, },
) -> Inventory {
  if @fs.exists(root + "/memory") {
    guard @fs.kind(root + "/memory", follow_symlink=false) == Directory else {
      fail("unsafe_memory_directory")
    }
  }
  inventory(root, "memory/procedures", result)
  inventory(root, "memory/beliefs", result)
  result.paths.sort()
  result
}

///|
/// Reads bounded bytes through a descriptor, preserving BOM and all line endings.
async fn read_record(root : String, path : String) -> Bytes {
  let full = root + "/" + path
  guard @fs.kind(full, follow_symlink=false) == Regular &&
    @fs.realpath(full) == full else {
    fail("unsafe_memory_entry")
  }
  let file = @fs.open(full, mode=ReadOnly)
  defer file.close()
  guard file.kind() == Regular else { fail("unsafe_memory_entry") }
  let size = file.size()
  if size > 32768L {
    fail("per_file_byte_budget")
  }
  let bytes = file.read_exactly(size.to_int())
  guard file.size() == size &&
    @fs.kind(full, follow_symlink=false) == Regular &&
    @fs.realpath(full) == full else {
    fail("source_changed_during_capture")
  }
  bytes
}

///|
async fn installation_lineage(root : String) -> Json {
  let path = "state/agent-installation.json"
  if !@fs.exists(root + "/" + path) {
    return Json::null()
  }
  // Lineage is optional ancestry, never admission or permission.
  if @fs.kind(root + "/state", follow_symlink=false) != Directory {
    return Json::null()
  }
  let value = @json.parse(
    @utf8.decode(read_record(root, path), ignore_bom=false),
  ) catch {
    error =>
      if @async.is_being_cancelled() {
        raise error
      } else {
        return Json::null()
      }
  }
  match value {
    {
      "agent_id": String(agent_id),
      "version": String(version),
      "bundle_digest": String(bundle_digest),
      "receipt_path": String(receipt_path),
      ..
    } =>
      {
        "agent_id": agent_id,
        "version": version,
        "bundle_digest": bundle_digest,
        "receipt_path": receipt_path,
      }
    _ => Json::null()
  }
}

///|
async fn capture_ready(
  binding : Binding,
  captured_at : Int,
  progress : Inventory,
  before_recheck? : async () -> Unit,
) -> Snapshot {
  let root = @fs.realpath(binding.source_root)
  guard @fs.kind(root) == Directory else { fail("source_root_not_canonical") }
  let before = inventory_all(root, result=progress)
  let records : Array[Record] = []
  let hashes : Map[String, String] = {}
  let mut excluded = 0
  let mut size = 0
  for path in before.paths {
    let bytes = read_record(root, path)
    let content = @utf8.decode(bytes, ignore_bom=false) catch {
      _ => fail("invalid_utf8")
    }
    hashes[path] = digest(bytes)
    if review_status(content) != "accepted" {
      excluded += 1
      progress.excluded += 1
      continue
    }
    progress.admitted += 1
    size += bytes.length()
    if records.length() >= 32 {
      fail("accepted_record_budget")
    }
    if size > 65536 {
      fail("aggregate_record_byte_budget")
    }
    records.push({
      path,
      category: if path.has_prefix("memory/procedures/") {
        "procedure"
      } else {
        "belief"
      },
      format: match (try? @json.parse(content)) {
        Ok(Object(_)) => "json"
        _ => "text"
      },
      size_bytes: bytes.length(),
      sha256: digest(bytes),
      content_utf8: content,
    })
  }
  if before_recheck is Some(hook) {
    hook()
  }
  let after = inventory_all(root)
  guard before.paths == after.paths && before.count == after.count else {
    fail("source_changed_during_capture")
  }
  for path in after.paths {
    guard hashes[path] == digest(read_record(root, path)) else {
      fail("source_changed_during_capture")
    }
  }
  guard @fs.realpath(binding.source_root) == root else {
    fail("source_changed_during_capture")
  }
  let snapshot = seal({
    ..empty(
      binding,
      if records.is_empty() {
        "empty"
      } else {
        "ready"
      },
      captured_at,
    ),
    records,
    observed_entries: before.count,
    admitted_records: records.length(),
    excluded_records: excluded,
    installation_lineage: installation_lineage(root),
  })
  if @utf8.encode(snapshot.to_json().stringify()).length() > 524288 {
    fail("snapshot_byte_budget")
  }
  snapshot
}

///|
/// Host-only capture. Optional learning never blocks unrelated ordinary work.
pub async fn capture(binding : Binding, captured_at : Int) -> Snapshot {
  capture_impl(binding, captured_at)
}

///|
async fn capture_impl(
  binding : Binding,
  captured_at : Int,
  before_recheck? : async () -> Unit,
) -> Snapshot {
  if binding.workspace_id.is_empty() || binding.book_id.is_empty() {
    return empty(binding, "not_applicable", captured_at)
  }
  let progress = Inventory::{ paths: [], count: 0, admitted: 0, excluded: 0, }
  capture_ready(binding, captured_at, progress, before_recheck?) catch {
    error => {
      if @async.is_being_cancelled() {
        raise error
      }
      let message = error.to_string()
      let codes = [
        "scan_entry_budget", "per_file_byte_budget", "accepted_record_budget", "aggregate_record_byte_budget",
        "snapshot_byte_budget", "unsafe_memory_directory", "unsafe_memory_entry",
        "source_root_not_canonical", "source_changed_during_capture", "invalid_utf8",
      ]
      let mut reason = "memory_read_unavailable"
      for code in codes {
        if message.contains(code) {
          reason = code
          break
        }
      }
      seal({
        ..empty(
          binding,
          if reason.contains("budget") {
            "over_budget"
          } else {
            "unavailable"
          },
          captured_at,
        ),
        observed_entries: progress.count,
        admitted_records: progress.admitted,
        excluded_records: progress.excluded,
        reasons: [reason],
      })
    }
  }
}
