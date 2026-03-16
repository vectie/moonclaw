///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  match args[1:] {
    ["conversations"] => @conversation.list()
    ["conversation", .. rest] => @conversation.show(rest)
    ["server", .. rest] => @server.start(rest)
    ["daemon", .. rest] => @daemon.start(rest)
    ["gateway", .. rest] => @gateway.start(rest)
    ["acp", .. rest] => @acp.start(rest)
    ["onboard", .. rest] => @onboard.start(rest)
    ["exec", .. rest] => @exec.exec(rest)
    ["tui", .. rest] => @tui.tui_interactive(rest)
    ["version"] => println(@buildinfo.version)
    [.. rest] => @interactive.interactive(rest)
  }
}
