///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  match arr[:] {
    ["import", packet_path, ..] => import_packet(arr, packet_path)
    ["run", run_id, ..] => run_packet_job(arr, run_id)
    ["status", run_id, ..] => status_packet_job(arr, run_id)
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
  println("  status <run_id>        Load and print a run without executing it")
  println("  version                Show version")
  println("")
  println("Options:")
  println("  --confirm        Confirm and execute after import")
  println("  --inline         Run confirmed import inline instead of detaching")
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
fn resolve_initial_input_file(args : Array[String]) -> String? {
  parse_string_arg(args, "--initial-input-file")
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
  let inline = args.contains("--inline")
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
  if confirm && !inline {
    let imported = match app.import_external_proposal_packet_file(packet_path) {
      Ok(imported) => imported
      Err(error) => fail("Proposal import failed: \{error}")
    }
    let confirm_result = match
      app.confirm_proposal_and_launch(imported.proposal, imported.proposal.id) {
      Ok(confirm_result) => confirm_result
      Err(error) => fail("Proposal import failed: \{error}")
    }
    let proposal = app
      .runtime()
      .store()
      .get_job_proposal(imported.proposal.id)
      .unwrap_or(imported.proposal)
    if json_mode {
      println(
        (
          {
            "proposal_id": proposal.id,
            "job_id": confirm_result.compilation.definition.id,
            "workflow_id": confirm_result.compilation.workflow.id,
            "run_id": confirm_result.run.id,
            "status": confirm_result.run.status.to_json(),
          } : Json).stringify(indent=2),
      )
    } else {
      let profile_label = proposal.suggested_family.unwrap_or("generic")
      println("Imported proposal: \{proposal.id}")
      println("Profile: \{profile_label}")
      println("Job: \{confirm_result.compilation.definition.id}")
      println("Run: \{confirm_result.run.id}")
      println("Run status: \{confirm_result.run.status.to_json().stringify()}")
    }
  } else {
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
}

///|
async fn run_packet_job(args : Array[String], run_id : String) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let workspace = @workspace.WorkspaceRuntime::new(home~, cwd~)
  let app = @job.GatewayJobApp::new(
    root=@pathx.join(home, "jobs"),
    cwd~,
    home~,
    workspace~,
    next_id=fn() { "\{workspace.root()}-run-\{run_id}" },
    now=fn() { @clock.epoch.now().ms().to_int() },
  )
  app.load()
  let initial_input = match resolve_initial_input_file(args) {
    Some(path) => {
      let text = @fsx.read_file(path) catch {
        error => fail("Failed to read initial input file \{path}: \{error}")
      }
      let json = @json.parse(text) catch {
        error => fail("Failed to parse initial input file \{path}: \{error}")
      }
      Some(json)
    }
    None => None
  }
  let result = app.execute_existing_run(run_id, initial_input~)
  match result {
    Ok(_) => ()
    Err(error) => fail("Detached proposal run failed: \{error}")
  }
}

///|
async fn status_packet_job(args : Array[String], run_id : String) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let json_mode = args.contains("--json")
  let workspace = @workspace.WorkspaceRuntime::new(home~, cwd~)
  let app = @job.GatewayJobApp::new(
    root=@pathx.join(home, "jobs"),
    cwd~,
    home~,
    workspace~,
    next_id=fn() { "\{workspace.root()}-status-\{run_id}" },
    now=fn() { @clock.epoch.now().ms().to_int() },
  )
  app.load()
  let store = app.runtime().store()
  let run = match store.get_run(run_id) {
    Some(run) => run
    None => fail("Unknown job run: \{run_id}")
  }
  let steps = store.list_step_runs(run_id)
  if json_mode {
    println(
      (
        {
          "run": run.to_json(),
          "steps": steps.map(fn(step) { step.to_json() }),
        } : Json).stringify(indent=2),
    )
  } else {
    println("Run: \{run.id}")
    println("Job: \{run.job_id}")
    println("Status: \{run.status.to_json().stringify()}")
    match run.summary {
      Some(summary) => println("Summary: \{summary}")
      None => ()
    }
    match run.error {
      Some(error) => println("Error: \{error}")
      None => ()
    }
    for step in steps {
      println("Step: \{step.step_id} \{step.status.to_json().stringify()}")
      match step.summary {
        Some(summary) => println("Step summary: \{summary}")
        None => ()
      }
      match step.error {
        Some(error) => println("Step error: \{error}")
        None => ()
      }
    }
  }
}
