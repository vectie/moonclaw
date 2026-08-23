///|
const MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS = 12000

///|
const MOONCODE_DEFAULT_TOOL_OUTPUT_MAX_CHARS = 50000

///|
const MOONCODE_OPT_IN_TOOL_OUTPUT_MAX_CHARS = 200000

///|
/// A stale mutation needs enough exact source to repair a large file without
/// guessing. This is intentionally below the operator opt-in ceiling.
const MOONCODE_MUTATION_RECOVERY_READ_CHARS = 120000

///|
/// Return the largest valid UTF-8 prefix whose encoded byte length does not
/// exceed `limit`. MoonBit string offsets are byte offsets, so direct slicing
/// at an arbitrary output budget can bisect a multibyte scalar and abort.
fn mooncode_utf8_prefix_within(text : String, limit : Int) -> String {
  if limit <= 0 {
    return ""
  }
  let bytes = @encoding/utf8.encode(text)
  if bytes.length() <= limit {
    return text
  }
  let mut end = limit.min(bytes.length())
  while end > 0 {
    let decoded = Some(@encoding/utf8.decode(bytes[:end])) catch { _ => None }
    match decoded {
      Some(value) => return value
      None => end -= 1
    }
  }
  ""
}

///|
/// Return the largest valid UTF-8 suffix whose encoded byte length does not
/// exceed `limit`.
fn mooncode_utf8_suffix_within(text : String, limit : Int) -> String {
  if limit <= 0 {
    return ""
  }
  let bytes = @encoding/utf8.encode(text)
  if bytes.length() <= limit {
    return text
  }
  let mut start = (bytes.length() - limit).max(0)
  while start < bytes.length() {
    let decoded = Some(@encoding/utf8.decode(bytes[start:])) catch { _ => None }
    match decoded {
      Some(value) => return value
      None => start += 1
    }
  }
  ""
}

///|
fn mooncode_normalize_tool_output_chars(
  requested : Int,
  maximum? : Int = MOONCODE_DEFAULT_TOOL_OUTPUT_MAX_CHARS,
) -> Int {
  let maximum = maximum.max(MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS)
  if requested <= 0 {
    MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS
  } else {
    requested.min(maximum)
  }
}

///|
fn mooncode_tool_output_maximum(arguments : Json) -> Int {
  if mooncode_json_bool(
      arguments,
      "mooncode_large_output_enabled",
      default=false,
    ) {
    MOONCODE_OPT_IN_TOOL_OUTPUT_MAX_CHARS
  } else {
    MOONCODE_DEFAULT_TOOL_OUTPUT_MAX_CHARS
  }
}

///|
fn mooncode_runtime_turn_tool_supports_output_limit(tool : String) -> Bool {
  match tool {
    "read" | "shell" | "browser" | "moon_ide" | "moon_cmd" | "moon_check" =>
      true
    _ => false
  }
}

///|
fn mooncode_runtime_turn_configured_output_chars(command : Json) -> Int? {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let requested = mooncode_json_int(
    payload,
    "planner_tool_output_chars",
    default=0,
  )
  if requested <= 0 {
    None
  } else {
    Some(
      mooncode_normalize_tool_output_chars(
        requested,
        maximum=MOONCODE_OPT_IN_TOOL_OUTPUT_MAX_CHARS,
      ),
    )
  }
}

///|
fn mooncode_runtime_turn_apply_output_policy(
  command : Json,
  tool : String,
  arguments : Json,
) -> Json {
  if !mooncode_runtime_turn_tool_supports_output_limit(tool) {
    return arguments
  }
  match arguments {
    Object(fields) if fields.contains("max_output_chars") => arguments
    _ =>
      match mooncode_runtime_turn_configured_output_chars(command) {
        None => arguments
        Some(limit) => {
          let arguments = mooncode_json_object_with_field(
            arguments,
            "max_output_chars",
            Json::number(limit.to_double()),
          )
          mooncode_json_object_with_field(
            arguments,
            "mooncode_large_output_enabled",
            Json::boolean(limit > MOONCODE_DEFAULT_TOOL_OUTPUT_MAX_CHARS),
          )
        }
      }
  }
}
