///|
/// Feed candidates discovered in a saved HTML head. JSON can be reviewed and
/// installed as a resource-provider manifest; discovery never fetches a URL.
pub struct FeedDiscovery {
  page_url : String
  base_url : String?
  providers : Array[Json]
  duplicate_links : Int
  rejected_links : Int
  warnings : Array[String]
} derive(Show, ToJson)

///|
/// Discover alternate RSS, Atom and JSON Feed links from a saved HTML head.
/// Resolve against the first base href or the explicitly supplied page URL.
/// Only HTTP(S) links without userinfo are emitted. Stops at an explicit end of
/// head or start of body; omitted-tag browser DOM inference is not performed.
pub fn discover_feeds(
  body : String,
  page_url : String,
  prefix? : String = "html",
) -> FeedDiscovery raise {
  guard body.length() <= 4194304 else {
    fail("HTML document exceeds 4 Mi UTF-16 code units")
  }
  guard !prefix.is_empty() && prefix.length() <= 64 else {
    fail(
      "prefix must contain 1..64 ASCII letters, digits, hyphens or underscores",
    )
  }
  for c in prefix.to_array() {
    guard c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_') else {
      fail(
        "prefix must contain 1..64 ASCII letters, digits, hyphens or underscores",
      )
    }
  }
  guard discovery_absolute(page_url.trim().to_owned()) is Some(page_url) else {
    fail(
      "page_url must be an absolute HTTP(S) URL without userinfo or unsafe characters",
    )
  }
  let cursor = DiscoveryHtml::{ body, lower: discovery_lower(body), pos: 0, }
  let links : Array[DiscoveryTag] = []
  let mut base_href : String? = None
  let mut inert_depth = 0
  while cursor.next() is Some(tag) {
    if tag.name == "template" {
      if tag.closing {
        inert_depth = Int::max(0, inert_depth - 1)
      } else {
        inert_depth += 1
      }
      continue
    }
    if !tag.closing &&
      tag.name is ("script" | "style" | "title" | "textarea" | "noscript") {
      cursor.skip_raw(tag.name)
      continue
    }
    if inert_depth > 0 {
      continue
    }
    if (tag.name == "head" && tag.closing) || tag.name == "body" {
      break
    }
    if tag.closing {
      continue
    }
    if tag.name == "base" &&
      base_href is None &&
      tag.attrs.get("href") is Some(href) {
      base_href = Some(href)
    }
    if tag.name != "link" {
      continue
    }
    let rel = discovery_lower(tag.attrs.get("rel").unwrap_or(""))
    let alternate = rel
      .to_array()
      .map(c => if c is ('\t' | '\r' | '\n' | '\u{000C}') { ' ' } else { c })
    if !String::from_array(alternate)
      .split(" ")
      .any(token => token == "alternate") {
      continue
    }
    let media_type = discovery_lower(
      tag.attrs
      .get("type")
      .unwrap_or("")
      .split(";")
      .next()
      .unwrap_or("")
      .trim()
      .to_owned(),
    )
    if !(media_type
      is ("application/rss+xml"
      | "application/atom+xml"
      | "application/feed+json")) {
      continue
    }
    guard links.length() < 256 else {
      fail("HTML discovery exceeds 256 candidate feed links")
    }
    links.push(tag)
  }
  let warnings : Array[String] = []
  let base_url = match base_href {
    Some(href) => discovery_resolve(href, page_url)
    None => Some(page_url)
  }
  if base_url is None {
    warnings.push(
      "Unsupported first base href; relative feed links were rejected",
    )
  }
  let providers : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let mut duplicate_links = 0
  let mut rejected_links = 0
  for link in links {
    let href = link.attrs.get("href").unwrap_or("").trim().to_owned()
    let endpoint = if href.is_empty() || href.has_prefix("#") {
      None
    } else {
      match base_url {
        Some(base) => discovery_resolve(href, base)
        None => discovery_absolute(href)
      }
    }
    guard endpoint is Some(endpoint) else {
      rejected_links += 1
      warnings.push("Skipped feed link with missing or unsupported HTTP(S) URL")
      continue
    }
    if seen.contains(endpoint) {
      duplicate_links += 1
      continue
    }
    seen[endpoint] = true
    let name = "\{prefix}-\{providers.length() + 1}"
    let title = link.attrs.get("title").unwrap_or("").trim().to_owned()
    providers.push({
      "name": name,
      "title": if title.is_empty() {
        endpoint
      } else {
        title
      },
      "description": "Discovered feed candidate; content has not been fetched or verified",
      "kind": "feed",
      "endpoint": endpoint,
      "capabilities": ["read_feed"],
      "metadata": {
        "import_format": "html-alternate",
        "page_url": page_url,
        "declared_type": discovery_lower(link.attrs.get("type").unwrap_or("")),
        "read_feed": { "source": "provider://\{name}" },
      },
    })
  }
  { page_url, base_url, providers, duplicate_links, rejected_links, warnings, }
}
