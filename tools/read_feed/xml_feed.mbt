///|
let atom_namespace : String = "http://www.w3.org/2005/Atom"

///|
fn feed_space(text : String) -> String {
  let out = StringBuilder()
  let mut pending = false
  let mut started = false
  for c in text {
    if c is (' ' | '\r' | '\n' | '\t' | '\u{a0}') {
      pending = started
    } else {
      if pending {
        out.write_char(' ')
      }
      out.write_char(c)
      pending = false
      started = true
    }
  }
  out.to_string()
}

///|
/// Produce plain text only, never execute/render publisher markup.
fn feed_html_text(html : String) -> String {
  let out = StringBuilder()
  let lower = html.to_lower()
  let mut pos = 0
  while pos < html.length() {
    if html[pos:].has_prefix("<!--") {
      pos = match html[pos + 4:].find("-->") {
        Some(n) => pos + n + 7
        None => html.length()
      }
    } else if html[pos] == '<' &&
      pos + 1 < html.length() &&
      html[pos + 1] is ('a'..<='z' | 'A'..<='Z' | '/' | '!') {
      let finish = feed_html_tag_end(html, pos)
      let tag = lower[pos + 1:finish - 1].trim().to_owned()
      let start = if tag.has_prefix("/") { 1 } else { 0 }
      let mut end = start
      while end < tag.length() && tag[end] is ('a'..<='z' | '0'..<='9') {
        end += 1
      }
      let name = tag[start:end].to_owned()
      if start == 0 && name is ("script" | "style") {
        let closing = if name == "script" { "</script>" } else { "</style>" }
        pos = match lower[finish:].find(closing) {
          Some(n) => finish + n + closing.length()
          None => html.length()
        }
      } else {
        pos = finish
      }
      if name
        is ("p"
        | "div"
        | "br"
        | "li"
        | "h1"
        | "h2"
        | "h3"
        | "tr"
        | "td"
        | "script"
        | "style") {
        out.write_char(' ')
      }
    } else if html[pos] == '&' {
      match html[pos:].find(";") {
        Some(length) if length <= 16 => {
          let entity = html[pos:pos + length + 1].to_owned()
          let decoded = match entity {
            "&nbsp;" => " "
            "&ndash;" => "–"
            "&mdash;" => "—"
            "&hellip;" => "…"
            "&copy;" => "©"
            _ =>
              match (Ok(xml_entities(entity)) catch { error => Err(error) }) {
                Ok(value) => value
                Err(_) => entity
              }
          }
          out.write_string(decoded)
          pos += length + 1
        }
        _ => {
          out.write_char('&')
          pos += 1
        }
      }
    } else {
      let c = html.get_char(pos).unwrap()
      out.write_char(c)
      pos += if c.to_int() > 0xffff { 2 } else { 1 }
    }
  }
  feed_space(out.to_string())
}

///|
fn feed_html_tag_end(html : String, start : Int32) -> Int32 {
  let mut quote : UInt16 = 0
  for i = start + 1; i < html.length(); i = i + 1 {
    let c = html[i]
    if quote != 0 {
      if c == quote {
        quote = 0
      }
    } else if c is ('\'' | '"') {
      quote = c
    } else if c == '>' {
      return i + 1
    }
  }
  html.length()
}

///|
/// Resolve publisher links against an HTTP source or xml:base. Non-web links
/// remain absent; they are neither fetched nor emitted as clickable article URLs.
fn feed_link(base : String, reference : String) -> String? {
  let reference = reference.trim().to_owned()
  if reference.is_empty() {
    return None
  }
  if reference.has_prefix("https://") || reference.has_prefix("http://") {
    return Some(reference)
  }
  guard base.has_prefix("https://") || base.has_prefix("http://") else {
    return None
  }
  if reference.has_prefix("//") {
    return Some(base[:base.find(":").unwrap() + 1].to_owned() + reference)
  }
  let first_segment = reference
    .split("/")
    .next()
    .unwrap_or("")
    .split("?")
    .next()
    .unwrap_or("")
    .split("#")
    .next()
    .unwrap_or("")
  if first_segment.contains(":") {
    return None
  }
  let scheme_end = base.find("://").unwrap() + 3
  let origin_end = scheme_end +
    Int32::min(
      base[scheme_end:].find("/").unwrap_or(base.length() - scheme_end),
      Int32::min(
        base[scheme_end:].find("?").unwrap_or(base.length() - scheme_end),
        base[scheme_end:].find("#").unwrap_or(base.length() - scheme_end),
      ),
    )
  let origin = base[:origin_end].to_owned()
  let base_path = base[origin_end:]
    .to_owned()
    .split("#")
    .next()
    .unwrap_or("")
    .to_owned()
  if reference.has_prefix("#") {
    return Some(origin + base_path + reference)
  }
  let base_path = base_path.split("?").next().unwrap_or("").to_owned()
  if reference.has_prefix("?") {
    return Some(
      origin + (if base_path.is_empty() { "/" } else { base_path }) + reference,
    )
  }
  let combined = if reference.has_prefix("/") {
    reference
  } else {
    let pieces = base_path.split("/").collect()
    ignore(pieces.pop())
    pieces.join("/") + "/" + reference
  }
  let suffix_start = Int32::min(
    combined.find("?").unwrap_or(combined.length()),
    combined.find("#").unwrap_or(combined.length()),
  )
  let segments : Array[String] = []
  for segment in combined[:suffix_start].split("/") {
    match segment {
      "." | "" => ()
      ".." => ignore(segments.pop())
      _ => segments.push(segment.to_owned())
    }
  }
  let trailing = if combined[:suffix_start].has_suffix("/") &&
    !segments.is_empty() {
    "/"
  } else {
    ""
  }
  Some(
    origin +
    "/" +
    segments.join("/") +
    trailing +
    combined[suffix_start:].to_owned(),
  )
}

///|
fn FeedXml::base(self : FeedXml, parent : String) -> String {
  match self.attrs.get("xml:base") {
    Some(value) => feed_link(parent, value).unwrap_or(parent)
    None => parent
  }
}

///|
fn atom_link(node : FeedXml, relation : String, base : String) -> String? {
  for child in node.children {
    if child.name == "link" &&
      child.ns == atom_namespace &&
      child.attrs.get("rel").unwrap_or("alternate") == relation {
      if child.attrs.get("href") is Some(href) {
        if feed_link(child.base(base), href) is Some(url) {
          return Some(url)
        }
      }
    }
  }
  None
}

///|
fn atom_text(node : FeedXml) -> String {
  match node.attrs.get("type") {
    Some("html" | "text/html") => feed_html_text(node.text)
    Some("text" | "text/plain" | "xhtml") | None => feed_space(node.text)
    _ => ""
  }
}

///|
fn fallback_feed_id(source : String, article : FeedXml) -> String {
  let mut hash : UInt32 = 2166136261
  for byte in @utf8.encode(article.text) {
    hash = (hash ^ byte.to_uint()) * 16777619
  }
  source + "#content-" + hash.to_string()
}

///|
fn parse_xml_feed(body : String, source : String) -> FeedDocument raise {
  let root = read_feed_xml(body)
  let base = root.base(source)
  if root.name == "rss" && root.ns == "" {
    guard root.attrs.get("version") is Some("2.0") else {
      fail("Expected RSS version 2.0")
    }
    guard root.child("channel") is Some(channel) else {
      fail("RSS channel is required")
    }
    guard channel.value("title") is Some(title) else {
      fail("RSS channel title is required")
    }
    let base = channel.base(base)
    let articles = channel.children
      .filter(n => n.name == "item" && n.ns == "")
      .map(item => {
        let base = item.base(base)
        let url = match item.value("link") {
          Some(value) => feed_link(base, value)
          None =>
            match item.child("guid") {
              Some(guid) if guid.attrs.get("isPermaLink").unwrap_or("true") ==
                "true" => feed_link(base, guid.text)
              _ => None
            }
        }
        let title = item.value("title").unwrap_or("(untitled)")
        let summary = item
          .value("description")
          .unwrap_or(
            item
            .value("encoded", ns="http://purl.org/rss/1.0/modules/content/")
            .unwrap_or(""),
          )
        FeedArticle::{
          id: item
          .value("guid")
          .unwrap_or(url.unwrap_or(fallback_feed_id(source, item))),
          title: feed_space(title),
          date_published: feed_or(
            item.value("pubDate"),
            item.value("date", ns="http://purl.org/dc/elements/1.1/"),
          ),
          summary: short_summary(feed_html_text(summary)),
          url,
        }
      })
    {
      title: feed_space(title),
      articles,
      next_url: atom_link(channel, "next", base),
      format: "rss",
    }
  } else if root.name == "feed" && root.ns == atom_namespace {
    guard root.child("title") is Some(title) else {
      fail("Atom feed title is required")
    }
    let articles = root.children
      .filter(n => n.name == "entry" && n.ns == atom_namespace)
      .map(entry => {
        let base = entry.base(base)
        let url = atom_link(entry, "alternate", base)
        let summary = match
          feed_or(entry.child("summary"), entry.child("content")) {
          Some(node) => atom_text(node)
          None => ""
        }
        FeedArticle::{
          id: entry
          .value("id")
          .unwrap_or(url.unwrap_or(fallback_feed_id(source, entry))),
          title: match entry.child("title") {
            Some(node) => atom_text(node)
            None => "(untitled)"
          },
          date_published: feed_or(
            entry.value("published"),
            entry.value("updated"),
          ),
          summary: short_summary(summary),
          url,
        }
      })
    {
      title: atom_text(title),
      articles,
      next_url: atom_link(root, "next", base),
      format: "atom",
    }
  } else {
    fail("Expected RSS 2.0 or Atom feed root")
  }
}

///|
fn[T] feed_or(first : T?, second : T?) -> T? {
  match first {
    Some(_) => first
    None => second
  }
}
