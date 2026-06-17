///|
test "mooncode package result validates command scoped proof" {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-demo",
    "event": mooncode_event_package_verified(),
    "path": "portable/app-tool/mooncode/session-demo/package-cmd-1.json",
    "detail": "bundle checks passed",
    "command_packet": { "command_id": "cmd-1", "action": "package" },
    "package_manifest": { "kind": "mooncode-package-manifest" },
    "package_index": { "kind": "mooncode-package-index" },
  }
  let report = mooncode_validate_package_result_body("session-demo", body)
  assert_true(mooncode_json_bool(report, "ok", default=false))
  assert_eq(mooncode_json_string(report, "command_id", default=""), "cmd-1")
  assert_eq(mooncode_package_result_status("package_verified"), "verified")
  let event = mooncode_package_result_event_record(
    session_id="session-demo",
    command_id="cmd-1",
    body,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(
    mooncode_json_string(event, "kind", default=""),
    "runtime.package_verified",
  )
  assert_eq(mooncode_json_string(event, "lane", default=""), "artifact")
  assert_true(event.stringify().contains("mooncode-package-manifest"))
}

///|
test "mooncode package result rejects missing path and unsupported event" {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-demo",
    "command_id": "cmd-1",
    "event": "package_started",
  }
  let report = mooncode_validate_package_result_body("session-demo", body)
  assert_false(mooncode_json_bool(report, "ok", default=true))
  let payload = report.stringify()
  assert_true(payload.contains("event"))
  assert_true(payload.contains("path"))
}

///|
test "mooncode package result book root prefers request then body then binding" {
  assert_eq(
    mooncode_package_result_book_root(
      requested_book_root="/query/book",
      { "book_root": "/body/book" },
      binding_book_root="/binding/book",
    ),
    "/query/book",
  )
  assert_eq(
    mooncode_package_result_book_root(
      requested_book_root="",
      { "book_root": "/body/book" },
      binding_book_root="/binding/book",
    ),
    "/body/book",
  )
  assert_eq(
    mooncode_package_result_book_root(
      requested_book_root="",
      {},
      binding_book_root="/binding/book",
    ),
    "/binding/book",
  )
}
