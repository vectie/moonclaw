///|
async fn load_feed(cwd : String, source : String) -> String {
  if source.has_prefix("file://") {
    let path = source[7:].to_owned()
    guard !path.is_empty() else { fail("file:// requires a path") }
    return @fsx.read_file(
      if @pathx.is_absolute(path) {
        path
      } else {
        @pathx.join(cwd, path)
      },
    )
  }
  guard source.has_prefix("https://") || source.has_prefix("http://") else {
    fail(
      "Expected an HTTP(S) URL, file:// fixture, or provider:// registered source",
    )
  }
  let scheme_end = source.find("://").unwrap() + 3
  let rest = source[scheme_end:].to_owned()
  let split = Int32::min(
    rest.find("/").unwrap_or(rest.length()),
    rest.find("?").unwrap_or(rest.length()),
  )
  let origin = source[:scheme_end].to_owned() + rest[:split].to_owned()
  let path = if split == rest.length() {
    "/"
  } else if rest[split] == '?' {
    "/" + rest[split:].to_owned()
  } else {
    rest[split:].to_owned()
  }
  let client = @http.Client(origin, headers={
    "Accept": "application/feed+json, application/rss+xml, application/atom+xml, application/xml, text/xml, application/json",
    "Connection": "close",
  })
  defer client.close()
  let response = client.get(path)
  guard response.code is (200..<=299) else {
    fail("Feed HTTP status \{response.code}")
  }
  @utf8.decode_lossy(client.read_all().binary())
}

///|
pub fn new(
  cwd : String,
  home? : String?,
  allow_files~ : Bool = true,
) -> @tool.Tool[FeedPage] {
  @tool.new(
    name="read_feed",
    description="Read public JSON Feed 1/1.1, RSS 2.0 or Atom articles (titles, dates, plain-text summaries, links). Select an HTTP(S) URL, provider:// registered source, or file:// offline fixture. Optional query filters titles, summaries, IDs and links before pagination. Use next_offset with the same query and source, then explicitly select next_url. No login required.",
    schema={
      "type": "object",
      "properties": {
        "source": { "type": "string" },
        "limit": {
          "type": "integer",
          "minimum": 1,
          "maximum": 50,
          "default": 10,
        },
        "offset": { "type": "integer", "minimum": 0, "default": 0 },
        "query": {
          "type": "string",
          "description": "Case-insensitive substring in article title, summary, ID or URL",
          "default": "",
        },
      },
      "required": ["source"],
    },
    async fn(args) -> @tool.ToolResult[FeedPage] noraise {
      guard args is { "source": String(source), .. } else {
        return @tool.error("source is required")
      }
      let limit = match args {
        { "limit": Number(n, ..), .. } if n >= 1 &&
          n <= 50 &&
          n == n.to_int().to_double() => n.to_int()
        { "limit": _, .. } =>
          return @tool.error("limit must be an integer from 1 to 50")
        _ => 10
      }
      let offset = match args {
        { "offset": Number(n, ..), .. } if n >= 0 &&
          n <= 2147483647.0 &&
          n == n.to_int().to_double() => n.to_int()
        { "offset": _, .. } =>
          return @tool.error("offset must be a nonnegative integer")
        _ => 0
      }
      let query = match args {
        { "query": String(query), .. } => query
        { "query": _, .. } => return @tool.error("query must be a string")
        _ => ""
      }
      if limit < 1 || limit > 50 || offset < 0 {
        return @tool.error("limit must be 1..50 and offset must be nonnegative")
      }
      let result = try {
        let resolved = if source.has_prefix("provider://") {
          let name = source[11:].to_owned()
          guard @resource_providers.find_resource_provider(
              cwd,
              name,
              home=home.unwrap_or(None),
            )
            is Some(provider) else {
            fail("Registered source not found: \{name}")
          }
          guard provider.endpoint is Some(endpoint) else {
            fail("Registered source has no endpoint: \{name}")
          }
          endpoint
        } else {
          source
        }
        guard allow_files || !resolved.has_prefix("file://") else {
          fail("This job's existing tool contract does not allow file reading")
        }
        let body = @async.with_timeout(
          45000,
          () => load_feed(cwd, resolved),
          error=Failure::Failure("Feed read timed out after 45 seconds"),
        )
        parse_feed(body, resolved, limit~, offset~, query~)
      } catch {
        error => return @tool.error("Feed read failed: \{error}")
      }
      @tool.ok(result)
    },
  )
}
