///|
fn usage() -> String {
  "Usage: run_journal FILE.jsonl [FILE.jsonl ...] [--run ID] [--step ID] [--type TYPE] [--query TEXT] [--since TIMESTAMP] [--until TIMESTAMP] [--offset N] [--limit N] [--markdown]"
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  let files : Array[String] = []
  let options : Map[String, String] = Map::new()
  let mut markdown = false
  for index = 1; index < args.length(); {
    let arg = args[index]
    if arg == "--markdown" {
      guard !markdown else { fail("Repeated --markdown option") }
      markdown = true
      continue index + 1
    }
    if [
        "--run", "--step", "--type", "--query", "--since", "--until", "--offset",
        "--limit",
      ].contains(arg) {
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
  let page = @journal.explore_journal(
    entries,
    run_id?=options.get("--run"),
    step_id?=options.get("--step"),
    event_type?=options.get("--type"),
    query?=options.get("--query"),
    since?=parse_number(options, "--since"),
    until?=parse_number(options, "--until"),
    offset=parse_number(options, "--offset").unwrap_or(0),
    limit=parse_number(options, "--limit").unwrap_or(100),
  )
  if markdown {
    @stdio.stdout.write(page.to_markdown())
  } else {
    println(page.to_json().stringify())
  }
}

///|
fn parse_number(options : Map[String, String], name : String) -> Int? raise {
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
      @stdio.stderr.write("run_journal: \{error}\n")
      @sys.exit(1)
    }
  }
}
