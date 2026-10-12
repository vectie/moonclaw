///|
async fn run(args : Array[String]) -> Unit {
  guard args.length() == 3 || args.length() == 4 else {
    fail("Usage: discover_feeds SAVED_PAGE.html PAGE_URL [NAME_PREFIX]")
  }
  let discovered = @feed.discover_feeds(
    @fsx.read_file(args[1]),
    args[2],
    prefix=if args.length() == 4 { args[3] } else { "html" },
  )
  println(discovered.to_json().stringify())
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("discover_feeds: \{error}\n")
      @sys.exit(1)
    }
  }
}
