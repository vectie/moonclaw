///|
pub struct WebFetchResult {
  url : String
  final_url : String
  domain : String
  status_code : Int
  content_type : String?
  title : String?
  text : String
  truncated : Bool
  source : String
  metadata : Json
} derive(ToJson, FromJson)

///|
pub impl Show for WebFetchResult with fn output(
  result : WebFetchResult,
  logger : &Logger,
) -> Unit {
  let lines = [
    "URL: \{result.url}",
    "Final URL: \{result.final_url}",
    "Domain: \{result.domain}",
    "Status: \{result.status_code}",
    "Source: \{result.source}",
  ]
  if result.content_type is Some(content_type) && !content_type.is_blank() {
    lines.push("Content-Type: \{content_type}")
  }
  if result.title is Some(title) && !title.is_blank() {
    lines.push("Title: \{title}")
  }
  lines.push("")
  lines.push(result.text)
  if result.truncated {
    lines.push("")
    lines.push("[truncated]")
  }
  logger.write_string(lines.join("\n"))
}

///|
priv struct FetchUri {
  scheme : String
  host : String
  path : String
}

///|
priv suberror WebFetchError {
  InvalidUrl(message~ : String)
} derive(Debug)

///|
fn parse_fetch_uri(url : String) -> FetchUri raise WebFetchError {
  guard url.find("://") is Some(index) else {
    raise InvalidUrl(message="URL must include a scheme")
  }
  let scheme = url[:index].to_owned()
  let remainder = url[index + 3:].to_owned()
  let (host, path) = match remainder.find("/") {
    Some(path_index) =>
      (remainder[:path_index].to_owned(), remainder[path_index:].to_owned())
    None => (remainder, "/")
  }
  guard !scheme.trim().is_empty() else {
    raise InvalidUrl(message="URL scheme must not be blank")
  }
  guard !host.trim().is_empty() else {
    raise InvalidUrl(message="URL host must not be blank")
  }
  { scheme, host, path }
}

///|
fn normalized_content_type(headers : Map[String, String]) -> String? {
  match headers.get("content-type") {
    Some(value) if !value.trim().to_owned().is_blank() =>
      Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn html_title(text : String) -> String? {
  let lower = text.to_lower()
  let start = match lower.find("<title>") {
    Some(index) => index + 7
    None => return None
  }
  let end = match lower[start:].find("</title>") {
    Some(offset) => start + offset
    None => return None
  }
  let title = text[start:end].trim().to_owned()
  if title.is_blank() {
    None
  } else {
    Some(title)
  }
}

///|
fn html_body_text(text : String) -> String {
  let lower = text.to_lower()
  match lower.find("<body") {
    Some(body_start) =>
      match lower[body_start:].find(">") {
        Some(offset) => {
          let content_start = body_start + offset + 1
          let content_end = match lower[content_start:].find("</body>") {
            Some(body_end_offset) => content_start + body_end_offset
            None => text.length()
          }
          text[content_start:content_end].to_owned()
        }
        None => text
      }
    None => text
  }
}

///|
fn decode_html_entity(entity : String) -> String? {
  match entity {
    "amp" => Some("&")
    "lt" => Some("<")
    "gt" => Some(">")
    "quot" => Some("\"")
    "#39" => Some("'")
    "nbsp" => Some(" ")
    _ => None
  }
}

///|
fn strip_html_tags(text : String) -> String {
  let buf = StringBuilder::new()
  let chars = text.to_array()
  let mut i = 0
  let mut in_tag = false
  let mut last_space = true
  while i < chars.length() {
    let ch = chars[i]
    if in_tag {
      if ch == '>' {
        in_tag = false
      }
      i = i + 1
      continue
    }
    match ch {
      '<' => {
        in_tag = true
        if !last_space {
          buf.write_char(' ')
          last_space = true
        }
      }
      '&' => {
        let mut entity_end : Int? = None
        let mut j = i + 1
        while j < chars.length() {
          if chars[j] == ';' {
            entity_end = Some(j)
            break
          }
          j += 1
        }
        match entity_end {
          Some(end_index) => {
            let entity = String::from_array(chars[i + 1:end_index].to_owned())
            match decode_html_entity(entity) {
              Some(decoded) => {
                buf.write_string(decoded)
                last_space = decoded == " "
                i = end_index + 1
                continue
              }
              None => ()
            }
          }
          None => ()
        }
        buf.write_char(ch)
        last_space = false
      }
      '\n' | '\r' | '\t' | ' ' =>
        if !last_space {
          buf.write_char(' ')
          last_space = true
        }
      _ => {
        buf.write_char(ch)
        last_space = false
      }
    }
    i = i + 1
  }
  buf.to_string().trim().to_owned()
}

///|
fn truncate_text(text : String, max_chars : Int) -> (String, Bool) {
  if max_chars <= 0 {
    return ("", !text.is_empty())
  }
  if text.length() <= max_chars {
    return (text, false)
  }
  let truncated = text[:max_chars].trim().to_owned()
  (truncated, true)
}

///|
fn extracted_fetch_text(
  body : String,
  content_type : String?,
) -> (String, String?) {
  match content_type {
    Some(content_type) if content_type.to_lower().contains("html") =>
      (strip_html_tags(html_body_text(body)), html_title(body))
    _ => (body.trim().to_owned(), None)
  }
}

///|
fn content_type_is_pdf(content_type : String?) -> Bool {
  match content_type {
    Some(value) => value.to_lower().contains("application/pdf")
    None => false
  }
}

///|
async fn extracted_pdf_text(
  body : Bytes,
  max_chars : Int,
) -> (String, Bool, String) {
  @fsx.with_temporary_directory("/tmp/moonclaw-web-fetch-pdf-XXXXXX", async fn(
    dir,
  ) {
    let pdf_path = dir + "/document.pdf"
    let text_path = dir + "/document.txt"
    @fsx.write_bytes_to_file(pdf_path, body) catch {
      error => fail("web_fetch could not stage PDF: \{error}")
    }
    let (extracted_path, note) = @pdf_ocr.extract_text_from_pdf(
      pdf_path,
      text_path,
      dir,
      (command, arguments, cwd) => {
        @pdf_ocr.run_process(command, arguments, cwd~)
      },
    )
    let path = match extracted_path {
      Some(path) => path
      None =>
        fail(
          "web_fetch PDF extraction failed: \{note.unwrap_or("no extractor produced text")}",
        )
    }
    let text = @fsx.read_file(path) catch {
      error => fail("web_fetch could not read extracted PDF text: \{error}")
    }
    let cleaned = text.trim().to_owned()
    guard !cleaned.is_blank() else {
      fail("web_fetch PDF extraction produced no readable text")
    }
    let (truncated_text, truncated) = truncate_text(cleaned, max_chars)
    (truncated_text, truncated, note.unwrap_or("Extracted PDF text"))
  })
}

///|
async fn perform_web_fetch(url : String, max_chars : Int) -> WebFetchResult {
  let uri = parse_fetch_uri(url) catch { error => fail("\{Repr(error)}") }
  let client = @http.Client("\{uri.scheme}://\{uri.host}", headers={
    "Accept": "text/html,application/xhtml+xml,application/json,text/plain;q=0.9,*/*;q=0.8",
    "Connection": "close",
    // Some authoritative public sites reject bot-shaped user agents even for
    // ordinary read-only pages. Use a browser-compatible UA while retaining a
    // clear MoonClaw product token for observability.
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36 MoonClawWebFetch/1.0",
  })
  defer client.close()
  let response = client.get(uri.path)
  let body = client.read_all().binary()
  guard response.code is (200..=299) else {
    fail(
      "web_fetch HTTP \{response.code}: \{@encoding/utf8.decode_lossy(body)}",
    )
  }
  let content_type = normalized_content_type(response.headers)
  let is_pdf = content_type_is_pdf(content_type)
  let (truncated_text, truncated, title, extraction_note) = if is_pdf {
    let (text, truncated, note) = extracted_pdf_text(body, max_chars)
    (text, truncated, None, Some(note))
  } else {
    let decoded = @encoding/utf8.decode_lossy(body)
    let (text, title) = extracted_fetch_text(decoded, content_type)
    let (truncated_text, truncated) = truncate_text(text, max_chars)
    (truncated_text, truncated, title, None)
  }
  let metadata : Map[String, Json] = {
    "scheme": uri.scheme.to_json(),
    "host": uri.host.to_json(),
    "path": uri.path.to_json(),
    "extracted_as_html": match content_type {
      Some(content_type) => content_type.to_lower().contains("html").to_json()
      None => false.to_json()
    },
    "extracted_as_pdf": is_pdf.to_json(),
  }
  match extraction_note {
    Some(note) => metadata.set("extraction_note", note.to_json())
    None => ()
  }
  {
    url,
    final_url: url,
    domain: uri.host,
    status_code: response.code,
    content_type,
    title,
    text: truncated_text,
    truncated,
    source: if is_pdf {
      "http-fetch-pdf"
    } else {
      "http-fetch"
    },
    metadata: Json::object(metadata),
  }
}

///|
pub fn new() -> @tool.Tool[WebFetchResult] {
  @tool.new(
    name="web_fetch",
    description="Fetch a URL and return cleaned text content. Use this after finding a promising source or when you need the actual page contents rather than search snippets.",
    schema={
      "type": "object",
      "properties": {
        "url": { "type": "string", "description": "HTTP or HTTPS URL to fetch" },
        "max_chars": {
          "type": "integer",
          "description": "Maximum number of characters to return from the fetched content",
          "minimum": 200,
          "maximum": 20000,
        },
      },
      "required": ["url"],
    },
    ToolFn(async fn(args) -> @tool.ToolResult[WebFetchResult] noraise {
      guard args is { "url": String(url), .. } else {
        return @tool.error("Error: 'url' parameter is required")
      }
      let trimmed = url.trim().to_owned()
      guard !trimmed.is_blank() else {
        return @tool.error("Error: 'url' must not be blank")
      }
      let max_chars = match args {
        { "max_chars": Number(value, ..), .. } =>
          Int::min(20000, Int::max(200, value.to_int()))
        _ => 5000
      }
      // Public sources occasionally accept the connection but never finish a
      // response. Bound every fetch so one source cannot stall an analysis
      // step until its much larger job timeout expires.
      let result = @async.with_timeout(
        45000,
        async fn() { perform_web_fetch(trimmed, max_chars) },
        error=Failure::Failure("web_fetch timed out after 45 seconds"),
      ) catch {
        error => return @tool.error("Web fetch failed: \{error}")
      }
      @tool.ok(result)
    }),
  )
}
