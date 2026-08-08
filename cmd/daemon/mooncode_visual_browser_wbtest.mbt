///|
async test "mooncode exposes bounded image evidence without journaling bytes" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-image-evidence-XXXXXX"),
  )
  let path = @pathx.join(book_root, "page.png")
  @fsx.write_to_file(path, "png fixture bytes")
  let execution = mooncode_execute_tool_call(
    "session-image",
    book_root,
    {
      "tool": "view_image",
      "command_id": "cmd-image",
      "arguments": { "path": "page.png" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(mooncode_json_bool(execution, "accepted", default=false))
  let serialized = execution.stringify()
  assert_false(serialized.contains("base64"))
  assert_true(serialized.contains("model_image_evidence"))
  assert_true(mooncode_tool_supported("browser"))
  assert_true(mooncode_browser_loopback_url("http://127.0.0.1:4199/"))
  assert_false(mooncode_browser_loopback_url("https://example.com/"))
}

///|
test "mooncode durable model messages replace image bytes with receipts" {
  let durable = mooncode_runtime_turn_durable_model_messages([
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Visual evidence from MoonBook path `screenshots/page.png`.",
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/png;base64,very-large-binary-payload",
            "detail": "high",
          },
        },
      ],
    },
  ])
  let serialized = Json::array(durable).stringify()
  assert_false(serialized.contains("data:image/"))
  assert_false(serialized.contains("very-large-binary-payload"))
  assert_true(serialized.contains("screenshots/page.png"))
  assert_true(serialized.contains("intentionally omitted"))
}
