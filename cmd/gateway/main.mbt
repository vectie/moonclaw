///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  @gateway_command.start(args)
}
