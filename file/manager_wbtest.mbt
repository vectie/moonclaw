///|
test "scoped manager rejects absolute and parent traversal escapes" {
  let manager = manager(cwd="/tmp/moonclaw-capsule")
  assert_eq(
    manager.resolve_scoped("inputs/goal.txt"),
    Some("/tmp/moonclaw-capsule/inputs/goal.txt"),
  )
  assert_eq(manager.resolve_scoped("../secret.txt"), None)
  assert_eq(manager.resolve_scoped("/Users/example/secret.txt"), None)
}
