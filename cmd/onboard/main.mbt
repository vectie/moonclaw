///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  @onboard_command.start(args)
}
