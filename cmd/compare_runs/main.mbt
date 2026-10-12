///|
fn usage() -> String {
  "Usage: compare_runs FILE.jsonl [FILE.jsonl ...] --baseline RUN_ID --candidate RUN_ID [--markdown]"
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
    if arg == "--baseline" || arg == "--candidate" {
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
    fail("Supply 1–32 explicit journal files")
  }
  guard options.get("--baseline") is Some(baseline_run) &&
    options.get("--candidate") is Some(candidate_run) else {
    fail(usage())
  }
  let entries : Array[@journal.JournalEntry] = []
  for file in files {
    entries.append(@journal.parse_journal(@fsx.read_file(file), source=file))
    guard entries.length() <= 10000 else {
      fail("Combined journals exceed 10000 events")
    }
  }
  let comparison = @journal.compare_journal_runs(
    entries,
    baseline_run~,
    candidate_run~,
  )
  if markdown {
    @stdio.stdout.write(comparison.to_markdown())
  } else {
    println(comparison.to_json().stringify())
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("compare_runs: \{error}\n")
      @sys.exit(1)
    }
  }
}
