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
    match
      @job.parse_job_chat_action("/plan-job review yesterday papers", false) {
      Some(@job.JobChatAction::PlanJob(args)) => args
      _ => ""
    },
    content="review yesterday papers",
  )
  inspect(
    match @job.parse_job_chat_action("confirm", true) {
      Some(@job.JobChatAction::Confirm(args)) => args
      _ => "missing"
    },
    content="",
  )
  inspect(
    match @job.parse_job_chat_action("/job-force-stop run-1", false) {
      Some(@job.JobChatAction::JobForceStop(args)) => args
      _ => ""
    },
    content="run-1",
  )
  inspect(
    match @job.parse_job_chat_action("/resume parcel docs attached", false) {
      Some(@job.JobChatAction::Resume(args)) => args
      _ => ""
    },
    content="parcel docs attached",
  )
  inspect(
    match @job.parse_job_chat_action("/remember save this note", false) {
      Some(@job.JobChatAction::Remember(args)) => args
      _ => ""
    },
    content="save this note",
  )
  inspect(
    match @job.parse_job_chat_action("/memories", false) {
      Some(@job.JobChatAction::Memories) => "memories"
      _ => ""
    },
    content="memories",
  )
  inspect(
    match @job.parse_job_chat_action("/memory-search retrieval", false) {
      Some(@job.JobChatAction::MemorySearch(args)) => args
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
  let payload = message_resume_input(@channel.Message::{
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
      @channel.Attachment::{
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
    @channel.Message::{
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
        @channel.Attachment::{
          id: "file-2",
          mime_type: "text/plain",
          url: "https://example.test/memo.txt",
          filename: Some("memo.txt"),
          size: Some(7),
        },
      ],
    },
    "Analyze the attached memo.\nOutput format: Executive summary",
  )
  let payload_text = payload.stringify()
  inspect(
    payload_text.contains("\"requested_output_format\":\"Executive summary\""),
    content="true",
  )
  inspect(payload_text.contains("\"starter_attachments\":"), content="true")
  inspect(payload_text.contains("\"filename\":\"memo.txt\""), content="true")
}
