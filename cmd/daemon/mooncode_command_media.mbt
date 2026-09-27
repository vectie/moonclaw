///|
fn mooncode_media_fields_allowed(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Bool {
  for key, _ in fields.iter2() {
    if !allowed.contains(key) {
      return false
    }
  }
  true
}

///|
fn mooncode_media_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    None => Some("")
    Some(_) => None
  }
}

///|
fn mooncode_media_image_signature_valid(
  media_type : String,
  bytes : Bytes,
) -> Bool {
  let raw = bytes.to_fixedarray()
  match media_type {
    "image/png" =>
      raw.length() >= 8 &&
      raw[0] == b'\x89' &&
      raw[1] == b'P' &&
      raw[2] == b'N' &&
      raw[3] == b'G' &&
      raw[4] == b'\r' &&
      raw[5] == b'\n' &&
      raw[6] == b'\x1a' &&
      raw[7] == b'\n'
    "image/jpeg" =>
      raw.length() >= 3 &&
      raw[0] == b'\xff' &&
      raw[1] == b'\xd8' &&
      raw[2] == b'\xff'
    "image/webp" =>
      raw.length() >= 12 &&
      raw[0] == b'R' &&
      raw[1] == b'I' &&
      raw[2] == b'F' &&
      raw[3] == b'F' &&
      raw[8] == b'W' &&
      raw[9] == b'E' &&
      raw[10] == b'B' &&
      raw[11] == b'P'
    _ => false
  }
}

///|
/// Validates the exact daemon-owned media contract before a command can be
/// journaled. The boolean result says whether provider image input is needed.
fn mooncode_command_media_validation(body : Json) -> Result[Bool, String] {
  guard body is Object(fields) else {
    return Err("MoonCode command must be an object")
  }
  let packet_parts = match fields.get("packet") {
    Some(Object(packet)) => packet.get("content_parts")
    _ => None
  }
  match (fields.get("content_parts"), packet_parts) {
    (None, Some(_)) =>
      return Err("packet content_parts require matching native content_parts")
    (Some(native), Some(packet)) if native != packet =>
      return Err("packet and native content_parts differ")
    _ => ()
  }
  let values = match fields.get("content_parts") {
    None => return Ok(false)
    Some(Array(parts)) if parts.length() > 0 && parts.length() <= 12 => parts
    _ => return Err("content_parts must contain 1–12 ordered parts")
  }
  if mooncode_json_string(body, "command", default="") != "prompt" {
    return Err("content_parts are available only for prompt turns")
  }
  let text = mooncode_json_string(body, "text", default="")
  let ordered_text = StringBuilder()
  let mut image_count = 0
  let mut total_bytes = 0
  for value in values {
    guard value is Object(part) else {
      return Err("content_parts entries must be objects")
    }
    match mooncode_media_string(part, "type") {
      Some("text") => {
        if !mooncode_media_fields_allowed(part, ["type", "text"]) {
          return Err("text content part has unsupported fields")
        }
        let part_text = match mooncode_media_string(part, "text") {
          Some(value) if value != "" && value.length() <= 64 * 1024 => value
          _ => return Err("Invalid text content part")
        }
        ordered_text.write_string(part_text)
      }
      Some("image") => {
        if !mooncode_media_fields_allowed(part, [
            "type", "media_type", "data_base64", "name",
          ]) {
          return Err("image content part has unsupported fields")
        }
        let media_type = match mooncode_media_string(part, "media_type") {
          Some(value) if ["image/png", "image/jpeg", "image/webp"].contains(
              value,
            ) => value
          _ => return Err("Unsupported Code image media type")
        }
        let data = match mooncode_media_string(part, "data_base64") {
          Some(value) if value != "" && value.length() <= 11 * 1024 * 1024 =>
            value
          _ => return Err("Code image data is missing or too large")
        }
        let name = match mooncode_media_string(part, "name") {
          Some(value) if value.length() <= 120 && !value.contains("\u{0000}") =>
            value
          _ => return Err("Invalid Code image name")
        }
        ignore(name)
        let bytes = @base64.decode(data) catch {
          _ => return Err("Code image data is not valid base64")
        }
        if bytes.length() == 0 ||
          bytes.length() > 8 * 1024 * 1024 ||
          @base64.encode(bytes) != data ||
          !mooncode_media_image_signature_valid(media_type, bytes) {
          return Err(
            "Code image data is invalid or exceeds the 8 MB image limit",
          )
        }
        image_count += 1
        total_bytes += bytes.length()
        if image_count > 4 || total_bytes > 16 * 1024 * 1024 {
          return Err("Code images exceed the four-image or 16 MB turn limit")
        }
      }
      _ => return Err("Unsupported content part type")
    }
  }
  if ordered_text.to_string() != text {
    return Err("text must match the ordered text content exactly")
  }
  Ok(image_count > 0)
}
