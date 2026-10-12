///|
fn usage() -> String {
  "Usage: import_artifacts EXPORT_DIRECTORY NEW_INSPECTION_STORE\nReopen a portable artifact export for search, comparison and exact-content export."
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  guard args.length() == 3 else { fail(usage()) }
  let result = @job.import_artifact_export(args[1], args[2])
  println(result.to_json().stringify())
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("import_artifacts: \{error}\n")
      @sys.exit(1)
    }
  }
}
