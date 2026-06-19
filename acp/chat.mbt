///|
pub(all) enum AcpChatAction {
  Targets
  Status
  Attach(String)
  Detach(String)
  Run(String)
} derive(Debug)

///|
fn chat_run_summary(run : AcpRun) -> String? {
  match run.result {
    Some({ "content": String(content), .. }) if !content.trim().is_blank() =>
      Some(content.trim().to_owned())
    Some({ "stdout": String(stdout), .. }) if !stdout.trim().is_blank() =>
      Some(stdout.trim().to_owned())
    Some({ "stderr": String(stderr), .. }) if !stderr.trim().is_blank() =>
      Some(stderr.trim().to_owned())
    _ =>
      match run.error {
        Some(error) if !error.trim().is_blank() => Some(error.trim().to_owned())
        _ => None
      }
  }
}

///|
fn chat_stdio_preview(run : AcpRun) -> String {
  match run.result {
    Some({ "stdout": String(stdout), "stderr": String(stderr), .. }) => {
      let stdout = stdout.trim().to_owned()
      let stderr = stderr.trim().to_owned()
      if !stdout.is_blank() && !stderr.is_blank() {
        "stdout=\{stdout}\nstderr=\{stderr}"
      } else if !stdout.is_blank() {
        "stdout=\{stdout}"
      } else if !stderr.is_blank() {
        "stderr=\{stderr}"
      } else {
        ""
      }
    }
    _ => ""
  }
}

///|
fn latest_run_for_status(session : AcpSession, runs : Array[AcpRun]) -> AcpRun? {
  for run in runs {
    if run.session_id == session.id {
      return Some(run)
    }
  }
  None
}

///|
fn render_session_status_line(
  session : AcpSession,
  runs : Array[AcpRun],
) -> String {
  let workspace = match session.workspace {
    Some(workspace) => workspace
    None => session.cwd.unwrap_or(".")
  }
  let run_line = match latest_run_for_status(session, runs) {
    Some(run) =>
      match chat_run_summary(run) {
        Some(summary) => {
          let io = chat_stdio_preview(run)
          if io.is_blank() {
            " | run \{run.id} [\{run.status}] \{summary}"
          } else {
            " | run \{run.id} [\{run.status}] \{summary}\n  \{io}"
          }
        }
        None => " | run \{run.id} [\{run.status}]"
      }
    None => ""
  }
  "\{session.id} -> \{session.target_id} [\{session.status}] @ \{workspace}\{run_line}"
}

///|
fn split_acp_chat_command(text : String) -> (String, String) {
  let trimmed = text.trim()
  match trimmed.find(" ") {
    Some(index) =>
      (trimmed[:index].to_owned(), trimmed[index + 1:].trim().to_owned())
    None => (trimmed.to_owned(), "")
  }
}

///|
pub fn parse_acp_chat_action(text : String) -> AcpChatAction? {
  let trimmed = text.trim().to_owned()
  guard trimmed.has_prefix("/") else { return None }
  let (command, args) = split_acp_chat_command(trimmed)
  match command {
    "/acp-targets" => Some(Targets)
    "/acp-status" => Some(Status)
    "/acp-attach" => Some(Attach(args))
    "/acp-detach" => Some(Detach(args))
    "/acp-run" => Some(Run(args))
    _ => None
  }
}

///|
pub fn render_acp_targets(targets : Array[AcpTarget]) -> String {
  if targets.is_empty() {
    return "No ACP targets configured."
  }
  let lines = targets.map(fn(target) {
    let label = target.label.unwrap_or(target.id)
    let cwd = target.cwd.unwrap_or(target.workspace.unwrap_or("."))
    "\{target.id} (\{target.backend}) - \{label} @ \{cwd}"
  })
  ["ACP targets:", ..lines].join("\n")
}

///|
pub fn render_acp_status(
  session_key : String,
  sessions : Array[AcpSession],
  runs : Array[AcpRun],
) -> String {
  if sessions.is_empty() {
    return "No ACP session is bound to this chat.\nUse /acp-attach <target_id>."
  }
  let lines : Array[String] = sessions.map(fn(session) {
    render_session_status_line(session, runs)
  })
  ["ACP sessions for \{session_key}:", ..lines].join("\n")
}

///|
pub fn render_acp_attach_usage() -> String {
  "Usage: /acp-attach <target_id>"
}

///|
pub fn render_acp_run_usage() -> String {
  "Usage: /acp-run <message>"
}

///|
pub fn render_acp_attached(session : AcpSession) -> String {
  [
    "ACP session attached.",
    "Session: \{session.id}",
    "Target: \{session.target_id}",
    "Status: \{session.status}",
  ].join("\n")
}

///|
pub fn render_acp_detached(session : AcpSession) -> String {
  [
    "ACP session detached.",
    "Session: \{session.id}",
    "Target: \{session.target_id}",
  ].join("\n")
}

///|
pub fn render_acp_no_session() -> String {
  "No ACP session is bound to this chat.\nUse /acp-attach <target_id> first."
}

///|
pub fn render_acp_ambiguous_sessions(sessions : Array[AcpSession]) -> String {
  let lines = sessions.map(fn(session) {
    "\{session.id} -> \{session.target_id} [\{session.status}]"
  })
  [
    "Multiple ACP sessions are bound to this chat. Detach one or target a single chat/session.",
    ..lines,
  ].join("\n")
}

///|
pub fn render_acp_run_failed(error : String) -> String {
  "ACP run failed: \{error}"
}
