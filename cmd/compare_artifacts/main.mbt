///|
fn usage() -> String {
  "Usage: compare_artifacts STORE_ROOT LEFT_ARTIFACT_ID RIGHT_ARTIFACT_ID [--markdown]"
}

///|
async fn run(args : Array[String]) -> Unit {
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  guard args.length() == 4 || (args.length() == 5 && args[4] == "--markdown") else {
    fail(usage())
  }
  let result = @job.compare_retained_artifacts(args[1], args[2], args[3])
  if args.length() == 5 {
    @stdio.stdout.write(result.to_markdown())
  } else {
    println(result.to_json().stringify())
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("compare_artifacts: \{error}\n")
      @sys.exit(1)
    }
  }
}
