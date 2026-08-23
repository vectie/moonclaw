///|
fn mooncode_browser_action_supported(action : String) -> Bool {
  action == "open" ||
  action == "snapshot" ||
  action == "screenshot" ||
  action == "set_viewport" ||
  action == "click" ||
  action == "fill" ||
  action == "press" ||
  action == "wait" ||
  action == "get" ||
  action == "eval" ||
  action == "console" ||
  action == "errors" ||
  action == "reload" ||
  action == "close"
}

///|
fn mooncode_browser_loopback_url(url : String) -> Bool {
  let lower = url.trim().to_lower().to_string()
  lower.has_prefix("http://127.0.0.1") ||
  lower.has_prefix("https://127.0.0.1") ||
  lower.has_prefix("http://localhost") ||
  lower.has_prefix("https://localhost") ||
  lower.has_prefix("http://[::1]") ||
  lower.has_prefix("https://[::1]")
}

///|
async fn mooncode_tool_browser(
  session_id : String,
  book_root : String,
  arguments : Json,
) -> Json {
  ignore(session_id)
  ignore(book_root)
  let action = mooncode_json_string(arguments, "action", default="")
  if !mooncode_browser_action_supported(action) {
    return mooncode_tool_error_result(
      "browser",
      message="unsupported browser action `\{action}`",
    )
  }
  mooncode_execution_sandbox_refusal("browser")
}
