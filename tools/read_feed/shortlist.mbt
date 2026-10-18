///|
priv struct ShortlistSnapshot {
  source : String
  label : String
  source_title : String
  format : String
  body_sha256 : String
  article_index : Int32
  article : FeedArticle
} derive(ToJson)

///|
extend ShortlistSnapshot with ToJson::{to_json}

///|
priv struct ShortlistEntry {
  entry_id : String
  snapshot : ShortlistSnapshot
  state : String
  note : String
} derive(ToJson)

///|
extend ShortlistEntry with ToJson::{to_json}

///|
/// A captured catalog and an ordered selection. Private fields prevent mutation
/// of saved snapshots; edits return a new value and never reopen source feeds.
pub struct ReadingShortlist {
  priv title : String
  priv entries : Array[ShortlistEntry]
  priv order : Array[String]
}

///|
pub extend ReadingShortlist with ToJson::{to_json}

///|
let shortlist_scope : String = "Saved normalized article snapshots, not full articles. Summaries contain at most 2000 Unicode characters. Source labels are caller assertions, not verified capture times. No fetching, refresh, remapping, deduplication or acceptance of publisher claims."

///|
fn shortlist_digest(text : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
fn shortlist_id(snapshot : ShortlistSnapshot) -> String {
  "article-" +
  shortlist_digest("moonclaw-shortlist-v1\n" + snapshot.to_json().stringify())
}

///|
pub impl ToJson for ReadingShortlist with fn to_json(self : ReadingShortlist) -> Json {
  {
    "schema": "moonclaw.reading-shortlist",
    "schema_version": 1,
    "title": self.title,
    "entries": self.entries.map(entry => entry.to_json()),
    "order": self.order,
  }
}

///|
/// Capture all supplied snapshots, independently of collection search and paging.
/// Nothing is selected initially. Publisher IDs/URLs are not identity keys.
pub fn capture_reading_shortlist(
  snapshots : Array[FeedSnapshot],
  title~ : String = "Reading shortlist",
) -> ReadingShortlist raise {
  // Reuse the collection's whole-input and source-identity validation.
  let page = collect_feeds(snapshots)
  guard page.total_items <= 1000 else {
    fail("A reading shortlist supports at most 1000 captured articles")
  }
  guard title.length() <= 4096 else {
    fail("Shortlist title exceeds 4096 code units")
  }
  let entries : Array[ShortlistEntry] = []
  for input in snapshots {
    let document = parse_feed_document(input.body, input.source)
    let body_sha256 = shortlist_digest(input.body)
    for article_index, article in document.articles {
      let snapshot : ShortlistSnapshot = {
        source: input.source,
        label: input.label,
        source_title: document.title,
        format: document.format,
        body_sha256,
        article_index,
        article,
      }
      entries.push({
        entry_id: shortlist_id(snapshot),
        snapshot,
        state: "unread",
        note: "",
      })
    }
  }
  let result = ReadingShortlist::{ title, entries, order: [], }
  ignore(result.to_archive())
  result
}

///|
/// Capture a local collection manifest once. Subsequent archive operations do
/// not consult this manifest or its source files.
pub async fn capture_reading_shortlist_file(
  manifest_path : String,
) -> ReadingShortlist {
  let (title, snapshots) = load_feed_snapshots(manifest_path)
  capture_reading_shortlist(snapshots, title~)
}

///|
/// Serialize the complete catalog, notes and ordered selection for later reopen.
pub fn ReadingShortlist::to_archive(self : ReadingShortlist) -> String raise {
  let text = self.to_json().stringify()
  guard text.length() <= 16777216 else {
    fail("Shortlist archive exceeds 16 Mi UTF-16 code units")
  }
  text
}

///|
/// Return a fresh, searchable overview with stable IDs for explicit selection.
pub fn ReadingShortlist::catalog(
  self : ReadingShortlist,
  query~ : String = "",
) -> Json {
  let needle = query.trim().to_owned().to_lower()
  let selected : Map[String, Int32] = Map([])
  for index, id in self.order {
    selected[id] = index + 1
  }
  let rows : Array[Json] = []
  for entry in self.entries {
    let snapshot = entry.snapshot
    if needle.is_empty() ||
      (snapshot.article.title +
      "\n" +
      snapshot.article.summary +
      "\n" +
      snapshot.source +
      "\n" +
      entry.note)
      .to_lower()
      .contains(needle) {
      rows.push({
        "entry_id": entry.entry_id,
        "title": snapshot.article.title,
        "source": snapshot.source,
        "label": snapshot.label,
        "article_index": snapshot.article_index,
        "state": entry.state,
        "note": entry.note,
        "position": match selected.get(entry.entry_id) {
          Some(position) => Json(position)
          None => Json::null()
        },
      })
    }
  }
  {
    "title": self.title,
    "total_captured": self.entries.length(),
    "selected": self.order.length(),
    "articles": rows,
  }
}

///|
/// Apply an explicit full selection/order and/or note/status updates atomically.
/// Omitted fields retain their values. Deselection keeps the snapshot and notes.
pub fn ReadingShortlist::edit(
  self : ReadingShortlist,
  changes : Json,
) -> ReadingShortlist raise {
  let fields = shortlist_object(changes, ["title", "order", "annotations"])
  let title = match fields.get("title") {
    None => self.title
    Some(String(title)) if title.length() <= 4096 => title
    _ => fail("Shortlist title must be a string of at most 4096 code units")
  }
  let known : Map[String, Bool] = Map([])
  for entry in self.entries {
    known[entry.entry_id] = true
  }
  let order = match fields.get("order") {
    None => self.order.copy()
    Some(value) => shortlist_order(value, known)
  }
  let updates : Map[String, (String?, String?)] = Map([])
  match fields.get("annotations") {
    None => ()
    Some(Array(values)) => {
      guard values.length() <= 1000 else { fail("Too many annotations") }
      for value in values {
        let item = shortlist_object(value, ["entry_id", "state", "note"])
        let id = shortlist_text(item, "entry_id")
        guard known.contains(id) else {
          fail("Unknown annotation entry_id: \{id}")
        }
        guard !updates.contains(id) else {
          fail("Duplicate annotation entry_id: \{id}")
        }
        let state = match item.get("state") {
          None => None
          Some(String(state)) if shortlist_state(state) => Some(state)
          _ => fail("state must be unread, reading or read")
        }
        let note = match item.get("note") {
          None => None
          Some(String(note)) if note.length() <= 16384 => Some(note)
          _ => fail("note must be a string of at most 16384 code units")
        }
        updates[id] = (state, note)
      }
    }
    _ => fail("annotations must be an array")
  }
  let entries = self.entries.map(entry => {
    match updates.get(entry.entry_id) {
      None => entry
      Some((state, note)) =>
        {
          entry_id: entry.entry_id,
          snapshot: entry.snapshot,
          state: state.unwrap_or(entry.state),
          note: note.unwrap_or(entry.note),
        }
    }
  })
  let result = ReadingShortlist::{ title, entries, order, }
  ignore(result.to_archive())
  result
}
