///|
/// A portable reading-list import. Its JSON is accepted directly by the
/// existing resource-provider registry; importing never fetches subscriptions.
pub struct FeedCollection {
  title : String
  providers : Array[Json]
  duplicate_feeds : Int32
  skipped_outlines : Int32
  warnings : Array[String]
} derive(Show, ToJson)

///|
priv struct OpmlImport {
  providers : Array[Json]
  seen : Map[String, Bool]
  warnings : Array[String]
  prefix : String
  mut duplicates : Int32
  mut skipped : Int32
}

///|
fn opml_label(node : FeedXml) -> String {
  for key in ["title", "text"] {
    if node.attrs.get(key) is Some(value) && !value.trim().is_empty() {
      return value.trim().to_owned()
    }
  }
  ""
}

///|
fn OpmlImport::outline(
  self : OpmlImport,
  node : FeedXml,
  folders : Array[String],
) -> Unit {
  if node.name != "outline" || !node.ns.is_empty() {
    return
  }
  let label = opml_label(node)
  let endpoint = node.attrs.get("xmlUrl").unwrap_or("").trim().to_owned()
  let is_feed = !endpoint.is_empty()
  if is_feed {
    if !opml_http_url(endpoint) {
      self.skipped += 1
      self.warnings.push(
        "Skipped subscription with unsupported URL; only absolute HTTP(S) URLs without userinfo or whitespace are supported",
      )
    } else if self.seen.contains(endpoint) {
      self.duplicates += 1
    } else {
      self.seen[endpoint] = true
      let name = "\{self.prefix}-\{self.providers.length() + 1}"
      self.providers.push({
        "name": name,
        "title": if label.is_empty() {
          endpoint
        } else {
          label
        },
        "description": node.attrs.get("description").unwrap_or(""),
        "kind": "feed",
        "endpoint": endpoint,
        "capabilities": ["read_feed"],
        "metadata": {
          "import_format": "opml",
          "folders": folders,
          "read_feed": { "source": "provider://\{name}" },
        },
      })
    }
  } else if node.children.is_empty() {
    self.skipped += 1
  }
  let nested = if !is_feed && !label.is_empty() {
    [..folders, label]
  } else {
    folders
  }
  for child in node.children {
    self.outline(child, nested)
  }
}

///|
fn opml_http_url(url : String) -> Bool {
  let rest = if url.has_prefix("https://") {
    url[8:].to_owned()
  } else if url.has_prefix("http://") {
    url[7:].to_owned()
  } else {
    return false
  }
  if rest.is_empty() || rest[0] is ('/' | '?' | '#') {
    return false
  }
  for c in url.to_array() {
    if c.to_int() <= 32 || c.to_int() == 127 {
      return false
    }
  }
  // Keep credential-bearing subscription URLs out of generated registries.
  let end = Int32::min(
    rest.find("/").unwrap_or(rest.length()),
    Int32::min(
      rest.find("?").unwrap_or(rest.length()),
      rest.find("#").unwrap_or(rest.length()),
    ),
  )
  let authority = rest[:end]
  !authority.contains("@")
}

///|
/// Convert UTF-8 OPML 1.0, 1.1 or 2.0 into registered read_feed sources.
/// Exact decoded URLs are deduplicated in document order (first entry wins).
pub fn parse_opml(
  body : String,
  prefix~ : String = "opml",
) -> FeedCollection raise {
  guard !prefix.is_empty() && prefix.length() <= 64 else {
    fail(
      "prefix must contain 1..64 ASCII letters, digits, hyphens or underscores",
    )
  }
  for c in prefix.to_array() {
    guard c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | '_') else {
      fail(
        "prefix must contain 1..64 ASCII letters, digits, hyphens or underscores",
      )
    }
  }
  guard body.length() <= 4194304 else {
    fail("OPML document exceeds 4 Mi UTF-16 code units")
  }
  let root = read_feed_xml(body)
  guard root.name == "opml" && root.ns.is_empty() else {
    fail("Expected an OPML document")
  }
  guard root.attrs.get("version") is Some("1.0" | "1.1" | "2.0") else {
    fail("Expected OPML version 1.0, 1.1 or 2.0")
  }
  guard root.child("body") is Some(outlines) else {
    fail("OPML body is required")
  }
  let title = match root.child("head") {
    Some(head) => head.value("title").unwrap_or("Imported feeds")
    None => "Imported feeds"
  }
  let state = OpmlImport::{
    providers: [],
    seen: {},
    warnings: [],
    prefix,
    duplicates: 0,
    skipped: 0,
  }
  for outline in outlines.children {
    state.outline(outline, [])
  }
  {
    title,
    providers: state.providers,
    duplicate_feeds: state.duplicates,
    skipped_outlines: state.skipped,
    warnings: state.warnings,
  }
}
