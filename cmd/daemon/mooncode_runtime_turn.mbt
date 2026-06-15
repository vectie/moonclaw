///|
async fn Daemon::mooncode_runtime_turn(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_string()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime turn requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let turn = self.mooncode_runtime_turn_execute(session_id, book_root, body)
  w.header().set("Content-Type", "application/json")
  w.write_header(
    if mooncode_json_bool(turn, "accepted", default=false) {
      202
    } else {
      200
    },
    reason=if mooncode_json_bool(turn, "accepted", default=false) {
      "Accepted"
    } else {
      "OK"
    },
  )
  w.write(turn.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_turn_execute(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let consumer_id = mooncode_json_string(
    payload,
    "consumer_id",
    default="moonclaw-native-runtime-turn",
  )
  let before = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let claim_receipts = if mooncode_json_array_items(before, "claimed_commands").length() ==
    0 {
    mooncode_runtime_claim_receipts(
      session_id,
      book_root,
      before,
      payload,
      now=self.clock.now(),
    )
  } else {
    []
  }
  for receipt in claim_receipts {
    mooncode_append_jsonl(
      mooncode_runtime_dispatches_path(book_root, session_id),
      receipt,
    )
  }
  let claimed_state = self.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  let claimed = mooncode_json_array_items(claimed_state, "claimed_commands")
  if claimed.length() == 0 {
    return {
      "kind": "mooncode-runtime-turn",
      "protocol": "mooncode.v1",
      "owner": "moonclaw",
      "accepted": false,
      "session_id": session_id,
      "book_root": book_root,
      "ran": false,
      "message": "No claimable or claimed MoonCode command is ready for a native runtime turn.",
      "claim_receipts": Json::array(claim_receipts),
      "claim_state": claimed_state,
      "previous_claim_state": before,
    }
  }
  let item = claimed[0]
  let command = mooncode_json_object_field_or_empty(item, "command")
  let command_id = mooncode_json_string(item, "command_id", default="")
  let report = mooncode_validate_command_body(session_id, command)
  let now = self.clock.now()
  let started = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.turn_started",
    title="MoonCode native runtime turn started",
    status="running",
    detail="MoonClaw claimed command \{command_id} for book-local native tool execution.",
    now~,
  )
  let tool_results : Array[Json] = []
  let events : Array[Json] = [started]
  let execution : Json = if mooncode_json_bool(report, "ok", default=false) {
    let tool_calls = mooncode_runtime_turn_tool_calls(command)
    for tool_call in tool_calls {
      let execution = mooncode_execute_tool_call(
        session_id,
        book_root,
        mooncode_runtime_turn_tool_body(command, tool_call),
        now=self.clock.now(),
      )
      tool_results.push(execution)
      events.push(mooncode_json_object_field_or_empty(execution, "event"))
      if !mooncode_json_bool(execution, "accepted", default=false) {
        break
      }
    }
    let accepted = tool_results.all(result => {
      mooncode_json_bool(result, "accepted", default=false)
    })
    let finished = mooncode_runtime_turn_finished_event(
      session_id,
      command_id,
      accepted~,
      tool_count=tool_results.length(),
      now=self.clock.now(),
    )
    events.push(finished)
    (
      {
        "accepted": accepted,
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "control": mooncode_json_string(command, "command", default="prompt"),
        "message": if accepted {
          "MoonClaw native runtime turn completed `\{mooncode_json_string(command, "command", default="prompt")}`"
        } else {
          "MoonClaw native runtime turn failed during tool execution"
        },
        "tool_results": Json::array(tool_results),
        "events": Json::array(events),
      } : Json)
  } else {
    let failed = mooncode_event(
      session_id~,
      command_id~,
      lane="runtime",
      kind="runtime.turn_invalid",
      title="MoonCode native runtime turn rejected invalid command",
      status="failed",
      detail=mooncode_json_string(
        report,
        "message",
        default="Invalid MoonCode command",
      ),
      now=self.clock.now(),
    )
    events.push(failed)
    (
      {
        "accepted": false,
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "control": "invalid",
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode command",
        ),
        "validation": report,
        "tool_results": Json::array(tool_results),
        "events": Json::array(events),
      } : Json)
  }
  let receipt = mooncode_runtime_turn_receipt(
    session_id,
    book_root,
    item,
    execution,
    consumer_id~,
    now=self.clock.now(),
  )
  mooncode_append_jsonl(
    mooncode_runtime_dispatches_path(book_root, session_id),
    receipt,
  )
  let binding = self.mooncode_binding_for_session(session_id)
  binding.book_root = book_root
  binding.command_count += 1
  binding.last_command_id = command_id
  binding.last_updated = self.clock.now()
  for event in events {
    binding.events.put(event)
    self.mooncode_persist_event(binding, event)
  }
  self.mooncode_persist_session(binding)
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  {
    "kind": "mooncode-runtime-turn",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "session_id": session_id,
    "book_root": book_root,
    "ran": true,
    "command_id": command_id,
    "claim_receipts": Json::array(claim_receipts),
    "turn_receipt": receipt,
    "execution": execution,
    "claim_state": after,
    "previous_claim_state": before,
  }
}

///|
fn mooncode_runtime_turn_tool_calls(command : Json) -> Array[Json] {
  let explicit = mooncode_json_array_items(command, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let explicit = mooncode_json_array_items(packet, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  match action {
    "prompt" | "steer" => mooncode_runtime_turn_prompt_tool_calls(command)
    "run_tests" | "run_eval" =>
      [
        {
          "tool": "moon_check",
          "arguments": mooncode_runtime_turn_moon_check_arguments(command),
        },
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime completed \{action}.",
          },
        },
      ]
    "cancel" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded cancel with no legacy task dispatch.",
          },
        },
      ]
    _ =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded command `\{action}`. No explicit runtime_tool_calls were provided.",
          },
        },
      ]
  }
}

///|
fn mooncode_runtime_turn_prompt_tool_calls(command : Json) -> Array[Json] {
  let request = mooncode_runtime_turn_prompt_text(command)
  let lower = request.to_lower().to_string()
  if mooncode_runtime_turn_mentions_miniapp(lower) {
    return mooncode_runtime_turn_miniapp_tool_calls(command, request)
  }
  if mooncode_runtime_turn_mentions_tool(lower) {
    return mooncode_runtime_turn_script_tool_calls(command, request)
  }
  [
    {
      "tool": "finish",
      "arguments": {
        "answer": "Native MoonCode runtime recorded this prompt. Ask for a tool, script, miniapp, app, or generated site to have MoonClaw create executable MoonBook code with native tools.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_prompt_text(command : Json) -> String {
  let text = mooncode_json_string(command, "text", default="")
  if text != "" {
    return text
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let message = mooncode_json_string(packet, "message", default="")
  if message != "" {
    return message
  }
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_string(payload, "message", default="")
}

///|
fn mooncode_runtime_turn_mentions_tool(lower : String) -> Bool {
  lower.contains("tool") ||
  lower.contains("script") ||
  lower.contains("executable") ||
  lower.contains("command") ||
  lower.contains("create code") ||
  lower.contains("generate code") ||
  lower.contains("build code")
}

///|
fn mooncode_runtime_turn_mentions_miniapp(lower : String) -> Bool {
  lower.contains("miniapp") ||
  lower.contains("mini app") ||
  lower.contains("app-tool") ||
  lower.contains("web app") ||
  lower.contains("site") ||
  lower.contains("html")
}

///|
fn mooncode_runtime_turn_script_tool_calls(
  command : Json,
  request : String,
) -> Array[Json] {
  let slug = mooncode_runtime_turn_artifact_slug(command)
  let base = "tools/mooncode-generated/\{slug}"
  let script_path = base + "/run.sh"
  let readme_path = base + "/README.md"
  [
    {
      "tool": "write",
      "arguments": {
        "path": script_path,
        "content": "#!/bin/sh\nset -eu\nprintf 'MoonCode generated tool executed.\\n'\n",
      },
    },
    {
      "tool": "write",
      "arguments": {
        "path": readme_path,
        "content": mooncode_runtime_turn_artifact_readme(
          "MoonCode Generated Tool",
          request,
          script_path,
          "Run with `sh \{script_path}` from the MoonBook root.",
        ),
      },
    },
    {
      "tool": "shell",
      "arguments": {
        "cmd": "sh \{script_path}",
        "timeout_ms": 10000,
        "max_output_chars": 4000,
      },
    },
    {
      "tool": "finish",
      "arguments": {
        "answer": "Created a MoonBook-owned executable tool at `\{script_path}` and verified it with a shell run.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_miniapp_tool_calls(
  command : Json,
  request : String,
) -> Array[Json] {
  let slug = mooncode_runtime_turn_artifact_slug(command)
  let base = "apps/mooncode-generated/\{slug}"
  let app_path = base + "/index.html"
  let readme_path = base + "/README.md"
  [
    {
      "tool": "write",
      "arguments": {
        "path": app_path,
        "content": mooncode_runtime_turn_miniapp_html(request),
      },
    },
    {
      "tool": "write",
      "arguments": {
        "path": readme_path,
        "content": mooncode_runtime_turn_artifact_readme(
          "MoonCode Generated Miniapp",
          request,
          app_path,
          "Open `\{app_path}` from the MoonBook or publish it through the MoonBook site flow.",
        ),
      },
    },
    {
      "tool": "finish",
      "arguments": {
        "answer": "Created a MoonBook-owned miniapp at `\{app_path}`.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_artifact_slug(command : Json) -> String {
  let command_id = mooncode_command_id(command)
  let safe = mooncode_safe_session_id(command_id)
  if safe == "" {
    "prompt"
  } else {
    safe
  }
}

///|
fn mooncode_runtime_turn_artifact_readme(
  title : String,
  request : String,
  entrypoint : String,
  usage : String,
) -> String {
  "# \{title}\n\n" +
  "Generated by MoonClaw native MoonCode runtime-turn.\n\n" +
  "## Request\n\n" +
  mooncode_runtime_turn_markdown_quote(request) +
  "\n\n## Entrypoint\n\n- `\{entrypoint}`\n\n## Usage\n\n\{usage}\n"
}

///|
fn mooncode_runtime_turn_markdown_quote(text : String) -> String {
  let clean = text.trim().to_string()
  if clean == "" {
    "> No prompt text was provided."
  } else {
    clean.split("\n").map(line => "> " + line.to_string()).collect().join("\n")
  }
}

///|
fn mooncode_runtime_turn_miniapp_html(request : String) -> String {
  let escaped = mooncode_runtime_turn_escape_html(request)
  "<!doctype html>\n" +
  "<html lang=\"en\">\n" +
  "<head>\n" +
  "  <meta charset=\"utf-8\">\n" +
  "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
  "  <title>MoonCode Miniapp</title>\n" +
  "  <style>\n" +
  "    body { font-family: system-ui, sans-serif; margin: 0; padding: 32px; background: #f7f4ed; color: #202124; }\n" +
  "    main { max-width: 760px; margin: 0 auto; }\n" +
  "    button { border: 1px solid #202124; background: #fff; padding: 8px 12px; cursor: pointer; }\n" +
  "    output { display: block; margin-top: 16px; padding: 12px; background: #fff; border: 1px solid #d8d2c4; }\n" +
  "  </style>\n" +
  "</head>\n" +
  "<body>\n" +
  "  <main>\n" +
  "    <h1>MoonCode Miniapp</h1>\n" +
  "    <p>This miniapp was generated inside a MoonBook from the prompt below.</p>\n" +
  "    <blockquote>\{escaped}</blockquote>\n" +
  "    <button type=\"button\" id=\"run\">Run</button>\n" +
  "    <output id=\"result\">Ready.</output>\n" +
  "  </main>\n" +
  "  <script>\n" +
  "    document.getElementById('run').addEventListener('click', function () {\n" +
  "      document.getElementById('result').textContent = 'MoonCode miniapp executed at ' + new Date().toISOString();\n" +
  "    });\n" +
  "  </script>\n" +
  "</body>\n" +
  "</html>\n"
}

///|
fn mooncode_runtime_turn_escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn mooncode_runtime_turn_moon_check_arguments(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let target = mooncode_json_string(payload, "moon_check_target", default="")
  if target == "" {
    { "timeout_ms": 60000, "max_output_chars": 16000 }
  } else {
    { "target": target, "timeout_ms": 60000, "max_output_chars": 16000 }
  }
}

///|
fn mooncode_runtime_turn_tool_body(command : Json, tool_call : Json) -> Json {
  let command_id = mooncode_command_id(command)
  {
    "protocol": "mooncode.v1",
    "session_id": mooncode_json_string(command, "session_id", default=""),
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "tool": mooncode_json_string(
      tool_call,
      "tool",
      default=mooncode_json_string(tool_call, "name", default=""),
    ),
    "arguments": mooncode_json_object_field_or_empty(tool_call, "arguments"),
  }
}

///|
fn mooncode_runtime_turn_finished_event(
  session_id : String,
  command_id : String,
  accepted~ : Bool,
  tool_count~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.turn_finished",
    title=if accepted {
      "MoonCode native runtime turn completed"
    } else {
      "MoonCode native runtime turn failed"
    },
    status=if accepted { "done" } else { "failed" },
    detail="MoonClaw native runtime turn executed \{tool_count} tool call(s).",
    now~,
  )
}

///|
fn mooncode_runtime_turn_receipt(
  session_id : String,
  book_root : String,
  claim_item : Json,
  execution : Json,
  consumer_id~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(claim_item, "command_id", default="")
  let accepted = mooncode_json_bool(execution, "accepted", default=false)
  let receipt = mooncode_json_object_field_or_empty(claim_item, "receipt")
  let claim_id = mooncode_json_string(receipt, "claim_id", default="")
  {
    "kind": "mooncode.runtime-dispatch",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "status": if accepted {
      "runtime-completed"
    } else {
      "runtime-failed"
    },
    "dispatch_mode": "moonclaw-native-runtime-turn",
    "claim_id": claim_id,
    "consumer_id": consumer_id,
    "completed_at": now,
    "control": mooncode_json_string(execution, "control", default=""),
    "message": mooncode_json_string(execution, "message", default=""),
    "command": mooncode_json_object_field_or_empty(claim_item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(
      claim_item, "command_entry",
    ),
    "execution": execution,
    "events": Json::array(mooncode_json_array_items(execution, "events")),
  }
}

///|
async test "mooncode native runtime turn executes explicit tool calls" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-turn-XXXXXX"),
  )
  @fsx.write_to_file(@pathx.join(book_root, "README.md"), "hello mooncode")
  let session_id = "session-runtime-turn"
  let command_id = "cmd-runtime-turn"
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "packet": { "command_id": command_id },
    "runtime_tool_calls": [
      { "tool": "read", "arguments": { "path": "README.md" } },
      {
        "tool": "shell",
        "arguments": { "cmd": "printf turn-ok", "timeout_ms": 5000 },
      },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(1L),
    "command": command,
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  assert_eq(mooncode_json_string(result, "command_id", default=""), command_id)
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 3)
  assert_true(execution.stringify().contains("turn-ok"))
  let dispatch_log = @fsx.read_file(
    mooncode_runtime_dispatches_path(book_root, session_id),
  )
  assert_true(dispatch_log.contains("\"runtime-claimed\""))
  assert_true(dispatch_log.contains("\"runtime-completed\""))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.turn_started\""))
  assert_true(events_log.contains("\"tool_result\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
}

///|
test "mooncode native runtime turn plans prompt tool calls" {
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "packet": { "command_id": "cmd-planner" },
  }
  let calls = mooncode_runtime_turn_tool_calls(command)
  assert_eq(calls.length(), 4)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "write")
  assert_true(calls[0].stringify().contains("tools/mooncode-generated"))
  assert_eq(mooncode_json_string(calls[2], "tool", default=""), "shell")
  assert_eq(mooncode_json_string(calls[3], "tool", default=""), "finish")
  let miniapp : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Build a tiny html miniapp",
    "packet": { "command_id": "cmd-miniapp" },
  }
  let miniapp_calls = mooncode_runtime_turn_tool_calls(miniapp)
  assert_eq(miniapp_calls.length(), 3)
  assert_true(miniapp_calls[0].stringify().contains("apps/mooncode-generated"))
}

///|
async test "mooncode native runtime turn creates executable tool from prompt" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-prompt-XXXXXX"),
  )
  let session_id = "session-runtime-prompt"
  let command_id = "cmd-runtime-prompt"
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "packet": { "command_id": command_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(2L),
    "command": command,
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 4)
  assert_true(
    execution.stringify().contains("MoonCode generated tool executed."),
  )
  let script_path = @pathx.join(
    book_root, "tools/mooncode-generated/cmd-runtime-prompt/run.sh",
  )
  let readme_path = @pathx.join(
    book_root, "tools/mooncode-generated/cmd-runtime-prompt/README.md",
  )
  assert_true(@fsx.exists(script_path))
  assert_true(@fsx.exists(readme_path))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.turn_started\""))
  assert_true(events_log.contains("\"tool_result\""))
  assert_true(events_log.contains("\"finish\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
}
