///|
/// Export the selected collection page with source provenance on every article.
pub fn FeedCollectionPage::to_markdown(self : FeedCollectionPage) -> String {
  let out = StringBuilder()
  out.write_string("# " + markdown_text(self.title) + "\n\n")
  out.write_string(
    "Showing \{self.articles.length()} of \{self.matched_items} matching articles (\{self.total_items} in \{self.sources.length()} supplied snapshots).\n\n",
  )
  if !self.query.is_empty() {
    out.write_string("Filter: " + markdown_text(self.query) + "\n\n")
  }
  if !self.source_filter.is_empty() {
    out.write_string(
      "Source filter: " + markdown_text(self.source_filter) + "\n\n",
    )
  }
  out.write_string(collection_scope + "\n\n")
  out.write_string("## Sources\n\n")
  for source in self.sources {
    out.write_string(
      "- " +
      markdown_text(source.title) +
      " (" +
      markdown_text(source.source) +
      "): \{source.matched_items} matching of \{source.total_items}; observation " +
      markdown_text(source.label) +
      "\n",
    )
    if source.next_url is Some(next) {
      out.write_string(
        "  Publisher next document, not fetched: " + markdown_text(next) + "\n",
      )
    }
  }
  out.write_string("\n")
  if self.articles.is_empty() {
    out.write_string("No articles on this selected page.\n\n")
  }
  for entry in self.articles {
    let article = entry.article
    out.write_string("## " + markdown_text(article.title) + "\n\n")
    out.write_string(
      "Source: " +
      markdown_text(entry.source_title) +
      " (" +
      markdown_text(entry.source) +
      ")\n\n",
    )
    out.write_string(
      "Observation: " +
      markdown_text(entry.label) +
      "; article index: \{entry.article_index}; publisher ID: " +
      markdown_text(article.id) +
      "\n\n",
    )
    if article.date_published is Some(date) {
      out.write_string(markdown_text(date) + "\n\n")
    }
    if !article.summary.is_empty() {
      out.write_string(markdown_text(article.summary) + "\n\n")
    }
    if article.url is Some(url) &&
      (url.has_prefix("https://") || url.has_prefix("http://")) {
      let escaped = url
        .replace_all(old=" ", new="%20")
        .replace_all(old="<", new="%3C")
        .replace_all(old=">", new="%3E")
        .replace_all(old="\r", new="%0D")
        .replace_all(old="\n", new="%0A")
      out.write_string("[Read article](<" + escaped + ">)\n\n")
    }
  }
  if self.next_offset is Some(offset) {
    out.write_string(
      "Next page: use offset \{offset} with the same manifest, source filter and query.\n",
    )
  }
  out.to_string()
}
