///|
test "instruction reads, local validation and replay have separate contracts" {
  let skill = @mooncode_tools.classify("read_skill", {})
  assert_true(skill.local_operation && skill.replay)
  assert_false(skill.parallel_read || skill.after_skill)
  let check = @mooncode_tools.classify("moon_cmd", { "command": "check" })
  assert_true(
    check.local_operation && check.local_validation && check.parallel_read,
  )
  assert_false(check.replay || check.after_skill)
  let fmt = @mooncode_tools.classify("moon_cmd", { "command": "fmt" })
  assert_true(fmt.local_validation)
  assert_false(fmt.parallel_read || fmt.after_skill || fmt.replay)
  let browser = @mooncode_tools.classify("browser", { "action": "eval" })
  assert_true(browser.local_operation)
  assert_false(browser.parallel_read || browser.replay || browser.after_skill)
}

///|
test "unknown tools and snapshot updates cannot borrow observation properties" {
  let calls : Array[(String, Json)] = [
    ("future_tool", {}),
    ("moon_cmd", { "command": "test", "args": ["--update"] }),
    ("moon_cmd", { "command": "test", "arg": "-u" }),
    ("browser", { "action": "open", "url": "https://example.com" }),
  ]
  for (tool, arguments) in calls {
    let policy = @mooncode_tools.classify(tool, arguments)
    assert_false(
      policy.parallel_read ||
      policy.replay ||
      policy.local_operation ||
      policy.local_validation,
    )
  }
}

///|
test "safe shell inspection does not imply background concurrency or replay" {
  let foreground = @mooncode_tools.classify("shell", {
    "cmd": "git status --short",
  })
  assert_true(
    foreground.parallel_read &&
    foreground.after_skill &&
    foreground.local_operation,
  )
  assert_false(foreground.replay)
  let background = @mooncode_tools.classify("shell", {
    "cmd": "git status --short",
    "background": true,
  })
  assert_false(
    background.parallel_read || background.after_skill || background.replay,
  )
  let mutation = @mooncode_tools.classify("shell", { "cmd": "touch marker.txt" })
  assert_false(
    mutation.parallel_read ||
    mutation.after_skill ||
    mutation.replay ||
    mutation.local_operation,
  )
}
