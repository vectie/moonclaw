///|
test "mooncode stream normalizes moonclaw task events into lanes" {
  let pre_conversation = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(42L),
        PreConversation,
      ),
    ),
    index=0,
  )
  assert_eq(
    mooncode_json_string(pre_conversation, "kind", default=""),
    "conversation_started",
  )
  assert_eq(
    mooncode_json_string(pre_conversation, "status", default=""),
    "running",
  )
  let assistant = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(43L),
        AssistantMessageDelta("working"),
      ),
    ),
    index=1,
  )
  assert_eq(mooncode_json_string(assistant, "lane", default=""), "transcript")
  assert_eq(
    mooncode_json_string(assistant, "kind", default=""),
    "assistant_delta",
  )
  assert_eq(mooncode_json_string(assistant, "detail", default=""), "working")
  let assistant_message = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(43L),
        AssistantMessage(usage=None, tool_calls=[], "final answer"),
      ),
    ),
    index=2,
  )
  assert_eq(
    mooncode_json_string(assistant_message, "kind", default=""),
    "assistant_message",
  )
  assert_eq(
    mooncode_json_string(assistant_message, "status", default=""),
    "done",
  )
  assert_eq(
    mooncode_json_string(assistant_message, "detail", default=""),
    "final answer",
  )
  let pre_tool = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(44L),
        PreToolCall(@ai.tool_call(id="tc-1", name="read_file")),
      ),
    ),
    index=3,
  )
  assert_eq(mooncode_json_string(pre_tool, "lane", default=""), "tool")
  assert_eq(mooncode_json_string(pre_tool, "kind", default=""), "tool_call")
  assert_eq(mooncode_json_string(pre_tool, "status", default=""), "running")
  assert_eq(mooncode_json_string(pre_tool, "detail", default=""), "read_file")
  let tool = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(45L),
        PostToolCall(
          @ai.tool_call(id="tc-1", name="read_file"),
          result=Ok({ "ok": true }),
          rendered="ok",
        ),
      ),
    ),
    index=4,
  )
  assert_eq(mooncode_json_string(tool, "lane", default=""), "tool")
  assert_eq(mooncode_json_string(tool, "kind", default=""), "tool_result")
  assert_eq(mooncode_json_string(tool, "detail", default=""), "read_file")
  assert_eq(mooncode_json_string(tool, "rendered_text", default=""), "ok")
  assert_true(
    mooncode_json_object_field_or_empty(tool, "structured_result")
    .stringify()
    .contains("\"ok\":true"),
  )
  let pruned = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(46L),
        ContextPruned(origin_token_count=100, pruned_token_count=40),
      ),
    ),
    index=5,
  )
  assert_eq(mooncode_json_string(pruned, "lane", default=""), "runtime")
  assert_eq(mooncode_json_string(pruned, "kind", default=""), "context_pruned")
  assert_eq(
    mooncode_json_string(pruned, "detail", default=""),
    "Context pruned from 100 to 40 tokens",
  )
  let pruned_event = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(47L),
        Pruned(id=@uuid.nil),
      ),
    ),
    index=6,
  )
  assert_eq(
    mooncode_json_string(pruned_event, "kind", default=""),
    "context_event_pruned",
  )
  let cancelled = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(48L),
        Cancelled,
      ),
    ),
    index=7,
  )
  assert_eq(mooncode_json_string(cancelled, "lane", default=""), "review")
  assert_eq(
    mooncode_json_string(cancelled, "kind", default=""),
    "runtime_aborted",
  )
  assert_eq(mooncode_json_string(cancelled, "status", default=""), "cancelled")
  let failed = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(49L),
        Failed({ "code": "boom" }),
      ),
    ),
    index=8,
  )
  assert_eq(mooncode_json_string(failed, "lane", default=""), "review")
  assert_eq(mooncode_json_string(failed, "kind", default=""), "runtime_aborted")
  assert_eq(mooncode_json_string(failed, "status", default=""), "failed")
  assert_true(
    mooncode_json_object_field_or_empty(failed, "structured_result")
    .stringify()
    .contains("\"code\":\"boom\""),
  )
  let post_conversation = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(50L),
        PostConversation,
      ),
    ),
    index=9,
  )
  assert_eq(
    mooncode_json_string(post_conversation, "kind", default=""),
    "conversation_finished",
  )
  assert_eq(
    mooncode_json_string(post_conversation, "status", default=""),
    "done",
  )
}

///|
test "mooncode durable stream records support resumable sequence replay" {
  let first : Json = {
    "id": "event-1",
    "kind": "assistant_delta",
    "lane": "transcript",
  }
  let second : Json = { "id": "event-2", "kind": "tool_result", "lane": "tool" }
  let records = mooncode_stream_records(
    "session-stream",
    "/tmp/book",
    [first, second],
    since=1,
    wait_ms=1000,
    poll_ms=100,
    wait_elapsed_ms=300,
    wait_attempt_count=3,
  )
  assert_eq(records.length(), 3)
  assert_eq(mooncode_json_string(records[0], "type", default=""), "meta")
  assert_eq(mooncode_json_int(records[0], "event_count", default=0), 2)
  assert_eq(mooncode_json_int(records[0], "emitted_count", default=0), 1)
  assert_eq(mooncode_json_int(records[0], "wait_ms", default=0), 1000)
  assert_eq(mooncode_json_int(records[0], "poll_ms", default=0), 100)
  assert_eq(mooncode_json_int(records[0], "wait_elapsed_ms", default=0), 300)
  assert_eq(mooncode_json_int(records[0], "wait_attempt_count", default=0), 3)
  assert_eq(mooncode_json_string(records[1], "type", default=""), "event")
  assert_eq(mooncode_json_int(records[1], "sequence", default=0), 2)
  assert_eq(mooncode_json_string(records[1], "event_id", default=""), "event-2")
  assert_eq(mooncode_json_string(records[2], "type", default=""), "done")
  assert_eq(mooncode_json_int(records[2], "next_since", default=0), 2)
  assert_eq(mooncode_json_int(records[2], "wait_elapsed_ms", default=0), 300)
}

///|
test "mooncode durable stream serializes jsonl and sse envelopes" {
  let event : Json = { "id": "event-1", "kind": "tool_result", "lane": "tool" }
  let jsonl = mooncode_stream_jsonl_payload(
    "session-stream",
    "/tmp/book",
    [event],
    since=0,
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_true(jsonl.contains("\"type\":\"meta\""))
  assert_true(jsonl.contains("\"type\":\"event\""))
  assert_true(jsonl.contains("\"type\":\"done\""))
  let sse = mooncode_stream_sse_payload(
    "session-stream",
    "/tmp/book",
    [event],
    since=0,
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_true(sse.contains("event: meta\n"))
  assert_true(sse.contains("event: event\n"))
  assert_true(sse.contains("data: {"))
}

///|
test "mooncode stream wait options clamp to bounded live tail values" {
  assert_eq(mooncode_stream_wait_ms_value(-1), 0)
  assert_eq(mooncode_stream_wait_ms_value(0), 0)
  assert_eq(mooncode_stream_wait_ms_value(1000), 1000)
  assert_eq(mooncode_stream_wait_ms_value(90000), 30000)
  assert_eq(mooncode_stream_poll_ms_value(1), 25)
  assert_eq(mooncode_stream_poll_ms_value(100), 100)
  assert_eq(mooncode_stream_poll_ms_value(9000), 2000)
}
