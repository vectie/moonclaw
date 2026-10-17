///|
fn usage() -> String {
  "Usage: journal_csv FILE.jsonl [FILE.jsonl ...] [--run ID] [--step ID] [--type TYPE] [--query TEXT] [--since TIMESTAMP] [--until TIMESTAMP]\nExport all matching saved observations as CSV. Import text columns as text in your spreadsheet; recorded observations are not current runtime status."
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
    if ["--run", "--step", "--type", "--query", "--since", "--until"].contains(
        arg,
      ) {
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
  let entries : Array[@journal.JournalEntry] = []
  for path in files {
    entries.append(@journal.parse_journal(@fsx.read_file(path), source=path))
    guard entries.length() <= 10000 else {
      fail("Combined journals exceed 10000 events")
    }
  }
  let csv = @journal.journal_csv(
    entries,
    run_id?=options.get("--run"),
    step_id?=options.get("--step"),
    event_type?=options.get("--type"),
    query?=options.get("--query"),
    since?=parse_number(options, "--since"),
    until?=parse_number(options, "--until"),
  )
  @stdio.stdout.write(csv)
}

///|
fn parse_number(options : Map[String, String], name : String) -> Int32? raise {
  match options.get(name) {
    Some(value) =>
      Some(@string.parse_int(value)) catch {
        _ => fail("Expected an integer for \{name}")
      }
    None => None
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("journal_csv: \{error}\n")
      @sys.exit(1)
    }
  }
}
