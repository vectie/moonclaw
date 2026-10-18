///|
pub struct FeedArticle {
  id : String
  title : String
  date_published : String?
  summary : String
  url : String?
}

///|
pub struct FeedPage {
  source : String
  title : String
  articles : Array[FeedArticle]
  offset : Int32
  next_offset : Int32?
  next_url : String?
  total_items : Int32
  matched_items : Int32
  format : String
  query : String
}

///|
fn optional_text(value : String?) -> Json {
  match value {
    Some(value) => Json(value)
    None => Json::null()
  }
}

///|
pub impl ToJson for FeedArticle with fn to_json(self : FeedArticle) -> Json {
  {
    "id": self.id,
    "title": self.title,
    "date_published": optional_text(self.date_published),
    "summary": self.summary,
    "url": optional_text(self.url),
  }
}

///|
pub impl ToJson for FeedPage with fn to_json(self : FeedPage) -> Json {
  {
    "source": self.source,
    "title": self.title,
    "articles": self.articles,
    "offset": self.offset,
    "next_offset": match self.next_offset {
      Some(value) => Json(value)
      None => Json::null()
    },
    "next_url": optional_text(self.next_url),
    "total_items": self.total_items,
    "matched_items": self.matched_items,
    "format": self.format,
    "query": self.query,
  }
}

///|
fn text_field(value : Json, key : String) -> String? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
/// Read one JSON Feed, RSS 2.0 or Atom document. Filter before pagination;
/// next_url is exposed only after its final local page, never fetched implicitly.
pub fn parse_feed(
  body : String,
  source : String,
  limit~ : Int32 = 10,
  offset~ : Int32 = 0,
  query~ : String = "",
) -> FeedPage raise {
  guard limit >= 1 && limit <= 50 && offset >= 0 else {
    fail("limit must be 1..50 and offset must be nonnegative")
  }
  let document = parse_feed_document(body, source)
  let query = query.trim().to_owned()
  let needle = query.to_lower()
  let matching = document.articles.filter(article => {
    needle.is_empty() ||
    (article.title +
    "\n" +
    article.summary +
    "\n" +
    article.id +
    "\n" +
    article.url.unwrap_or(""))
    .to_lower()
    .contains(needle)
  })
  let start = Int32::min(offset, matching.length())
  let end = start + Int32::min(limit, matching.length() - start)
  {
    source,
    title: document.title,
    articles: matching[start:end].to_owned(),
    offset,
    next_offset: if end < matching.length() {
      Some(end)
    } else {
      None
    },
    next_url: if end == matching.length() {
      document.next_url
    } else {
      None
    },
    total_items: document.articles.length(),
    matched_items: matching.length(),
    format: document.format,
    query,
  }
}

///|
priv struct FeedDocument {
  title : String
  articles : Array[FeedArticle]
  next_url : String?
  format : String
}

///|
// Share whole-document normalization with observation comparison. Presentation
// pagination must never decide which articles participate in a comparison.
fn parse_feed_document(body : String, source : String) -> FeedDocument raise {
  guard body.length() <= 4194304 else {
    fail("Feed document exceeds 4 Mi UTF-16 code units")
  }
  let body = if body.has_prefix("\u{FEFF}") {
    body[1:].to_owned()
  } else {
    body
  }
  if body.trim_start().has_prefix("<") {
    parse_xml_feed(body, source)
  } else {
    parse_json_feed(body)
  }
}

///|
fn short_summary(text : String) -> String {
  String::from_array(text.to_array().iter().take(2000).collect())
}

///|
fn parse_json_feed(body : String) -> FeedDocument raise {
  let json = @json.parse(body)
  guard text_field(json, "version")
    is Some(
      "https://jsonfeed.org/version/1"
      | "https://jsonfeed.org/version/1.1"
    ) else {
    fail("Expected JSON Feed version 1 or 1.1, RSS 2.0 or Atom")
  }
  guard text_field(json, "title") is Some(title) else {
    fail("Feed title is required")
  }
  guard json is { "items": Array(items), .. } else {
    fail("Feed items array is required")
  }
  let articles = items.map(item => {
    guard text_field(item, "id") is Some(id) else {
      fail("Feed item id is required")
    }
    let summary = text_field(item, "summary").unwrap_or(
      text_field(item, "content_text").unwrap_or(""),
    )
    // Keep output compact and Unicode-safe. HTML is never executed or rendered.
    let summary = short_summary(summary)
    FeedArticle::{
      id,
      title: text_field(item, "title").unwrap_or("(untitled)"),
      date_published: text_field(item, "date_published"),
      summary,
      url: match text_field(item, "url") {
        Some(url) => Some(url)
        None => text_field(item, "external_url")
      },
    }
  })
  {
    title,
    articles,
    next_url: text_field(json, "next_url"),
    format: "json-feed",
  }
}

///|
pub extend FeedArticle with Show::{to_string, output}

///|
pub extend FeedPage with Show::{to_string, output}

///|
pub extend FeedArticle with ToJson::{to_json}

///|
pub extend FeedPage with ToJson::{to_json}

///|
pub impl Show for FeedArticle with fn output(self, logger) {
  logger.write_string(
    "{id: \{self.id}, title: \{self.title}, date_published: \{feed_show_optional(self.date_published)}, summary: \{self.summary}, url: \{feed_show_optional(self.url)}}",
  )
}

///|
pub impl Show for FeedPage with fn output(self, logger) {
  logger.write_string(
    "{source: \{self.source}, title: \{self.title}, articles: \{feed_show_array(self.articles)}, offset: \{self.offset}, next_offset: \{feed_show_optional(self.next_offset)}, next_url: \{feed_show_optional(self.next_url)}, total_items: \{self.total_items}, matched_items: \{self.matched_items}, format: \{self.format}, query: \{self.query}}",
  )
}
