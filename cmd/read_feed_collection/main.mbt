///|
fn option_text(fields : Map[String, Json], key : String) -> String raise {
  match fields.get(key) {
    None => ""
    Some(String(text)) => text
    _ => fail("\{key} must be a string")
  }
}

///|
fn option_number(
  fields : Map[String, Json],
  key : String,
  fallback : Int,
) -> Int raise {
  match fields.get(key) {
    None => fallback
    Some(Number(n, ..)) if n >= 0 &&
      n <= 2147483647.0 &&
      n == n.to_int().to_double() => n.to_int()
    _ => fail("\{key} must be a nonnegative integer")
  }
}

///|
async fn run(args : Array[String]) -> Unit {
  let usage = "Usage: read_feed_collection MANIFEST_FILE [OPTIONS_JSON] [--markdown]"
  guard args.length() >= 2 && args.length() <= 4 else { fail(usage) }
  let markdown = args[args.length() - 1] == "--markdown"
  let count = args.length() - (if markdown { 1 } else { 0 })
  guard count == 2 || count == 3 else { fail(usage) }
  let options : Json = if count == 3 { @json.parse(args[2]) } else { {} }
  guard options is Object(fields) else { fail("options must be a JSON object") }
  for key, _ in fields {
    guard key is ("query" | "source" | "limit" | "offset") else {
      fail("Unknown collection option: \{key}")
    }
  }
  let page = @feed.read_feed_collection(
    args[1],
    query=option_text(fields, "query"),
    source=option_text(fields, "source"),
    limit=option_number(fields, "limit", 50),
    offset=option_number(fields, "offset", 0),
  )
  println(
    if markdown {
      page.to_markdown()
    } else {
      page.to_json().stringify()
    },
  )
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("read_feed_collection: \{error}\n")
      @sys.exit(1)
    }
  }
}
