///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  @acp_command.start(args)
}
