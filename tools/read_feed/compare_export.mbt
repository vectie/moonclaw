///|
pub impl ToJson for FeedObservation with fn to_json(self : FeedObservation) -> Json {
  {
    "label": self.label,
    "title": self.title,
    "format": self.format,
    "total_items": self.total_items,
    "next_url": optional_text(self.next_url),
  }
}

///|
fn optional_article(article : FeedArticle?) -> Json {
  match article {
    Some(article) => article.to_json()
    None => Json::null()
  }
}

///|
pub impl ToJson for FeedChange with fn to_json(self : FeedChange) -> Json {
  {
    "kind": self.kind,
    "id": self.id,
    "before": optional_article(self.before),
    "after": optional_article(self.after),
    "changed_fields": self.changed_fields,
  }
}

///|
pub impl ToJson for FeedComparison with fn to_json(self : FeedComparison) -> Json {
  {
    "schema_version": 1,
    "source": self.source,
    "comparison_scope": comparison_scope,
    "absence_caveat": comparison_caveat,
    "before": self.before,
    "after": self.after,
    "newly_listed": self.newly_listed,
    "changed": self.changed,
    "no_longer_listed": self.no_longer_listed,
    "unchanged": self.unchanged,
    "changes": self.changes,
    "total_changes": self.total_changes,
    "matched_changes": self.matched_changes,
    "offset": self.offset,
    "next_offset": match self.next_offset {
      Some(offset) => offset.to_json()
      None => Json::null()
    },
    "query": self.query,
    "kind": self.kind,
  }
}

///|
fn write_observation(
  out : StringBuilder,
  side : String,
  observation : FeedObservation,
) -> Unit {
  out.write_string(
    "\{side}: " +
    markdown_text(observation.label) +
    " (" +
    observation.format +
    ", \{observation.total_items} items); title: " +
    markdown_text(observation.title) +
    "\n\n",
  )
  if observation.next_url is Some(url) {
    out.write_string(
      "\{side} publisher next document (not fetched): " +
      markdown_text(url) +
      "\n\n",
    )
  }
}

///|
fn write_comparison_article(
  out : StringBuilder,
  side : String,
  article : FeedArticle,
) -> Unit {
  out.write_string("### \{side}\n\n")
  out.write_string("Title: " + markdown_text(article.title) + "\n\n")
  out.write_string(
    "Date: " +
    markdown_text(article.date_published.unwrap_or("(absent)")) +
    "\n\n",
  )
  out.write_string("Summary: " + markdown_text(article.summary) + "\n\n")
  // Keep publisher URLs as escaped text, including unsafe schemes; do not
  // manufacture Markdown links from observations of untrusted feed content.
  out.write_string(
    "URL: " + markdown_text(article.url.unwrap_or("(absent)")) + "\n\n",
  )
}

///|
/// Export the selected comparison page, including old and new visible values.
pub fn FeedComparison::to_markdown(self : FeedComparison) -> String {
  let out = StringBuilder::new()
  out.write_string("# Feed observation comparison\n\n")
  out.write_string("Source: " + markdown_text(self.source) + "\n\n")
  write_observation(out, "Before", self.before)
  write_observation(out, "After", self.after)
  out.write_string(comparison_scope + "\n\n" + comparison_caveat + "\n\n")
  out.write_string(
    "All supplied items: \{self.newly_listed} newly listed, \{self.changed} changed, \{self.no_longer_listed} no longer listed, \{self.unchanged} unchanged.\n\n",
  )
  out.write_string(
    "Showing \{self.changes.length()} of \{self.matched_changes} matching changes (\{self.total_changes} total); offset \{self.offset}.\n\n",
  )
  out.write_string(
    "Kind: " +
    markdown_text(self.kind) +
    "; filter: " +
    markdown_text(self.query) +
    "\n\n",
  )
  if self.changes.is_empty() {
    out.write_string("No changes on this selected page.\n\n")
  }
  for change in self.changes {
    let label = match change.kind {
      "newly_listed" => "Newly listed"
      "changed" => "Changed"
      _ => "No longer listed"
    }
    out.write_string("## \{label}: " + markdown_text(change.id) + "\n\n")
    if !change.changed_fields.is_empty() {
      out.write_string(
        "Changed fields: " + change.changed_fields.join(", ") + "\n\n",
      )
    }
    if change.before is Some(article) {
      write_comparison_article(out, "Before", article)
    }
    if change.after is Some(article) {
      write_comparison_article(out, "After", article)
    }
  }
  if self.next_offset is Some(offset) {
    out.write_string(
      "Next page: use offset \{offset} with the same observations, source and filters.\n",
    )
  }
  out.to_string()
}
