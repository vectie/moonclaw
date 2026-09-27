///|
test "MoonCode accepts bounded ordered text and PNG content" {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-image",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Inspect this screenshot.",
    "packet": { "command_id": "cmd-image" },
    "content_parts": [
      { "type": "text", "text": "Inspect this " },
      {
        "type": "image",
        "media_type": "image/png",
        "data_base64": "iVBORw0KGgo=",
        "name": "screen.png",
      },
      { "type": "text", "text": "screenshot." },
    ],
  }
  assert_true(mooncode_command_media_validation(body) is Ok(true))
  assert_true(
    mooncode_json_bool(
      mooncode_validate_command_body("session-image", body),
      "ok",
      default=false,
    ),
  )
  let media = mooncode_runtime_turn_user_media_messages(body)
  assert_eq(media.length(), 1)
  let parts = mooncode_json_array_items(media[0], "content")
  assert_eq(parts.length(), 3)
  assert_eq(mooncode_json_string(parts[0], "text", default=""), "Inspect this ")
  assert_eq(mooncode_json_string(parts[1], "type", default=""), "image_url")
  assert_eq(mooncode_json_string(parts[2], "text", default=""), "screenshot.")
  let durable = mooncode_runtime_turn_durable_model_message(media[0])
  assert_false(durable.stringify().contains("iVBORw0KGgo="))
  let resumed = mooncode_runtime_turn_model_followup_base_messages(
    body,
    {
      "model_messages": Json::array(
        mooncode_runtime_turn_model_initial_messages(body),
      ),
    },
    [],
  )
  let mut image_count = 0
  for message in resumed {
    for part in mooncode_json_array_items(message, "content") {
      if mooncode_json_string(part, "type", default="") == "image_url" {
        image_count += 1
      }
    }
  }
  assert_eq(image_count, 1)
  let user = mooncode_conversation_user_message({}, body)
  assert_eq(mooncode_json_array_items(user, "content_parts").length(), 3)
  assert_false(user.stringify().contains("iVBORw0KGgo="))
  assert_eq(
    mooncode_json_int(
      mooncode_json_array_items(user, "content_parts")[1],
      "image_index",
      default=-1,
    ),
    1,
  )
  let fetched = mooncode_command_media_from_entries(
    [{ "command_id": "cmd-image", "command": body }],
    "cmd-image",
    1,
  )
  assert_eq(
    mooncode_json_string(fetched, "data_base64", default=""),
    "iVBORw0KGgo=",
  )
  assert_eq(
    mooncode_command_media_from_entries(
      [{ "command_id": "cmd-image", "command": body }],
      "other",
      1,
    ).stringify(),
    "{}",
  )
}

///|
test "MoonCode rejects mismatched text and unsupported image signatures" {
  let mismatched : Json = {
    "command": "prompt",
    "text": "different",
    "content_parts": [{ "type": "text", "text": "actual" }],
  }
  assert_true(mooncode_command_media_validation(mismatched) is Err(_))
  let forged : Json = {
    "command": "prompt",
    "text": "",
    "content_parts": [
      { "type": "image", "media_type": "image/png", "data_base64": "/9j/" },
    ],
  }
  assert_true(mooncode_command_media_validation(forged) is Err(_))
}
