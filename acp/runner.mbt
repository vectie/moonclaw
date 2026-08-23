///|
pub struct AcpLaunchCommand {
  command : String
  args : Array[String]
  env : Map[String, String]
} derive(ToJson, FromJson, Debug)

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
  let stdout = stdout.trim().to_owned()
  let stderr = stderr.trim().to_owned()
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
priv struct AcpProcessResult {
  status : Int
  stdout : String
  stderr : String
}

///|
async fn acp_git_stdout(
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
async fn acp_git_head(cwd : String) -> String {
  acp_git_stdout(cwd, @trusted_host_process.Head).unwrap_or("")
}

///|
async fn acp_git_status(cwd : String) -> String {
  acp_git_stdout(cwd, @trusted_host_process.StatusShort).unwrap_or("")
}

///|
async fn acp_git_diff_check_status(cwd : String) -> String {
  let process = @trusted_host_process.run_git(
    cwd,
    @trusted_host_process.DiffCheck,
  ) catch {
    _ => return "unavailable"
  }
  if process.status() == 0 {
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
  acp_git_stdout(cwd, @trusted_host_process.CommitSubject).unwrap_or("")
}

///|
fn acp_changed_file_from_status_line(line : String) -> String? {
  let raw = line.to_string()
  if raw.trim().to_owned().is_blank() {
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
  Some(builder.to_string().trim().to_owned())
}

///|
fn acp_changed_files_from_status(status : String) -> Array[String] {
  let files : Array[String] = []
  for line in status.split("\n") {
    match acp_changed_file_from_status_line(line.to_owned()) {
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
  match
    acp_git_stdout(
      cwd,
      @trusted_host_process.DiffNamesBetween(base=base_head, target=final_head),
    ) {
    Some(output) => {
      let files : Array[String] = []
      for line in output.split("\n") {
        let file = line.trim().to_owned()
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
  let target = target.trim().to_owned()
  if target.is_blank() {
    return None
  }
  let source_prefix = "\{cwd}/"
  if target.has_prefix(source_prefix) {
    let relative = target[source_prefix.length():].to_owned()
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
  if !files.is_empty() {
    ignore(
      @trusted_host_process.run_git(
        cwd,
        @trusted_host_process.RestoreHeadFiles(files),
      ) catch {
        _ => return
      },
    )
  }
}

///|
fn acp_repair_commit_message(linkage : Json) -> String {
  match acp_json_string_field_with_step_metadata(linkage, "commit_message") {
    Some(message) if !message.trim().to_owned().is_blank() =>
      message.trim().to_owned()
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
  let add = @trusted_host_process.run_git(
    cwd,
    @trusted_host_process.AddFiles(files),
  ) catch {
    _ => return false
  }
  if add.status() != 0 {
    return false
  }
  let commit = @trusted_host_process.run_git(
    cwd,
    @trusted_host_process.Commit(message),
  ) catch {
    _ => return false
  }
  commit.status() == 0
}

///|
async fn acp_commit_repair_owned_files_after_validation(
  plan : AcpLaunchPlan,
  process : AcpProcessResult,
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
  process : AcpProcessResult,
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
  process : AcpProcessResult,
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
fn codex_output_summary(process : AcpProcessResult) -> String {
  let stdout = process.stdout.trim().to_owned()
  let stderr = process.stderr.trim().to_owned()
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
  Ok({
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
  ignore(request)
  Err(
    "ACP backend execution is disabled for target \{plan.target_id}: a MoonFort ExecutionSandbox grant is required",
  )
}
