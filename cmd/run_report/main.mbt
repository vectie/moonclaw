///|
fn usage() -> String {
  "Usage: run_report FILE.jsonl [FILE.jsonl ...] --job ID --run ID\nWrite a standalone HTML report for one exact saved job/run pair to stdout. Historical observations only."
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  let files : Array[String] = []
  let options : Map[String, String] = Map::new()
  for index = 1; index < args.length(); {
    let arg = args[index]
    if ["--job", "--run"].contains(arg) {
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
  guard !files.is_empty() else { fail(usage()) }
  guard files.length() <= 32 else {
    fail("At most 32 journal files are supported")
  }
  guard options.get("--job") is Some(job_id) else {
    fail("Required option --job")
  }
  guard options.get("--run") is Some(run_id) else {
    fail("Required option --run")
  }
  let entries : Array[@journal.JournalEntry] = []
  for path in files {
    entries.append(@journal.parse_journal(@fsx.read_file(path), source=path))
    guard entries.length() <= 10000 else {
      fail("Combined journals exceed 10000 events")
    }
  }
  let output = @journal.journal_run_html(entries, job_id~, run_id~)
  @stdio.stdout.write(output)
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("run_report: \{error}\n")
      @sys.exit(1)
    }
  }
}
