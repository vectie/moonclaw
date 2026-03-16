///|
pub struct AcpRunRequest {
  message : String
  run_id : String?
  model : String?
  cwd : String?
  idempotency_key : String?
  metadata : Json?
} derive(ToJson, FromJson, Show)

///|
pub fn new_run_request(
  message~ : String,
  run_id? : String,
  model? : String,
  cwd? : String,
  idempotency_key? : String,
  metadata? : Json,
) -> AcpRunRequest {
  AcpRunRequest::{ message, run_id, model, cwd, idempotency_key, metadata }
}

///|
pub struct AcpLaunchPlan {
  backend : String
  target_id : String
  session_id : String
  session_key : String
  cwd : String
  workspace : String?
  command : String?
  args : Array[String]
  model : String?
  env : Json
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
fn resolved_workspace(target : AcpTarget, session : AcpSession) -> String? {
  match session.workspace {
    Some(workspace) => Some(workspace)
    None => target.workspace
  }
}

///|
fn resolved_cwd(
  target : AcpTarget,
  session : AcpSession,
  request : AcpRunRequest,
) -> String {
  match request.cwd {
    Some(cwd) => cwd
    None =>
      match session.cwd {
        Some(cwd) => cwd
        None =>
          match target.cwd {
            Some(cwd) => cwd
            None =>
              match resolved_workspace(target, session) {
                Some(workspace) => workspace
                None => "."
              }
          }
      }
  }
}

///|
fn resolved_model(target : AcpTarget, request : AcpRunRequest) -> String? {
  match request.model {
    Some(model) => Some(model)
    None => target.model
  }
}

///|
fn resolved_command(target : AcpTarget) -> String? {
  match target.command {
    Some(command) => Some(command)
    None =>
      match target.backend {
        "codex" => Some("codex")
        _ => None
      }
  }
}

///|
fn resolved_args(target : AcpTarget) -> Array[String] {
  if !target.args.is_empty() {
    target.args
  } else {
    match target.backend {
      "codex" => ["exec"]
      _ => []
    }
  }
}

///|
fn codex_env(
  target : AcpTarget,
  session : AcpSession,
  request : AcpRunRequest,
) -> Json {
  {
    "ACP_TARGET_ID": target.id,
    "ACP_SESSION_ID": session.id,
    "ACP_SESSION_KEY": session.session_key,
    "ACP_BACKEND": "codex",
    "ACP_WORKSPACE": resolved_workspace(target, session),
    "ACP_MODEL": resolved_model(target, request),
  }
}

///|
fn codex_metadata(
  target : AcpTarget,
  session : AcpSession,
  request : AcpRunRequest,
) -> Json {
  {
    "adapter": "codex",
    "label": target.label,
    "workspace": resolved_workspace(target, session),
    "request": request.to_json(),
    "linkage": request.metadata,
    "target_metadata": target.metadata,
    "session_metadata": session.metadata,
  }
}

///|
pub fn prepare_launch_plan(
  target : AcpTarget,
  session : AcpSession,
  request : AcpRunRequest,
) -> Result[AcpLaunchPlan, String] {
  let cwd = resolved_cwd(target, session, request)
  match target.backend {
    "codex" =>
      Ok(AcpLaunchPlan::{
        backend: "codex",
        target_id: target.id,
        session_id: session.id,
        session_key: session.session_key,
        cwd,
        workspace: resolved_workspace(target, session),
        command: resolved_command(target),
        args: resolved_args(target),
        model: resolved_model(target, request),
        env: codex_env(target, session, request),
        metadata: codex_metadata(target, session, request),
      })
    backend => Err("Unsupported ACP backend: \{backend}")
  }
}
