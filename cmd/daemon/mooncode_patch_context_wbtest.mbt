///|
test "unified diff no-match teaches body-context matching" {
  let result = mooncode_tool_apply_unified_chunks_to_content(
    "apply_patch",
    "target.mbt",
    "/book/target.mbt",
    "fn actual {\n  1\n}\n",
    [{ "old_text": "fn stale {\n  1\n}\n", "new_text": "fn stale {\n  2\n}\n" }],
    reverse=false,
  )
  let message = mooncode_json_string(result, "message", default="")
  assert_true(message.contains("did not match target.mbt"))
  assert_true(
    message.contains("hunk labels are descriptive, not match anchors"),
  )
  assert_true(message.contains("matching uses unchanged hunk body context"))
  assert_true(message.contains("unique unchanged lines from target.mbt"))
  assert_true(message.contains("use `edit`/`write` with exact content"))
}

///|
test "unified diff ambiguity teaches unique body context" {
  let repeated = "fn one {\n  shared()\n}\nfn two {\n  shared()\n}\n"
  let result = mooncode_tool_apply_unified_chunks_to_content(
    "apply_patch",
    "target.mbt",
    "/book/target.mbt",
    repeated,
    [{ "old_text": "  shared()\n", "new_text": "  changed()\n" }],
    reverse=false,
  )
  let message = mooncode_json_string(result, "message", default="")
  assert_true(message.contains("matched 2 times in target.mbt"))
  assert_true(message.contains("refusing ambiguous patch"))
  assert_true(
    message.contains("hunk labels are descriptive, not match anchors"),
  )
  assert_true(message.contains("matching uses unchanged hunk body context"))
  assert_true(message.contains("unique unchanged lines from target.mbt"))
  assert_true(message.contains("use `edit`/`write` with exact content"))
}
