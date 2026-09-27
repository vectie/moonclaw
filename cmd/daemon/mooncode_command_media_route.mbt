///|
/// Read an image from the committed command journal. The canonical session
/// projection only carries its ordinal, never the base64 payload.
async fn Daemon::mooncode_get_command_media(
  self : Daemon,
  session_id~ : StringView,
  command_id~ : StringView,
  index~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let command_id = command_id.to_owned()
  let book_root = mooncode_request_book_root(r)
  guard self.mooncode_session_record(session_id, book_root) is Some(_) else {
    raise json_error(404, "Not Found", {
      "error": { "code": -1, "message": "MoonCode session not found" },
    })
  }
  let ordinal = @string.parse_int(index.to_owned()) catch { _ => -1 }
  guard ordinal >= 0 && ordinal < 12 && ordinal.to_string() == index.to_owned() else {
    raise json_error(404, "Not Found", {
      "error": { "code": -1, "message": "MoonCode image not found" },
    })
  }
  let journal = mooncode_read_session_journal(book_root, session_id)
  let result = mooncode_command_media_from_entries(
    mooncode_journal_entries(journal, mooncode_journal_command()),
    command_id,
    ordinal,
  )
  guard mooncode_json_string(result, "data_base64", default="") != "" else {
    raise json_error(404, "Not Found", {
      "error": { "code": -1, "message": "MoonCode image not found" },
    })
  }
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "private, no-store")
  w.write_header(200)
  w.write(result.stringify())
}

///|
fn mooncode_command_media_from_entries(
  entries : Array[Json],
  command_id : String,
  ordinal : Int,
) -> Json {
  for entry in entries {
    let command = mooncode_conversation_command_body(entry)
    if mooncode_conversation_command_id(entry, command) == command_id &&
      mooncode_command_media_validation(command) is Ok(true) {
      let parts = mooncode_json_array_items(command, "content_parts")
      if ordinal < parts.length() &&
        mooncode_json_string(parts[ordinal], "type", default="") == "image" {
        return {
          "media_type": mooncode_json_string(
            parts[ordinal],
            "media_type",
            default="",
          ),
          "data_base64": mooncode_json_string(
            parts[ordinal],
            "data_base64",
            default="",
          ),
          "name": mooncode_json_string(parts[ordinal], "name", default=""),
        }
      }
      return Json::object({})
    }
  }
  Json::object({})
}
