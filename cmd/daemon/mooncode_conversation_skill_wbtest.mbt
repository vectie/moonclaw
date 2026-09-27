///|
test "canonical skill evidence shows installed source and digest without skill body" {
  let event : Json = {
    "kind": "runtime.tool_result",
    "event": "tool_result",
    "lane": "runtime",
    "tool": "read_skill",
    "status": "done",
    "tool_call_id": "skill-call",
    "tool_result": {
      "ok": true,
      "output": "private skill body",
      "metadata": {
        "name": "moonbit-agent-guide",
        "path": "SKILL.md",
        "content_sha256_base64": "abc123",
      },
    },
  }
  assert_eq(mooncode_conversation_work_step_kind(event), "skill")
  let evidence = mooncode_conversation_work_evidence(event)
  assert_eq(mooncode_json_string(evidence, "kind", default=""), "skill")
  assert_eq(
    mooncode_json_string(evidence, "path", default=""),
    "moonbit-agent-guide/SKILL.md",
  )
  let output = mooncode_json_string(evidence, "output", default="")
  assert_true(output.contains("installed skill catalog"))
  assert_true(output.contains("abc123"))
  assert_false(output.contains("private skill body"))
  let failed = mooncode_conversation_work_evidence({
    "kind": "runtime.tool_result",
    "event": "tool_result",
    "lane": "runtime",
    "tool": "read_skill",
    "status": "failed",
    "tool_result": { "ok": false, "metadata": { "name": "missing" } },
  })
  assert_true(
    mooncode_json_string(failed, "output", default="").contains(
      "could not be loaded",
    ),
  )
}
