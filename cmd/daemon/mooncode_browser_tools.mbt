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
fn mooncode_browser_required_string(
  arguments : Json,
  key : String,
  action : String,
) -> (String, Json?) {
  let value = mooncode_json_string(arguments, key, default="")
  if value == "" {
    (
      "",
      Some(
        mooncode_tool_error_result(
          "browser",
          message="browser \{action} requires non-empty `\{key}`",
        ),
      ),
    )
  } else {
    (value, None)
  }
}

///|
async fn mooncode_tool_browser(
  session_id : String,
  book_root : String,
  arguments : Json,
) -> Json {
  let action = mooncode_json_string(arguments, "action", default="")
  if !mooncode_browser_action_supported(action) {
    return mooncode_tool_error_result(
      "browser",
      message="unsupported browser action `\{action}`",
    )
  }
  let args : Array[String] = [
    "--session",
    "mooncode-" + mooncode_safe_session_id(session_id),
    "--json",
  ]
  // Prefer an installed system browser when agent-browser's optional managed
  // Chromium cache is absent. This keeps UI automation a host capability and
  // avoids per-project Playwright installs.
  for
    candidate in [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge", "/usr/bin/google-chrome",
      "/usr/bin/chromium", "/usr/bin/chromium-browser",
    ] {
    let available = @fsx.exists_as_file(candidate) catch { _ => false }
    if available {
      args.append(["--executable-path", candidate])
      break
    }
  }
  let mut evidence_path = ""
  match action {
    "open" => {
      let (url, error) = mooncode_browser_required_string(
        arguments, "url", action,
      )
      if error is Some(error) {
        return error
      }
      args.push("open")
      args.push(url)
    }
    "snapshot" => {
      args.push("snapshot")
      if mooncode_json_bool(arguments, "interactive", default=false) {
        args.push("--interactive")
      }
      if mooncode_json_bool(arguments, "compact", default=true) {
        args.push("--compact")
      }
      let depth = mooncode_json_int(arguments, "depth", default=0)
      if depth > 0 {
        args.push("--depth")
        args.push(depth.to_string())
      }
      let selector = mooncode_json_string(arguments, "selector", default="")
      if selector != "" {
        args.push("--selector")
        args.push(selector)
      }
    }
    "screenshot" => {
      let (requested_path, error) = mooncode_browser_required_string(
        arguments, "path", action,
      )
      if error is Some(error) {
        return error
      }
      let path = mooncode_resolve_book_path(book_root, requested_path)
      if !mooncode_json_bool(path, "ok", default=false) {
        return mooncode_tool_error_result(
          "browser",
          message=mooncode_json_string(path, "message", default="invalid path"),
        )
      }
      let absolute = mooncode_json_string(path, "absolute_path", default="")
      evidence_path = mooncode_json_string(path, "relative_path", default="")
      let lower = evidence_path.to_lower()
      if !lower.has_suffix(".png") &&
        !lower.has_suffix(".jpg") &&
        !lower.has_suffix(".jpeg") {
        return mooncode_tool_error_result(
          "browser",
          message="browser screenshot path must end in .png, .jpg, or .jpeg",
        )
      }
      @fsx.make_directory(
        @pathx.dirname(absolute),
        recursive=true,
        exists_ok=true,
      )
      args.push("screenshot")
      args.push(absolute)
      if mooncode_json_bool(arguments, "full_page", default=false) {
        args.push("--full")
      }
    }
    "set_viewport" => {
      let width = mooncode_json_int(arguments, "width", default=0)
      let height = mooncode_json_int(arguments, "height", default=0)
      if width <= 0 || height <= 0 {
        return mooncode_tool_error_result(
          "browser",
          message="browser set_viewport requires positive width and height",
        )
      }
      args.append(["set", "viewport", width.to_string(), height.to_string()])
    }
    "click" => {
      let (selector, error) = mooncode_browser_required_string(
        arguments, "selector", action,
      )
      if error is Some(error) {
        return error
      }
      args.append(["click", selector])
    }
    "fill" => {
      let (selector, error) = mooncode_browser_required_string(
        arguments, "selector", action,
      )
      if error is Some(error) {
        return error
      }
      args.append([
        "fill",
        selector,
        mooncode_json_string(arguments, "text", default=""),
      ])
    }
    "press" => {
      let (key, error) = mooncode_browser_required_string(
        arguments, "key", action,
      )
      if error is Some(error) {
        return error
      }
      args.append(["press", key])
    }
    "wait" => {
      let wait_ms = mooncode_json_int(arguments, "wait_ms", default=0)
      let selector = mooncode_json_string(arguments, "selector", default="")
      if wait_ms <= 0 && selector == "" {
        return mooncode_tool_error_result(
          "browser",
          message="browser wait requires a positive wait_ms or selector",
        )
      }
      args.append([
        "wait",
        if selector != "" {
          selector
        } else {
          wait_ms.to_string()
        },
      ])
    }
    "get" => {
      let (what, error) = mooncode_browser_required_string(
        arguments, "what", action,
      )
      if error is Some(error) {
        return error
      }
      args.append(["get", what])
      if what == "attr" {
        let (attribute, error) = mooncode_browser_required_string(
          arguments, "attribute", action,
        )
        if error is Some(error) {
          return error
        }
        args.push(attribute)
      }
      let selector = mooncode_json_string(arguments, "selector", default="")
      if selector != "" {
        args.push(selector)
      }
    }
    "eval" => {
      let (script, error) = mooncode_browser_required_string(
        arguments, "script", action,
      )
      if error is Some(error) {
        return error
      }
      args.append(["eval", script])
    }
    "console" | "errors" | "reload" | "close" => args.push(action)
    _ => abort("browser action validated above")
  }
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=30000)
  let process = @spawn.spawn(
    "agent-browser",
    args.map(fn(arg) { arg }),
    timeout~,
    cwd=book_root,
  ) catch {
    error =>
      return mooncode_tool_error_result(
        "browser",
        message="error running native browser capability: \{error}",
      )
  }
  let capped = mooncode_cap_tool_output(
    process.stdout + process.stderr,
    mooncode_json_int(arguments, "max_output_chars", default=20000),
  )
  let metadata : Json = {
    "action": action,
    "status": process.status,
    "elapsed_ms": process.elapsed,
    "truncated": mooncode_json_bool(capped, "truncated", default=false),
    "path": evidence_path,
    "model_image_evidence": action == "screenshot" && process.status == 0,
    "mime_type": if evidence_path.to_lower().has_suffix(".png") {
      "image/png"
    } else {
      "image/jpeg"
    },
  }
  if process.status == 0 {
    mooncode_tool_ok_result(
      "browser",
      message="browser \{action} completed",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  } else {
    let selector = mooncode_json_string(arguments, "selector", default="")
    let selector_hint = if (
        action == "click" || action == "fill" || action == "wait"
      ) &&
      selector != "" &&
      !selector.has_prefix("@") {
      " If targeting snapshot evidence, pass its element ref with the @ prefix (for example @e21); visible label text is not a selector."
    } else {
      ""
    }
    mooncode_tool_error_result(
      "browser",
      message="browser \{action} exited \{process.status}.\{selector_hint}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  }
}
