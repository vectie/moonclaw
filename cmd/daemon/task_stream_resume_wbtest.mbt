///|
fn task_stream_test_event(desc : @event.EventDesc) -> @server.ServerStreamEvent {
  Moonclaw(
    @event.Event::new(
      id=try! @uuid.parse("123e4567-e89b-12d3-a456-426614174000"),
      desc,
    ),
  )
}

///|
test "task stream exposes answers and hides internal events" {
  let projected = task_stream_project(
    task_stream_test_event(AssistantMessageDelta("hello")),
  )
  assert_true(
    projected
    is Some(
      {
        "contract": "moonclaw-task-stream.v2",
        "kind": "answer_delta",
        "content": "hello",
        ..
      }
    ),
  )
  assert_true(
    task_stream_project(task_stream_test_event(TokenCounted(123456))) is None,
  )
  assert_true(
    task_stream_project(
      task_stream_test_event(SystemPromptSet(Some("private prompt"))),
    )
    is None,
  )
}

///|
test "task stream failure projection does not expose provider error" {
  let serialized = task_stream_project(
      task_stream_test_event(
        Failed({
          "message": "secret /Users/operator/workspace and raw provider trace",
        }),
      ),
    )
    .unwrap()
    .stringify()
  assert_true(serialized.contains("could not complete"))
  assert_false(serialized.contains("provider trace"))
  assert_false(serialized.contains("/Users/"))
}

///|
async test "task stream cursor is task-bound and tamper evident" {
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "task-stream-cursor-XXXXXX"),
  )
  let daemon = mooncode_control_test_daemon(root)
  task_stream_install_cursor_secret(root, "0123456789abcdef0123456789abcdef")
  let cursor = daemon.task_stream_cursor("task-a", 37)
  assert_eq(daemon.task_stream_parse_cursor("task-a", cursor), Some(37))
  assert_eq(daemon.task_stream_parse_cursor("task-b", cursor), None)
  assert_eq(daemon.task_stream_parse_cursor("task-a", cursor + "0"), None)
}

///|
test "task stream content cap preserves valid UTF-8" {
  let text = "中🚀e\u{301}".repeat(50000)
  let capped = task_stream_content(text)
  assert_true(@encoding/utf8.encode(capped).length() <= 200100)
  assert_true(capped.contains("answer projection truncated"))
  assert_eq(@encoding/utf8.decode(@encoding/utf8.encode(capped)), capped)
}
