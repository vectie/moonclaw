///|
test "parse_reply_thread_job_action recognizes reply controls" {
  inspect(
    @job.parse_reply_thread_job_action("confirm")
    .map(fn(pair) { "\{pair.0}:\{pair.1}" })
    .unwrap_or(""),
    content="confirm:",
  )
  inspect(
    @job.parse_reply_thread_job_action("revise add more validation")
    .map(fn(pair) { "\{pair.0}:\{pair.1}" })
    .unwrap_or(""),
    content="revise:add more validation",
  )
  inspect(@job.parse_reply_thread_job_action("hello") is None, content="true")
}

///|
test "parse_notification_verbosity accepts expected values" {
  inspect(
    @job.parse_notification_verbosity("verbose")
    .map(fn(level) { level.to_json().stringify() })
    .unwrap_or(""),
    content="\"Verbose\"",
  )
  inspect(
    @job.parse_notification_verbosity("off")
    .map(fn(level) { level.to_json().stringify() })
    .unwrap_or(""),
    content="\"Off\"",
  )
  inspect(@job.parse_notification_verbosity("unknown") is None, content="true")
}

///|
test "parse_job_chat_action recognizes slash and reply commands" {
  inspect(
    match @job.parse_job_chat_action("/plan review yesterday papers", false) {
      Some(Plan(args)) => args
      _ => ""
    },
    content="review yesterday papers",
  )
  inspect(
    match
      @job.parse_job_chat_action("/plan-job review yesterday papers", false) {
      Some(PlanJob(args)) => args
      _ => ""
    },
    content="review yesterday papers",
  )
  inspect(
    match @job.parse_job_chat_action("/e2e review yesterday papers", false) {
      Some(E2EJob(args)) => args
      _ => ""
    },
    content="review yesterday papers",
  )
  inspect(
    match @job.parse_job_chat_action("/preview", false) {
      Some(Preview(args)) => args
      _ => "missing"
    },
    content="",
  )
  inspect(
    match
      @job.parse_job_chat_action("/preview tighten cost assumptions", false) {
      Some(Preview(args)) => args
      _ => ""
    },
    content="tighten cost assumptions",
  )
  inspect(
    match @job.parse_job_chat_action("/promote keep the market comps", false) {
      Some(Promote(args)) => args
      _ => ""
    },
    content="keep the market comps",
  )
  inspect(
    match @job.parse_job_chat_action("confirm", true) {
      Some(Confirm(args)) => args
      _ => "missing"
    },
    content="",
  )
  inspect(
    match @job.parse_job_chat_action("/job-force-stop run-1", false) {
      Some(JobForceStop(args)) => args
      _ => ""
    },
    content="run-1",
  )
  inspect(
    match @job.parse_job_chat_action("/resume parcel docs attached", false) {
      Some(Resume(args)) => args
      _ => ""
    },
    content="parcel docs attached",
  )
  inspect(
    match @job.parse_job_chat_action("/remember save this note", false) {
      Some(Remember(args)) => args
      _ => ""
    },
    content="save this note",
  )
  inspect(
    match @job.parse_job_chat_action("/memories", false) {
      Some(Memories) => "memories"
      _ => ""
    },
    content="memories",
  )
  inspect(
    match @job.parse_job_chat_action("/memory-search retrieval", false) {
      Some(MemorySearch(args)) => args
      _ => ""
    },
    content="retrieval",
  )
  inspect(
    match @job.parse_job_chat_action("hello", false) {
      None => true
      _ => false
    },
    content="true",
  )
}

///|
test "feishu progress status helpers render expected text" {
  inspect(thinking_status_text(), content="thinking")
  inspect(tool_status_text("execute_command"), content="tool")
  inspect(drafting_status_text(), content="drafting")
}

///|
test "message_resume_input includes content and attachments" {
  let payload = message_resume_input({
    id: "msg-1",
    channel: "feishu",
    from: "user-1",
    to: "chat-1",
    content: "here is the missing file",
    content_type: "text",
    timestamp: 123,
    thread_id: Some("thread-1"),
    reply_to: Some("reply-1"),
    attachments: [
      {
        id: "file-1",
        mime_type: "application/pdf",
        url: "https://example.test/file.pdf",
        filename: Some("file.pdf"),
        size: Some(42),
      },
    ],
  })
  let payload_text = payload.stringify()
  inspect(
    payload_text.contains("\"resume_content\":\"here is the missing file\""),
    content="true",
  )
  inspect(
    payload_text.contains(
      "\"attachments\":[{\"id\":\"file-1\",\"mime_type\":\"application/pdf\",\"url\":\"https://example.test/file.pdf\",\"filename\":\"file.pdf\",\"size\":\"42\"}]",
    ),
    content="true",
  )
}

///|
test "plan_job_input includes attachments and output format hint" {
  let payload = plan_job_input(
    "feishu",
    "default",
    {
      id: "msg-2",
      channel: "feishu",
      from: "user-1",
      to: "chat-1",
      content: "/plan-job Analyze the attached memo.\nOutput format: Executive summary",
      content_type: "text",
      timestamp: 123,
      thread_id: Some("thread-2"),
      reply_to: None,
      attachments: [
        {
          id: "file-2",
          mime_type: "text/plain",
          url: "https://example.test/memo.txt",
          filename: Some("memo.txt"),
          size: Some(7),
        },
      ],
    },
    "Analyze the attached memo.\nOutput format: Executive summary",
    starter_attachments_from_channel([
      {
        id: "file-2",
        mime_type: "text/plain",
        url: "https://example.test/memo.txt",
        filename: Some("memo.txt"),
        size: Some(7),
      },
    ]),
  )
  let payload_text = payload.stringify()
  inspect(
    payload_text.contains("\"requested_output_format\":\"Executive summary\""),
    content="true",
  )
  inspect(payload_text.contains("\"starter_attachments\":"), content="true")
  inspect(payload_text.contains("\"filename\":\"memo.txt\""), content="true")
  inspect(payload_text.contains("\"channel_id\":\"feishu\""), content="true")
  inspect(payload_text.contains("\"account_id\":\"default\""), content="true")
  inspect(payload_text.contains("\"recipient\":\"chat-1\""), content="true")
}

///|
test "merge_starter_attachments de-duplicates by attachment id" {
  let merged = merge_starter_attachments(
    [
      @job.E2EStarterAttachment::new(
        id="file-1",
        mime_type="application/pdf",
        url="https://example.test/one.pdf",
        filename=Some("one.pdf"),
      ),
    ],
    [
      @job.E2EStarterAttachment::new(
        id="file-1",
        mime_type="application/pdf",
        url="https://example.test/one.pdf",
        filename=Some("one.pdf"),
      ),
      @job.E2EStarterAttachment::new(
        id="file-2",
        mime_type="text/plain",
        url="https://example.test/two.txt",
        filename=Some("two.txt"),
      ),
    ],
  )
  inspect(merged.length(), content="2")
  inspect(merged[0].id, content="file-1")
  inspect(merged[1].id, content="file-2")
}

///|
test "thread_attachment_key falls back to chat scope when thread id is missing" {
  inspect(
    thread_attachment_key("feishu", "default", {
      id: "msg-1",
      channel: "feishu",
      from: "user-1",
      to: "oc_chat_123",
      content: "file upload",
      content_type: "file",
      timestamp: 1,
      thread_id: None,
      reply_to: None,
      attachments: [],
    }).unwrap_or(""),
    content="feishu:default:oc_chat_123:chat",
  )
}

///|
test "seed_resume_notification_cursor skips historical events on resume" {
  let state = @job.GatewayJobState::new(root="unused")
  seed_resume_notification_cursor(state, "run-1", 5, 123)
  let runtime_state = state.notification_runtime_state("run-1")
  inspect(runtime_state.last_notified_event_count.to_string(), content="5")
  inspect(runtime_state.last_sent_at.to_string(), content="123")
}

///|
test "plan_job_input can use starter files gathered earlier in the thread" {
  let payload = plan_job_input(
    "feishu",
    "default",
    {
      id: "msg-3",
      channel: "feishu",
      from: "user-1",
      to: "chat-1",
      content: "/e2e Land acquisition estimation Output format: Board memo",
      content_type: "text",
      timestamp: 123,
      thread_id: Some("thread-3"),
      reply_to: None,
      attachments: [],
    },
    "Land acquisition estimation Output format: Board memo",
    [
      @job.E2EStarterAttachment::new(
        id="file-3",
        mime_type="application/pdf",
        url="https://example.test/parcel.pdf",
        filename=Some("parcel.pdf"),
      ),
    ],
  )
  let payload_text = payload.stringify()
  inspect(
    payload_text.contains("\"request_text\":\"Land acquisition estimation\""),
    content="true",
  )
  inspect(
    payload_text.contains("\"requested_output_format\":\"Board memo\""),
    content="true",
  )
  inspect(payload_text.contains("\"starter_attachments\":"), content="true")
  inspect(payload_text.contains("\"filename\":\"parcel.pdf\""), content="true")
}
