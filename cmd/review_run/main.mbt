///|
fn usage() -> String {
  "Usage: review_run FILE.jsonl [FILE.jsonl ...] --artifacts EXPORT_MANIFEST.json --run RUN_ID [--markdown]\nJoin saved events and exported revisions. Save Markdown beside the manifest for relative file links. Content checksums are not verified."
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  let files : Array[String] = []
  let options : Map[String, String] = {}
  let mut markdown = false
  for index = 1; index < args.length(); {
    let arg = args[index]
    if arg == "--markdown" {
      guard !markdown else { fail("Repeated --markdown option") }
      markdown = true
      continue index + 1
    }
    if arg == "--artifacts" || arg == "--run" {
      guard index + 1 < args.length() else { fail("Missing value for \{arg}") }
      guard !options.contains(arg) else { fail("Repeated option \{arg}") }
      options[arg] = args[index + 1]
      continue index + 2
    }
    guard !arg.has_prefix("--") else { fail("Unknown option \{arg}") }
    guard !files.contains(arg) else { fail("Repeated journal input") }
    files.push(arg)
    continue index + 1
  }
  guard !files.is_empty() && files.length() <= 32 else {
    fail("Supply 1–32 explicit journal files (an empty file is allowed)")
  }
  guard options.get("--artifacts") is Some(manifest_source) &&
    options.get("--run") is Some(run_id) else {
    fail(usage())
  }
  let entries : Array[@journal.JournalEntry] = []
  for file in files {
    entries.append(@journal.parse_journal(@fsx.read_file(file), source=file))
    guard entries.length() <= 10000 else {
      fail("Combined journals exceed 10000 events")
    }
  }
  let review = @journal.review_run(
    entries,
    @fsx.read_file(manifest_source),
    manifest_source~,
    run_id~,
  )
  if markdown {
    @stdio.stdout.write(review.to_markdown())
  } else {
    println(review.to_json().stringify())
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("review_run: \{error}\n")
      @sys.exit(1)
    }
  }
}
