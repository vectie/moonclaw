///|
/// Local MoonSuite Agent service entry point. This deliberately exposes only
/// MoonClaw's daemon command, keeping unrelated CLI and gateway packages out
/// of a desktop service build.
async fn main {
  @daemon.start(@os.args()[1:])
}
