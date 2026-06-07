///|
pub struct AcpLaunchCommand {
  command : String
  args : Array[String]
  env : Map[String, String]
} derive(ToJson, FromJson, Show)

///|
fn launch_arguments(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Array[String] {
  let args = plan.args.map(fn(arg) { arg })
  if !request.message.trim().is_blank() {
    args.push(request.message)
  }
  args
}

///|
fn launch_env(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Map[String, String] {
  let env = {}
  match plan.env {
    Object(entries) =>
      for key, value in entries {
        match value {
          String(text) => env[key] = text
          Null => ()
          _ => env[key] = value.stringify()
        }
      }
    _ => ()
  }
  env["ACP_MESSAGE"] = request.message
  env
}

///|
pub fn process_output_summary(
  stdout : String,
  stderr : String,
  status : Int,
) -> String {
  let stdout = stdout.trim().to_string()
  let stderr = stderr.trim().to_string()
  if !stdout.is_blank() {
    stdout
  } else if !stderr.is_blank() {
    stderr
  } else {
    "Codex backend exited with status \{status}"
  }
}

///|
fn acp_patch_receipt_contract() -> String {
  "planbook.repair.patch_receipt.v1"
}

///|
async fn acp_git_stdout(cwd : String, args : Array[String]) -> String? {
  let process = @spawn.spawn("git", args.map(fn(arg) { arg[:] }), cwd~) catch {
    _ => return None
  }
  if process.status == 0 {
    Some(process.stdout.trim().to_string())
  } else {
    None
  }
}

///|
async fn acp_git_head(cwd : String) -> String {
  acp_git_stdout(cwd, ["rev-parse", "HEAD"]).unwrap_or("")
}

///|
async fn acp_git_status(cwd : String) -> String {
  acp_git_stdout(cwd, ["status", "--short", "--untracked-files=all"]).unwrap_or(
    "",
  )
}

///|
async fn acp_git_diff_check_status(cwd : String) -> String {
  let process = @spawn.spawn("git", ["diff", "--check"], cwd~) catch {
    _ => return "unavailable"
  }
  if process.status == 0 {
    "passed"
  } else {
    "failed"
  }
}

///|
async fn acp_git_commit_message(
  cwd : String,
  base_head : String,
  final_head : String,
) -> String {
  if base_head.is_blank() || final_head.is_blank() || base_head == final_head {
    return ""
  }
  acp_git_stdout(cwd, ["log", "-1", "--pretty=%s"]).unwrap_or("")
}

///|
fn acp_changed_file_from_status_line(line : String) -> String? {
  let raw = line.to_string()
  if raw.trim().to_string().is_blank() {
    return None
  }
  let chars = raw.to_array()
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
  Some(builder.to_string().trim().to_string())
}

///|
fn acp_changed_files_from_status(status : String) -> Array[String] {
  let files : Array[String] = []
  for line in status.split("\n") {
    match acp_changed_file_from_status_line(line.to_string()) {
      Some(file) if !file.is_blank() => files.push(file)
      _ => ()
    }
  }
  files
}

///|
async fn acp_changed_files_between_heads(
  cwd : String,
  base_head : String,
  final_head : String,
) -> Array[String] {
  if base_head.is_blank() || final_head.is_blank() || base_head == final_head {
    return []
  }
  match acp_git_stdout(cwd, ["diff", "--name-only", base_head, final_head]) {
    Some(output) => {
      let files : Array[String] = []
      for line in output.split("\n") {
        let file = line.trim().to_string()
        if !file.is_blank() {
          files.push(file)
        }
      }
      files
    }
    None => []
  }
}

///|
fn acp_json_string_field(value : Json, key : String) -> String? {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn acp_json_field_with_step_metadata(value : Json, key : String) -> Json? {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(value) => Some(value)
        None =>
          match object.get("step_metadata") {
            Some(nested) => acp_json_field_with_step_metadata(nested, key)
            None =>
              match object.get("metadata") {
                Some(nested) => acp_json_field_with_step_metadata(nested, key)
                None => None
              }
          }
      }
    _ => None
  }
}

///|
fn acp_json_string_field_with_step_metadata(
  value : Json,
  key : String,
) -> String? {
  match acp_json_string_field(value, key) {
    Some(text) => return Some(text)
    None => ()
  }
  match acp_json_field_with_step_metadata(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn acp_json_array_field(value : Json, key : String) -> Json {
  match acp_json_field_with_step_metadata(value, key) {
    Some(value) =>
      match value {
        Array(_) => return value
        _ => ()
      }
    None => ()
  }
  match value {
    Object(object) =>
      match object.get(key) {
        Some(value) =>
          match value {
            Array(_) => value
            _ => []
          }
        _ => []
      }
    _ => []
  }
}

///|
fn acp_json_bool_field_with_step_metadata(value : Json, key : String) -> Bool? {
  match acp_json_field_with_step_metadata(value, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn acp_json_string_array_values(value : Json, key : String) -> Array[String] {
  match acp_json_array_field(value, key) {
    Array(items) => {
      let result : Array[String] = []
      for item in items {
        match item {
          String(text) => result.push(text)
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
fn acp_git_policy_commit_after_validation(linkage : Json) -> Bool {
  match acp_json_field_with_step_metadata(linkage, "git_policy") {
    Some(policy) =>
      acp_json_bool_field_with_step_metadata(policy, "commit_after_validation").unwrap_or(
        false,
      )
    None => false
  }
}

///|
fn acp_source_relative_target_file(cwd : String, target : String) -> String? {
  let target = target.trim().to_string()
  if target.is_blank() {
    return None
  }
  let source_prefix = "\{cwd}/"
  if target.has_prefix(source_prefix) {
    let relative = target[source_prefix.length():].to_string()
    if relative.contains("../") {
      None
    } else {
      Some(relative)
    }
  } else if !target.has_prefix("/") && !target.contains("../") {
    Some(target)
  } else {
    None
  }
}

///|
fn acp_source_relative_target_files(
  cwd : String,
  linkage : Json,
) -> Array[String] {
  let files : Array[String] = []
  for target in acp_json_string_array_values(linkage, "target_files") {
    match acp_source_relative_target_file(cwd, target) {
      Some(relative) if !files.contains(relative) => files.push(relative)
      _ => ()
    }
  }
  files
}

///|
fn acp_filter_changed_target_files(
  changed_files : Array[String],
  target_files : Array[String],
) -> Array[String] {
  let files : Array[String] = []
  for file in changed_files {
    if target_files.contains(file) && !files.contains(file) {
      files.push(file)
    }
  }
  files
}

///|
fn acp_filter_new_non_target_files(
  base_changed_files : Array[String],
  current_changed_files : Array[String],
  target_files : Array[String],
) -> Array[String] {
  let files : Array[String] = []
  for file in current_changed_files {
    if !base_changed_files.contains(file) &&
      !target_files.contains(file) &&
      !files.contains(file) {
      files.push(file)
    }
  }
  files
}

///|
async fn acp_restore_tracked_files(cwd : String, files : Array[String]) -> Unit {
  for file in files {
    ignore(
      @spawn.spawn("git", ["restore", "--source=HEAD", "--", file], cwd~) catch {
        _ => continue
      },
    )
  }
}

///|
fn acp_repair_commit_message(linkage : Json) -> String {
  match acp_json_string_field_with_step_metadata(linkage, "commit_message") {
    Some(message) if !message.trim().to_string().is_blank() =>
      message.trim().to_string()
    _ => {
      let criterion = acp_json_string_field_with_step_metadata(
        linkage, "criterion_id",
      ).unwrap_or("repair")
      "Repair \{criterion} through ACP"
    }
  }
}

///|
async fn acp_git_add_and_commit(
  cwd : String,
  files : Array[String],
  message : String,
) -> Bool {
  if files.is_empty() {
    return false
  }
  let add_args = ["add", "--"]
  for file in files {
    add_args.push(file)
  }
  let add = @spawn.spawn("git", add_args.map(fn(arg) { arg[:] }), cwd~) catch {
    _ => return false
  }
  if add.status != 0 {
    return false
  }
  let commit = @spawn.spawn(
    "git",
    [
      "-c", "user.name=MoonClaw ACP", "-c", "user.email=moonclaw-acp@local", "commit",
      "-m", message,
    ],
    cwd~,
  ) catch {
    _ => return false
  }
  commit.status == 0
}

///|
async fn acp_commit_repair_owned_files_after_validation(
  plan : AcpLaunchPlan,
  process : @spawn.CompletedProcess,
  linkage : Json,
  base_status : String,
) -> Unit {
  if process.status != 0 || !acp_git_policy_commit_after_validation(linkage) {
    return
  }
  let target_files = acp_source_relative_target_files(plan.cwd, linkage)
  if target_files.is_empty() {
    return
  }
  let base_changed_files = acp_changed_files_from_status(base_status)
  let changed_files = acp_changed_files_from_status(acp_git_status(plan.cwd))
  acp_restore_tracked_files(
    plan.cwd,
    acp_filter_new_non_target_files(
      base_changed_files, changed_files, target_files,
    ),
  )
  if acp_git_diff_check_status(plan.cwd) != "passed" {
    return
  }
  let changed_files = acp_changed_files_from_status(acp_git_status(plan.cwd))
  let files = acp_filter_changed_target_files(changed_files, target_files)
  ignore(
    acp_git_add_and_commit(plan.cwd, files, acp_repair_commit_message(linkage)),
  )
}

///|
fn acp_patch_receipt_result_decision(
  process : @spawn.CompletedProcess,
  changed_files : Array[String],
  diff_check_status : String,
  commit_status : String,
) -> String {
  if process.status != 0 {
    "blocked"
  } else if changed_files.is_empty() {
    "no_change"
  } else if diff_check_status != "passed" || commit_status != "committed" {
    "blocked"
  } else {
    "accepted"
  }
}

///|
fn acp_patch_receipt_commit_status(
  base_head : String,
  final_head : String,
  changed_files : Array[String],
) -> String {
  if changed_files.is_empty() {
    "skipped_no_change"
  } else if !base_head.is_blank() &&
    !final_head.is_blank() &&
    base_head != final_head {
    "committed"
  } else {
    "ready_to_commit"
  }
}

///|
async fn acp_patch_receipt(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
  process : @spawn.CompletedProcess,
  base_head : String,
  base_status : String,
  final_head : String,
  final_status : String,
) -> Json {
  let changed_from_commit = acp_changed_files_between_heads(
    plan.cwd,
    base_head,
    final_head,
  )
  let changed_files = if changed_from_commit.is_empty() {
    acp_changed_files_from_status(final_status)
  } else {
    changed_from_commit
  }
  let linkage = request.metadata.unwrap_or({})
  let commit_status = acp_patch_receipt_commit_status(
    base_head, final_head, changed_files,
  )
  let diff_check_status = acp_git_diff_check_status(plan.cwd)
  let result_decision = acp_patch_receipt_result_decision(
    process, changed_files, diff_check_status, commit_status,
  )
  let commit_message = acp_json_string_field_with_step_metadata(
    linkage, "commit_message",
  ).unwrap_or(acp_git_commit_message(plan.cwd, base_head, final_head))
  {
    "contract": acp_patch_receipt_contract(),
    "criterion_id": acp_json_string_field_with_step_metadata(
      linkage, "criterion_id",
    ).unwrap_or(""),
    "source_root": plan.cwd,
    "execution_mode": "acp",
    "execution_target": plan.target_id,
    "run_id": acp_json_string_field_with_step_metadata(linkage, "job_run_id").unwrap_or(
      "",
    ),
    "acp_run_id": request.run_id.unwrap_or(""),
    "base_head": base_head,
    "base_status": base_status,
    "final_head": final_head,
    "final_status": final_status,
    "changed_files": changed_files,
    "validation_commands": acp_json_array_field(
      linkage, "required_validation_commands",
    ),
    "diff_check_status": diff_check_status,
    "commit_status": commit_status,
    "commit_sha": if commit_status == "committed" {
      final_head
    } else {
      ""
    },
    "commit_message": commit_message,
    "push_status": "not_pushed_by_policy",
    "result_decision": result_decision,
  }
}

///|
fn codex_output_summary(process : @spawn.CompletedProcess) -> String {
  let stdout = process.stdout.trim().to_string()
  let stderr = process.stderr.trim().to_string()
  process_output_summary(stdout, stderr, process.status)
}

///|
pub fn prepare_launch_command(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[AcpLaunchCommand, String] {
  let command = match plan.command {
    Some(command) => command
    None =>
      return Err(
        "ACP launch plan is missing a command for backend \{plan.backend}",
      )
  }
  Ok(AcpLaunchCommand::{
    command,
    args: launch_arguments(plan, request),
    env: launch_env(plan, request),
  })
}

///|
pub async fn execute_launch_plan(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[Json, String] {
  if plan.backend == "codex" &&
    plan.command == Some("codex") &&
    !@codex.credentials_exist() {
    return Err(
      "Codex credentials are not available. Authenticate first with the Codex OAuth flow.",
    )
  }
  let command = match prepare_launch_command(plan, request) {
    Ok(command) => command
    Err(error) => return Err(error)
  }
  let base_head = acp_git_head(plan.cwd)
  let base_status = acp_git_status(plan.cwd)
  let process = @spawn.spawn(
    command.command,
    command.args.map(fn(arg) { arg }),
    cwd=plan.cwd,
    env=command.env,
  ) catch {
    error => return Err("Failed to start ACP backend: \{error}")
  }
  let linkage = request.metadata.unwrap_or({})
  acp_commit_repair_owned_files_after_validation(
    plan, process, linkage, base_status,
  )
  let final_head = acp_git_head(plan.cwd)
  let final_status = acp_git_status(plan.cwd)
  let patch_receipt = acp_patch_receipt(
    plan, request, process, base_head, base_status, final_head, final_status,
  )
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
    "stdout": process.stdout,
    "stderr": process.stderr,
    "elapsed_ms": process.elapsed,
    "content": codex_output_summary(process),
    "patch_receipt": patch_receipt,
  }
  if process.status == 0 {
    Ok(result)
  } else {
    Err(codex_output_summary(process))
  }
}
