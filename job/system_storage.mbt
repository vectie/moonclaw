///|
struct DefinitionsIndexFile {
  definitions : Array[JobDefinition]
  workflows : Array[WorkflowDefinition]
} derive(ToJson, FromJson, Debug)

///|
struct RunsIndexFile {
  runs : Array[JobRun]
  steps : Array[JobStepRun]
} derive(ToJson, FromJson, Debug)

///|
struct ArtifactsIndexFile {
  artifacts : Array[ArtifactRecord]
} derive(ToJson, FromJson, Debug)

///|
struct MemoriesFile {
  memories : Array[MemoryRecord]
} derive(ToJson, FromJson, Debug)

///|
struct ChatBindingsFile {
  bindings : Array[ChatBinding]
} derive(ToJson, FromJson, Debug)

///|
struct NotificationPreferencesFile {
  preferences : Array[JobNotificationPreference]
} derive(ToJson, FromJson, Debug)

///|
struct JobProposalsFile {
  proposals : Array[JobProposal]
} derive(ToJson, FromJson, Debug)

///|
struct ControllerStateFile {
  states : Array[JobControllerState]
} derive(ToJson, FromJson, Debug)

///|
struct ControllerIterationsFile {
  iterations : Array[JobControllerIteration]
} derive(ToJson, FromJson, Debug)

///|
struct ControllerLineageFile {
  edges : Array[JobControllerLineageEdge]
} derive(ToJson, FromJson, Debug)

///|
struct ControllerDecisionsFile {
  decisions : Array[JobControllerDecision]
} derive(ToJson, FromJson, Debug)

///|
pub struct SystemStore {
  root : String
  definitions : Map[String, JobDefinition]
  workflows : Map[String, WorkflowDefinition]
  runs : Map[String, JobRun]
  steps : Map[String, JobStepRun]
  artifacts : Map[String, ArtifactRecord]
  memories : Map[String, MemoryRecord]
  chat_bindings : Map[String, ChatBinding]
  notification_preferences : Map[String, JobNotificationPreference]
  proposals : Map[String, JobProposal]
  controller_states : Map[String, JobControllerState]
  controller_iterations : Map[String, JobControllerIteration]
  controller_lineage_edges : Map[String, JobControllerLineageEdge]
  controller_decisions : Map[String, JobControllerDecision]
}

///|
pub fn SystemStore::new(root~ : String) -> SystemStore {
  {
    root,
    definitions: {},
    workflows: {},
    runs: {},
    steps: {},
    artifacts: {},
    memories: {},
    chat_bindings: {},
    notification_preferences: {},
    proposals: {},
    controller_states: {},
    controller_iterations: {},
    controller_lineage_edges: {},
    controller_decisions: {},
  }
}

///|
pub fn SystemStore::root_dir(self : SystemStore) -> String {
  self.root
}

///|
fn SystemStore::definitions_file(self : SystemStore) -> String {
  self.root |> @pathx.join("definitions.json")
}

///|
fn SystemStore::runs_index_file(self : SystemStore) -> String {
  self.root |> @pathx.join("index") |> @pathx.join("runs.json")
}

///|
fn SystemStore::store_lock_file(self : SystemStore) -> String {
  self.root |> @pathx.join(".store.lock")
}

///|
fn SystemStore::artifacts_index_file(self : SystemStore) -> String {
  self.root |> @pathx.join("index") |> @pathx.join("artifacts.json")
}

///|
fn SystemStore::memories_file(self : SystemStore) -> String {
  self.root |> @pathx.join("memories.json")
}

///|
fn SystemStore::chat_bindings_file(self : SystemStore) -> String {
  self.root |> @pathx.join("chat_bindings.json")
}

///|
fn SystemStore::notification_preferences_file(self : SystemStore) -> String {
  self.root |> @pathx.join("notification_preferences.json")
}

///|
fn SystemStore::job_proposals_file(self : SystemStore) -> String {
  self.root |> @pathx.join("job_proposals.json")
}

///|
fn SystemStore::controller_states_file(self : SystemStore) -> String {
  self.root |> @pathx.join("controller_states.json")
}

///|
fn SystemStore::controller_iterations_file(self : SystemStore) -> String {
  self.root |> @pathx.join("controller_iterations.json")
}

///|
fn SystemStore::controller_lineage_file(self : SystemStore) -> String {
  self.root |> @pathx.join("controller_lineage.json")
}

///|
fn SystemStore::controller_decisions_file(self : SystemStore) -> String {
  self.root |> @pathx.join("controller_decisions.json")
}

///|
fn SystemStore::run_dir(self : SystemStore, run_id : String) -> String {
  self.root |> @pathx.join("runs") |> @pathx.join(run_id)
}

///|
fn SystemStore::run_meta_file(self : SystemStore, run_id : String) -> String {
  self.run_dir(run_id) |> @pathx.join("meta.json")
}

///|
fn SystemStore::step_dir(self : SystemStore, run_id : String) -> String {
  self.run_dir(run_id) |> @pathx.join("steps")
}

///|
fn safe_step_file_segment(step_id : String) -> String {
  let buf = StringBuilder::new()
  let mut chars_written = 0
  let mut last_dash = true
  for c in step_id.to_lower() {
    let normalized = match c {
      'a'..='z' => Some(c)
      '0'..='9' => Some(c)
      _ => None
    }
    match normalized {
      Some(c) => {
        if chars_written >= 48 {
          break
        }
        buf.write_char(c)
        chars_written += 1
        last_dash = false
      }
      None =>
        if !last_dash && chars_written < 48 {
          buf.write_char('-')
          chars_written += 1
          last_dash = true
        }
    }
  }
  let slug = buf.to_string().trim(chars="-").to_owned()
  let prefix = if slug.is_blank() { "step" } else { slug }
  let suffix = step_id.hash().to_string().trim(chars="-").to_owned()
  "\{prefix}-\{suffix}"
}

///|
fn SystemStore::step_meta_file(
  self : SystemStore,
  run_id : String,
  step_id : String,
) -> String {
  self.step_dir(run_id)
  |> @pathx.join("\{safe_step_file_segment(step_id)}.json")
}

///|
pub fn SystemStore::run_events_file(
  self : SystemStore,
  run_id : String,
) -> String {
  self.run_dir(run_id) |> @pathx.join("events.jsonl")
}

///|
fn SystemStore::artifact_record_file(
  self : SystemStore,
  artifact_id : String,
) -> String {
  self.artifact_dir(artifact_id) |> @pathx.join("record.json")
}

///|
pub fn SystemStore::artifact_dir(
  self : SystemStore,
  artifact_id : String,
) -> String {
  self.root |> @pathx.join("artifacts") |> @pathx.join(artifact_id)
}

///|
pub fn SystemStore::artifact_content_file(
  self : SystemStore,
  artifact_id : String,
  file_name? : String = "content.bin",
) -> String {
  self.artifact_dir(artifact_id) |> @pathx.join(file_name)
}

///|
async fn SystemStore::ensure_directories(self : SystemStore) -> Unit {
  @fsx.make_directory(self.root, recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.root |> @pathx.join("runs"), recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.root |> @pathx.join("artifacts"), recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.root |> @pathx.join("index"), recursive=true) catch {
    _ => ()
  }
}

///|
fn[K : Hash + Eq, V] clear_map(map : Map[K, V]) -> Unit {
  let keys = map.keys().to_array()
  for key in keys {
    map.remove(key) |> ignore()
  }
}

///|
async fn[T : @json.FromJson] load_json_file(
  path : String,
  message : String,
) -> T {
  let content = @fsx.read_file(path)
  @json.from_json(@json.parse(content)) catch {
    error => fail("\{message}: \{error}")
  }
}

///|
async fn[T] SystemStore::with_store_lock(
  self : SystemStore,
  f : async () -> T,
) -> T {
  self.ensure_directories()
  let lock_file = @fs.open(self.store_lock_file(), mode=WriteOnly, create=0o644)
  defer lock_file.close()
  @fsx.lock_file(lock_file)
  f()
}

///|
async fn[T : @json.FromJson] try_load_json_file(path : String) -> T? {
  Some(@json.from_json(@json.parse(@fsx.read_file(path)))) catch {
    _ => None
  }
}

///|
async fn try_load_runs_index_file(path : String) -> RunsIndexFile? {
  try_load_json_file(path)
}

///|
async fn SystemStore::runs_index_from_disk(self : SystemStore) -> RunsIndexFile {
  let runs : Array[JobRun] = []
  let steps : Array[JobStepRun] = []
  let runs_root = self.root |> @pathx.join("runs")
  if !@fsx.exists(runs_root) {
    return { runs, steps }
  }
  for entry in @fsx.list_directory(runs_root) {
    match entry.kind {
      Directory => ()
      _ => continue
    }
    let meta_path = entry.path |> @pathx.join("meta.json")
    if @fsx.exists(meta_path) {
      match try_load_json_file(meta_path) {
        Some(run) => runs.push(run)
        None => ()
      }
    }
    let steps_dir = entry.path |> @pathx.join("steps")
    if !@fsx.exists(steps_dir) {
      continue
    }
    for step_entry in @fsx.list_directory(steps_dir) {
      match step_entry.kind {
        Regular => ()
        _ => continue
      }
      if !step_entry.name.has_suffix(".json") {
        continue
      }
      match try_load_json_file(step_entry.path) {
        Some(step) => steps.push(step)
        None => ()
      }
    }
  }
  { runs, steps }
}

///|
async fn SystemStore::load_runs_index_best_effort(
  self : SystemStore,
) -> RunsIndexFile {
  let disk = self.runs_index_from_disk()
  if !@fsx.exists(self.runs_index_file()) {
    return disk
  }
  let existing = try_load_runs_index_file(self.runs_index_file())
  match existing {
    Some(file) => {
      let merged_runs : Map[String, JobRun] = {}
      let merged_steps : Map[String, JobStepRun] = {}
      for run in file.runs {
        merged_runs.set(run.id, run)
      }
      for step in file.steps {
        merged_steps.set("\{step.run_id}:\{step.step_id}", step)
      }
      // Per-run metadata is authoritative; the shared index is only a cache.
      for run in disk.runs {
        merged_runs.set(run.id, run)
      }
      for step in disk.steps {
        merged_steps.set("\{step.run_id}:\{step.step_id}", step)
      }
      {
        runs: merged_runs.values().to_array(),
        steps: merged_steps.values().to_array(),
      }
    }
    None => disk
  }
}

///|
async fn SystemStore::write_runs_index_cache_unlocked(
  self : SystemStore,
  file : RunsIndexFile,
) -> Unit {
  @fsx.write_to_file(self.runs_index_file(), file.to_json().stringify())
}

///|
fn run_status_is_terminal(status : RunStatus) -> Bool {
  match status {
    Succeeded | Failed | Cancelled => true
    _ => false
  }
}

///|
fn SystemStore::delegate_child_runs_for_step(
  self : SystemStore,
  run_id : String,
  step_id : String,
) -> Array[JobRun] {
  let children = self.runs
    .values()
    .filter(fn(candidate) {
      candidate.parent_run_id == Some(run_id) &&
      candidate.parent_step_id == Some(step_id)
    })
    .to_array()
  children.sort_by(fn(left, right) {
    let left_time = left.finished_at.unwrap_or(left.started_at.unwrap_or(0))
    let right_time = right.finished_at.unwrap_or(right.started_at.unwrap_or(0))
    right_time.compare(left_time)
  })
  children
}

///|
fn reconciled_delegate_step_run(
  run : JobRun,
  step : WorkflowStepDefinition,
  existing : JobStepRun?,
  child : JobRun,
) -> JobStepRun {
  let finished_at = child.finished_at.unwrap_or(child.started_at.unwrap_or(0))
  let summary = match child.status {
    Succeeded =>
      Some("Recovered delegate completion from child run \{child.id}")
    Failed => Some("Recovered delegate failure from child run \{child.id}")
    Cancelled =>
      Some("Recovered delegate cancellation from child run \{child.id}")
    _ => None
  }
  let logs = match existing {
    Some(existing) => existing.logs
    None => []
  }
  logs.push(
    "reconciled from child run \{child.id} status \{child.status.to_json().stringify()}",
  )
  let output : Json? = match existing {
    Some(existing) =>
      match existing.output {
        Some(output) => Some(output)
        None =>
          Some({
            "status": "completed",
            "child_job_id": child.job_id,
            "child_run_id": child.id,
          })
      }
    None =>
      Some({
        "status": "completed",
        "child_job_id": child.job_id,
        "child_run_id": child.id,
      })
  }
  let error = match child.status {
    Failed => Some(child.error.unwrap_or("child run failed"))
    Cancelled => Some(child.error.unwrap_or("child run cancelled"))
    _ => None
  }
  match existing {
    Some(existing) => {
      let resolved_summary = match summary {
        Some(summary) => Some(summary)
        None => existing.summary
      }
      {
        ..existing,
        status: child.status,
        finished_at: Some(finished_at),
        logs,
        summary: resolved_summary,
        output,
        error,
      }
    }
    None =>
      {
        id: "\{run.id}:\{step.id}",
        run_id: run.id,
        step_id: step.id,
        status: child.status,
        started_at: child.started_at,
        finished_at: Some(finished_at),
        metrics: {},
        logs,
        retry_count: 0,
        summary,
        output,
        error,
      }
  }
}

///|
async fn SystemStore::save_reconciled_step_run_unlocked(
  self : SystemStore,
  step : JobStepRun,
) -> Unit {
  self.steps.set("\{step.run_id}:\{step.step_id}", step)
  @fsx.make_directory(self.step_dir(step.run_id), recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(
    self.step_meta_file(step.run_id, step.step_id),
    step.to_json().stringify(),
  )
}

///|
async fn SystemStore::save_reconciled_run_unlocked(
  self : SystemStore,
  run : JobRun,
) -> Unit {
  self.runs.set(run.id, run)
  @fsx.make_directory(self.run_dir(run.id), recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(self.run_meta_file(run.id), run.to_json().stringify())
}

///|
fn workspace_result_file_for_step(
  workspace_dir : String,
  step : WorkflowStepDefinition,
) -> String {
  let config : AnalysisStepConfig = @json.from_json(step.config) catch {
    _ =>
      return workspace_dir
        |> @pathx.join("outputs")
        |> @pathx.join(workspace_result_file_name(step.id, step.id))
  }
  workspace_dir
  |> @pathx.join("outputs")
  |> @pathx.join(
    config.artifacts.result_file_name.unwrap_or(
      workspace_result_file_name(step.id, step.id),
    ),
  )
}

///|
fn workspace_report_file_for_step(
  workspace_dir : String,
  step : WorkflowStepDefinition,
) -> String {
  let config : AnalysisStepConfig = @json.from_json(step.config) catch {
    _ =>
      return workspace_dir
        |> @pathx.join("outputs")
        |> @pathx.join(workspace_report_file_name(step.id, step.id))
  }
  workspace_dir
  |> @pathx.join("outputs")
  |> @pathx.join(
    config.artifacts.report_file_name.unwrap_or(
      workspace_report_file_name(step.id, step.id),
    ),
  )
}

///|
fn json_nested_field(value : Json, key : String) -> Json? {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(value) => Some(value)
        None =>
          match object.get("metadata") {
            Some(metadata) => json_nested_field(metadata, key)
            None => None
          }
      }
    _ => None
  }
}

///|
fn json_nested_patch_receipt_contract(value : Json) -> String? {
  match json_nested_field(value, "patch_receipt") {
    Some(Object(receipt)) =>
      match receipt.get("contract") {
        Some(String(contract)) => Some(contract)
        _ => None
      }
    _ => None
  }
}

///|
fn analysis_step_requires_patch_receipt(step : WorkflowStepDefinition) -> Bool {
  let config : AnalysisStepConfig = @json.from_json(step.config) catch {
    _ => return false
  }
  match metadata_with_step_metadata(config.metadata, "patch_receipt_contract") {
    Some(String(contract)) if contract == "planbook.repair.patch_receipt.v1" =>
      true
    _ => false
  }
}

///|
fn materialized_analysis_result_satisfies_patch_receipt(payload : Json) -> Bool {
  json_nested_patch_receipt_contract(payload) ==
  Some("planbook.repair.patch_receipt.v1")
}

///|
fn reconciled_materialized_analysis_step_run(
  run : JobRun,
  step : WorkflowStepDefinition,
  existing : JobStepRun?,
  payload : Json,
  report_path : String,
  result_path : String,
) -> JobStepRun {
  let requires_receipt = analysis_step_requires_patch_receipt(step)
  let has_receipt = materialized_analysis_result_satisfies_patch_receipt(
    payload,
  )
  let status = if requires_receipt && !has_receipt {
    RunStatus::Failed
  } else {
    Succeeded
  }
  let summary = if status is Failed {
    "Recovered materialized analysis output without required patch receipt"
  } else {
    "Recovered materialized analysis output from run workspace"
  }
  let error = if status is Failed {
    Some("analysis output missing planbook.repair.patch_receipt.v1 evidence")
  } else {
    None
  }
  let logs = match existing {
    Some(existing) => existing.logs
    None => []
  }
  logs.push(
    "reconciled materialized analysis output report=\{report_path} result=\{result_path}",
  )
  match existing {
    Some(existing) =>
      {
        ..existing,
        status,
        finished_at: Some(run.started_at.unwrap_or(0)),
        logs,
        summary: Some(summary),
        output: Some(payload),
        error,
      }
    None =>
      {
        id: "\{run.id}:\{step.id}",
        run_id: run.id,
        step_id: step.id,
        status,
        started_at: run.started_at,
        finished_at: Some(run.started_at.unwrap_or(0)),
        metrics: {},
        logs,
        retry_count: 0,
        summary: Some(summary),
        output: Some(payload),
        error,
      }
  }
}

///|
async fn SystemStore::reconcile_materialized_analysis_outputs_unlocked(
  self : SystemStore,
) -> Unit {
  let runs = self.runs.values().to_array()
  for run in runs {
    match run.status {
      Pending | Running => ()
      _ => continue
    }
    let workspace_dir = match run.workspace_dir {
      Some(workspace_dir) if !workspace_dir.trim().to_owned().is_blank() =>
        workspace_dir
      _ => continue
    }
    let definition = match self.definitions.get(run.job_id) {
      Some(definition) => definition
      None => continue
    }
    let workflow_id = match definition.workflow_id {
      Some(workflow_id) => workflow_id
      None => continue
    }
    let workflow = match self.workflows.get(workflow_id) {
      Some(workflow) => workflow
      None => continue
    }
    let mut saw_materialized = false
    let mut saw_failed = false
    let mut all_steps_terminal = true
    let mut latest_finished_at = run.started_at.unwrap_or(0)
    for step in workflow.steps {
      let key = "\{run.id}:\{step.id}"
      let existing = self.steps.get(key)
      let step_run = match existing {
        Some(step_run) if run_status_is_terminal(step_run.status) =>
          Some(step_run)
        _ =>
          if step.kind == "job.analysis" {
            let result_path = workspace_result_file_for_step(
              workspace_dir, step,
            )
            if @fsx.exists(result_path) {
              let payload = @json.parse(@fsx.read_file(result_path)) catch {
                _ => {
                  all_steps_terminal = false
                  continue
                }
              }
              let report_path = workspace_report_file_for_step(
                workspace_dir, step,
              )
              let reconciled = reconciled_materialized_analysis_step_run(
                run, step, existing, payload, report_path, result_path,
              )
              self.save_reconciled_step_run_unlocked(reconciled)
              saw_materialized = true
              Some(reconciled)
            } else {
              existing
            }
          } else {
            existing
          }
      }
      match step_run {
        Some(step_run) =>
          if run_status_is_terminal(step_run.status) {
            let finished_at = step_run.finished_at.unwrap_or(
              step_run.started_at.unwrap_or(latest_finished_at),
            )
            if finished_at > latest_finished_at {
              latest_finished_at = finished_at
            }
            if step_run.status is Failed {
              saw_failed = true
            }
          } else {
            all_steps_terminal = false
          }
        None => all_steps_terminal = false
      }
    }
    if saw_materialized && all_steps_terminal {
      let status = if saw_failed { RunStatus::Failed } else { Succeeded }
      let summary = if saw_failed {
        "Recovered workflow failure from materialized analysis outputs"
      } else {
        "Recovered workflow completion from materialized analysis outputs"
      }
      let error = if saw_failed {
        Some("materialized analysis output failed receipt validation")
      } else {
        None
      }
      self.save_reconciled_run_unlocked({
        ..run,
        status,
        finished_at: Some(latest_finished_at),
        summary: Some(summary),
        error,
      })
    }
  }
}

///|
async fn SystemStore::reconcile_delegate_parent_runs_unlocked(
  self : SystemStore,
) -> Unit {
  let runs = self.runs.values().to_array()
  for run in runs {
    match run.status {
      Running => ()
      _ => continue
    }
    let definition = match self.definitions.get(run.job_id) {
      Some(definition) => definition
      None => continue
    }
    let workflow_id = match definition.workflow_id {
      Some(workflow_id) => workflow_id
      None => continue
    }
    let workflow = match self.workflows.get(workflow_id) {
      Some(workflow) => workflow
      None => continue
    }
    let mut all_terminal = true
    let mut saw_failed = false
    let mut saw_cancelled = false
    for step in workflow.steps {
      let key = "\{run.id}:\{step.id}"
      let existing = self.steps.get(key)
      let step_run = if step.kind == "job.delegate" {
        let children = self.delegate_child_runs_for_step(run.id, step.id)
        let mut latest_terminal : JobRun? = None
        for child in children {
          if run_status_is_terminal(child.status) {
            latest_terminal = Some(child)
            break
          }
        }
        match (existing, latest_terminal) {
          (Some(step_run), Some(child)) =>
            if run_status_is_terminal(step_run.status) {
              Some(step_run)
            } else {
              let reconciled = reconciled_delegate_step_run(
                run,
                step,
                Some(step_run),
                child,
              )
              self.save_reconciled_step_run_unlocked(reconciled)
              Some(reconciled)
            }
          (None, Some(child)) => {
            let reconciled = reconciled_delegate_step_run(
              run,
              step,
              None,
              child,
            )
            self.save_reconciled_step_run_unlocked(reconciled)
            Some(reconciled)
          }
          (Some(step_run), _) => Some(step_run)
          (None, _) => None
        }
      } else {
        existing
      }
      match step_run {
        Some(step_run) =>
          if !run_status_is_terminal(step_run.status) {
            all_terminal = false
          } else {
            match step_run.status {
              Failed => saw_failed = true
              Cancelled => saw_cancelled = true
              _ => ()
            }
          }
        None => all_terminal = false
      }
    }
    if !all_terminal {
      continue
    }
    let finished_at = workflow.steps.fold(init=0, fn(max_time, step) {
      let step_time = self.steps
        .get("\{run.id}:\{step.id}")
        .bind(fn(step_run) { step_run.finished_at })
        .unwrap_or(0)
      if step_time > max_time {
        step_time
      } else {
        max_time
      }
    })
    let (status, summary, error) = if saw_failed {
      (
        Failed,
        Some("Recovered workflow failure from terminal delegate child runs"),
        Some("delegate child run failed"),
      )
    } else if saw_cancelled {
      (
        Cancelled,
        Some(
          "Recovered workflow cancellation from terminal delegate child runs",
        ),
        Some("delegate child run cancelled"),
      )
    } else {
      (
        Succeeded,
        Some("Recovered workflow completion from terminal delegate child runs"),
        None,
      )
    }
    let resolved_summary = match summary {
      Some(summary) => Some(summary)
      None => run.summary
    }
    self.save_reconciled_run_unlocked({
      ..run,
      status,
      finished_at: Some(finished_at),
      summary: resolved_summary,
      error,
    })
  }
}

///|
pub async fn SystemStore::load(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    clear_map(self.definitions)
    clear_map(self.workflows)
    clear_map(self.runs)
    clear_map(self.steps)
    clear_map(self.artifacts)
    clear_map(self.memories)
    clear_map(self.chat_bindings)
    clear_map(self.notification_preferences)
    clear_map(self.proposals)
    clear_map(self.controller_states)
    clear_map(self.controller_iterations)
    clear_map(self.controller_lineage_edges)
    clear_map(self.controller_decisions)

    if @fsx.exists(self.definitions_file()) {
      let file : DefinitionsIndexFile = load_json_file(
        self.definitions_file(),
        "Failed to load job definitions",
      )
      for definition in file.definitions {
        self.definitions.set(definition.id, definition)
      }
      for workflow in file.workflows {
        self.workflows.set(workflow.id, workflow)
      }
    }

    let file = self.load_runs_index_best_effort()
    self.write_runs_index_cache_unlocked(file)
    for run in file.runs {
      self.runs.set(run.id, run)
    }
    for step in file.steps {
      self.steps.set("\{step.run_id}:\{step.step_id}", step)
    }

    if @fsx.exists(self.artifacts_index_file()) {
      let file : ArtifactsIndexFile = load_json_file(
        self.artifacts_index_file(),
        "Failed to load job artifacts index",
      )
      for artifact in file.artifacts {
        self.artifacts.set(artifact.id, artifact)
      }
    }

    if @fsx.exists(self.memories_file()) {
      let file : MemoriesFile = load_json_file(
        self.memories_file(),
        "Failed to load job memories",
      )
      for memory in file.memories {
        self.memories.set(memory.id, memory)
      }
    }

    if @fsx.exists(self.chat_bindings_file()) {
      let file : ChatBindingsFile = load_json_file(
        self.chat_bindings_file(),
        "Failed to load job chat bindings",
      )
      for binding in file.bindings {
        self.chat_bindings.set(binding.id, binding)
      }
    }

    if @fsx.exists(self.notification_preferences_file()) {
      let file : NotificationPreferencesFile = load_json_file(
        self.notification_preferences_file(),
        "Failed to load notification preferences",
      )
      for preference in file.preferences {
        self.notification_preferences.set(preference.id, preference)
      }
    }

    if @fsx.exists(self.job_proposals_file()) {
      let file : JobProposalsFile = load_json_file(
        self.job_proposals_file(),
        "Failed to load job proposals",
      )
      for proposal in file.proposals {
        self.proposals.set(proposal.id, proposal)
      }
    }

    if @fsx.exists(self.controller_states_file()) {
      let file : ControllerStateFile = load_json_file(
        self.controller_states_file(),
        "Failed to load controller states",
      )
      for state in file.states {
        self.controller_states.set(state.controller_run_id, state)
      }
    }

    if @fsx.exists(self.controller_iterations_file()) {
      let file : ControllerIterationsFile = load_json_file(
        self.controller_iterations_file(),
        "Failed to load controller iterations",
      )
      for iteration in file.iterations {
        self.controller_iterations.set(iteration.id, iteration)
      }
    }

    if @fsx.exists(self.controller_lineage_file()) {
      let file : ControllerLineageFile = load_json_file(
        self.controller_lineage_file(),
        "Failed to load controller lineage",
      )
      for edge in file.edges {
        self.controller_lineage_edges.set(edge.id, edge)
      }
    }

    if @fsx.exists(self.controller_decisions_file()) {
      let file : ControllerDecisionsFile = load_json_file(
        self.controller_decisions_file(),
        "Failed to load controller decisions",
      )
      for decision in file.decisions {
        self.controller_decisions.set(decision.id, decision)
      }
    }
    self.reconcile_delegate_parent_runs_unlocked()
    self.reconcile_materialized_analysis_outputs_unlocked()
    self.save_runs_index_unlocked()
  })
}

///|
async fn SystemStore::save_definitions_index_unlocked(
  self : SystemStore,
) -> Unit {
  let file = DefinitionsIndexFile::{
    definitions: self.definitions.values().to_array(),
    workflows: self.workflows.values().to_array(),
  }
  @fsx.write_to_file(self.definitions_file(), file.to_json().stringify())
}

///|
async fn SystemStore::save_definitions_index(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() { self.save_definitions_index_unlocked() })
}

///|
async fn SystemStore::save_runs_index_unlocked(self : SystemStore) -> Unit {
  let merged_runs : Map[String, JobRun] = {}
  let merged_steps : Map[String, JobStepRun] = {}
  let existing = self.runs_index_from_disk()
  for run in existing.runs {
    merged_runs.set(run.id, run)
  }
  for step in existing.steps {
    merged_steps.set("\{step.run_id}:\{step.step_id}", step)
  }
  for run in self.runs.values() {
    merged_runs.set(run.id, run)
  }
  for step in self.steps.values() {
    merged_steps.set("\{step.run_id}:\{step.step_id}", step)
  }
  let file = RunsIndexFile::{
    runs: merged_runs.values().to_array(),
    steps: merged_steps.values().to_array(),
  }
  self.write_runs_index_cache_unlocked(file)
}

///|
async fn SystemStore::save_artifacts_index_unlocked(self : SystemStore) -> Unit {
  let file = ArtifactsIndexFile::{
    artifacts: self.artifacts.values().to_array(),
  }
  @fsx.write_to_file(self.artifacts_index_file(), file.to_json().stringify())
}

///|
async fn SystemStore::save_artifacts_index(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() { self.save_artifacts_index_unlocked() })
}

///|
async fn SystemStore::save_memories(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = MemoriesFile::{ memories: self.memories.values().to_array() }
    @fsx.write_to_file(self.memories_file(), file.to_json().stringify())
  })
}

///|
async fn SystemStore::save_chat_bindings(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = ChatBindingsFile::{
      bindings: self.chat_bindings.values().to_array(),
    }
    @fsx.write_to_file(self.chat_bindings_file(), file.to_json().stringify())
  })
}

///|
async fn SystemStore::save_notification_preferences(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = NotificationPreferencesFile::{
      preferences: self.notification_preferences.values().to_array(),
    }
    @fsx.write_to_file(
      self.notification_preferences_file(),
      file.to_json().stringify(),
    )
  })
}

///|
async fn SystemStore::save_job_proposals(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = JobProposalsFile::{
      proposals: self.proposals.values().to_array(),
    }
    @fsx.write_to_file(self.job_proposals_file(), file.to_json().stringify())
  })
}

///|
async fn SystemStore::save_controller_states(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = ControllerStateFile::{
      states: self.controller_states.values().to_array(),
    }
    @fsx.write_to_file(
      self.controller_states_file(),
      file.to_json().stringify(),
    )
  })
}

///|
async fn SystemStore::save_controller_iterations(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = ControllerIterationsFile::{
      iterations: self.controller_iterations.values().to_array(),
    }
    @fsx.write_to_file(
      self.controller_iterations_file(),
      file.to_json().stringify(),
    )
  })
}

///|
async fn SystemStore::save_controller_lineage(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = ControllerLineageFile::{
      edges: self.controller_lineage_edges.values().to_array(),
    }
    @fsx.write_to_file(
      self.controller_lineage_file(),
      file.to_json().stringify(),
    )
  })
}

///|
async fn SystemStore::save_controller_decisions(self : SystemStore) -> Unit {
  self.with_store_lock(async fn() {
    let file = ControllerDecisionsFile::{
      decisions: self.controller_decisions.values().to_array(),
    }
    @fsx.write_to_file(
      self.controller_decisions_file(),
      file.to_json().stringify(),
    )
  })
}

///|
pub async fn SystemStore::save_definition(
  self : SystemStore,
  definition : JobDefinition,
) -> Unit {
  self.definitions.set(definition.id, definition)
  self.save_definitions_index()
}

///|
pub async fn SystemStore::save_workflow(
  self : SystemStore,
  workflow : WorkflowDefinition,
) -> Unit {
  self.workflows.set(workflow.id, workflow)
  self.save_definitions_index()
}

///|
pub async fn SystemStore::save_run(self : SystemStore, run : JobRun) -> Unit {
  self.runs.set(run.id, run)
  self.with_store_lock(async fn() {
    @fsx.make_directory(self.run_dir(run.id), recursive=true) catch {
      _ => ()
    }
    @fsx.make_directory(self.step_dir(run.id), recursive=true) catch {
      _ => ()
    }
    @fsx.write_to_file(self.run_meta_file(run.id), run.to_json().stringify())
    self.save_runs_index_unlocked()
  })
}

///|
pub async fn SystemStore::save_step_run(
  self : SystemStore,
  step : JobStepRun,
) -> Unit {
  self.steps.set("\{step.run_id}:\{step.step_id}", step)
  self.with_store_lock(async fn() {
    @fsx.make_directory(self.step_dir(step.run_id), recursive=true) catch {
      _ => ()
    }
    @fsx.write_to_file(
      self.step_meta_file(step.run_id, step.step_id),
      step.to_json().stringify(),
    )
    self.save_runs_index_unlocked()
  })
}

///|
pub async fn SystemStore::save_artifact(
  self : SystemStore,
  artifact : ArtifactRecord,
) -> Unit {
  self.artifacts.set(artifact.id, artifact)
  self.with_store_lock(async fn() {
    let artifact_dir = self.artifact_dir(artifact.id)
    @fsx.make_directory(artifact_dir, recursive=true) catch {
      _ => ()
    }
    @fsx.write_to_file(
      self.artifact_record_file(artifact.id),
      artifact.to_json().stringify(),
    )
    self.save_artifacts_index_unlocked()
  })
}

///|
pub async fn SystemStore::save_memory(
  self : SystemStore,
  memory : MemoryRecord,
) -> Unit {
  self.memories.set(memory.id, memory)
  self.save_memories()
}

///|
pub async fn SystemStore::save_chat_binding(
  self : SystemStore,
  binding : ChatBinding,
) -> Unit {
  self.chat_bindings.set(binding.id, binding)
  self.save_chat_bindings()
}

///|
pub async fn SystemStore::save_notification_preference(
  self : SystemStore,
  preference : JobNotificationPreference,
) -> Unit {
  self.notification_preferences.set(preference.id, preference)
  self.save_notification_preferences()
}

///|
pub async fn SystemStore::save_job_proposal(
  self : SystemStore,
  proposal : JobProposal,
) -> Unit {
  self.proposals.set(proposal.id, proposal)
  self.save_job_proposals()
}

///|
pub async fn SystemStore::save_controller_state(
  self : SystemStore,
  state : JobControllerState,
) -> Unit {
  self.controller_states.set(state.controller_run_id, state)
  self.save_controller_states()
}

///|
pub async fn SystemStore::save_controller_iteration(
  self : SystemStore,
  iteration : JobControllerIteration,
) -> Unit {
  self.controller_iterations.set(iteration.id, iteration)
  self.save_controller_iterations()
}

///|
pub async fn SystemStore::save_controller_lineage_edge(
  self : SystemStore,
  edge : JobControllerLineageEdge,
) -> Unit {
  self.controller_lineage_edges.set(edge.id, edge)
  self.save_controller_lineage()
}

///|
pub async fn SystemStore::save_controller_decision(
  self : SystemStore,
  decision : JobControllerDecision,
) -> Unit {
  self.controller_decisions.set(decision.id, decision)
  self.save_controller_decisions()
}

///|
pub async fn SystemStore::delete_artifact(
  self : SystemStore,
  artifact_id : String,
) -> Bool {
  let artifact = match self.artifacts.get(artifact_id) {
    Some(artifact) => artifact
    None => return false
  }
  self.artifacts.remove(artifact_id) |> ignore()
  if @fsx.exists(self.artifact_record_file(artifact_id)) {
    @fsx.remove(self.artifact_record_file(artifact_id))
  }
  if @fsx.exists(artifact.path) {
    @fsx.remove(artifact.path)
  }
  if @fsx.exists(self.artifact_dir(artifact_id)) {
    @fsx.remove(self.artifact_dir(artifact_id)) catch {
      _ => ()
    }
  }
  self.save_artifacts_index()
  true
}

///|
pub fn SystemStore::get_definition(
  self : SystemStore,
  id : String,
) -> JobDefinition? {
  self.definitions.get(id)
}

///|
pub fn SystemStore::get_workflow(
  self : SystemStore,
  id : String,
) -> WorkflowDefinition? {
  self.workflows.get(id)
}

///|
pub fn SystemStore::get_run(self : SystemStore, id : String) -> JobRun? {
  self.runs.get(id)
}

///|
pub fn SystemStore::get_step_run(
  self : SystemStore,
  run_id : String,
  step_id : String,
) -> JobStepRun? {
  self.steps.get("\{run_id}:\{step_id}")
}

///|
pub fn SystemStore::get_artifact(
  self : SystemStore,
  id : String,
) -> ArtifactRecord? {
  self.artifacts.get(id)
}

///|
pub fn SystemStore::get_memory(
  self : SystemStore,
  id : String,
) -> MemoryRecord? {
  self.memories.get(id)
}

///|
pub fn SystemStore::get_chat_binding(
  self : SystemStore,
  id : String,
) -> ChatBinding? {
  self.chat_bindings.get(id)
}

///|
pub fn SystemStore::get_notification_preference(
  self : SystemStore,
  id : String,
) -> JobNotificationPreference? {
  self.notification_preferences.get(id)
}

///|
pub fn SystemStore::get_job_proposal(
  self : SystemStore,
  id : String,
) -> JobProposal? {
  self.proposals.get(id)
}

///|
pub fn SystemStore::get_controller_state(
  self : SystemStore,
  controller_run_id : String,
) -> JobControllerState? {
  self.controller_states.get(controller_run_id)
}

///|
pub fn SystemStore::get_controller_iteration(
  self : SystemStore,
  id : String,
) -> JobControllerIteration? {
  self.controller_iterations.get(id)
}

///|
pub fn SystemStore::get_controller_decision(
  self : SystemStore,
  id : String,
) -> JobControllerDecision? {
  self.controller_decisions.get(id)
}

///|
pub fn SystemStore::find_job_proposal_by_message_id(
  self : SystemStore,
  message_id : String,
) -> JobProposal? {
  for proposal in self.proposals.values() {
    if proposal.presented_message_id == Some(message_id) {
      return Some(proposal)
    }
  }
  None
}

///|
pub fn SystemStore::list_definitions(
  self : SystemStore,
) -> Array[JobDefinition] {
  self.definitions.values().to_array()
}

///|
pub fn SystemStore::list_workflows(
  self : SystemStore,
) -> Array[WorkflowDefinition] {
  self.workflows.values().to_array()
}

///|
pub fn SystemStore::list_runs(self : SystemStore) -> Array[JobRun] {
  self.runs.values().to_array()
}

///|
pub fn SystemStore::list_step_runs(
  self : SystemStore,
  run_id : String,
) -> Array[JobStepRun] {
  self.steps.values().filter(fn(step) { step.run_id == run_id }).to_array()
}

///|
pub fn SystemStore::list_artifacts(
  self : SystemStore,
  run_id? : String,
) -> Array[ArtifactRecord] {
  match run_id {
    Some(run_id) =>
      self.artifacts
      .values()
      .filter(fn(artifact) { artifact.run_id == run_id })
      .to_array()
    None => self.artifacts.values().to_array()
  }
}

///|
pub fn SystemStore::list_memories(self : SystemStore) -> Array[MemoryRecord] {
  self.memories.values().to_array()
}

///|
pub fn SystemStore::list_chat_bindings(
  self : SystemStore,
) -> Array[ChatBinding] {
  self.chat_bindings.values().to_array()
}

///|
pub fn SystemStore::list_notification_preferences(
  self : SystemStore,
) -> Array[JobNotificationPreference] {
  self.notification_preferences.values().to_array()
}

///|
pub fn SystemStore::list_job_proposals(
  self : SystemStore,
) -> Array[JobProposal] {
  self.proposals.values().to_array()
}

///|
pub fn SystemStore::list_controller_states(
  self : SystemStore,
) -> Array[JobControllerState] {
  self.controller_states.values().to_array()
}

///|
pub fn SystemStore::list_controller_iterations(
  self : SystemStore,
  controller_run_id? : String? = None,
) -> Array[JobControllerIteration] {
  match controller_run_id {
    Some(controller_run_id) =>
      self.controller_iterations
      .values()
      .filter(fn(iteration) { iteration.controller_run_id == controller_run_id })
      .to_array()
    None => self.controller_iterations.values().to_array()
  }
}

///|
pub fn SystemStore::list_controller_lineage_edges(
  self : SystemStore,
  controller_job_id? : String? = None,
) -> Array[JobControllerLineageEdge] {
  match controller_job_id {
    Some(controller_job_id) =>
      self.controller_lineage_edges
      .values()
      .filter(fn(edge) { edge.controller_job_id == controller_job_id })
      .to_array()
    None => self.controller_lineage_edges.values().to_array()
  }
}

///|
pub fn SystemStore::list_controller_decisions(
  self : SystemStore,
  controller_run_id? : String? = None,
) -> Array[JobControllerDecision] {
  match controller_run_id {
    Some(controller_run_id) =>
      self.controller_decisions
      .values()
      .filter(fn(decision) { decision.controller_run_id == controller_run_id })
      .to_array()
    None => self.controller_decisions.values().to_array()
  }
}

///|
pub async fn SystemStore::append_run_event(
  self : SystemStore,
  event : JobRunEvent,
) -> Unit {
  self.ensure_directories()
  @fsx.make_directory(self.run_dir(event.run_id), recursive=true) catch {
    _ => ()
  }
  let path = self.run_events_file(event.run_id)
  let existing = if @fsx.exists(path) { @fsx.read_file(path) } else { "" }
  let line = event.to_json().stringify()
  let content = if existing.is_blank() { line } else { "\{existing}\n\{line}" }
  @fsx.write_to_file(path, content)
}

///|
pub async fn SystemStore::list_run_events(
  self : SystemStore,
  run_id : String,
) -> Array[JobRunEvent] {
  let path = self.run_events_file(run_id)
  guard @fsx.exists(path) else { return [] }
  let events : Array[JobRunEvent] = []
  for raw_line in @fsx.read_file(path).split("\n") {
    let line = raw_line.to_owned().trim().to_owned()
    if line.is_blank() {
      continue
    }
    let event : JobRunEvent = @json.from_json(@json.parse(line)) catch {
      error => fail("Failed to parse run event from \{path}: \{error}")
    }
    events.push(event)
  }
  events
}
