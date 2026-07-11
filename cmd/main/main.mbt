///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  match args[1:] {
    ["conversations"] => @conversation.list()
    ["conversation", .. rest] => @conversation.show(rest)
    ["server", .. rest] => @server.start(rest)
    ["daemon", .. rest] => @daemon.start(rest)
    ["gateway", .. rest] => @gateway_command.start(rest)
    ["acp", .. rest] => @acp_command.start(rest)
    ["onboard", .. rest] => @onboard_command.start(rest)
    ["proposal", .. rest] => @proposal.start(rest)
    ["evidence", .. rest] => @evidence_command.start(rest)
    ["exec", .. rest] => @exec.exec(rest)
    ["tui", .. rest] => @tui.tui_interactive(rest)
    ["version"] => println(@buildinfo.version)
    [.. rest] => @interactive.interactive(rest)
  }
}
