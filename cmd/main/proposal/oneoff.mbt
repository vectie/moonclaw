///|
async fn oneoff_packet(args : Array[String], packet_path : String) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let store_home = parse_string_arg(args, "--store-home").unwrap_or(home)
  let workspace = @workspace.WorkspaceRuntime::captured(cwd)
  let app = @job.GatewayJobApp::new(
    root=@job.moonclaw_jobs_root(store_home),
    cwd~,
    home~,
    workspace~,
    next_id=() => "oneoff",
    now=() => @clock.epoch.now().ms().to_int(),
  )
  match app.start_external_oneoff_file(packet_path) {
    Ok(receipt) => println(receipt.to_json().stringify(indent=2))
    Err(error) => fail(error)
  }
}
