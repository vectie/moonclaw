///|
fn discovery_without_fragment(value : String) -> String {
  value[:value.find("#").unwrap_or(value.length())].to_owned()
}

///|
fn discovery_url_characters(value : String) -> Bool {
  for c in value.to_array() {
    if c.to_int() <= 32 ||
      c.to_int() == 127 ||
      c is ('\\' | '<' | '>' | '"' | '\'') {
      return false
    }
  }
  true
}

///|
// Conservative HTTP(S) reference resolution. Keep query and percent escapes;
// remove literal dot segments only. This does not claim browser URL parsing.
fn discovery_absolute(value : String) -> String? {
  if value.length() > 8192 {
    return None
  }
  let value = discovery_without_fragment(value)
  let lower = discovery_lower(value)
  let scheme_end = if lower.has_prefix("https://") {
    8
  } else if lower.has_prefix("http://") {
    7
  } else {
    return None
  }
  if !discovery_url_characters(value) {
    return None
  }
  let rest = value[scheme_end:]
  let authority_end = Int::min(
    rest.find("/").unwrap_or(rest.length()),
    rest.find("?").unwrap_or(rest.length()),
  )
  let authority = rest[:authority_end].to_owned()
  if authority.is_empty() || authority.contains("@") {
    return None
  }
  let origin = lower[:scheme_end].to_owned() + authority
  let suffix = rest[authority_end:].to_owned()
  let query_at = suffix.find("?").unwrap_or(suffix.length())
  let path = suffix[:query_at].to_owned()
  let query = suffix[query_at:].to_owned()
  let parts : Array[String] = []
  for segment in path.split("/") {
    if segment == "." {
      continue
    }
    if segment == ".." {
      if parts.length() > 1 {
        ignore(parts.pop())
      }
    } else {
      parts.push(segment.to_owned())
    }
  }
  let mut normalized = parts.join("/")
  if normalized.is_empty() {
    normalized = "/"
  }
  if (path.has_suffix("/.") || path.has_suffix("/..")) &&
    !normalized.has_suffix("/") {
    normalized += "/"
  }
  Some(origin + normalized + query)
}

///|
fn discovery_resolve(reference : String, base : String) -> String? {
  if reference.length() > 8192 {
    return None
  }
  let reference = discovery_without_fragment(reference.trim().to_owned())
  if !discovery_url_characters(reference) {
    return None
  }
  if reference.has_prefix("//") {
    let scheme_end = base.find(":").unwrap_or(0)
    return discovery_absolute(base[:scheme_end + 1].to_owned() + reference)
  }
  let first_end = Int::min(
    reference.find("/").unwrap_or(reference.length()),
    reference.find("?").unwrap_or(reference.length()),
  )
  if reference[:first_end].contains(":") {
    return discovery_absolute(reference)
  }
  let scheme_end = if base.has_prefix("https://") { 8 } else { 7 }
  let path_at = scheme_end +
    base[scheme_end:].find("/").unwrap_or(base.length() - scheme_end)
  let origin = base[:path_at].to_owned()
  if reference.has_prefix("/") {
    return discovery_absolute(origin + reference)
  }
  let without_query = base[:base.find("?").unwrap_or(base.length())].to_owned()
  if reference.is_empty() {
    return Some(base)
  }
  if reference.has_prefix("?") {
    return discovery_absolute(without_query + reference)
  }
  let directory_end = without_query.rev_find("/").unwrap_or(path_at) + 1
  discovery_absolute(without_query[:directory_end].to_owned() + reference)
}
