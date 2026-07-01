///|
async fn mooncode_runtime_turn_commit_results(
  session_id : String,
  book_root : String,
  command : Json,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let command_id = mooncode_command_id(command)
  let message = mooncode_runtime_turn_commit_message(command, command_id)
  let status = mooncode_runtime_turn_git(
    book_root,
    mooncode_runtime_turn_commit_status_args(),
    timeout_ms=10000,
    max_output_chars=12000,
  )
  if !mooncode_json_bool(status, "ok", default=false) {
    return [
      mooncode_runtime_turn_commit_result(
        session_id,
        book_root,
        command,
        accepted=false,
        message~,
        status_before="",
        commit_sha="",
        detail=mooncode_json_string(
          status,
          "message",
          default="git status failed",
        ),
        output=mooncode_json_string(status, "output", default=""),
        now~,
      ),
    ]
  }
  let status_before = mooncode_json_string(status, "output", default="")
  if status_before.trim().to_owned() == "" {
    return [
      mooncode_runtime_turn_commit_result(
        session_id,
        book_root,
        command,
        accepted=false,
        message~,
        status_before~,
        commit_sha="",
        detail="No book-local changes were available to commit.",
        output="",
        now~,
      ),
    ]
  }
  let add = mooncode_runtime_turn_git(
    book_root,
    mooncode_runtime_turn_commit_add_args(),
    timeout_ms=10000,
    max_output_chars=12000,
  )
  if !mooncode_json_bool(add, "ok", default=false) {
    return [
      mooncode_runtime_turn_commit_result(
        session_id,
        book_root,
        command,
        accepted=false,
        message~,
        status_before~,
        commit_sha="",
        detail=mooncode_json_string(add, "message", default="git add failed"),
        output=mooncode_json_string(add, "output", default=""),
        now~,
      ),
    ]
  }
  let commit = mooncode_runtime_turn_git(
    book_root,
    ["commit", "-m", message],
    timeout_ms=30000,
    max_output_chars=20000,
  )
  if !mooncode_json_bool(commit, "ok", default=false) {
    return [
      mooncode_runtime_turn_commit_result(
        session_id,
        book_root,
        command,
        accepted=false,
        message~,
        status_before~,
        commit_sha="",
        detail=mooncode_json_string(
          commit,
          "message",
          default="git commit failed",
        ),
        output=mooncode_json_string(commit, "output", default=""),
        now~,
      ),
    ]
  }
  let head = mooncode_runtime_turn_git(
    book_root,
    ["rev-parse", "HEAD"],
    timeout_ms=10000,
    max_output_chars=4000,
  )
  let commit_sha = mooncode_json_string(head, "output", default="")
    .trim()
    .to_owned()
  if !mooncode_json_bool(head, "ok", default=false) || commit_sha == "" {
    return [
      mooncode_runtime_turn_commit_result(
        session_id,
        book_root,
        command,
        accepted=false,
        message~,
        status_before~,
        commit_sha="",
        detail=mooncode_json_string(
          head,
          "message",
          default="git rev-parse failed after commit",
        ),
        output=mooncode_json_string(head, "output", default=""),
        now~,
      ),
    ]
  }
  [
    mooncode_runtime_turn_commit_result(
      session_id,
      book_root,
      command,
      accepted=true,
      message~,
      status_before~,
      commit_sha~,
      detail="MoonClaw created a book-local git commit for the accepted MoonCode changes.",
      output=mooncode_json_string(commit, "output", default=""),
      now~,
    ),
  ]
}

///|
fn mooncode_runtime_turn_commit_status_args() -> Array[StringView] {
  ["status", "--porcelain", "--", ".", ":(exclude).moonsuite", ":(exclude).tmp"]
}

///|
fn mooncode_runtime_turn_commit_add_args() -> Array[StringView] {
  ["add", "-A", "--", ".", ":(exclude).moonsuite", ":(exclude).tmp"]
}

///|
fn mooncode_runtime_turn_commit_result(
  session_id : String,
  book_root : String,
  command : Json,
  accepted~ : Bool,
  message~ : String,
  status_before~ : String,
  commit_sha~ : String,
  detail~ : String,
  output~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "kind": "mooncode-commit-result",
    "protocol": mooncode_protocol_version(),
    "event": if accepted {
      "commit_created"
    } else {
      "commit_failed"
    },
    "accepted": accepted,
    "session_id": session_id,
    "book_root": book_root,
    "command_id": mooncode_command_id(command),
    "commit_sha": commit_sha,
    "commit_message": message,
    "status_before": status_before,
    "detail": detail,
    "output": output,
    "created_at": now,
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "owner": {
      "ui": "moondesk",
      "runtime": "moonclaw",
      "artifact": "moonbook",
      "review": "moonbook",
      "standalone_component": "mooncode",
    },
  }
}

///|
fn mooncode_runtime_turn_commit_event(
  session_id : String,
  command_id : String,
  command : Json,
  commit_result : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let accepted = mooncode_json_bool(commit_result, "accepted", default=false)
  let commit_sha = mooncode_json_string(commit_result, "commit_sha", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-commit-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "lane": "review",
    "kind": if accepted {
      "runtime.commit_created"
    } else {
      "runtime.commit_failed"
    },
    "event": if accepted {
      "commit_created"
    } else {
      "commit_failed"
    },
    "title": if accepted {
      "MoonCode git commit created"
    } else {
      "MoonCode git commit failed"
    },
    "status": if accepted {
      "done"
    } else {
      "failed"
    },
    "detail": mooncode_json_string(commit_result, "detail", default=""),
    "commit_sha": commit_sha,
    "commit_message": mooncode_json_string(
      commit_result,
      "commit_message",
      default="",
    ),
    "status_before": mooncode_json_string(
      commit_result,
      "status_before",
      default="",
    ),
    "commit_result": commit_result,
    "command": "commit",
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
async fn mooncode_runtime_turn_git(
  book_root : String,
  args : Array[StringView],
  timeout_ms~ : Int,
  max_output_chars~ : Int,
) -> Json {
  let process = @spawn.spawn("git", args, timeout=timeout_ms, cwd=book_root) catch {
    error =>
      return {
        "ok": false,
        "status": -1,
        "message": "error running git: \{error}",
        "output": "",
      }
  }
  let capped = mooncode_cap_tool_output(
    process.stdout + process.stderr,
    max_output_chars,
  )
  {
    "ok": process.status == 0,
    "status": process.status,
    "elapsed_ms": process.elapsed,
    "message": if process.status == 0 {
      "git exited 0"
    } else {
      "git exited \{process.status}"
    },
    "output": mooncode_json_string(capped, "output", default=""),
    "truncated": mooncode_json_bool(capped, "truncated", default=false),
  }
}

///|
fn mooncode_runtime_turn_commit_message(
  command : Json,
  command_id : String,
) -> String {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let packet_payload = mooncode_json_object_field_or_empty(packet, "payload")
  let candidates = [
    mooncode_json_string(payload, "commit_message", default=""),
    mooncode_json_string(payload, "message", default=""),
    mooncode_json_string(packet, "commit_message", default=""),
    mooncode_json_string(packet_payload, "commit_message", default=""),
    mooncode_runtime_turn_prompt_text(command),
  ]
  for candidate in candidates {
    let cleaned = mooncode_runtime_turn_commit_message_clean(candidate)
    if cleaned != "" {
      return cleaned
    }
  }
  if command_id == "" {
    "MoonCode commit"
  } else {
    "MoonCode commit \{command_id}"
  }
}

///|
fn mooncode_runtime_turn_commit_message_clean(text : String) -> String {
  let clean = text.trim().to_owned()
  if clean == "" {
    return ""
  }
  let mut first = clean
  for line in clean.split("\n") {
    first = line.to_owned()
    break
  }
  let first = first.trim().to_owned()
  if first.length() > 180 {
    first[:180].to_owned()
  } else {
    first
  }
}
