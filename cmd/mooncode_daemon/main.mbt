///|
/// Desktop runtime entry point. Uses the same daemon implementation and CLI
/// arguments as `moonclaw daemon`, and hosts its ordinary server workers,
/// without loading gateway or terminal UI code.
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  match args[1:] {
    ["version"] => println(@buildinfo.version)
    ["daemon", .. rest] => @daemon.start(rest)
    ["server", .. rest] => @server.start(rest)
    [.. rest] => @daemon.start(rest)
  }
}
