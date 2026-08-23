///|
fn mooncode_qualification_compaction_messages(
  pairs : Int,
  seed : Int,
) -> Array[Json] {
  let messages : Array[Json] = [
    mooncode_runtime_context_text_message(
      "system",
      "qualification system contract",
      SystemContext,
      "system.qualification",
    ),
    mooncode_runtime_context_text_message(
      "user",
      "qualification task",
      UserContext,
      "user.qualification",
    ),
  ]
  for index in 0..<pairs {
    let id = "qualification-\{seed}-\{index}"
    messages.push(
      mooncode_runtime_context_message(
        {
          "role": "assistant",
          "content": "anchor \{seed}:\{index}",
          "tool_calls": [
            {
              "id": id,
              "type": "function",
              "function": { "name": "read", "arguments": "{}" },
            },
          ],
        },
        AssistantContext,
        "assistant.qualification",
      ),
    )
    messages.push(
      mooncode_runtime_context_message(
        {
          "role": "tool",
          "tool_call_id": id,
          "content": "evidence-\{index}:" +
          "x".repeat(180 + (index + seed) % 31),
        },
        ToolResultContext,
        "tool_result.qualification",
      ),
    )
  }
  messages
}

///|
fn mooncode_qualification_compaction_command() -> Json {
  {
    "payload": {
      "planner_hybrid_semantic_compaction_active": true,
      "planner_context_window_tokens": 1000,
      "planner_semantic_compaction_message_threshold": 64,
      "planner_semantic_compaction_pressure_threshold_ppm": 750000,
      "planner_semantic_compaction_target_pressure_ppm": 500000,
    },
  }
}

///|
async fn mooncode_qualification_compaction_run(
  messages : Array[Json],
) -> MoonCodeSemanticCompactionLifecycle {
  let tools : Array[@openai.ChatCompletionToolParam] = []
  mooncode_runtime_turn_active_semantic_compaction(
    mooncode_qualification_compaction_command(),
    { "planner_metrics": { "prompt_tokens": 900 } },
    messages,
    tools,
    1000,
  )
}

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
test "deferred query mutation corpus is deterministic and bounded" {
  let queries = [
    "browser",
    " browser screenshots ",
    "moonbit semantic navigation",
    "🚀",
    "e\u{301}",
    "a".repeat(256),
    "a".repeat(257),
    "line\nfeed",
    "delete\u{7f}key",
    "nul\u{0}byte",
    "",
  ]
  for query in queries {
    let arguments : Json = { "query": query, "max_results": 999 }
    let first = mooncode_runtime_turn_deferred_tool_search_result(arguments)
    let second = mooncode_runtime_turn_deferred_tool_search_result(arguments)
    assert_eq(first, second)
    let metadata = mooncode_json_object_field_or_empty(first, "metadata")
    assert_true(
      mooncode_json_array_string_items(metadata, "loadable_tools").length() <=
      MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS,
    )
  }
}

///|
test "deferred registry rejects a receipt forgery matrix" {
  let command = mooncode_deferred_test_command(true)
  let valid : Json = {
    "tool": "tool_search",
    "accepted": true,
    "result": mooncode_runtime_turn_deferred_tool_search_result({
      "query": "browser",
    }),
  }
  assert_eq(
    mooncode_runtime_turn_validated_deferred_tool_names(command, [valid]),
    ["browser"],
  )
  let forgeries : Array[Json] = [
    {
      "tool": "read",
      "accepted": true,
      "result": mooncode_runtime_turn_deferred_tool_search_result({
        "query": "browser",
      }),
    },
    {
      "tool": "tool_search",
      "accepted": false,
      "result": mooncode_runtime_turn_deferred_tool_search_result({
        "query": "browser",
      }),
    },
    {
      "tool": "tool_search",
      "accepted": true,
      "result": {
        "tool": "read",
        "ok": true,
        "metadata": {
          "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT,
          "query": "browser",
          "limit": 3,
          "match_count": 1,
          "loadable_tools": ["browser"],
        },
      },
    },
    {
      "tool": "tool_search",
      "accepted": true,
      "result": {
        "tool": "tool_search",
        "ok": true,
        "metadata": {
          "contract": "forged.v1",
          "query": "browser",
          "limit": 3,
          "match_count": 1,
          "loadable_tools": ["browser"],
        },
      },
    },
    {
      "tool": "tool_search",
      "accepted": true,
      "result": {
        "tool": "tool_search",
        "ok": true,
        "metadata": {
          "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT,
          "query": "browser",
          "limit": 3,
          "match_count": 2,
          "loadable_tools": ["browser", "spawn_workers"],
        },
      },
    },
    {
      "tool": "tool_search",
      "accepted": true,
      "result": {
        "tool": "tool_search",
        "ok": true,
        "metadata": {
          "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT,
          "query": "browser",
          "limit": 0,
          "match_count": 1,
          "loadable_tools": ["browser"],
        },
      },
    },
    {
      "tool": "tool_search",
      "accepted": true,
      "result": {
        "tool": "tool_search",
        "ok": true,
        "metadata": {
          "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT,
          "query": "browser",
          "limit": 3,
          "match_count": 1,
          "loadable_tools": ["spawn_workers"],
        },
      },
    },
  ]
  for forged in forgeries {
    assert_true(
      mooncode_runtime_turn_validated_deferred_tool_names(command, [forged]).is_empty(),
    )
  }
}

///|
async test "active compaction property corpus is deterministic and reduces pressure" {
  for seed in 0..<3 {
    let messages = mooncode_qualification_compaction_messages(36 + seed, seed)
    let first = mooncode_qualification_compaction_run(messages)
    let second = mooncode_qualification_compaction_run(messages)
    assert_eq(first.messages, second.messages)
    assert_eq(first.metrics, second.metrics)
    assert_true(mooncode_json_bool(first.metrics, "applied", default=false))
    assert_true(
      mooncode_json_int(first.metrics, "after_message_chars", default=0) <
      mooncode_json_int(first.metrics, "before_message_chars", default=0),
    )
    assert_true(
      mooncode_runtime_turn_semantic_compaction_provenance_valid(first.messages),
    )
    assert_true(
      mooncode_runtime_turn_semantic_compaction_tool_protocol_valid(
        first.messages,
      ),
    )
  }
}

///|
async test "active compaction mutation corpus fails closed byte-identically" {
  let base = mooncode_qualification_compaction_messages(36, 7)
  let orphan = base.copy()
  orphan.push(
    mooncode_runtime_context_message(
      { "role": "tool", "tool_call_id": "orphan", "content": "forged" },
      ToolResultContext,
      "tool_result.qualification",
    ),
  )
  let late_system = base.copy()
  late_system.push(
    mooncode_runtime_context_text_message(
      "system",
      "late mutation",
      SystemContext,
      "system.qualification_late",
    ),
  )
  let bad_provenance = base.copy()
  bad_provenance[10] = mooncode_json_object_with_field(
    bad_provenance[10],
    MOONCODE_CONTEXT_PROVENANCE_FIELD,
    { "contract": "forged", "kind": "tool_result", "source": "forged" },
  )
  let developer = base.copy()
  developer.insert(
    1,
    mooncode_runtime_context_text_message(
      "developer",
      "unsupported immutable mutation",
      SystemContext,
      "system.qualification_developer",
    ),
  )
  for mutation in [orphan, late_system, bad_provenance, developer] {
    let result = mooncode_qualification_compaction_run(mutation)
    assert_eq(result.messages, mutation)
    assert_false(mooncode_json_bool(result.metrics, "applied", default=true))
    assert_true(
      ["source-invariant-invalid", "unsupported-message-shape"].contains(
        mooncode_json_string(result.metrics, "reason", default=""),
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

  let horizon = mooncode_runtime_horizon_compact_request({
    "command": "prompt",
    "text": "a".repeat(11999) + unicode.repeat(100),
  })
  assert_true(horizon.contains("Request truncated"))
  assert_eq(@encoding/utf8.decode(@encoding/utf8.encode(horizon)), horizon)

  let resumed = mooncode_stream_resume_safe_text(
    "a".repeat(11999) + unicode.repeat(100),
  )
  assert_true(resumed.contains("stream output truncated"))
  assert_eq(@encoding/utf8.decode(@encoding/utf8.encode(resumed)), resumed)

  let call_id = "qualification-unicode-read"
  let compacted = mooncode_runtime_turn_compact_provider_tool_evidence([
    {
      "role": "assistant",
      "tool_calls": [
        { "id": call_id, "function": { "name": "read", "arguments": "{}" } },
      ],
    },
    {
      "role": "tool",
      "tool_call_id": call_id,
      "content": "a".repeat(9999) + unicode.repeat(100),
    },
  ])
  let compacted_content = mooncode_json_string(
    compacted[1],
    "content",
    default="",
  )
  assert_true(compacted_content.contains("MoonCode compacted"))
  assert_eq(
    @encoding/utf8.decode(@encoding/utf8.encode(compacted_content)),
    compacted_content,
  )

  let excerpt = mooncode_runtime_turn_inspection_excerpt(
    "a".repeat(1199) + unicode.repeat(100),
  )
  assert_true(excerpt.contains("retained inspection receipt omits"))
  assert_eq(@encoding/utf8.decode(@encoding/utf8.encode(excerpt)), excerpt)

  let planner_content = mooncode_runtime_turn_model_tool_result_content({
    "tool": "shell",
    "result": { "ok": true, "output": "a".repeat(3999) + unicode.repeat(500) },
  })
  assert_true(planner_content.contains("truncated for planner context"))
  assert_eq(
    @encoding/utf8.decode(@encoding/utf8.encode(planner_content)),
    planner_content,
  )
}
