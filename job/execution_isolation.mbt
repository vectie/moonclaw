///|
pub(all) enum ExecutionIsolationMode {
  SharedWorkspace
  GitWorktree
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct ExecutionIsolationSpec {
  mode : ExecutionIsolationMode
  task_key : String
  base_dir : String?
  branch_name : String?
  commit : String?
  cleanup_policy : String?
  force_new_branch : Bool
} derive(ToJson, FromJson, Debug)

///|
pub fn ExecutionIsolationSpec::new(
  mode? : ExecutionIsolationMode = SharedWorkspace,
  task_key? : String = "",
  base_dir? : String? = None,
  branch_name? : String? = None,
  commit? : String? = None,
  cleanup_policy? : String? = None,
  force_new_branch? : Bool = false,
) -> ExecutionIsolationSpec {
  {
    mode,
    task_key,
    base_dir,
    branch_name,
    commit,
    cleanup_policy,
    force_new_branch,
  }
}

///|
pub(all) struct ExecutionIsolationResolution {
  cwd : String
  metadata : Json?
} derive(ToJson, FromJson, Debug)

///|
pub fn ExecutionIsolationResolution::new(
  cwd~ : String,
  metadata? : Json? = None,
) -> ExecutionIsolationResolution {
  { cwd, metadata }
}

///|
fn normalized_isolation_text(text : String) -> String {
  text.to_lower().trim().to_owned()
}

///|
fn contains_any_keyword(text : String, keywords : Array[String]) -> Bool {
  for keyword in keywords {
    if text.contains(keyword) {
      return true
    }
  }
  false
}

///|
pub fn subtask_prefers_git_worktree(
  title : String,
  prompt : String,
  kind : String?,
) -> Bool {
  let kind = kind.unwrap_or("job.analysis").trim().to_owned()
  if kind != "job.analysis" {
    return false
  }
  let text = normalized_isolation_text("\{title}\n\{prompt}")
  let action_keywords = [
    "implement", "edit", "modify", "refactor", "rewrite", "update", "fix", "patch",
    "rename", "change",
  ]
  let target_keywords = [
    "code", "file", "files", "module", "function", "repository", "repo", "source",
    "implementation", "implement requested change", "worker request", ".mbt", ".ts",
    ".js", ".py", ".go", ".rs", ".java", ".kt", ".swift", ".c", ".cpp", ".h",
  ]
  contains_any_keyword(text, action_keywords) &&
  contains_any_keyword(text, target_keywords)
}

///|
pub fn subtask_execution_isolation_metadata(
  step_id : String,
  title : String,
  prompt : String,
  kind : String?,
) -> Json {
  if !subtask_prefers_git_worktree(title, prompt, kind) {
    return {}
  }
  {
    "execution_isolation": {
      "mode": "git_worktree",
      "task_key": "\{step_id} \{title}",
      "cleanup_policy": "on_success",
    },
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
) -> ExecutionIsolationSpec? raise {
  match metadata_with_step_metadata(config.metadata, "execution_isolation") {
    Some(Object(obj)) => {
      let mode = match obj.get("mode") {
        Some(String("git_worktree")) => GitWorktree
        Some(String("shared_workspace")) => SharedWorkspace
        None => SharedWorkspace
        Some(String(mode)) =>
          raise Failure("unsupported execution isolation mode: \{mode}")
        Some(_) => raise Failure("execution isolation mode must be a string")
      }
      let task_key = match obj.get("task_key") {
        Some(String(task_key)) if !task_key.trim().is_blank() =>
          task_key.trim().to_owned()
        _ => default_execution_isolation_task_key(context)
      }
      let base_dir = match obj.get("base_dir") {
        Some(String(base_dir)) if !base_dir.trim().is_blank() =>
          Some(base_dir.trim().to_owned())
        _ => None
      }
      let branch_name = match obj.get("branch_name") {
        Some(String(branch_name)) if !branch_name.trim().is_blank() =>
          Some(branch_name.trim().to_owned())
        _ => None
      }
      let commit = match obj.get("commit") {
        Some(String(commit)) if !commit.trim().is_blank() =>
          Some(commit.trim().to_owned())
        _ => None
      }
      let cleanup_policy = match obj.get("cleanup_policy") {
        Some(String(cleanup_policy)) if !cleanup_policy.trim().is_blank() =>
          Some(cleanup_policy.trim().to_lower().to_owned())
        _ => None
      }
      let force_new_branch = match obj.get("force_new_branch") {
        Some(True) => true
        _ => false
      }
      Some({
        mode,
        task_key,
        base_dir,
        branch_name,
        commit,
        cleanup_policy,
        force_new_branch,
      })
    }
    _ => None
  }
}

///|
fn execution_isolation_mode_name(mode : ExecutionIsolationMode) -> String {
  match mode {
    SharedWorkspace => "shared_workspace"
    GitWorktree => "git_worktree"
  }
}

///|
fn execution_isolation_metadata(
  spec : ExecutionIsolationSpec,
  working_directory : String,
  base_cwd : String,
  repo_root : String?,
  auto_created : Bool,
) -> Json {
  {
    "mode": execution_isolation_mode_name(spec.mode),
    "cwd": working_directory,
    "base_cwd": base_cwd,
    "repo_root": repo_root,
    "task_key": spec.task_key,
    "branch_name": spec.branch_name,
    "cleanup_policy": spec.cleanup_policy,
    "auto_created": auto_created,
  }
}

///|
pub async fn resolve_analysis_execution_isolation(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  fallback_cwd : String,
) -> ExecutionIsolationResolution {
  match analysis_execution_isolation_spec(context, config) {
    Some(spec) =>
      match spec.mode {
        SharedWorkspace => ExecutionIsolationResolution::new(cwd=fallback_cwd)
        GitWorktree => {
          let handle = @worktree.plan_worktree(
            fallback_cwd,
            spec.task_key,
            base_dir=spec.base_dir,
            branch_name=spec.branch_name,
          ) catch {
            error =>
              raise Failure(
                "failed to plan required git worktree isolation: \{error}",
              )
          }
          let exists = @fsx.exists(handle.path) catch {
            error =>
              raise Failure(
                "failed to inspect required git worktree isolation: \{error}",
              )
          }
          let auto_created = !exists
          if !exists {
            ignore(
              @worktree.create_worktree(
                handle,
                commit=spec.commit,
                force_new_branch=spec.force_new_branch,
              ) catch {
                error =>
                  raise Failure(
                    "failed to create required git worktree isolation: \{error}",
                  )
              },
            )
          }
          ExecutionIsolationResolution::new(
            cwd=handle.path,
            metadata=Some(
              execution_isolation_metadata(
                spec,
                handle.path,
                fallback_cwd,
                Some(handle.repo_root),
                auto_created,
              ),
            ),
          )
        }
      }
    None => ExecutionIsolationResolution::new(cwd=fallback_cwd)
  }
}

///|
pub async fn resolve_analysis_execution_cwd(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  fallback_cwd : String,
) -> String {
  resolve_analysis_execution_isolation(context, config, fallback_cwd).cwd
}

///|
fn execution_isolation_cleanup_matches(
  run_status : RunStatus,
  cleanup_policy : String,
) -> Bool {
  match cleanup_policy {
    "always" => true
    "on_finish" => true
    "on_success" => run_status is Succeeded
    "on_failure" => run_status is Failed || run_status is Cancelled
    _ => false
  }
}

///|
pub async fn cleanup_run_execution_isolations(
  store : SystemStore,
  run : JobRun,
) -> Array[String] {
  let removed : Array[String] = []
  let seen : Map[String, Bool] = {}
  for artifact in store.list_artifacts(run_id=run.id) {
    match artifact.metadata {
      {
        "execution_isolation": {
          "mode": String("git_worktree"),
          "cwd": String(cwd),
          "base_cwd": String(base_cwd),
          "repo_root": String(repo_root),
          "auto_created": True,
          "cleanup_policy": String(cleanup_policy),
          ..
        },
        ..
      } if !cwd.trim().is_blank() &&
        !seen.contains(cwd) &&
        execution_isolation_cleanup_matches(run.status, cleanup_policy) => {
        seen.set(cwd, true)
        ignore(
          @worktree.remove_worktree_path(
            base_cwd,
            cwd,
            repo_root=Some(repo_root),
          ) catch {
            _ => ()
          },
        )
        removed.push(cwd)
      }
      _ => ()
    }
  }
  removed
}
