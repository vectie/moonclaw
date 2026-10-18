///|
fn markdown_text(text : String) -> String {
  let out = StringBuilder()
  for c in feed_space(text) {
    if c is ('\\' | '`' | '*' | '_' | '[' | ']' | '#' | '<' | '>' | '!' | '|') {
      out.write_char('\\')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
/// Export the currently selected page as a portable reading digest.
pub fn FeedPage::to_markdown(self : FeedPage) -> String {
  let out = StringBuilder()
  out.write_string("# " + markdown_text(self.title) + "\n\n")
  out.write_string("Source: " + markdown_text(self.source) + "\n\n")
  out.write_string(
    "Showing \{self.articles.length()} of \{self.matched_items} matching articles (\{self.total_items} in this document).\n\n",
  )
  if !self.query.is_empty() {
    out.write_string("Filter: " + markdown_text(self.query) + "\n\n")
  }
  for article in self.articles {
    out.write_string("## " + markdown_text(article.title) + "\n\n")
    if article.date_published is Some(date) {
      out.write_string(markdown_text(date) + "\n\n")
    }
    if !article.summary.is_empty() {
      out.write_string(markdown_text(article.summary) + "\n\n")
    }
    if article.url is Some(url) {
      if url.has_prefix("https://") || url.has_prefix("http://") {
        let escaped = url
          .replace(old=" ", new="%20")
          .replace(old="<", new="%3C")
          .replace(old=">", new="%3E")
          .replace(old="\r", new="%0D")
          .replace(old="\n", new="%0A")
        out.write_string("[Read article](<" + escaped + ">)\n\n")
      }
    }
  }
  if self.next_offset is Some(offset) {
    out.write_string(
      "Next page: use offset \{offset} with the same source and filter.\n",
    )
  }
  if self.next_url is Some(url) {
    out.write_string("Publisher next document: " + markdown_text(url) + "\n")
  }
  out.to_string()
}
