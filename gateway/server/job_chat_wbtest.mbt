///|
test "parse_reply_thread_job_action recognizes reply controls" {
  inspect(
    parse_reply_thread_job_action("confirm")
    .map(fn(pair) { "\{pair.0}:\{pair.1}" })
    .unwrap_or(""),
    content="confirm:",
  )
  inspect(
    parse_reply_thread_job_action("revise add more validation")
    .map(fn(pair) { "\{pair.0}:\{pair.1}" })
    .unwrap_or(""),
    content="revise:add more validation",
  )
  inspect(parse_reply_thread_job_action("hello") is None, content="true")
}

///|
test "parse_notification_verbosity accepts expected values" {
  inspect(
    parse_notification_verbosity("verbose")
    .map(fn(level) { level.to_json().stringify() })
    .unwrap_or(""),
    content="\"Verbose\"",
  )
  inspect(
    parse_notification_verbosity("off")
    .map(fn(level) { level.to_json().stringify() })
    .unwrap_or(""),
    content="\"Off\"",
  )
  inspect(parse_notification_verbosity("unknown") is None, content="true")
}
