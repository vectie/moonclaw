///|
fn run_result_content(run : AcpRun) -> String? {
  match run.result {
    Some({ "content": String(content), .. }) if !content.trim().is_blank() =>
      Some(content.trim().to_string())
    Some({ "stdout": String(stdout), .. }) if !stdout.trim().is_blank() =>
      Some(stdout.trim().to_string())
    Some({ "stderr": String(stderr), .. }) if !stderr.trim().is_blank() =>
      Some(stderr.trim().to_string())
    _ =>
      match run.error {
        Some(error) if !error.trim().is_blank() =>
          Some(error.trim().to_string())
        _ => None
      }
  }
}

///|
fn run_stdio_summary(run : AcpRun) -> Json {
  match run.result {
    Some(
      {
        "stdout": String(stdout),
        "stderr": String(stderr),
        "exit_status": exit_status,
        ..
      }
    ) => { "stdout": stdout, "stderr": stderr, "exit_status": exit_status }
    Some({ "stdout": String(stdout), "stderr": String(stderr), .. }) =>
      { "stdout": stdout, "stderr": stderr }
    _ => {}
  }
}

///|
fn target_node(target : AcpTarget) -> AcpUiNode {
  let location = Some(
    match target.workspace {
      Some(workspace) => workspace
      None => target.cwd.unwrap_or(".")
    },
  )
  AcpUiNode::{
    id: "target:\{target.id}",
    parent_id: None,
    kind: Target,
    title: target.label.unwrap_or(target.id),
    status: target.status,
    summary: Some(target.backend),
    detail: location,
    target_id: Some(target.id),
    session_id: None,
    run_id: None,
    created_at: None,
    updated_at: None,
    metadata: target.metadata,
  }
}

///|
fn session_node(
  target : AcpTarget?,
  session : AcpSession,
  latest_run : AcpRun?,
) -> AcpUiNode {
  let location = Some(
    match session.workspace {
      Some(workspace) => workspace
      None => session.cwd.unwrap_or(".")
    },
  )
  AcpUiNode::{
    id: "session:\{session.id}",
    parent_id: Some("target:\{session.target_id}"),
    kind: Session,
    title: session.id,
    status: session.status,
    summary: latest_run.bind(run_result_content),
    detail: location,
    target_id: Some(session.target_id),
    session_id: Some(session.id),
    run_id: latest_run.map(fn(run) { run.id }),
    created_at: Some(session.created_at),
    updated_at: Some(session.updated_at),
    metadata: {
      "session_key": session.session_key,
      "target_label": target.bind(fn(target) { target.label }),
      "last_error": session.last_error,
      "linkage": session.metadata,
    },
  }
}

///|
fn run_linkage_metadata(run : AcpRun) -> Json? {
  match run.request {
    { "metadata": metadata, .. } => Some(metadata)
    _ => None
  }
}

///|
fn run_node(run : AcpRun) -> AcpUiNode {
  AcpUiNode::{
    id: "run:\{run.id}",
    parent_id: Some("session:\{run.session_id}"),
    kind: Run,
    title: run.id,
    status: run.status,
    summary: run_result_content(run),
    detail: match run.request {
      { "message": String(message), .. } => Some(message)
      _ => None
    },
    target_id: Some(run.target_id),
    session_id: Some(run.session_id),
    run_id: Some(run.id),
    created_at: Some(run.created_at),
    updated_at: Some(run.updated_at),
    metadata: {
      "backend": run.backend,
      "session_key": run.session_key,
      "stdout_stderr": run_stdio_summary(run),
      "linkage": run_linkage_metadata(run),
    },
  }
}

///|
fn session_timeline_entry(
  target : AcpTarget?,
  session : AcpSession,
) -> AcpUiTimelineEntry {
  let target_label = match target {
    Some(target) => target.label.unwrap_or(target.id)
    None => session.target_id
  }
  AcpUiTimelineEntry::{
    id: "session:\{session.id}",
    event_type: "session.status",
    title: "Session \{session.status}",
    detail: "\{session.id} -> \{target_label}",
    timestamp: session.updated_at,
    target_id: Some(session.target_id),
    session_id: Some(session.id),
    run_id: None,
    status: Some(session.status),
    data: {
      "session_key": session.session_key,
      "workspace": session.workspace,
      "cwd": session.cwd,
      "last_error": session.last_error,
      "linkage": session.metadata,
    },
  }
}

///|
fn run_timeline_entry(run : AcpRun) -> AcpUiTimelineEntry {
  AcpUiTimelineEntry::{
    id: "run:\{run.id}",
    event_type: "run.\{run.status}",
    title: "Run \{run.status}",
    detail: run_result_content(run).unwrap_or(
      match run.request {
        { "message": String(message), .. } => message
        _ => run.id
      },
    ),
    timestamp: run.updated_at,
    target_id: Some(run.target_id),
    session_id: Some(run.session_id),
    run_id: Some(run.id),
    status: Some(run.status),
    data: {
      "request": run.request,
      "plan": run.plan,
      "result": run.result,
      "error": run.error,
      "stdout_stderr": run_stdio_summary(run),
      "linkage": run_linkage_metadata(run),
    },
  }
}

///|
pub fn build_acp_ui_snapshot(runtime : AcpRuntime) -> AcpUiSnapshot {
  let targets = runtime.list_targets()
  let sessions = runtime.list_sessions()
  let runs = runtime.list_runs()
  let nodes : Array[AcpUiNode] = []
  let timeline : Array[AcpUiTimelineEntry] = []
  for target in targets {
    nodes.push(target_node(target))
  }
  for session in sessions {
    let target = runtime.get_target(session.target_id)
    let latest_run = runtime.latest_run_for_session(session.id)
    nodes.push(session_node(target, session, latest_run))
    timeline.push(session_timeline_entry(target, session))
  }
  for run in runs {
    nodes.push(run_node(run))
    timeline.push(run_timeline_entry(run))
  }
  timeline.sort_by(fn(left, right) { right.timestamp.compare(left.timestamp) })
  AcpUiSnapshot::{ targets, sessions, runs, nodes, timeline }
}
