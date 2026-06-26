///|
pub struct WebSearchItem {
  title : String
  url : String
  snippet : String
  source : String
  domain : String?
  rank : Int
} derive(ToJson, FromJson)

///|
pub struct WebSearchResult {
  query : String
  search_url : String
  answer : String?
  results : Array[WebSearchItem]
  source : String
} derive(ToJson, FromJson)

///|
pub impl Show for WebSearchResult with fn output(
  result : WebSearchResult,
  logger : &Logger,
) -> Unit {
  let lines = [
    "Query: \{result.query}",
    "Source: \{result.source}",
    "Search URL: \{result.search_url}",
  ]
  if result.answer is Some(answer) && !answer.is_blank() {
    lines.push("")
    lines.push("Summary:")
    lines.push(answer)
  }
  if !result.results.is_empty() {
    lines.push("")
    lines.push("Results:")
    for item in result.results {
      let snippet = if item.snippet.is_blank() {
        ""
      } else {
        " — \{item.snippet}"
      }
      lines.push("- \{item.title} (\{item.url})\{snippet}")
    }
  }
  logger.write_string(lines.join("\n"))
}

///|
fn domain_from_url(url : String) -> String? {
  guard url.find("://") is Some(index) else { return None }
  let remainder = url[index + 3:].to_owned()
  let host = match remainder.find("/") {
    Some(path_index) => remainder[:path_index].to_owned()
    None => remainder
  }
  let host = host.trim().to_owned()
  if host.is_blank() {
    None
  } else {
    Some(host)
  }
}

///|
fn hex_digit(value : Int) -> Char {
  match value {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'A'
    11 => 'B'
    12 => 'C'
    13 => 'D'
    14 => 'E'
    _ => 'F'
  }
}

///|
fn append_percent_encoded(buf : StringBuilder, code : Int) -> Unit {
  let high = code / 16 % 16
  let low = code % 16
  buf.write_char('%')
  buf.write_char(hex_digit(high))
  buf.write_char(hex_digit(low))
}

///|
fn url_encode_component(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text.to_array() {
    match ch {
      'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' =>
        buf.write_char(ch)
      ' ' => buf.write_char('+')
      _ => append_percent_encoded(buf, ch.to_int())
    }
  }
  buf.to_string()
}

///|
fn json_string_like(value : Json?) -> String? {
  match value {
    Some(String(text)) => Some(text.trim().to_owned())
    Some(Number(num, ..)) => Some(num.to_string())
    Some(True) => Some("true")
    Some(False) => Some("false")
    _ => None
  }
}

///|
fn add_result(
  items : Array[WebSearchItem],
  seen : Map[String, Bool],
  title : String?,
  url : String?,
  snippet : String?,
  source~ : String,
) -> Unit {
  let resolved_title = title.unwrap_or("").trim().to_owned()
  let resolved_url = url.unwrap_or("").trim().to_owned()
  let resolved_snippet = snippet.unwrap_or("").trim().to_owned()
  guard !resolved_url.is_blank() else { return }
  let key = resolved_url
  guard !seen.contains(key) else { return }
  seen[key] = true
  items.push({
    title: if resolved_title.is_blank() {
      resolved_url
    } else {
      resolved_title
    },
    url: resolved_url,
    snippet: resolved_snippet,
    source,
    domain: domain_from_url(resolved_url),
    rank: items.length() + 1,
  })
}

///|
fn collect_related_topic_items(
  value : Json,
  items : Array[WebSearchItem],
  seen : Map[String, Bool],
) -> Unit {
  match value {
    Array(values) =>
      for item in values {
        collect_related_topic_items(item, items, seen)
      }
    Object(map) => {
      add_result(
        items,
        seen,
        json_string_like(map.get("Text")),
        json_string_like(map.get("FirstURL")),
        json_string_like(map.get("Text")),
        source="duckduckgo",
      )
      match map.get("Topics") {
        Some(nested) => collect_related_topic_items(nested, items, seen)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn first_present(
  first : String?,
  second : String?,
  third~ : String?,
) -> String? {
  if first is Some(value) && !value.is_blank() {
    return Some(value)
  }
  if second is Some(value) && !value.is_blank() {
    return Some(value)
  }
  if third is Some(value) && !value.is_blank() {
    return Some(value)
  }
  None
}

///|
fn parse_duckduckgo_result(
  query : String,
  search_url : String,
  body : String,
  max_results : Int,
) -> WebSearchResult raise {
  let json = @json.parse(body) catch {
    error => fail("Invalid web search response: \{error}")
  }
  let answer = match json {
    Object(map) =>
      first_present(
        json_string_like(map.get("AbstractText")),
        json_string_like(map.get("Answer")),
        third=json_string_like(map.get("Definition")),
      )
    _ => None
  }
  let items : Array[WebSearchItem] = []
  let seen : Map[String, Bool] = {}
  match json {
    Object(map) => {
      add_result(
        items,
        seen,
        json_string_like(map.get("Heading")),
        json_string_like(map.get("AbstractURL")),
        json_string_like(map.get("AbstractText")),
        source="duckduckgo",
      )
      match map.get("Results") {
        Some(Array(results)) =>
          for item in results {
            match item {
              Object(result) =>
                add_result(
                  items,
                  seen,
                  json_string_like(result.get("Text")),
                  json_string_like(result.get("FirstURL")),
                  json_string_like(result.get("Text")),
                  source="duckduckgo",
                )
              _ => ()
            }
            if items.length() >= max_results {
              break
            }
          }
        _ => ()
      }
      if items.length() < max_results {
        match map.get("RelatedTopics") {
          Some(related) => collect_related_topic_items(related, items, seen)
          None => ()
        }
      }
    }
    _ => ()
  }
  let limited : Array[WebSearchItem] = []
  for item in items {
    if limited.length() >= max_results {
      break
    }
    limited.push(item)
  }
  {
    query,
    search_url,
    answer,
    results: limited,
    source: "duckduckgo-instant-answer",
  }
}

///|
async fn perform_web_search(
  query : String,
  max_results : Int,
) -> WebSearchResult {
  let encoded = url_encode_component(query)
  let path = "/?q=\{encoded}&format=json&no_html=1&no_redirect=1&skip_disambig=0"
  let search_url = "https://duckduckgo.com/?q=\{encoded}"
  let client = @http.Client::new("https://api.duckduckgo.com", headers={
    "Accept": "application/json",
    "Connection": "close",
    "User-Agent": "moonclaw-web-search/1.0",
  })
  defer client.close()
  let response = client.get(path)
  guard response.code is (200..=299) else {
    let error_body = client.read_all().text()
    fail("web_search HTTP \{response.code}: \{error_body}")
  }
  let body = client.read_all().text()
  parse_duckduckgo_result(query, search_url, body, max_results)
}

///|
pub fn new() -> @tool.Tool[WebSearchResult] {
  @tool.new(
    name="web_search",
    description="Search the public web for background facts and source leads. Use this when local files are insufficient and you need public context.",
    schema={
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Search query to run on the public web",
        },
        "max_results": {
          "type": "integer",
          "description": "Maximum number of results to return",
          "minimum": 1,
          "maximum": 10,
        },
      },
      "required": ["query"],
    },
    ToolFn(async fn(args) -> @tool.ToolResult[WebSearchResult] noraise {
      guard args is { "query": String(query), .. } else {
        return @tool.error("Error: 'query' parameter is required")
      }
      let trimmed = query.trim().to_owned()
      guard !trimmed.is_blank() else {
        return @tool.error("Error: 'query' must not be blank")
      }
      let max_results = match args {
        { "max_results": Number(num, ..), .. } =>
          Int::min(10, Int::max(1, num.to_int()))
        _ => 5
      }
      let result = perform_web_search(trimmed, max_results) catch {
        error => return @tool.error("Web search failed: \{error}")
      }
      @tool.ok(result)
    }),
  )
}

///|
test "url_encode_component encodes spaces and punctuation" {
  inspect(
    url_encode_component("land acquisition? memo"),
    content="land+acquisition%3F+memo",
  )
}

///|
test "parse_duckduckgo_result collects abstract and related topics" {
  let result = parse_duckduckgo_result(
    "moonbit", "https://duckduckgo.com/?q=moonbit", "{\"AbstractText\":\"MoonBit is a programming language.\",\"AbstractURL\":\"https://example.test/moonbit\",\"Heading\":\"MoonBit\",\"RelatedTopics\":[{\"Text\":\"MoonBit docs\",\"FirstURL\":\"https://example.test/docs\"},{\"Name\":\"Nested\",\"Topics\":[{\"Text\":\"MoonBit repo\",\"FirstURL\":\"https://example.test/repo\"}]}]}",
    5,
  )
  inspect(
    result.answer.unwrap_or(""),
    content="MoonBit is a programming language.",
  )
  debug_inspect(result.results.length(), content="3")
  inspect(result.results[0].title, content="MoonBit")
  inspect(result.results[1].url, content="https://example.test/docs")
}
