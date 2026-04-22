///|
async test "apply_patch rejects absolute path outside workspace" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let outside = "/tmp/moonclaw-apply-patch-outside.txt"
    let patch =
      #|*** Begin Patch
      #|*** Add File: /tmp/moonclaw-apply-patch-outside.txt
      #|+escaped
      #|*** End Patch
    let tool = new(mock.cwd.path())
    let result = tool.call({ "patch": patch })
    guard result is Error(_) else {
      fail("Expected tool error for absolute path escape, got: \{result}")
    }
    inspect(
      mock.text(result),
      content="Failed to apply patch: Patch path must stay inside the current workspace: /tmp/moonclaw-apply-patch-outside.txt",
    )
    assert_false(@fsx.exists(outside))
  })
}

///|
async test "apply_patch rejects parent path escape" (t : @test.Test) {
  @mock.run(t, mock => {
    let patch =
      #|*** Begin Patch
      #|*** Add File: ../escape.txt
      #|+escaped
      #|*** End Patch
    let tool = new(mock.cwd.path())
    let result = tool.call({ "patch": patch })
    guard result is Error(_) else {
      fail("Expected tool error for parent path escape, got: \{result}")
    }
    inspect(
      mock.text(result),
      content="Failed to apply patch: Patch path must not escape the current workspace: ../escape.txt",
    )
  })
}
