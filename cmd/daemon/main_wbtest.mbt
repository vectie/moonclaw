///|
async test "foreground daemon startup permits an unconfigured home" (
  t : @test.Test,
) {
  ignore(t)
  let serve = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-daemon-unconfigured-XXXXXX"),
  )
  let daemon = prepare_foreground_daemon(
    Some(@os.executable()),
    0,
    serve,
    lock=false,
  )
  assert_true(daemon is Some(_))
}
