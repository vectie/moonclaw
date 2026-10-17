///|
fn shortlist_object(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise {
  guard value is Object(fields) else { fail("Expected a shortlist object") }
  for key, _ in fields {
    guard allowed.contains(key) else { fail("Unknown shortlist field: \{key}") }
  }
  fields
}

///|
fn shortlist_text(fields : Map[String, Json], key : String) -> String raise {
  guard fields.get(key) is Some(String(text)) else {
    fail("\{key} must be a string")
  }
  text
}

///|
fn shortlist_optional_text(
  fields : Map[String, Json],
  key : String,
) -> String? raise {
  match fields.get(key) {
    Some(Null) => None
    Some(String(text)) => Some(text)
    _ => fail("\{key} must be a string or null")
  }
}

///|
fn shortlist_integer(fields : Map[String, Json], key : String) -> Int32 raise {
  match fields.get(key) {
    Some(Number(n, ..)) if n >= 0 &&
      n <= 2147483647.0 &&
      n == n.to_int().to_double() => n.to_int()
    _ => fail("\{key} must be a nonnegative integer")
  }
}

///|
fn shortlist_state(state : String) -> Bool {
  state is ("unread" | "reading" | "read")
}

///|
fn shortlist_order(
  value : Json,
  known : Map[String, Bool],
) -> Array[String] raise {
  guard value is Array(values) else { fail("order must be an array") }
  guard values.length() <= 1000 else { fail("Too many selected articles") }
  let seen : Map[String, Bool] = Map([])
  let order : Array[String] = []
  for value in values {
    guard value is String(id) else {
      fail("order entries must be entry_id strings")
    }
    guard known.contains(id) else { fail("Unknown selected entry_id: \{id}") }
    guard !seen.contains(id) else { fail("Duplicate selected entry_id: \{id}") }
    seen[id] = true
    order.push(id)
  }
  order
}

///|
fn shortlist_snapshot(value : Json) -> ShortlistSnapshot raise {
  let fields = shortlist_object(value, [
    "source", "label", "source_title", "format", "body_sha256", "article_index",
    "article",
  ])
  let source = shortlist_text(fields, "source")
  guard !source.trim().is_empty() else {
    fail("Snapshot source must be nonblank")
  }
  let format = shortlist_text(fields, "format")
  guard format is ("rss" | "atom" | "json-feed") else {
    fail("Unknown snapshot format")
  }
  let body_sha256 = shortlist_text(fields, "body_sha256")
  guard body_sha256.length() == 64 &&
    body_sha256.to_array().all(c => c is ('0'..<='9' | 'a'..<='f')) else {
    fail("body_sha256 must be a lowercase SHA-256 digest")
  }
  let article_fields = shortlist_object(
    fields.get("article").unwrap_or(Json::null()),
    ["id", "title", "date_published", "summary", "url"],
  )
  let summary = shortlist_text(article_fields, "summary")
  guard summary.to_array().length() <= 2000 else {
    fail("Snapshot summary exceeds 2000 Unicode characters")
  }
  {
    source,
    label: shortlist_text(fields, "label"),
    source_title: shortlist_text(fields, "source_title"),
    format,
    body_sha256,
    article_index: shortlist_integer(fields, "article_index"),
    article: {
      id: shortlist_text(article_fields, "id"),
      title: shortlist_text(article_fields, "title"),
      date_published: shortlist_optional_text(article_fields, "date_published"),
      summary,
      url: shortlist_optional_text(article_fields, "url"),
    },
  }
}

///|
/// Reopen only the archive. Validate schema, identity, state and selection before
/// returning anything. Digests detect accidental payload edits, not forgery.
pub fn parse_reading_shortlist(text : String) -> ReadingShortlist raise {
  guard text.length() <= 16777216 else {
    fail("Shortlist archive exceeds 16 Mi UTF-16 code units")
  }
  let fields = shortlist_object(@json.parse(text), [
    "schema", "schema_version", "title", "entries", "order",
  ])
  guard shortlist_text(fields, "schema") == "moonclaw.reading-shortlist" &&
    shortlist_integer(fields, "schema_version") == 1 else {
    fail("Unsupported reading shortlist schema")
  }
  let title = shortlist_text(fields, "title")
  guard title.length() <= 4096 else {
    fail("Shortlist title exceeds 4096 code units")
  }
  guard fields.get("entries") is Some(Array(values)) && values.length() <= 1000 else {
    fail("entries must be an array of at most 1000 captured articles")
  }
  let entries : Array[ShortlistEntry] = []
  let known : Map[String, Bool] = Map([])
  for value in values {
    let fields = shortlist_object(value, [
      "entry_id", "snapshot", "state", "note",
    ])
    let entry_id = shortlist_text(fields, "entry_id")
    guard !known.contains(entry_id) else {
      fail("Duplicate captured entry_id: \{entry_id}")
    }
    let snapshot = shortlist_snapshot(
      fields.get("snapshot").unwrap_or(Json::null()),
    )
    guard entry_id == shortlist_id(snapshot) else {
      fail("Snapshot identity mismatch: \{entry_id}")
    }
    let state = shortlist_text(fields, "state")
    guard shortlist_state(state) else {
      fail("state must be unread, reading or read")
    }
    let note = shortlist_text(fields, "note")
    guard note.length() <= 16384 else { fail("note exceeds 16384 code units") }
    known[entry_id] = true
    entries.push({ entry_id, snapshot, state, note, })
  }
  let order = shortlist_order(
    fields.get("order").unwrap_or(Json::null()),
    known,
  )
  { title, entries, order, }
}

///|
pub async fn read_reading_shortlist(path : String) -> ReadingShortlist {
  parse_reading_shortlist(@fsx.read_file(path))
}
