///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 || (args.length() == 4 && args[3] == "--markdown") else {
    fail(
      "Usage: read_feed WORKSPACE '{\"source\":\"file://feed.xml\",\"limit\":10,\"query\":\"topic\"}' [--markdown]",
    )
  }
  match @feed.new(args[1]).call(@json.parse(args[2])) {
    Ok(page) =>
      println(
        if args.length() == 4 {
          page.to_markdown()
        } else {
          page.to_json().stringify()
        },
      )
    error => fail("\{error}")
  }
}
