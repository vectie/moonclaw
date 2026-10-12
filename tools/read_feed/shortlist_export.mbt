///|
// Escape all ASCII punctuation so a standalone summary cannot become a list,
// thematic break or other block. Keep this stricter contract shortlist-local.
fn shortlist_markdown_text(text : String) -> String {
  let out = StringBuilder()
  for c in feed_space(text) {
    if c is ('!'..='/' | ':'..='@' | '['..='`' | '{'..='~') {
      out.write_char('\\')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
/// Export only the ordered selection. Includes frozen provenance and reader
/// annotations; omits unselected catalog items and never fetches article URLs.
pub fn ReadingShortlist::to_markdown(self : ReadingShortlist) -> String {
  let out = StringBuilder()
  out.write_string("# " + shortlist_markdown_text(self.title) + "\n\n")
  out.write_string(
    "\{self.order.length()} selected articles from \{self.entries.length()} captured articles.\n\n" +
    shortlist_scope +
    "\n\n",
  )
  let entries : Map[String, ShortlistEntry] = Map([])
  for entry in self.entries {
    entries[entry.entry_id] = entry
  }
  if self.order.is_empty() {
    out.write_string("No articles selected.\n")
  }
  for index, id in self.order {
    let entry = entries[id]
    let snapshot = entry.snapshot
    let article = snapshot.article
    out.write_string(
      "## \{index + 1}. " + shortlist_markdown_text(article.title) + "\n\n",
    )
    out.write_string("Reading state: " + entry.state + "\n\n")
    out.write_string(
      "Reader note: " + shortlist_markdown_text(entry.note) + "\n\n",
    )
    out.write_string(
      "Source: " +
      shortlist_markdown_text(snapshot.source_title) +
      " (" +
      shortlist_markdown_text(snapshot.source) +
      ")\n\n",
    )
    out.write_string(
      "Observation label: " +
      shortlist_markdown_text(snapshot.label) +
      "; format: " +
      snapshot.format +
      "; original article index: \{snapshot.article_index}\n\n",
    )
    out.write_string("Source body SHA-256: " + snapshot.body_sha256 + "\n\n")
    out.write_string("Saved entry ID: " + id + "\n\n")
    out.write_string(
      "Publisher ID: " + shortlist_markdown_text(article.id) + "\n\n",
    )
    if article.date_published is Some(date) {
      out.write_string(
        "Publisher date: " + shortlist_markdown_text(date) + "\n\n",
      )
    }
    if !article.summary.is_empty() {
      out.write_string(shortlist_markdown_text(article.summary) + "\n\n")
    }
    if article.url is Some(url) &&
      (url.has_prefix("https://") || url.has_prefix("http://")) {
      let escaped = url
        .replace_all(old=" ", new="%20")
        .replace_all(old="<", new="%3C")
        .replace_all(old=">", new="%3E")
        .replace_all(old="\r", new="%0D")
        .replace_all(old="\n", new="%0A")
        .replace_all(old="\\", new="%5C")
        .replace_all(old="\t", new="%09")
      out.write_string("[Read article](<" + escaped + ">)\n\n")
    }
  }
  out.to_string()
}
