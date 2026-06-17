///|
test "mooncode eval report records delegated task execution" {
  let report = mooncode_eval_report_payload(
    "session-demo",
    None,
    None,
    None,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(mooncode_json_string(report, "status", default=""), "pending")
  assert_true(report.stringify().contains("tool-loop-execution"))
}

///|
test "mooncode eval report accepts durable sidecar evidence" {
  let report = mooncode_eval_report_payload(
    "session-demo",
    None,
    Some({
      "kind": "mooncode-session-record",
      "book_root": "/tmp/book",
      "command_log_count": 2,
      "event_log_count": 5,
      "package_result_log_count": 1,
    }),
    None,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(mooncode_json_string(report, "status", default=""), "accepted")
  assert_eq(
    mooncode_json_string(report, "source", default=""),
    "moonclaw-native-sidecar",
  )
  assert_true(report.stringify().contains("durable-sidecar-replay"))
  assert_true(report.stringify().contains("5 event(s)"))
}

///|
test "mooncode eval report embeds native harness evidence" {
  let report = mooncode_eval_report_payload(
    "session-demo",
    None,
    Some({
      "kind": "mooncode-session-record",
      "book_root": "/tmp/book",
      "command_log_count": 1,
    }),
    Some({
      "kind": "mooncode-native-eval-harness-report",
      "protocol": mooncode_protocol_version(),
      "status": "passed",
      "harnesses": [
        { "id": "tool_harness", "status": "passed" },
        { "id": "file_edit", "status": "passed" },
      ],
    }),
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(mooncode_json_string(report, "status", default=""), "accepted")
  assert_true(report.stringify().contains("tool_harness"))
  assert_true(report.stringify().contains("file_edit"))
  assert_true(report.stringify().contains("status=passed"))
}
