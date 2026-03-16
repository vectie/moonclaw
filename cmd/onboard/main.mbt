///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  match arr[:] {
    [] | ["status", ..] | ["doctor", ..] => show_status(arr)
    ["models", ..] => show_models(arr)
    ["auth", ..] => run_auth(arr)
    ["init", ..] | ["configure", ..] => apply_onboarding(arr)
    ["switch", ..] => switch_model(arr)
    ["print-config", ..] => print_config(arr)
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
  println("MoonClaw onboarding")
  println("")
  println("Usage: moonclaw onboard <command> [options]")
  println("")
  println("Commands:")
  println("  status         Show current onboarding status")
  println("  doctor         Alias for status")
  println("  models         List configured provider/model choices")
  println("  auth           Show or manage Codex/Copilot OAuth")
  println("  init           Create or update config and workspace files")
  println("  configure      Alias for init with explicit config choices")
  println("  switch         Change the primary model quickly")
  println("  print-config   Print the config template with optional overrides")
  println("  version        Show version")
  println("")
  println("Options:")
  println("  --home <dir>   Home config directory (default: ~/.moonclaw)")
  println("  --cwd <dir>    Working directory (default: current)")
  println(
    "  --model <id>   Set agents.defaults.model.primary (for example: bailian/qwen3.5-plus)",
  )
  println("  --agent-cwd <dir>        Set agents.defaults.cwd")
  println("  --workspace <dir>        Set agents.defaults.workspace")
  println("  --gateway-port <port>    Set gateway.port")
  println("  --gateway-token <token>  Set gateway.auth.token")
  println("  --enable-feishu          Enable channels.feishu")
  println("  --disable-feishu         Disable channels.feishu")
  println("  --feishu-app-id <id>     Set channels.feishu.appId")
  println("  --feishu-app-secret <s>  Set channels.feishu.appSecret")
  println("  --json         Print JSON instead of text")
  println("")
  println("Auth:")
  println("  moonclaw onboard auth status")
  println("  moonclaw onboard auth codex")
  println("  moonclaw onboard auth copilot")
  println("  moonclaw onboard auth logout codex")
  println("  moonclaw onboard auth logout copilot")
  println("")
  println("Switch:")
  println("  moonclaw onboard switch codex")
  println("  moonclaw onboard switch copilot/gpt-5.2")
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
fn parse_int_arg(args : Array[String], flag : String) -> Int? {
  match parse_string_arg(args, flag) {
    Some(raw) => Some(@strconv.parse_int(raw)) catch { _ => None }
    None => None
  }
}

///|
fn resolve_options(args : Array[String]) -> @onboarding.OnboardingOptions {
  @onboarding.onboarding_options(
    primary_model=parse_string_arg(args, "--model"),
    working_directory=parse_string_arg(args, "--agent-cwd"),
    workspace_root=parse_string_arg(args, "--workspace"),
    gateway_port=parse_int_arg(args, "--gateway-port"),
    gateway_token=parse_string_arg(args, "--gateway-token"),
    feishu_enabled=if args.contains("--enable-feishu") {
      Some(true)
    } else if args.contains("--disable-feishu") {
      Some(false)
    } else {
      None
    },
    feishu_app_id=parse_string_arg(args, "--feishu-app-id"),
    feishu_app_secret=parse_string_arg(args, "--feishu-app-secret"),
  )
}

///|
fn normalize_switch_target(target : String) -> String {
  match target.trim() {
    "codex" => "codex/gpt-5.4"
    "copilot" => "copilot/gpt-5.2"
    model if !model.is_empty() => model.to_string()
    _ => ""
  }
}

///|
async fn show_status(args : Array[String]) -> Unit {
  let logger = @pino.logger("onboard", @pino.Transport::console())
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let json_mode = args.contains("--json")
  let status = @onboarding.collect_status(home~, cwd~)
  if json_mode {
    println(status.to_json().stringify(indent=2))
  } else {
    println(@onboarding.render_status(status))
  }
  if !status.issues.is_empty() {
    logger.warn("Onboarding is incomplete")
  }
}

///|
async fn show_models(args : Array[String]) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let json_mode = args.contains("--json")
  let models = @onboarding.discover_models(home~, cwd~)
  if json_mode {
    println(models.to_json().stringify(indent=2))
  } else {
    println(@onboarding.render_model_list(models))
  }
}

///|
async fn run_auth(args : Array[String]) -> Unit {
  let rest = args[1:].to_array()
  let json_mode = args.contains("--json")
  match rest[:] {
    [] | ["status", ..] => {
      let status = @onboarding.auth_status()
      if json_mode {
        println(status.to_json().stringify(indent=2))
      } else {
        println(@onboarding.render_auth_status(status))
      }
    }
    ["codex", ..] => {
      let home = resolve_home(args)
      let cwd = resolve_cwd(args)
      let auth_message = @onboarding.start_auth_flow("codex") catch {
        err => {
          println("Codex OAuth failed: \{err}")
          return
        }
      }
      let target = normalize_switch_target("codex")
      let result = @onboarding.bootstrap_with_options(
        home~,
        cwd~,
        @onboarding.onboarding_options(primary_model=Some(target)),
      )
      if json_mode {
        println(
          (
            {
              "auth": auth_message,
              "primary_model_updated": true,
              "primary_model": target,
              "onboarding": result.to_json(),
            } : Json).stringify(indent=2),
        )
      } else {
        println(auth_message)
        println("Primary model updated to \{target} via onboard auth.")
        println("")
        println(@onboarding.render_bootstrap_result(result))
      }
    }
    ["copilot", ..] => {
      let home = resolve_home(args)
      let cwd = resolve_cwd(args)
      let auth_message = @onboarding.start_auth_flow("copilot") catch {
        err => {
          println("Copilot OAuth failed: \{err}")
          return
        }
      }
      let target = normalize_switch_target("copilot")
      let result = @onboarding.bootstrap_with_options(
        home~,
        cwd~,
        @onboarding.onboarding_options(primary_model=Some(target)),
      )
      if json_mode {
        println(
          (
            {
              "auth": auth_message,
              "primary_model_updated": true,
              "primary_model": target,
              "onboarding": result.to_json(),
            } : Json).stringify(indent=2),
        )
      } else {
        println(auth_message)
        println("Primary model updated to \{target} via onboard auth.")
        println("")
        println(@onboarding.render_bootstrap_result(result))
      }
    }
    ["logout", provider, ..] => {
      let message = @onboarding.clear_auth(provider) catch {
        err => "Failed to clear \{provider} auth: \{err}"
      }
      println(message)
    }
    _ => print_help()
  }
}

///|
async fn apply_onboarding(args : Array[String]) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let json_mode = args.contains("--json")
  let options = resolve_options(args)
  let result = @onboarding.bootstrap_with_options(home~, cwd~, options)
  if json_mode {
    println(result.to_json().stringify(indent=2))
  } else {
    println(@onboarding.render_bootstrap_result(result))
  }
}

///|
async fn switch_model(args : Array[String]) -> Unit {
  match args[1:] {
    [raw_target, ..] => {
      let home = resolve_home(args)
      let cwd = resolve_cwd(args)
      let target = normalize_switch_target(raw_target)
      if target.is_empty() {
        print_help()
        return
      }
      let result = @onboarding.bootstrap_with_options(
        home~,
        cwd~,
        @onboarding.onboarding_options(primary_model=Some(target)),
      )
      println(@onboarding.render_bootstrap_result(result))
    }
    _ => print_help()
  }
}

///|
fn print_config(args : Array[String]) -> Unit {
  let home = resolve_home(args)
  let options = resolve_options(args)
  println(@onboarding.render_config_with_options(home~, options))
}
