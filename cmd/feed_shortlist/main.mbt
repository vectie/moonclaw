///|
async fn run(args : Array[String]) -> Unit {
  let usage = "Usage: feed_shortlist capture MANIFEST | show ARCHIVE | catalog ARCHIVE [QUERY] | edit ARCHIVE CHANGES_FILE | export ARCHIVE | inspect-merge ARCHIVE INCOMING | merge ARCHIVE INCOMING [error|keep-existing|use-incoming]"
  guard args.length() >= 3 && args.length() <= 5 else { fail(usage) }
  let output = match args[1] {
    "capture" if args.length() == 3 =>
      @feed.capture_reading_shortlist_file(args[2]).to_archive()
    "show" if args.length() == 3 =>
      @feed.read_reading_shortlist(args[2]).to_archive()
    "export" if args.length() == 3 =>
      @feed.read_reading_shortlist(args[2]).to_markdown()
    "catalog" if args.length() <= 4 =>
      @feed.read_reading_shortlist(args[2])
      .catalog(query=if args.length() == 4 { args[3] } else { "" })
      .stringify()
    "inspect-merge" if args.length() == 4 =>
      @feed.read_reading_shortlist(args[2])
      .preview_merge(@feed.read_reading_shortlist(args[3]))
      .stringify()
    "merge" if args.length() >= 4 =>
      @feed.read_reading_shortlist(args[2])
      .merge(
        @feed.read_reading_shortlist(args[3]),
        conflict=if args.length() == 5 { args[4] } else { "error" },
      )
      .to_archive()
    "edit" if args.length() == 4 => {
      let saved = @feed.read_reading_shortlist(args[2])
      let body = @fsx.read_file(args[3])
      guard body.length() <= 16777216 else {
        fail("Changes file exceeds 16 Mi UTF-16 code units")
      }
      saved.edit(@json.parse(body)).to_archive()
    }
    _ => fail(usage)
  }
  println(output)
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("feed_shortlist: \{error}\n")
      @sys.exit(1)
    }
  }
}
