///|
fn option_text(options : Json, key : String, fallback : String) -> String raise {
  guard options is Object(fields) else { fail("options must be a JSON object") }
  match fields.get(key) {
    None => fallback
    Some(String(text)) => text
    _ => fail("\{key} must be a string")
  }
}

///|
fn option_number(options : Json, key : String, fallback : Int) -> Int raise {
  guard options is Object(fields) else { fail("options must be a JSON object") }
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
  guard args.length() >= 4 && args.length() <= 6 else {
    fail(
      "Usage: compare_feeds SOURCE BEFORE_FILE AFTER_FILE [OPTIONS_JSON] [--markdown]",
    )
  }
  let markdown = args[args.length() - 1] == "--markdown"
  let count = args.length() - (if markdown { 1 } else { 0 })
  guard count == 4 || count == 5 else {
    fail(
      "Usage: compare_feeds SOURCE BEFORE_FILE AFTER_FILE [OPTIONS_JSON] [--markdown]",
    )
  }
  let options : Json = if count == 5 { @json.parse(args[4]) } else { {} }
  guard options is Object(fields) else { fail("options must be a JSON object") }
  for key, _ in fields {
    guard key is ("query" | "kind" | "limit" | "offset") else {
      fail("Unknown comparison option: \{key}")
    }
  }
  let query = option_text(options, "query", "")
  let kind = option_text(options, "kind", "all")
  let limit = option_number(options, "limit", 50)
  let offset = option_number(options, "offset", 0)
  let comparison = @feed.compare_feeds(
    @fsx.read_file(args[2]),
    @fsx.read_file(args[3]),
    args[1],
    before_label=args[2],
    after_label=args[3],
    query~,
    kind~,
    limit~,
    offset~,
  )
  println(
    if markdown {
      comparison.to_markdown()
    } else {
      comparison.to_json().stringify()
    },
  )
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("compare_feeds: \{error}\n")
      @sys.exit(1)
    }
  }
}
