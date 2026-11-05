///|
test "instruction loading, concurrency and replay have separate contracts" {
  let skill = @mooncode_tools.classify("read_skill", {})
  assert_true(skill.replay)
  assert_false(skill.parallel_read || skill.after_skill)
  assert_true(
    @mooncode_tools.classify("moon_cmd", { "command": "check" }).parallel_read,
  )
  let calls : Array[(String, Json)] = [
    ("moon_cmd", { "command": "fmt" }),
    ("moon_cmd", { "command": "test", "args": ["--update"] }),
    ("moon_cmd", { "command": "test", "arg": "-u" }),
    ("browser", { "action": "eval" }),
    ("future_tool", {}),
  ]
  for (tool, arguments) in calls {
    let policy = @mooncode_tools.classify(tool, arguments)
    assert_false(policy.parallel_read || policy.replay || policy.after_skill)
  }
}

///|
test "shell observations may run concurrently but mutations remain serial" {
  let foreground = @mooncode_tools.classify("shell", {
    "cmd": "git status --short",
  })
  assert_true(foreground.parallel_read && foreground.after_skill)
  assert_false(foreground.replay)
  let calls : Array[Json] = [
    { "cmd": "git status --short", "background": true },
    { "cmd": "printf changed > result.txt" },
    { "cmd": "sed -i 's/before/after/' result.txt" },
    { "cmd": "moon run generate.mbtx" },
  ]
  for arguments in calls {
    let policy = @mooncode_tools.classify("shell", arguments)
    assert_false(policy.parallel_read || policy.after_skill || policy.replay)
  }
}
