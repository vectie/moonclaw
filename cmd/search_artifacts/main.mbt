///|
fn usage() -> String {
  "Usage: search_artifacts STORE_ROOT [--text LITERAL] [--job ID] [--run ID] [--type TYPE] [--key KEY] [--scope SCOPE] [--status active|archived|all] [--limit 1..32] [--format json|text] [--export NEW_DIRECTORY]\nSearches saved exact artifact revisions offline. Without --text, catalogs binary and text outputs."
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  guard args.length() >= 2 else { fail(usage()) }
  let mut query = @job.ArtifactQuery::new()
  let mut text : String? = None
  let mut destination : String? = None
  let mut format = "json"
  let mut limit = 32
  let seen : Map[String, Bool] = {}
  for i = 2; i < args.length(); i = i + 2 {
    guard i + 1 < args.length() else {
      fail("Missing option value\n" + usage())
    }
    let option = args[i]
    let value = args[i + 1]
    guard !seen.contains(option) else { fail("Duplicate option: " + option) }
    seen[option] = true
    match option {
      "--text" => text = Some(value)
      "--job" => query = { ..query, job_id: Some(value), }
      "--run" => query = { ..query, run_id: Some(value), }
      "--type" => query = { ..query, artifact_type: Some(value), }
      "--key" => query = { ..query, logical_key: Some(value), }
      "--scope" => query = { ..query, scope: Some(value), }
      "--status" =>
        query = {
          ..query,
          status: match value {
            "active" => Some(Active)
            "archived" => Some(Archived)
            "all" => None
            _ => fail("Status must be active, archived or all")
          },
        }
      "--limit" => limit = @string.parse_int(value)
      "--format" => {
        guard value == "json" || value == "text" else {
          fail("Format must be json or text")
        }
        format = value
      }
      "--export" => destination = Some(value)
      _ => fail("Unknown option: " + option + "\n" + usage())
    }
  }
  let result = @job.search_retained_artifacts(args[1], query~, text~, limit~)
  let exported = match destination {
    Some(path) => Some(result.export_selected(path))
    None => None
  }
  if format == "text" {
    @stdio.stdout.write(result.to_text())
    if destination is Some(path) {
      println("Exported exact matches to " + path.to_json().stringify())
    }
  } else {
    let output : Json = {
      "search": result.to_json(),
      "export": match exported {
        Some(value) => value.to_json()
        None => null
      },
    }
    println(output.stringify())
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("search_artifacts: \{error}\n")
      @sys.exit(1)
    }
  }
}
