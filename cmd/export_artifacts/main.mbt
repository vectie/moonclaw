///|
fn usage() -> String {
  "Usage: export_artifacts STORE_ROOT NEW_EXPORT_DIRECTORY ARTIFACT_ID [ARTIFACT_ID ...]\nExports exact retained content and original records with manifest.json, README.txt and SHA256SUMS."
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  guard args.length() >= 4 else { fail(usage()) }
  let result = @job.export_retained_artifacts(
    args[1],
    args[3:].to_array(),
    args[2],
  )
  println(result.to_json().stringify())
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("export_artifacts: \{error}\n")
      @sys.exit(1)
    }
  }
}
