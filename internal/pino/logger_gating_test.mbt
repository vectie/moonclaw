///|
async test "threshold query matches actual filtering at every severity and on children" {
  let levels : Array[@pino.Level] = [Trace, Debug, Info, Warn, Error, Fatal]
  for threshold in levels {
    let logs : Array[Json] = []
    let logger = @pino.logger(
      "threshold",
      level=threshold,
      @pino.Transport::callback(log => logs.push(log)),
    )
    let child = logger.child({ "child": true })
    for severity in levels {
      let expected = severity >= threshold
      assert_eq(logger.is_enabled(severity), expected)
      assert_eq(child.is_enabled(severity), expected)
      let before = logs.length()
      child.log(severity, "threshold fixture", data={
        "marker": "quoted \" 你🌙",
      })
      assert_eq(logs.length() - before, if expected { 1 } else { 0 })
      if expected {
        guard logs[before]
          is {
            "level": level,
            "child": True,
            "marker": String("quoted \" 你🌙"),
            ..
          } else {
          fail("Log payload or child context changed")
        }
        assert_eq(level, ToJson::to_json(severity))
      }
    }
  }
}

///|
test "default Info avoids diagnostic construction but permits errors" {
  let logger = @pino.logger("default", @pino.Transport::sink())
  assert_false(logger.is_enabled(Trace))
  assert_false(logger.is_enabled(Debug))
  assert_true(logger.is_enabled(Info))
  assert_true(logger.is_enabled(Warn))
  assert_true(logger.is_enabled(Error))
  assert_true(logger.is_enabled(Fatal))
}
