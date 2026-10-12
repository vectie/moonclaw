///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 || args.length() == 3 else {
    fail("Usage: import_feeds COLLECTION.opml [NAME_PREFIX]")
  }
  let collection = @feed.parse_opml(
    @fsx.read_file(args[1]),
    prefix=if args.length() == 3 { args[2] } else { "opml" },
  )
  println(collection.to_json().stringify())
}
