///|
fn usage() -> String {
  "Usage: list_runs FILE.jsonl [FILE.jsonl ...] [--job ID] [--query TEXT] [--offset N] [--limit N] [--markdown]\nDiscover whole saved runs, newest observation first. No live state or execution controls."
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
      guard !markdown else { fail("Repeated option --markdown") }
      markdown = true
      continue index + 1
    }
    if ["--job", "--query", "--offset", "--limit"].contains(arg) {
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
  let directory = @journal.journal_run_directory(
    entries,
    job_id?=options.get("--job"),
    query?=options.get("--query"),
    offset=parse_number(options, "--offset", 0),
    limit=parse_number(options, "--limit", 50),
  )
  let output = if markdown {
    directory.to_markdown()
  } else {
    directory.to_json().stringify(indent=2) + "\n"
  }
  guard output.length() <= 16777216 else {
    fail("Output exceeds 16 Mi code units; reduce --limit")
  }
  @stdio.stdout.write(output)
}

///|
fn parse_number(
  options : Map[String, String],
  name : String,
  fallback : Int32,
) -> Int32 raise {
  match options.get(name) {
    Some(value) =>
      @string.parse_int(value) catch {
        _ => fail("Expected an integer for \{name}")
      }
    None => fallback
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("list_runs: \{error}\n")
      @sys.exit(1)
    }
  }
}
