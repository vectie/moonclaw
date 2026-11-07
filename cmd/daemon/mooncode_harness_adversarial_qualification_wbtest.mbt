///|
test "context provenance token boundaries and normalization are fail-soft" {
  let valid_64 = "a".repeat(64)
  let valid_160 = "s".repeat(160)
  assert_true(mooncode_runtime_context_token_valid(valid_64, 64))
  assert_false(mooncode_runtime_context_token_valid(valid_64 + "a", 64))
  assert_true(mooncode_runtime_context_token_valid(valid_160, 160))
  assert_false(mooncode_runtime_context_token_valid(valid_160 + "s", 160))
  for
    invalid in [
      "", "has space", "slash/value", "line\nfeed", "nul\u{0}", "中", "🚀",
    ] {
    assert_false(mooncode_runtime_context_token_valid(invalid, 160))
    let visible : Json = {
      "role": "user",
      "content": "visible:\{invalid.length()}",
    }
    let malformed = mooncode_json_object_with_field(
      visible,
      MOONCODE_CONTEXT_PROVENANCE_FIELD,
      {
        "contract": MOONCODE_CONTEXT_PROVENANCE_CONTRACT,
        "kind": invalid,
        "source": invalid,
      },
    )
    let normalized = mooncode_runtime_context_normalize_message(malformed)
    assert_eq(mooncode_runtime_context_visible_message(normalized), visible)
    assert_true(
      mooncode_runtime_context_provenance_valid(
        mooncode_runtime_context_provenance(normalized),
      ),
    )
  }
}

///|
test "tool output cap preserves Unicode boundaries and exact accounting" {
  let text = "中🚀e\u{301}".repeat(5000)
  for limit in [1, 2, 3, 7, 11999, 12000, 12001, 49999, 50000, 50001] {
    let capped = mooncode_cap_tool_output(text, limit)
    let effective = mooncode_json_int(capped, "max_output_chars", default=0)
    let output = mooncode_json_string(capped, "output", default="")
    assert_true(output.length() <= effective.min(text.length()))
    assert_true(text.has_prefix(output))
    assert_eq(
      mooncode_json_int(capped, "char_count", default=-1),
      text.length(),
    )
    assert_eq(
      mooncode_json_bool(capped, "truncated", default=false),
      text.length() > effective,
    )
  }
}

///|
test "failed output cap remains bounded at Unicode-heavy boundaries" {
  let text = "prefix中🚀\n" + "诊断🚨".repeat(6000) + "\nfinal-error🚫"
  for limit in [1, 2, 39, 40, 11999, 12000, 12001] {
    let capped = mooncode_cap_failed_process_output(text, limit)
    let effective = mooncode_json_int(capped, "max_output_chars", default=0)
    let output = mooncode_json_string(capped, "output", default="")
    assert_true(output.length() <= effective)
    assert_true(mooncode_json_bool(capped, "truncated", default=false))
  }
}

///|
test "all planner truncation surfaces preserve UTF-8 boundaries" {
  let unicode = "中🚀e\u{301}"
  for limit in [0, 1, 2, 3, 4, 7, 31, 12000] {
    let prefix = mooncode_utf8_prefix_within(unicode.repeat(2000), limit)
    let suffix = mooncode_utf8_suffix_within(unicode.repeat(2000), limit)
    assert_true(prefix.length() <= limit.max(0))
    assert_true(suffix.length() <= limit.max(0))
    assert_true(unicode.repeat(2000).has_prefix(prefix))
    assert_true(unicode.repeat(2000).has_suffix(suffix))
    assert_eq(@encoding/utf8.decode(@encoding/utf8.encode(prefix)), prefix)
    assert_eq(@encoding/utf8.decode(@encoding/utf8.encode(suffix)), suffix)
  }

  let planner_content = mooncode_runtime_turn_model_tool_result_content({
    "tool": "shell",
    "result": { "ok": true, "output": "a".repeat(3999) + unicode.repeat(500) },
  })
  assert_true(planner_content.contains(unicode.repeat(500)))
  ignore(@json.parse(planner_content.split("\n").head().unwrap()))
  assert_eq(
    @encoding/utf8.decode(@encoding/utf8.encode(planner_content)),
    planner_content,
  )
}
