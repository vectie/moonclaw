///|
pub struct FeedObservation {
  label : String
  title : String
  format : String
  total_items : Int32
  next_url : String?
}

///|
pub struct FeedChange {
  kind : String
  id : String
  before : FeedArticle?
  after : FeedArticle?
  changed_fields : Array[String]
}

///|
pub struct FeedComparison {
  source : String
  before : FeedObservation
  after : FeedObservation
  newly_listed : Int32
  changed : Int32
  no_longer_listed : Int32
  unchanged : Int32
  changes : Array[FeedChange]
  total_changes : Int32
  matched_changes : Int32
  offset : Int32
  next_offset : Int32?
  query : String
  kind : String
}

///|
let comparison_scope : String = "Normalized visible fields: title, date_published, summary (first 2000 Unicode characters), url. Match by exact parsed ID; no full-content comparison."

///|
let comparison_caveat : String = "No longer listed means absent from the supplied after document, not deleted. Publisher next documents are not fetched; these observations may be partial."

///|
fn observation_index(
  document : FeedDocument,
  side : String,
) -> Map[String, FeedArticle] raise {
  let index : Map[String, FeedArticle] = Map([])
  for article in document.articles {
    guard !article.id.trim().is_empty() else {
      fail("\{side} observation has an empty article ID")
    }
    guard index.get(article.id) is None else {
      fail("\{side} observation has duplicate article ID: \{article.id}")
    }
    index[article.id] = article
  }
  index
}

///|
fn changed_fields(before : FeedArticle, after : FeedArticle) -> Array[String] {
  let fields : Array[String] = []
  if before.title != after.title {
    fields.push("title")
  }
  if before.date_published != after.date_published {
    fields.push("date_published")
  }
  if before.summary != after.summary {
    fields.push("summary")
  }
  if before.url != after.url {
    fields.push("url")
  }
  fields
}

///|
fn article_matches(article : FeedArticle?, needle : String) -> Bool {
  match article {
    None => false
    Some(article) =>
      (article.id +
      "\n" +
      article.title +
      "\n" +
      article.summary +
      "\n" +
      article.url.unwrap_or("") +
      "\n" +
      article.date_published.unwrap_or(""))
      .to_lower()
      .contains(needle)
  }
}

///|
/// Compare two explicitly selected observations of the same logical source.
/// All entries in both supplied documents participate before filtering/paging.
/// Duplicate or empty IDs fail rather than silently choosing an article.
/// Current-order new/changed entries precede prior-order no-longer-listed entries.
/// Only normalized reader-visible fields are compared, not full article content.
pub fn compare_feeds(
  before_body : String,
  after_body : String,
  source : String,
  before_label~ : String = "before",
  after_label~ : String = "after",
  query~ : String = "",
  kind~ : String = "all",
  limit~ : Int32 = 50,
  offset~ : Int32 = 0,
) -> FeedComparison raise {
  guard !source.trim().is_empty() else {
    fail("source must identify the same logical feed for both observations")
  }
  guard limit >= 1 && limit <= 50 && offset >= 0 else {
    fail("limit must be 1..50 and offset must be nonnegative")
  }
  guard kind is ("all" | "newly_listed" | "changed" | "no_longer_listed") else {
    fail("kind must be all, newly_listed, changed or no_longer_listed")
  }
  let before = parse_feed_document(before_body, source)
  let after = parse_feed_document(after_body, source)
  let prior = observation_index(before, "before")
  let current = observation_index(after, "after")
  let changes : Array[FeedChange] = []
  let mut newly_listed = 0
  let mut changed = 0
  let mut no_longer_listed = 0
  let mut unchanged = 0
  for article in after.articles {
    match prior.get(article.id) {
      None => {
        newly_listed += 1
        changes.push({
          kind: "newly_listed",
          id: article.id,
          before: None,
          after: Some(article),
          changed_fields: [],
        })
      }
      Some(old) => {
        let fields = changed_fields(old, article)
        if fields.is_empty() {
          unchanged += 1
        } else {
          changed += 1
          changes.push({
            kind: "changed",
            id: article.id,
            before: Some(old),
            after: Some(article),
            changed_fields: fields,
          })
        }
      }
    }
  }
  for article in before.articles {
    if current.get(article.id) is None {
      no_longer_listed += 1
      changes.push({
        kind: "no_longer_listed",
        id: article.id,
        before: Some(article),
        after: None,
        changed_fields: [],
      })
    }
  }
  let query = query.trim().to_owned()
  let needle = query.to_lower()
  let matching = changes.filter(change => {
    (kind == "all" || change.kind == kind) &&
    (
      needle.is_empty() ||
      article_matches(change.before, needle) ||
      article_matches(change.after, needle)
    )
  })
  let start = Int32::min(offset, matching.length())
  let end = start + Int32::min(limit, matching.length() - start)
  {
    source,
    before: {
      label: before_label,
      title: before.title,
      format: before.format,
      total_items: before.articles.length(),
      next_url: before.next_url,
    },
    after: {
      label: after_label,
      title: after.title,
      format: after.format,
      total_items: after.articles.length(),
      next_url: after.next_url,
    },
    newly_listed,
    changed,
    no_longer_listed,
    unchanged,
    changes: matching[start:end].to_owned(),
    total_changes: changes.length(),
    matched_changes: matching.length(),
    offset,
    next_offset: if end < matching.length() {
      Some(end)
    } else {
      None
    },
    query,
    kind,
  }
}

///|
pub extend FeedObservation with Show::{to_string, output}

///|
pub extend FeedChange with Show::{to_string, output}

///|
pub extend FeedComparison with Show::{to_string, output}

///|
pub impl Show for FeedObservation with fn output(self, logger) {
  logger.write_string(
    "{label: \{self.label}, title: \{self.title}, format: \{self.format}, total_items: \{self.total_items}, next_url: \{feed_show_optional(self.next_url)}}",
  )
}

///|
pub impl Show for FeedChange with fn output(self, logger) {
  logger.write_string(
    "{kind: \{self.kind}, id: \{self.id}, before: \{feed_show_optional(self.before)}, after: \{feed_show_optional(self.after)}, changed_fields: \{feed_show_array(self.changed_fields)}}",
  )
}

///|
pub impl Show for FeedComparison with fn output(self, logger) {
  logger.write_string(
    "{source: \{self.source}, before: \{self.before}, after: \{self.after}, newly_listed: \{self.newly_listed}, changed: \{self.changed}, no_longer_listed: \{self.no_longer_listed}, unchanged: \{self.unchanged}, changes: \{feed_show_array(self.changes)}, total_changes: \{self.total_changes}, matched_changes: \{self.matched_changes}, offset: \{self.offset}, next_offset: \{feed_show_optional(self.next_offset)}, query: \{self.query}, kind: \{self.kind}}",
  )
}
