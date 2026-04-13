///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  match arr[:] {
    ["import", packet_path, ..] => import_packet(arr, packet_path)
    ["help"] | ["--help"] | ["-h"] | [] => print_help()
    ["version"] | ["--version"] | ["-v"] => println(@buildinfo.version)
    _ => print_help()
  }
}

///|
fn print_help() -> Unit {
  println("MoonClaw proposal commands")
  println("")
  println("Usage: moonclaw proposal import <packet.json> [options]")
  println("")
  println("Commands:")
  println("  import <packet.json>   Import an external proposal packet")
  println("  version                Show version")
  println("")
  println("Options:")
  println("  --confirm        Confirm and execute after import")
  println("  --json           Print JSON instead of text")
  println("  --home <dir>     Home config directory (default: ~/.moonclaw)")
  println("  --cwd <dir>      Working directory (default: current)")
}

///|
fn parse_string_arg(args : Array[String], flag : String) -> String? {
  for i in 0..<args.length() {
    if args[i] == flag && i + 1 < args.length() {
      return Some(args[i + 1])
    }
  }
  None
}

///|
fn resolve_home(args : Array[String]) -> String {
  match parse_string_arg(args, "--home") {
    Some(home) => home
    None => @pathx.join(@os.home() catch { _ => "." }, ".moonclaw")
  }
}

///|
fn resolve_cwd(args : Array[String]) -> String {
  match parse_string_arg(args, "--cwd") {
    Some(cwd) => cwd
    None => @os.cwd() catch { _ => "." }
  }
}

///|
fn import_result_json(result : @job.ExternalProposalImportResult) -> Json {
  match result.confirm_result {
    Some(confirm_result) =>
      (
        {
          "proposal_id": result.proposal.id,
          "job_id": confirm_result.compilation.definition.id,
          "workflow_id": confirm_result.compilation.workflow.id,
          "run_id": confirm_result.run.id,
          "status": confirm_result.run.status.to_json(),
        } : Json)
    None =>
      (
        {
          "proposal_id": result.proposal.id,
          "status": result.proposal.status.to_json(),
        } : Json)
  }
}

///|
async fn import_packet(args : Array[String], packet_path : String) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let json_mode = args.contains("--json")
  let confirm = args.contains("--confirm")
  let workspace = @workspace.WorkspaceRuntime::new(home~, cwd~)
  let app = @job.GatewayJobApp::new(
    root=@pathx.join(home, "jobs"),
    cwd~,
    home~,
    workspace~,
    next_id=fn() { "\{workspace.root()}-\{packet_path}" },
    now=fn() { @clock.epoch.now().ms().to_int() },
  )
  app.load()
  let result = app.import_external_proposal_packet_file(packet_path, confirm~)
  match result {
    Ok(result) =>
      if json_mode {
        println(import_result_json(result).stringify(indent=2))
      } else {
        let profile_label = result.proposal.suggested_family.unwrap_or(
          "generic",
        )
        println("Imported proposal: \{result.proposal.id}")
        println("Profile: \{profile_label}")
        match result.confirm_result {
          Some(confirm_result) => {
            println("Job: \{confirm_result.compilation.definition.id}")
            println("Run: \{confirm_result.run.id}")
            println(
              "Run status: \{confirm_result.run.status.to_json().stringify()}",
            )
          }
          None => println("Status: draft")
        }
      }
    Err(error) => fail("Proposal import failed: \{error}")
  }
}
