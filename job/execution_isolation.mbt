///|
pub(all) enum ExecutionIsolationMode {
  SharedWorkspace
  GitWorktree
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ExecutionIsolationSpec {
  mode : ExecutionIsolationMode
  task_key : String
  base_dir : String?
  branch_name : String?
  commit : String?
  force_new_branch : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn ExecutionIsolationSpec::new(
  mode? : ExecutionIsolationMode = SharedWorkspace,
  task_key? : String = "",
  base_dir? : String? = None,
  branch_name? : String? = None,
  commit? : String? = None,
  force_new_branch? : Bool = false,
) -> ExecutionIsolationSpec {
  ExecutionIsolationSpec::{
    mode,
    task_key,
    base_dir,
    branch_name,
    commit,
    force_new_branch,
  }
}

///|
fn default_execution_isolation_task_key(
  context : WorkflowStepContext,
) -> String {
  "\{context.run.id}-\{context.step.id}"
}

///|
pub fn analysis_execution_isolation_spec(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> ExecutionIsolationSpec? {
  match metadata_with_step_metadata(config.metadata, "execution_isolation") {
    Some(Object(obj)) => {
      let mode = match obj.get("mode") {
        Some(String("git_worktree")) => GitWorktree
        Some(String("shared_workspace")) => SharedWorkspace
        _ => SharedWorkspace
      }
      let task_key = match obj.get("task_key") {
        Some(String(task_key)) if !task_key.trim().is_blank() =>
          task_key.trim().to_string()
        _ => default_execution_isolation_task_key(context)
      }
      let base_dir = match obj.get("base_dir") {
        Some(String(base_dir)) if !base_dir.trim().is_blank() =>
          Some(base_dir.trim().to_string())
        _ => None
      }
      let branch_name = match obj.get("branch_name") {
        Some(String(branch_name)) if !branch_name.trim().is_blank() =>
          Some(branch_name.trim().to_string())
        _ => None
      }
      let commit = match obj.get("commit") {
        Some(String(commit)) if !commit.trim().is_blank() =>
          Some(commit.trim().to_string())
        _ => None
      }
      let force_new_branch = match obj.get("force_new_branch") {
        Some(True) => true
        _ => false
      }
      Some(ExecutionIsolationSpec::{
        mode,
        task_key,
        base_dir,
        branch_name,
        commit,
        force_new_branch,
      })
    }
    _ => None
  }
}

///|
pub async fn resolve_analysis_execution_cwd(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  fallback_cwd : String,
) -> String {
  match analysis_execution_isolation_spec(context, config) {
    Some(spec) =>
      match spec.mode {
        SharedWorkspace => fallback_cwd
        GitWorktree => {
          let handle = @worktree.plan_worktree(
            fallback_cwd,
            spec.task_key,
            base_dir=spec.base_dir,
            branch_name=spec.branch_name,
          ) catch {
            _ => return fallback_cwd
          }
          let exists = @fsx.exists(handle.path) catch { _ => false }
          if !exists {
            ignore(
              @worktree.create_worktree(
                handle,
                commit=spec.commit,
                force_new_branch=spec.force_new_branch,
              ) catch {
                _ => return fallback_cwd
              },
            )
          }
          handle.path
        }
      }
    None => fallback_cwd
  }
}
