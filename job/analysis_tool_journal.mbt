///|
const ANALYSIS_TOOL_JOURNAL_LIMIT = 20

///|
const ANALYSIS_TOOL_JOURNAL_LOG_LIMIT = 6

///|
fn analysis_tool_journal_path(request : AnalysisRequest) -> String {
  let step_key = safe_step_file_segment(request.step_id)
  @pathx.join(
    request.cwd,
    ".moonclaw-tool-journal-\{request.run_id}-\{step_key}.json",
  )
}

///|
fn analysis_session_journal_entry(request : AnalysisRequest) -> Json {
  {
    "phase": "session",
    "event": "started",
    "job_id": request.job_id,
    "run_id": request.run_id,
    "step_id": request.step_id,
    "cwd": request.cwd,
    "execution_mode": request.execution_mode,
    "execution_target": request.execution_target,
    "enable_tools": request.enable_tools,
    "enabled_tools": enabled_tool_names(
      constrain_tool_contract_for_request(request),
    ),
    "web_search": request.web_search,
    "timeout_ms": analysis_request_timeout_ms(request),
  }
}

///|
async fn write_analysis_tool_journal(
  request : AnalysisRequest,
  entries : Array[Json],
) -> String {
  let path = analysis_tool_journal_path(request)
  @fsx.write_to_file(path, Json::array(entries).stringify(indent=2)) catch {
    _ => ()
  }
  path
}

///|
pub async fn initialize_analysis_tool_journal(
  request : AnalysisRequest,
) -> String {
  write_analysis_tool_journal(request, [analysis_session_journal_entry(request)])
}

///|
fn compact_tool_journal_text(text : String, limit? : Int = 240) -> String {
  let normalized = text.trim().to_string()
  if normalized.is_blank() {
    return ""
  }
  let chars = normalized.to_array()
  if chars.length() <= limit {
    return normalized
  }
  let buf = StringBuilder::new()
  for i in 0..<limit {
    buf.write_char(chars[i])
  }
  buf.write_string("...")
  buf.to_string()
}

///|
fn recent_analysis_tool_journal(entries : Array[Json]) -> Array[Json] {
  if entries.length() <= ANALYSIS_TOOL_JOURNAL_LIMIT {
    return entries
  }
  let trimmed = []
  let start = entries.length() - ANALYSIS_TOOL_JOURNAL_LIMIT
  for index in start..<entries.length() {
    trimmed.push(entries[index])
  }
  trimmed
}

///|
fn push_analysis_tool_journal_entry(
  journal : Array[Json],
  entry : Json,
) -> Unit {
  journal.push(entry)
  if journal.length() > ANALYSIS_TOOL_JOURNAL_LIMIT {
    ignore(journal.remove(0))
  }
}

///|
fn analysis_tool_call_start_entry(tool_call : @ai.ToolCall) -> Json {
  {
    "phase": "start",
    "tool": tool_call.name,
    "call_id": tool_call.id,
    "arguments": compact_tool_journal_text(
      tool_call.arguments.unwrap_or(""),
      limit=400,
    ),
  }
}

///|
fn analysis_tool_call_finish_entry(
  tool_call : @ai.ToolCall,
  result : Result[Json, Json],
  rendered : String,
) -> Json {
  let payload : Map[String, Json] = {
    "phase": "finish",
    "tool": tool_call.name.to_json(),
    "call_id": tool_call.id.to_json(),
    "preview": compact_tool_journal_text(rendered, limit=280).to_json(),
  }
  match result {
    Ok(value) => {
      payload["ok"] = true.to_json()
      payload["result"] = value
    }
    Err(error) => {
      payload["ok"] = false.to_json()
      payload["error"] = error
    }
  }
  Json::object(payload)
}

///|
fn analysis_execution_metadata_with_tool_journal(
  request : AnalysisRequest,
  journal : Array[Json],
) -> Json {
  let recent = recent_analysis_tool_journal(journal)
  {
    "job_id": request.job_id,
    "run_id": request.run_id,
    "step_id": request.step_id,
    "execution_isolation": request.execution_isolation,
    "role_runtime_contract": request.role_runtime_contract,
    "tool_call_journal_path": analysis_tool_journal_path(request),
    "tool_call_journal": Json::array(recent),
  }
}

///|
fn compact_analysis_tool_journal_entry(entry : Json) -> Json {
  match entry {
    Object(obj) => {
      let compact : Map[String, Json] = {}
      for key in ["phase", "tool", "call_id", "ok", "preview", "arguments"] {
        match obj.get(key) {
          Some(value) => compact.set(key, value)
          None => ()
        }
      }
      if compact.is_empty() {
        entry
      } else {
        Json::object(compact)
      }
    }
    _ => entry
  }
}

///|
pub fn compact_analysis_result_metadata(metadata : Json) -> Json {
  match metadata {
    Object(obj) => {
      let compact : Map[String, Json] = {}
      for key in obj.keys() {
        match obj.get(key) {
          Some(value) =>
            if key == "tool_call_journal" {
              match value {
                Array(entries) => {
                  let compact_entries : Array[Json] = []
                  for entry in entries {
                    compact_entries.push(
                      compact_analysis_tool_journal_entry(entry),
                    )
                  }
                  compact.set(key, Json::array(compact_entries))
                  compact.set(
                    "tool_call_journal_count",
                    entries.length().to_json(),
                  )
                }
                _ => compact.set(key, value)
              }
            } else {
              compact.set(key, value)
            }
          None => ()
        }
      }
      Json::object(compact)
    }
    _ => metadata
  }
}

///|
fn render_analysis_tool_journal_entry(entry : Json) -> String? {
  match entry {
    Object(obj) => {
      let phase = match obj.get("phase") {
        Some(String(phase)) => phase
        _ => return None
      }
      let tool = match obj.get("tool") {
        Some(String(tool)) => tool
        _ => return None
      }
      match phase {
        "start" => {
          let arguments = match obj.get("arguments") {
            Some(String(arguments)) => arguments
            _ => ""
          }
          Some(
            "tool[start]: \{tool} args=\{compact_tool_journal_text(arguments, limit=120)}",
          )
        }
        "finish" => {
          let status = match obj.get("ok") {
            Some(True) => "ok"
            Some(False) => "error"
            _ => "unknown"
          }
          let preview = match obj.get("preview") {
            Some(String(preview)) => preview
            _ => ""
          }
          Some(
            "tool[finish]: \{tool} \{status} \{compact_tool_journal_text(preview, limit=120)}",
          )
        }
        _ => Some("tool[\{phase}]: \{tool}")
      }
    }
    _ => None
  }
}

///|
fn analysis_tool_journal_logs(metadata : Json) -> Array[String] {
  let logs = []
  let path = match metadata {
    { "tool_call_journal_path": String(path), .. } => Some(path)
    _ => None
  }
  if path is Some(path) {
    logs.push("tool journal: \{path}")
  }
  let entries = match metadata {
    { "tool_call_journal": Array(entries), .. } => entries
    _ => []
  }
  let start = if entries.length() > ANALYSIS_TOOL_JOURNAL_LOG_LIMIT {
    entries.length() - ANALYSIS_TOOL_JOURNAL_LOG_LIMIT
  } else {
    0
  }
  for index in start..<entries.length() {
    match render_analysis_tool_journal_entry(entries[index]) {
      Some(line) => logs.push(line)
      None => ()
    }
  }
  logs
}
