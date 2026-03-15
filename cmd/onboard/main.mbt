///|
pub async fn start(args : ArrayView[String]) -> Unit {
  let arr = args.to_array()
  match arr[:] {
    [] | ["status", ..] | ["doctor", ..] => show_status(arr)
    ["init", ..] => apply_onboarding(arr)
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
  println("  init           Create or fill baseline config and workspace files")
  println("  print-config   Print the baseline config template")
  println("  version        Show version")
  println("")
  println("Options:")
  println("  --home <dir>   Home config directory (default: ~/.moonclaw)")
  println("  --cwd <dir>    Working directory (default: current)")
  println("  --json         Print JSON instead of text")
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
    None => @os.home() catch { _ => ".moonclaw" }
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
async fn apply_onboarding(args : Array[String]) -> Unit {
  let home = resolve_home(args)
  let cwd = resolve_cwd(args)
  let json_mode = args.contains("--json")
  let result = @onboarding.bootstrap(home~, cwd~)
  if json_mode {
    println(result.to_json().stringify(indent=2))
  } else {
    println(@onboarding.render_bootstrap_result(result))
  }
}

///|
fn print_config(args : Array[String]) -> Unit {
  let home = resolve_home(args)
  println(@onboarding.render_default_config(home~))
}
