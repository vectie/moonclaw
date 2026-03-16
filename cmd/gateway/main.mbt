///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  match arr[:] {
    ["start", ..] => start_gateway(arr)
    ["connect", ..] => connect_gateway(arr)
    ["agent", ..] => run_agent(arr)
    ["jobs", ..] => list_jobs(arr)
    ["job", ..] => get_job(arr)
    ["job-create", ..] => create_job(arr)
    ["job-update", ..] => update_job(arr)
    ["job-run", ..] => run_job(arr)
    ["job-cancel", ..] => cancel_job(arr, false)
    ["job-force-cancel", ..] => cancel_job(arr, true)
    ["job-runs", ..] => list_job_runs(arr)
    ["job-run-status", ..] => get_job_run(arr)
    ["runs", ..] => list_runs(arr)
    ["run", ..] => get_run(arr)
    ["job-ask", ..] => ask_job(arr)
    ["channels", ..] => list_channels(arr)
    ["channel", ..] => get_channel(arr)
    ["channel-configure", ..] => configure_channel(arr)
    ["channel-start", ..] => start_channel(arr)
    ["channel-stop", ..] => stop_channel(arr)
    ["health", ..] => check_health(arr)
    ["help"] | ["--help"] | ["-h"] => print_help()
    ["version"] | ["--version"] | ["-v"] => println(@buildinfo.version)
    _ => print_help()
  }
}

///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  start(args)
}

///|
fn print_help() -> Unit {
  println("MoonClaw Gateway - Long-running AI agent service")
  println("")
  println("Usage: moonclaw gateway <command> [options]")
  println("")
  println("Commands:")
  println("  start     Start the gateway server")
  println("  connect   Connect to a running gateway")
  println("  agent     Send an agent request to the gateway")
  println("  jobs      List job definitions")
  println("  job       Get a single job definition")
  println("  job-create        Create a job definition from JSON")
  println("  job-update        Update a job definition from JSON")
  println("  job-run           Trigger a job definition")
  println("  job-cancel        Cancel the active run for a job definition")
  println(
    "  job-force-cancel  Force-cancel the active run for a job definition",
  )
  println("  job-runs          List job runs")
  println("  job-run-status    Get a single job run with steps and artifacts")
  println("  runs      List agent runs")
  println("  run       Get a single run")
  println("  job-ask   Ask grounded questions over job artifacts")
  println("  channels  List channels")
  println("  channel   Get a single channel")
  println("  channel-configure  Configure a channel from JSON")
  println("  channel-start      Start a channel account from JSON")
  println("  channel-stop       Stop a channel account")
  println("  health    Check gateway health")
  println("  version   Show version")
  println("  help      Show this help message")
  println("")
  println("Start options:")
  println("  --port <port>      Port to listen on (default: config or 18123)")
  println(
    "  --cwd <dir>        Working directory (default: config cwd or current)",
  )
  println("  --home <dir>       Home directory (default: ~/.moonclaw)")
  println("")
  println("Connect options:")
  println(
    "  --url <url>        Gateway URL (default: config port or http://localhost:18123)",
  )
  println("  --token <token>    Auth token (default: config token)")
  println("  --home <dir>       Home directory for config discovery")
  println("  --cwd <dir>        Working directory for config discovery")
  println("")
  println("Agent options:")
  println(
    "  --url <url>        Gateway URL (default: config port or http://localhost:18123)",
  )
  println("  --token <token>    Auth token (default: config token)")
  println("  --message <msg>    Message to send (required)")
  println("  --session <key>    Session key for conversation continuity")
  println("  --model <name>     Model to use (default: config primary model)")
  println("  --cwd <dir>        Working directory (default: config cwd)")
  println("  --home <dir>       Home directory for config discovery")
  println("  --wait             Wait for completion")
  println("  --timeout <ms>     Timeout for waiting (default: 60000)")
  println("")
  println("Run options:")
  println("  --id <run_id>      Run id")
  println("")
  println("Job ask options:")
  println("  --question <text>      Question to ask (required)")
  println("  --binding <id>         Optional persisted chat binding id")
  println("  --query-json <json>    Optional ArtifactQuery JSON override")
  println("  --max-hits <n>         Retrieval hit limit (default: 5)")
  println("")
  println("Job definition options:")
  println("  --id <job_id>          Job definition id")
  println("  --definition-json <json>  Raw JobDefinition JSON")
  println("  --run-id <run_id>      Job run id")
  println("")
  println("Channel options:")
  println("  --id <channel_id>      Channel id")
  println("  --account <account>    Account id")
  println("  --config-json <json>   Raw channel/account JSON config")
}

///|
async fn start_gateway(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let home = resolve_home(args)
  let discovery_cwd = resolve_cwd(args)
  let config = load_config(home, discovery_cwd)
  let port = parse_int_arg(
    args,
    "--port",
    default=configured_gateway_port(config).unwrap_or(@protocol.DEFAULT_PORT),
  )
  let cwd = parse_string_arg(args, "--cwd").unwrap_or(
    configured_agent_cwd(config).unwrap_or(discovery_cwd),
  )
  logger.info("Starting MoonClaw Gateway on port \{port}")
  let gateway = @server.Gateway::new(port~, cwd=cwd[:], home=home[:])
  logger.info("Gateway started on port \{gateway.port()}")
  gateway.start()
}

///|
async fn connect_gateway(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let defaults = gateway_cli_defaults(args)
  let config = @client.ClientConfig::{
    base_url: defaults.url,
    token: defaults.token,
    client_id: None,
    client_mode: @protocol.ClientMode::Cli,
  }
  let client = @client.Client::new(config)
  let result = client.connect()
  match result {
    Err(e) => logger.error("Connection failed: \{e}")
    Ok(hello) => {
      logger.info("Connected to gateway v\{hello.server.version}")
      logger.info("Protocol version: \{hello.protocol}")
      let methods = hello.features.methods.join(", ")
      logger.info("Available methods: \{methods}")
    }
  }
}

///|
async fn run_agent(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let defaults = gateway_cli_defaults(args)
  let message = parse_string_arg(args, "--message")
  let message = match message {
    Some(m) => m
    None => {
      logger.error("--message is required")
      return
    }
  }
  let session_key = parse_string_arg(args, "--session")
  let cwd = match parse_string_arg(args, "--cwd") {
    Some(cwd) => Some(cwd)
    None => defaults.cwd
  }
  let model = match parse_string_arg(args, "--model") {
    Some(model) => Some(model)
    None => defaults.primary_model
  }
  let wait = args.contains("--wait")
  let timeout = parse_int_arg(args, "--timeout", default=60000)
  let config = @client.ClientConfig::{
    base_url: defaults.url,
    token: defaults.token,
    client_id: None,
    client_mode: @protocol.ClientMode::Cli,
  }
  let client = @client.Client::new(config)
  let connect_result = client.connect()
  match connect_result {
    Err(e) => {
      logger.error("Connection failed: \{e}")
      return
    }
    Ok(_) => ()
  }
  let agent_result = client.agent(message~, session_key?, cwd?, model?)
  match agent_result {
    Err(e) => {
      logger.error("Agent request failed: \{e}")
      return
    }
    Ok(accepted) => {
      logger.info("Agent request accepted: \{accepted.run_id}")
      if wait {
        logger.info("Waiting for completion...")
        let wait_result = client.wait_agent(
          run_id=accepted.run_id,
          timeout_ms=timeout,
        )
        match wait_result {
          Err(e) => logger.error("Wait failed: \{e}")
          Ok(payload) => {
            logger.info("Agent completed")
            println(payload.stringify())
          }
        }
      }
    }
  }
}

///|
async fn check_health(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let defaults = gateway_cli_defaults(args)
  let config = @client.ClientConfig::{
    base_url: defaults.url,
    token: defaults.token,
    client_id: None,
    client_mode: @protocol.ClientMode::Probe,
  }
  let client = @client.Client::new(config)
  let result = client.health()
  match result {
    Err(e) => logger.error("Health check failed: \{e}")
    Ok(health) => {
      println("Status: \{health.status}")
      println("Uptime: \{health.uptime_ms}ms")
      println("Active sessions: \{health.active_sessions}")
      println("Pending requests: \{health.pending_requests}")
    }
  }
}

///|
async fn list_runs(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.list_runs() {
    Err(error) => logger.error("Runs list failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn list_jobs(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.list_jobs() {
    Err(error) => logger.error("Jobs list failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn get_job(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let job_id = match parse_string_arg(args, "--id") {
    Some(job_id) => job_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.get_job(job_id~) {
    Err(error) => logger.error("Job lookup failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn create_job(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let definition_json = match parse_json_arg(args, "--definition-json") {
    Ok(definition) => definition
    Err(error) => {
      logger.error(error)
      return
    }
  }
  let definition : @job.JobDefinition = @json.from_json(definition_json) catch {
    error => {
      logger.error("Invalid job definition JSON: \{error}")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.create_job(definition) {
    Err(error) => logger.error("Job create failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn update_job(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let definition_json = match parse_json_arg(args, "--definition-json") {
    Ok(definition) => definition
    Err(error) => {
      logger.error(error)
      return
    }
  }
  let definition : @job.JobDefinition = @json.from_json(definition_json) catch {
    error => {
      logger.error("Invalid job definition JSON: \{error}")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.update_job(definition) {
    Err(error) => logger.error("Job update failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn run_job(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let job_id = match parse_string_arg(args, "--id") {
    Some(job_id) => job_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.run_job(job_id~) {
    Err(error) => logger.error("Job run failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn cancel_job(args : Array[String], force : Bool) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let job_id = match parse_string_arg(args, "--id") {
    Some(job_id) => job_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  let result = if force {
    client.force_cancel_job(job_id~)
  } else {
    client.cancel_job(job_id~)
  }
  match result {
    Err(error) =>
      logger.error(
        if force {
          "Job force-cancel failed: \{error}"
        } else {
          "Job cancel failed: \{error}"
        },
      )
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn list_job_runs(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.list_job_runs() {
    Err(error) => logger.error("Job runs list failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn get_job_run(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let run_id = match parse_string_arg(args, "--run-id") {
    Some(run_id) => run_id
    None =>
      match parse_string_arg(args, "--id") {
        Some(run_id) => run_id
        None => {
          logger.error("--run-id or --id is required")
          return
        }
      }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.get_job_run(run_id~) {
    Err(error) => logger.error("Job run lookup failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn get_run(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let run_id = match parse_string_arg(args, "--id") {
    Some(run_id) => run_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.get_run(run_id~) {
    Err(error) => logger.error("Run lookup failed: \{error}")
    Ok(run) => println(run.to_json().stringify())
  }
}

///|
async fn ask_job(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let question = match parse_string_arg(args, "--question") {
    Some(question) => question
    None => {
      logger.error("--question is required")
      return
    }
  }
  let query = match parse_optional_json_arg(args, "--query-json") {
    Ok(query) => query
    Err(error) => {
      logger.error(error)
      return
    }
  }
  let artifact_query : @job.ArtifactQuery? = match query {
    Some(query_json) =>
      @json.from_json(query_json) catch {
        error => {
          logger.error("Invalid artifact query JSON: \{error}")
          return
        }
      }
    None => None
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match
    client.ask_job(@job.JobAskParams::{
      question,
      binding_id: parse_string_arg(args, "--binding"),
      artifact_query,
      max_hits: Some(parse_int_arg(args, "--max-hits", default=5)),
    }) {
    Err(error) => logger.error("Job ask failed: \{error}")
    Ok(answer) => println(answer.to_json().stringify())
  }
}

///|
async fn list_channels(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.list_channels() {
    Err(error) => logger.error("Channels list failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn get_channel(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let channel_id = match parse_string_arg(args, "--id") {
    Some(channel_id) => channel_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.get_channel(channel_id~) {
    Err(error) => logger.error("Channel lookup failed: \{error}")
    Ok(channel) => println(channel.to_json().stringify())
  }
}

///|
async fn configure_channel(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let channel_id = match parse_string_arg(args, "--id") {
    Some(channel_id) => channel_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let config_json = match parse_json_arg(args, "--config-json") {
    Ok(config) => config
    Err(error) => {
      logger.error(error)
      return
    }
  }
  let config : @channel.ChannelConfig = @json.from_json(config_json) catch {
    error => {
      logger.error("Invalid channel config JSON: \{error}")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.configure_channel(channel_id~, config) {
    Err(error) => logger.error("Channel configure failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn start_channel(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let channel_id = match parse_string_arg(args, "--id") {
    Some(channel_id) => channel_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let account_id = match parse_string_arg(args, "--account") {
    Some(account_id) => account_id
    None => {
      logger.error("--account is required")
      return
    }
  }
  let config = match parse_json_arg(args, "--config-json") {
    Ok(config) => config
    Err(error) => {
      logger.error(error)
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.start_channel(channel_id~, account_id~, config) {
    Err(error) => logger.error("Channel start failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn stop_channel(args : Array[String]) -> Unit {
  let logger = @pino.logger("gateway", @pino.Transport::console())
  let channel_id = match parse_string_arg(args, "--id") {
    Some(channel_id) => channel_id
    None => {
      logger.error("--id is required")
      return
    }
  }
  let account_id = match parse_string_arg(args, "--account") {
    Some(account_id) => account_id
    None => {
      logger.error("--account is required")
      return
    }
  }
  let client = make_client(args, mode=@protocol.ClientMode::Cli)
  match client.stop_channel(channel_id~, account_id~) {
    Err(error) => logger.error("Channel stop failed: \{error}")
    Ok(payload) => println(payload.to_json().stringify())
  }
}

///|
async fn make_client(
  args : Array[String],
  mode~ : @protocol.ClientMode,
) -> @client.Client {
  let defaults = gateway_cli_defaults(args)
  @client.Client::new(@client.ClientConfig::{
    base_url: defaults.url,
    token: defaults.token,
    client_id: None,
    client_mode: mode,
  })
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
fn root_config_path(root : String) -> String {
  root |> @pathx.join("moonclaw.json")
}

///|
fn nested_config_path(root : String) -> String {
  root |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json")
}

///|
fn config_candidates(home : String, cwd : String) -> Array[String] {
  [
    root_config_path(home),
    nested_config_path(home),
    root_config_path(cwd),
    nested_config_path(cwd),
  ]
}

///|
async fn load_config(home : String, cwd : String) -> Json? {
  for path in config_candidates(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    return Some(json)
  }
  None
}

///|
fn json_string_field(value : Json, field : String) -> String? {
  match value {
    Object(obj) =>
      match obj.get(field) {
        Some(String(text)) if !text.trim().is_empty() =>
          Some(text.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn configured_agent_cwd(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("cwd") {
                Some(String(cwd)) if !cwd.trim().is_empty() =>
                  Some(cwd.trim().to_string())
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn configured_primary_model(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("model") {
                Some(model) => json_string_field(model, "primary")
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn configured_gateway_port(json : Json?) -> Int? {
  match json {
    Some(Object(root)) =>
      match root.get("gateway") {
        Some(Object(gateway)) =>
          match gateway.get("port") {
            Some(Number(port, ..)) => Some(port.to_int())
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn configured_gateway_token(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("gateway") {
        Some(Object(gateway)) =>
          match gateway.get("auth") {
            Some(auth) => json_string_field(auth, "token")
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
struct GatewayCliDefaults {
  url : String
  token : String?
  cwd : String?
  primary_model : String?
}

///|
async fn gateway_cli_defaults(args : Array[String]) -> GatewayCliDefaults {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let config = load_config(home, cwd)
  let url = match parse_string_arg(args, "--url") {
    Some(url) => url
    None =>
      "http://localhost:\{configured_gateway_port(config).unwrap_or(@protocol.DEFAULT_PORT)}"
  }
  let token = match parse_string_arg(args, "--token") {
    Some(token) => Some(token)
    None => configured_gateway_token(config)
  }
  {
    url,
    token,
    cwd: configured_agent_cwd(config),
    primary_model: configured_primary_model(config),
  }
}

///|
fn parse_string_arg(args : Array[String], name : String) -> String? {
  let mut i = 0
  while i < args.length() {
    if args[i] == name && i + 1 < args.length() {
      return Some(args[i + 1])
    }
    i = i + 1
  }
  None
}

///|
fn parse_int_arg(args : Array[String], name : String, default~ : Int) -> Int {
  match parse_string_arg(args, name) {
    Some(s) => {
      let result : Result[Int, Error] = try? @strconv.parse_int(s[:], base=10)
      match result {
        Ok(n) => n
        Err(_) => default
      }
    }
    None => default
  }
}

///|
fn parse_json_arg(args : Array[String], name : String) -> Result[Json, String] {
  match parse_string_arg(args, name) {
    Some(text) =>
      Ok(
        @json.parse(text) catch {
          error => return Err("Invalid JSON for \{name}: \{error}")
        },
      )
    None => Err("\{name} is required")
  }
}

///|
fn parse_optional_json_arg(
  args : Array[String],
  name : String,
) -> Result[Json?, String] {
  match parse_string_arg(args, name) {
    Some(text) =>
      Ok(
        Some(
          @json.parse(text) catch {
            error => return Err("Invalid JSON for \{name}: \{error}")
          },
        ),
      )
    None => Ok(None)
  }
}
