///|
// Verification-only local provider. It accepts the actual Town adapter command
// and invokes the production Claw proposal/workflow/artifact lifecycle. It never
// uses a provider account, process tool, network, or external agent.
async fn main {
  let args = @env.args()
  guard (args.length() == 9 || args.length() == 11) &&
    args[1] == "proposal" &&
    args[2] == "oneoff" &&
    args[4] == "--json" &&
    args[5] == "--home" &&
    args[7] == "--cwd" else {
    fail(
      "Verification fixture expects proposal oneoff PACKET --json --home HOME --cwd WORKSPACE",
    )
  }
  let path = args[3]
  let home = args[6]
  let cwd = args[8]
  let store_home = if args.length() == 11 && args[9] == "--store-home" {
    args[10]
  } else {
    home
  }
  let packet : Json = @json.parse(@fsx.read_file(path))
  guard packet is { "context_pages": Array(pages), .. } else {
    fail("Missing captured context paths")
  }
  let app = @job.GatewayJobApp::new(
    root=@job.moonclaw_jobs_root(store_home),
    home~,
    cwd~,
    workspace=@workspace.WorkspaceRuntime::captured(cwd),
    next_id=() => "fixture",
    now=() => 1000,
  )
  let provider = @job.AnalysisExecutor::new(run=async fn(request) {
    let reports : Array[String] = [
      "Deterministic local fixture output. No real external provider or human reviewed this work.",
    ]
    for page in pages {
      guard page is String(relative) &&
        relative.has_prefix("input/") &&
        !relative.contains("..") else {
        return Err("Unexpected fixture input reference")
      }
      let content = @fsx.read_file(cwd + "/" + relative)
      if content.contains("SLOW_PARTICIPANT_FIXTURE") {
        @async.sleep(300)
      }
      if content.contains("FAIL_PARTICIPANT_FIXTURE") {
        return Err("Requested deterministic participant failure")
      }
      reports.push("Source: " + relative + "\n" + content)
    }
    Ok({
      model_name: "local-deterministic-fixture",
      content: reports.join("\n\n"),
      conversation_id: None,
      usage: None,
      metadata: {
        "fixture": true,
        "external_work": false,
        "request_run_id": request.run_id,
      },
    })
  })
  match app.start_external_oneoff_file(path, analysis_executor=Some(provider)) {
    Ok(receipt) => println(receipt.to_json().stringify())
    Err(error) => fail(error)
  }
}
