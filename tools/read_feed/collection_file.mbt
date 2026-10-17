///|
fn collection_text(
  fields : Map[String, Json],
  key : String,
  fallback? : String,
) -> String raise {
  match fields.get(key) {
    Some(String(value)) => value
    None =>
      match fallback {
        Some(value) => value
        None => fail("Collection field \{key} is required")
      }
    _ => fail("Collection field \{key} must be a string")
  }
}

///|
/// Read a local JSON manifest and its explicitly named local feed files.
/// Relative paths resolve beside the manifest, never against the current cwd.
/// The logical source URL is used only for identity and relative XML links.
/// This does not use the provider registry, fetch URLs or write any files.
pub async fn read_feed_collection(
  manifest_path : String,
  query~ : String = "",
  source~ : String = "",
  limit~ : Int32 = 50,
  offset~ : Int32 = 0,
) -> FeedCollectionPage {
  check_collection_options(limit, offset)
  let (title, snapshots) = load_feed_snapshots(manifest_path)
  collect_feeds(snapshots, title~, query~, source~, limit~, offset~)
}

///|
async fn load_feed_snapshots(
  manifest_path : String,
) -> (String, Array[FeedSnapshot]) {
  let body = @fsx.read_file(manifest_path)
  guard body.length() <= 1048576 else {
    fail("Collection manifest exceeds 1 Mi UTF-16 code units")
  }
  guard @json.parse(body) is Object(fields) else {
    fail("Collection manifest must be a JSON object")
  }
  for key, _ in fields {
    guard key is ("title" | "sources") else {
      fail("Unknown collection field: \{key}")
    }
  }
  let title = collection_text(fields, "title", fallback="Feed collection")
  guard fields.get("sources") is Some(Array(entries)) else {
    fail("Collection sources must be an array")
  }
  guard entries.length() <= 32 else {
    fail("A collection supports at most 32 source snapshots")
  }
  let snapshots : Array[FeedSnapshot] = []
  let seen : Map[String, Bool] = Map([])
  let mut size = 0
  for index, entry in entries {
    guard entry is Object(fields) else {
      fail("Collection source \{index} must be an object")
    }
    for key, _ in fields {
      guard key is ("source" | "label" | "path") else {
        fail("Unknown collection source field: \{key}")
      }
    }
    let source = collection_text(fields, "source")
    guard !source.trim().is_empty() else {
      fail("Each snapshot requires a nonblank source identity")
    }
    guard !seen.contains(source) else {
      fail("Duplicate source identity: \{source}")
    }
    seen[source] = true
    let label = collection_text(fields, "label", fallback=source)
    let path = collection_text(fields, "path")
    guard !path.trim().is_empty() && !path.contains("://") else {
      fail("Collection path must name a local file: source \{index}")
    }
    let path = if @pathx.is_absolute(path) {
      path
    } else {
      @pathx.join(@pathx.dirname(manifest_path), path)
    }
    let body = @fsx.read_file(path)
    guard body.length() <= 4194304 else {
      fail("Feed document exceeds 4 Mi UTF-16 code units: \{source}")
    }
    size += body.length()
    guard size <= 16777216 else {
      fail("Collection documents exceed 16 Mi UTF-16 code units")
    }
    snapshots.push({ source, label, body, })
  }
  (title, snapshots)
}
