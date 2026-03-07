///|
fn logger() -> @pino.Logger {
  @pino.logger("gateway", @pino.Transport::console())
}
