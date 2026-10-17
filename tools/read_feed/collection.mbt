///|
/// One explicitly supplied observation. Source is its logical feed identity and
/// relative-link base; label describes the observation without implying freshness.
pub(all) struct FeedSnapshot {
  source : String
  label : String
  body : String
}

///|
pub struct CollectionSource {
  source : String
  label : String
  title : String
  format : String
  total_items : Int32
  matched_items : Int32
  next_url : String?
}

///|
pub extend CollectionSource with ToJson::{to_json}

///|
pub impl ToJson for CollectionSource with fn to_json(self : CollectionSource) -> Json {
  {
    "source": self.source,
    "label": self.label,
    "title": self.title,
    "format": self.format,
    "total_items": self.total_items,
    "matched_items": self.matched_items,
    "next_url": optional_text(self.next_url),
  }
}

///|
/// article_index is the zero-based position in the supplied source document.
/// Repeated publisher IDs and syndicated articles are deliberately retained.
pub struct CollectionArticle {
  source : String
  label : String
  source_title : String
  article_index : Int32
  article : FeedArticle
} derive(ToJson)

///|
pub extend CollectionArticle with ToJson::{to_json}

///|
pub struct FeedCollectionPage {
  title : String
  sources : Array[CollectionSource]
  articles : Array[CollectionArticle]
  total_items : Int32
  matched_items : Int32
  offset : Int32
  next_offset : Int32?
  query : String
  source_filter : String
}

///|
pub extend FeedCollectionPage with ToJson::{to_json}

///|
let collection_scope : String = "Only supplied snapshots are searched, in source order then publisher order. No fetching, date sorting or deduplication. Summaries contain at most 2000 Unicode characters; snapshot freshness is not verified."

///|
pub impl ToJson for FeedCollectionPage with fn to_json(
  self : FeedCollectionPage,
) -> Json {
  {
    "schema_version": 1,
    "title": self.title,
    "sources": self.sources,
    "articles": self.articles,
    "total_items": self.total_items,
    "matched_items": self.matched_items,
    "offset": self.offset,
    "next_offset": match self.next_offset {
      Some(offset) => offset.to_json()
      None => Json::null()
    },
    "query": self.query,
    "source_filter": self.source_filter,
    "scope": collection_scope,
  }
}

///|
fn check_collection_options(limit : Int32, offset : Int32) -> Unit raise {
  guard limit >= 1 && limit <= 50 && offset >= 0 else {
    fail("limit must be 1..50 and offset must be nonnegative")
  }
}

///|
/// Search every supplied RSS, Atom or JSON Feed observation before paging.
/// Source identities must be unique; articles themselves are never deduplicated.
/// Source filtering is exact, and query searches the normalized article fields
/// including publisher date. Neither option excludes documents from validation.
///
/// ```mbt check
/// test {
///   let saved : @read_feed.FeedSnapshot = {
///     source: "https://example.test/feed",
///     label: "Saved research",
///     body: "{\"version\":\"https://jsonfeed.org/version/1.1\",\"title\":\"Notes\",\"items\":[{\"id\":\"1\",\"title\":\"Moon sample\"}]}",
///   }
///   let page = @read_feed.collect_feeds([saved], query="moon")
///   assert_eq(page.matched_items, 1)
///   assert_eq(page.articles[0].label, "Saved research")
///   assert_true(page.to_markdown().contains("Moon sample"))
/// }
/// ```
pub fn collect_feeds(
  snapshots : Array[FeedSnapshot],
  title~ : String = "Feed collection",
  query~ : String = "",
  source~ : String = "",
  limit~ : Int32 = 50,
  offset~ : Int32 = 0,
) -> FeedCollectionPage raise {
  check_collection_options(limit, offset)
  guard snapshots.length() <= 32 else {
    fail("A collection supports at most 32 source snapshots")
  }
  let seen : Map[String, Bool] = Map([])
  let mut size = 0
  for snapshot in snapshots {
    guard !snapshot.source.trim().is_empty() else {
      fail("Each snapshot requires a nonblank source identity")
    }
    guard !seen.contains(snapshot.source) else {
      fail("Duplicate source identity: \{snapshot.source}")
    }
    seen[snapshot.source] = true
    guard snapshot.body.length() <= 4194304 else {
      fail("Feed document exceeds 4 Mi UTF-16 code units: \{snapshot.source}")
    }
    size += snapshot.body.length()
    guard size <= 16777216 else {
      fail("Collection documents exceed 16 Mi UTF-16 code units")
    }
  }
  guard source.is_empty() || seen.contains(source) else {
    fail("Source filter does not name a supplied snapshot: \{source}")
  }
  let query = query.trim().to_owned()
  let needle = query.to_lower()
  let sources : Array[CollectionSource] = []
  let matching : Array[CollectionArticle] = []
  let mut total_items = 0
  for snapshot in snapshots {
    let document = parse_feed_document(snapshot.body, snapshot.source) catch {
      error => fail("Could not parse source \{snapshot.source}: \{error}")
    }
    total_items += document.articles.length()
    let mut matched_items = 0
    for index, article in document.articles {
      if (source.is_empty() || source == snapshot.source) &&
        (needle.is_empty() || article_matches(Some(article), needle)) {
        matched_items += 1
        matching.push({
          source: snapshot.source,
          label: snapshot.label,
          source_title: document.title,
          article_index: index,
          article,
        })
      }
    }
    sources.push({
      source: snapshot.source,
      label: snapshot.label,
      title: document.title,
      format: document.format,
      total_items: document.articles.length(),
      matched_items,
      next_url: document.next_url,
    })
  }
  let start = Int32::min(offset, matching.length())
  let end = start + Int32::min(limit, matching.length() - start)
  {
    title,
    sources,
    articles: matching[start:end].to_owned(),
    total_items,
    matched_items: matching.length(),
    offset,
    next_offset: if end < matching.length() {
      Some(end)
    } else {
      None
    },
    query,
    source_filter: source,
  }
}
