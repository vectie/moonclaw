///|
test "tool effects classify reads, mutations, and batch seals explicitly" {
  assert_true(
    mooncode_runtime_tool_effect({ "tool": "read", "arguments": {} })
    is ConcurrentRead,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "moon_ide",
      "arguments": { "action": "outline", "path": "cmd/daemon" },
    })
    is ConcurrentRead,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "moon_cmd",
      "arguments": { "command": "build" },
    })
    is ConcurrentRead,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "moon_cmd",
      "arguments": { "command": "test", "args": ["--update"] },
    })
    is ExclusiveMutation,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "browser",
      "arguments": { "action": "snapshot" },
    })
    is ConcurrentRead,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "browser",
      "arguments": { "action": "eval", "expression": "document.body.remove()" },
    })
    is ExclusiveMutation,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "browser",
      "arguments": { "action": "open", "url": "http://127.0.0.1:3000" },
    })
    is ExclusiveMutation,
  )
  assert_true(
    mooncode_runtime_tool_effect({ "tool": "grep", "arguments": {} })
    is ExclusiveMutation,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "shell",
      "arguments": { "cmd": "printf 'read-only'" },
    })
    is ConcurrentRead,
  )
  assert_true(
    mooncode_runtime_tool_effect({
      "tool": "edit",
      "arguments": { "path": "wiki/index.md" },
    })
    is ExclusiveMutation,
  )
  assert_true(
    mooncode_runtime_tool_effect({ "tool": "finish", "arguments": {} })
    is BatchSeal,
  )
  assert_eq(mooncode_runtime_tool_effect_key(ConcurrentRead), "concurrent_read")
  assert_eq(
    mooncode_runtime_tool_effect_key(ExclusiveMutation),
    "exclusive_mutation",
  )
  assert_eq(mooncode_runtime_tool_effect_key(BatchSeal), "batch_seal")
}
