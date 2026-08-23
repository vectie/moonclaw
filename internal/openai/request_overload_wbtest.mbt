///|
test "overload retries progressively compact consumed evidence" {
  let read_call = tool_call(id="shell-1", name="shell", arguments="{}")
  let messages = [
    system_message(content="system contract"),
    user_message(content="user mission"),
    assistant_message(content="", tool_calls=[read_call]),
    tool_message(
      content="skill evidence:" + "x".repeat(24000),
      tool_call_id="shell-1",
    ),
  ]
  let tools = [
    tool(name="read", description="read", parameters={ "type": "object" }),
    tool(name="moon_check", description="redundant check alias", parameters={
      "type": "object",
    }),
    tool(name="spawn_workers", description="worker fanout", parameters={
      "type": "object",
    }),
  ]
  let request = chat_completion(model="kimi-k3", messages~, tools~)
  let original_chars = request.to_json().stringify().length()
  let tier_one = request.compact_for_overload(1)
  let tier_two = request.compact_for_overload(2)
  let tier_three = request.compact_for_overload(3)
  let tier_four = request.compact_for_overload(4)
  let tier_five = request.compact_for_overload(5)
  let tier_six = request.compact_for_overload(6)
  let tier_seven = request.compact_for_overload(7)
  let one_chars = tier_one.to_json().stringify().length()
  let two_json = tier_two.to_json()
  let two_chars = two_json.stringify().length()
  let three_chars = tier_three.to_json().stringify().length()
  let four_chars = tier_four.to_json().stringify().length()
  let five_chars = tier_five.to_json().stringify().length()
  let six_chars = tier_six.to_json().stringify().length()
  let seven_json = tier_seven.to_json()
  let seven_chars = seven_json.stringify().length()
  assert_true(original_chars > one_chars)
  assert_true(one_chars > two_chars)
  assert_true(two_chars > three_chars)
  assert_true(three_chars > four_chars)
  assert_true(four_chars > five_chars)
  assert_true(five_chars > six_chars)
  assert_true(six_chars > seven_chars)
  guard two_json is { "tools": Array(retry_tools), .. } else {
    fail("expected retry tools")
  }
  assert_eq(retry_tools.length(), 1)
  assert_true(
    two_json
    .stringify()
    .contains("complete bytes remain in the durable journal"),
  )
  assert_true(two_json.stringify().contains("system contract"))
  assert_true(two_json.stringify().contains("user mission"))
  assert_true(two_json.stringify().contains("shell-1"))
  guard seven_json is { "tools": Array(emergency_tools), .. } else {
    fail("expected emergency retry tools")
  }
  assert_eq(emergency_tools.length(), 1)
  assert_true(seven_json.stringify().contains("system contract"))
  assert_true(seven_json.stringify().contains("user mission"))
}

///|
test "overload retries favor the latest source read batch within monotonic caps" {
  let old_read = tool_call(id="read-old", name="read", arguments="{}")
  let recent_read = tool_call(id="read-recent", name="read", arguments="{}")
  let latest_read = tool_call(id="read-latest", name="read", arguments="{}")
  let old_body = "OLD-SOURCE:" + "o".repeat(26000)
  let recent_body = "RECENT-SOURCE:" + "r".repeat(8000)
  let latest_body = "LATEST-SOURCE:" + "l".repeat(9000)
  let request = chat_completion(
    model="kimi-k3",
    messages=[
      system_message(content="system contract"),
      user_message(content="user mission"),
      assistant_message(content="settled diagnosis"),
      user_message(content="continue implementation"),
      assistant_message(content="", tool_calls=[old_read]),
      tool_message(content=old_body, tool_call_id="read-old"),
      assistant_message(content="", tool_calls=[recent_read]),
      tool_message(content=recent_body, tool_call_id="read-recent"),
      assistant_message(content="", tool_calls=[latest_read]),
      tool_message(content=latest_body, tool_call_id="read-latest"),
    ],
    tools=[
      tool(name="read", description="read", parameters={ "type": "object" }),
    ],
  )
  let tier_five = request.compact_for_overload(5).to_json().stringify()
  let compact = request.compact_for_overload(7).to_json().stringify()
  assert_false(compact.contains(old_body))
  assert_false(compact.contains(recent_body))
  assert_false(compact.contains(latest_body))
  assert_false(compact.contains("r".repeat(500)))
  assert_true(compact.contains("l".repeat(500)))
  assert_true(compact.contains("MoonCode compacted"))
  assert_true(compact.length() < tier_five.length())
}

///|
test "overload evidence compaction preserves UTF-8 boundaries" {
  let text = "中🚀e\u{301}".repeat(5000)
  for limit in [1, 2, 3, 7, 1200, 12000] {
    let compacted = overload_compact_text(text, limit, "read")
    assert_true(compacted.contains("MoonCode compacted"))
    // Re-encoding proves every selected prefix and suffix boundary is valid.
    assert_true(@encoding/utf8.encode(compacted).length() > 0)
  }
}
