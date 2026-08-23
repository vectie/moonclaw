///|
priv struct AcpSandboxProcessResult {
  status : Int
  output : String
  changed_paths : Array[String]
}

///|
async fn acp_sandbox_git_stdout(
  cwd : String,
  operation : @trusted_host_process.GitOperation,
) -> String? {
  let process = @trusted_host_process.run_git(cwd, operation) catch {
    _ => return None
  }
  if process.status() == 0 {
    Some(process.stdout().trim().to_owned())
  } else {
    None
  }
}

///|
async fn acp_sandbox_git_head(cwd : String) -> String {
  acp_sandbox_git_stdout(cwd, Head).unwrap_or("")
}

///|
async fn acp_sandbox_git_status(cwd : String) -> String {
  acp_sandbox_git_stdout(cwd, StatusShort).unwrap_or("")
}

///|
async fn acp_sandbox_git_diff_check_status(cwd : String) -> String {
  let process = @trusted_host_process.run_git(cwd, DiffCheck) catch {
    _ => return "unavailable"
  }
  if process.status() == 0 {
    "passed"
  } else {
    "failed"
  }
}

///|
async fn acp_sandbox_git_commit_message(
  cwd : String,
  base_head : String,
  final_head : String,
) -> String {
  if base_head.is_blank() || final_head.is_blank() || base_head == final_head {
    return ""
  }
  acp_sandbox_git_stdout(cwd, CommitSubject).unwrap_or("")
}

///|
fn acp_sandbox_changed_file_from_status_line(line : String) -> String? {
  let chars = line.to_array()
  if chars.length() <= 2 {
    return None
  }
  let path_start = if chars.length() > 2 && chars[2] == ' ' {
    3
  } else if chars.length() > 1 && chars[1] == ' ' {
    2
  } else if chars.length() > 3 {
    3
  } else {
    return None
  }
  let builder = StringBuilder::new()
  for index in path_start..<chars.length() {
    builder.write_char(chars[index])
  }
  let path = builder.to_string().trim().to_owned()
  if path.is_blank() {
    None
  } else {
    Some(path)
  }
}

///|
fn acp_sandbox_changed_files_from_status(status : String) -> Array[String] {
  let files : Array[String] = []
  for line in status.split("\n") {
    match acp_sandbox_changed_file_from_status_line(line.to_owned()) {
      Some(file) if !files.contains(file) => files.push(file)
      _ => ()
    }
  }
  files
}

///|
async fn acp_sandbox_changed_files_between_heads(
  cwd : String,
  base_head : String,
  final_head : String,
) -> Array[String] {
  if base_head.is_blank() || final_head.is_blank() || base_head == final_head {
    return []
  }
  match
    acp_sandbox_git_stdout(
      cwd,
      DiffNamesBetween(base=base_head, target=final_head),
    ) {
    Some(output) => {
      let files : Array[String] = []
      for line in output.split("\n") {
        let file = line.trim().to_owned()
        if !file.is_blank() && !files.contains(file) {
          files.push(file)
        }
      }
      files
    }
    None => []
  }
}

///|
fn acp_sandbox_json_field(value : Json, key : String) -> Json? {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(value) => Some(value)
        None =>
          match object.get("step_metadata") {
            Some(nested) => acp_sandbox_json_field(nested, key)
            None =>
              match object.get("metadata") {
                Some(nested) => acp_sandbox_json_field(nested, key)
                None => None
              }
          }
      }
    _ => None
  }
}

///|
fn acp_sandbox_json_string(value : Json, key : String) -> String? {
  match acp_sandbox_json_field(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn acp_sandbox_json_array(value : Json, key : String) -> Json {
  match acp_sandbox_json_field(value, key) {
    Some(Array(_) as value) => value
    _ => []
  }
}

///|
fn acp_sandbox_json_bool(value : Json, key : String) -> Bool {
  match acp_sandbox_json_field(value, key) {
    Some(True) => true
    _ => false
  }
}

///|
fn acp_sandbox_json_strings(value : Json, key : String) -> Array[String] {
  match acp_sandbox_json_array(value, key) {
    Array(items) =>
      items.filter_map(item => {
        match item {
          String(text) => Some(text)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn acp_sandbox_relative_target(cwd : String, target : String) -> String? {
  let target = target.trim().to_owned()
  let relative = if target.has_prefix(cwd + "/") {
    target[cwd.length() + 1:].to_owned()
  } else if !target.has_prefix("/") {
    target
  } else {
    return None
  }
  if relative.is_blank() ||
    relative.split("/").any(component => component == ".." || component == ".") {
    None
  } else {
    Some(relative)
  }
}

///|
fn acp_sandbox_target_files(cwd : String, linkage : Json) -> Array[String] {
  let files : Array[String] = []
  for target in acp_sandbox_json_strings(linkage, "target_files") {
    match acp_sandbox_relative_target(cwd, target) {
      Some(relative) if !files.contains(relative) => files.push(relative)
      _ => ()
    }
  }
  files
}

///|
async fn acp_sandbox_commit_owned_files(
  plan : AcpLaunchPlan,
  process : AcpSandboxProcessResult,
  linkage : Json,
  base_status : String,
) -> Unit {
  let commit_after_validation = match
    acp_sandbox_json_field(linkage, "git_policy") {
    Some(policy) => acp_sandbox_json_bool(policy, "commit_after_validation")
    None => false
  }
  if process.status != 0 || !commit_after_validation {
    return
  }
  let targets = acp_sandbox_target_files(plan.cwd, linkage)
  if targets.is_empty() {
    return
  }
  let baseline = acp_sandbox_changed_files_from_status(base_status)
  let current = if process.changed_paths.is_empty() {
    acp_sandbox_changed_files_from_status(acp_sandbox_git_status(plan.cwd))
  } else {
    process.changed_paths
  }
  let restore = current.filter(file => {
    !baseline.contains(file) && !targets.contains(file)
  })
  if !restore.is_empty() {
    ignore(
      @trusted_host_process.run_git(plan.cwd, RestoreHeadFiles(restore)) catch {
        _ => return
      },
    )
  }
  if acp_sandbox_git_diff_check_status(plan.cwd) != "passed" {
    return
  }
  let changed = (if process.changed_paths.is_empty() {
    acp_sandbox_changed_files_from_status(acp_sandbox_git_status(plan.cwd))
  } else {
    process.changed_paths
  }).filter(file => targets.contains(file))
  if changed.is_empty() {
    return
  }
  let added = @trusted_host_process.run_git(plan.cwd, AddFiles(changed)) catch {
    _ => return
  }
  if added.status() != 0 {
    return
  }
  let criterion = acp_sandbox_json_string(linkage, "criterion_id").unwrap_or(
    "repair",
  )
  let message = acp_sandbox_json_string(linkage, "commit_message").unwrap_or(
    "Repair \{criterion} through ACP",
  )
  ignore(
    @trusted_host_process.run_git(plan.cwd, Commit(message)) catch {
      _ => return
    },
  )
}

///|
async fn acp_sandbox_patch_receipt(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
  process : AcpSandboxProcessResult,
  base_head : String,
  base_status : String,
  final_head : String,
  final_status : String,
) -> Json {
  let committed_files = acp_sandbox_changed_files_between_heads(
    plan.cwd,
    base_head,
    final_head,
  )
  let changed_files = if !committed_files.is_empty() {
    committed_files
  } else if !process.changed_paths.is_empty() {
    process.changed_paths
  } else {
    acp_sandbox_changed_files_from_status(final_status)
  }
  let linkage = request.metadata.unwrap_or({})
  let commit_status = if changed_files.is_empty() {
    "skipped_no_change"
  } else if !base_head.is_blank() &&
    !final_head.is_blank() &&
    base_head != final_head {
    "committed"
  } else {
    "ready_to_commit"
  }
  let diff_check_status = acp_sandbox_git_diff_check_status(plan.cwd)
  let decision = if process.status != 0 {
    "blocked"
  } else if changed_files.is_empty() {
    "no_change"
  } else if diff_check_status == "passed" && commit_status == "committed" {
    "accepted"
  } else {
    "blocked"
  }
  {
    "contract": "planbook.repair.patch_receipt.v1",
    "criterion_id": acp_sandbox_json_string(linkage, "criterion_id").unwrap_or(
      "",
    ),
    "source_root": plan.cwd,
    "execution_mode": "acp",
    "execution_target": plan.target_id,
    "run_id": acp_sandbox_json_string(linkage, "job_run_id").unwrap_or(""),
    "acp_run_id": request.run_id.unwrap_or(""),
    "base_head": base_head,
    "base_status": base_status,
    "final_head": final_head,
    "final_status": final_status,
    "changed_files": changed_files,
    "validation_commands": acp_sandbox_json_array(
      linkage, "required_validation_commands",
    ),
    "diff_check_status": diff_check_status,
    "commit_status": commit_status,
    "commit_sha": if commit_status == "committed" {
      final_head
    } else {
      ""
    },
    "commit_message": acp_sandbox_json_string(linkage, "commit_message").unwrap_or(
      acp_sandbox_git_commit_message(plan.cwd, base_head, final_head),
    ),
    "push_status": "not_pushed_by_policy",
    "result_decision": decision,
  }
}

///|
fn acp_sandbox_launch_environment_supported(command : AcpLaunchCommand) -> Bool {
  command.env.keys().all(key => key == "ACP_MESSAGE")
}

///|
/// Consume an exact, pre-approved typed MoonFort plan for an ACP launch. This
/// is deliberately separate from `execute_launch_plan`: callers must obtain
/// and persist operator approval before invoking it, and no direct host-process
/// fallback exists.
pub async fn execute_launch_plan_with_approved_sandbox(
  config : @execution_sandbox.SandboxExecutorConfig,
  approved_plan : @execution_sandbox.SandboxApprovalPlan,
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[Json, String] {
  let command = match prepare_launch_command(plan, request) {
    Ok(command) => command
    Err(error) => return Err(error)
  }
  guard acp_sandbox_launch_environment_supported(command) else {
    return Err(
      "ACP sandbox execution refuses target environment variables until the MoonFort grant contract binds them",
    )
  }
  let workspace = plan.workspace.unwrap_or(plan.cwd)
  let base_head = acp_sandbox_git_head(plan.cwd)
  let base_status = acp_sandbox_git_status(plan.cwd)
  let execution = @execution_sandbox.run_approved_exec(
    config,
    workspace,
    plan.cwd,
    command.command,
    command.args,
    approved_plan,
  ) catch {
    error => return Err("MoonFort ACP execution failed closed: \{error}")
  }
  let receipt = execution.receipt
  guard receipt.status is Exited && receipt.exit_code is Some(status) else {
    return Err("MoonFort ACP execution omitted a terminal exit status")
  }
  guard !receipt.output_truncated else {
    return Err("MoonFort ACP execution output is incomplete")
  }
  let process = AcpSandboxProcessResult::{
    status,
    output: receipt.output,
    changed_paths: receipt.changed_paths,
  }
  let linkage = request.metadata.unwrap_or({})
  acp_sandbox_commit_owned_files(plan, process, linkage, base_status)
  let final_head = acp_sandbox_git_head(plan.cwd)
  let final_status = acp_sandbox_git_status(plan.cwd)
  let patch_receipt = acp_sandbox_patch_receipt(
    plan, request, process, base_head, base_status, final_head, final_status,
  )
  let content = process_output_summary(process.output, "", process.status)
  let result : Json = {
    "backend": plan.backend,
    "target_id": plan.target_id,
    "session_id": plan.session_id,
    "session_key": plan.session_key,
    "cwd": plan.cwd,
    "workspace": plan.workspace,
    "command": command.command,
    "args": command.args,
    "status": if process.status == 0 {
      "completed"
    } else {
      "failed"
    },
    "exit_status": process.status,
    "stdout": process.output,
    "stderr": "",
    "content": content,
    "patch_receipt": patch_receipt,
    "sandbox": {
      "approval_id": receipt.approval_id,
      "approval_digest": receipt.approval_digest,
      "backend": receipt.backend,
      "enforcement": receipt.enforcement,
      "cleanup_verified": receipt.cleanup_verified,
      "profile_digest": receipt.profile_digest,
    },
  }
  if process.status == 0 {
    Ok(result)
  } else {
    Err(content)
  }
}

///|
/// White-box integration seam for the shared protocol fixture. Production
/// callers use the approved-sandbox entry point, which refuses unbound target
/// environment variables. This helper accepts only the fixture workspace
/// marker and degraded test backend before removing generated ACP linkage env.
pub async fn execute_launch_plan_with_fixture_sandbox(
  config : @execution_sandbox.SandboxExecutorConfig,
  approved_plan : @execution_sandbox.SandboxApprovalPlan,
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[Json, String] {
  guard config.workspace_id == "fixture-workspace" &&
    config.enforcement_requirement is AllowDegraded else {
    return Err("ACP fixture sandbox requires the explicit test deployment")
  }
  let fixture_plan = { ..plan, env: ({} : Json) }
  execute_launch_plan_with_approved_sandbox(
    config, approved_plan, fixture_plan, request,
  )
}
