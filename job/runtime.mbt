///|
pub(all) struct CheckpointRecord {
  job_id : String
  last_triggered_at : Int?
  last_started_at : Int?
  last_completed_at : Int?
  last_success_at : Int?
  last_run_id : String?
} derive(ToJson, FromJson, Show)

///|
pub struct CheckpointStore {
  root : String
  checkpoints : Map[String, CheckpointRecord]
}

///|
pub fn CheckpointStore::new(root~ : String) -> CheckpointStore {
  CheckpointStore::{ root, checkpoints: {} }
}

///|
fn CheckpointStore::checkpoint_file(
  self : CheckpointStore,
  job_id : String,
) -> String {
  self.root |> @pathx.join("\{job_id}.json")
}

///|
pub async fn CheckpointStore::load(self : CheckpointStore) -> Unit {
  clear_map(self.checkpoints)
  if !@fsx.exists(self.root) {
    return
  }
  let entries = @fsx.list_directory(self.root)
  for entry in entries {
    if !(entry.kind is @fsx.FileKind::Regular) ||
      !entry.name.has_suffix(".json") {
      continue
    }
    let content = @fsx.read_file(entry.path)
    let checkpoint : CheckpointRecord = @json.from_json(@json.parse(content)) catch {
      error =>
        fail("Failed to load job checkpoint from \{entry.path}: \{error}")
    }
    self.checkpoints.set(checkpoint.job_id, checkpoint)
  }
}

///|
pub async fn CheckpointStore::save(self : CheckpointStore) -> Unit {
  @fsx.make_directory(self.root, recursive=true, exists_ok=true) catch {
    _ => ()
  }
  for checkpoint in self.checkpoints.values() {
    @fsx.write_to_file(
      self.checkpoint_file(checkpoint.job_id),
      checkpoint.to_json().stringify(),
    )
  }
}

///|
pub async fn CheckpointStore::save_checkpoint(
  self : CheckpointStore,
  checkpoint : CheckpointRecord,
) -> Unit {
  self.checkpoints.set(checkpoint.job_id, checkpoint)
  @fsx.make_directory(self.root, recursive=true, exists_ok=true) catch {
    _ => ()
  }
  @fsx.write_to_file(
    self.checkpoint_file(checkpoint.job_id),
    checkpoint.to_json().stringify(),
  )
}

///|
pub fn CheckpointStore::get(
  self : CheckpointStore,
  job_id : String,
) -> CheckpointRecord? {
  self.checkpoints.get(job_id)
}

///|
pub fn CheckpointStore::list(self : CheckpointStore) -> Array[CheckpointRecord] {
  self.checkpoints.values().to_array()
}

///|
pub struct RuntimeManager {
  store : SystemStore
  checkpoints : CheckpointStore
  active_runs : Map[String, String]
}

///|
pub fn RuntimeManager::new(root~ : String) -> RuntimeManager {
  RuntimeManager::{
    store: SystemStore::new(root~),
    checkpoints: CheckpointStore::new(root=root |> @pathx.join("checkpoints")),
    active_runs: {},
  }
}

///|
pub async fn RuntimeManager::load(self : RuntimeManager) -> Unit {
  self.store.load()
  self.checkpoints.load()
  clear_map(self.active_runs)
  for run in self.store.list_runs() {
    if run.status is Running {
      self.active_runs.set(run.job_id, run.id)
    }
  }
}

///|
pub fn RuntimeManager::store(self : RuntimeManager) -> SystemStore {
  self.store
}

///|
pub fn RuntimeManager::checkpoints(self : RuntimeManager) -> CheckpointStore {
  self.checkpoints
}

///|
pub fn RuntimeManager::is_job_active(
  self : RuntimeManager,
  job_id : String,
) -> Bool {
  self.active_runs.get(job_id) is Some(_)
}

///|
pub fn RuntimeManager::active_run_id(
  self : RuntimeManager,
  job_id : String,
) -> String? {
  self.active_runs.get(job_id)
}

///|
pub async fn RuntimeManager::register_definition(
  self : RuntimeManager,
  definition : JobDefinition,
) -> Unit {
  self.store.save_definition(definition)
}

///|
pub async fn RuntimeManager::register_workflow(
  self : RuntimeManager,
  workflow : WorkflowDefinition,
) -> Unit {
  self.store.save_workflow(workflow)
}

///|
pub async fn RuntimeManager::create_run(
  self : RuntimeManager,
  run_id : String,
  job_id : String,
  trigger : TriggerSource,
  now_ms : Int,
) -> Result[JobRun, String] {
  if self.is_job_active(job_id) {
    return Err("Job \{job_id} already has an active run")
  }
  guard self.store.get_definition(job_id) is Some(_) else {
    return Err("Unknown job definition: \{job_id}")
  }
  let run = JobRun::{
    id: run_id,
    job_id,
    trigger,
    status: Pending,
    started_at: None,
    completed_at: None,
    summary: None,
    error: None,
  }
  self.store.save_run(run)
  let checkpoint = match self.checkpoints.get(job_id) {
    Some(existing) =>
      CheckpointRecord::{
        ..existing,
        last_triggered_at: Some(now_ms),
        last_run_id: Some(run_id),
      }
    None =>
      CheckpointRecord::{
        job_id,
        last_triggered_at: Some(now_ms),
        last_started_at: None,
        last_completed_at: None,
        last_success_at: None,
        last_run_id: Some(run_id),
      }
  }
  self.checkpoints.save_checkpoint(checkpoint)
  Ok(run)
}

///|
pub async fn RuntimeManager::mark_run_started(
  self : RuntimeManager,
  run_id : String,
  now_ms : Int,
) -> JobRun? {
  let run = match self.store.get_run(run_id) {
    Some(run) => run
    None => return None
  }
  let updated = JobRun::{ ..run, status: Running, started_at: Some(now_ms) }
  self.store.save_run(updated)
  self.active_runs.set(updated.job_id, updated.id)
  let checkpoint = match self.checkpoints.get(updated.job_id) {
    Some(existing) =>
      CheckpointRecord::{
        ..existing,
        last_started_at: Some(now_ms),
        last_run_id: Some(updated.id),
      }
    None =>
      CheckpointRecord::{
        job_id: updated.job_id,
        last_triggered_at: Some(now_ms),
        last_started_at: Some(now_ms),
        last_completed_at: None,
        last_success_at: None,
        last_run_id: Some(updated.id),
      }
  }
  self.checkpoints.save_checkpoint(checkpoint)
  Some(updated)
}

///|
async fn RuntimeManager::finish_run_with_status(
  self : RuntimeManager,
  run_id : String,
  status : RunStatus,
  now_ms : Int,
  summary : String?,
  error : String?,
) -> JobRun? {
  let run = match self.store.get_run(run_id) {
    Some(run) => run
    None => return None
  }
  let updated = JobRun::{
    ..run,
    status,
    completed_at: Some(now_ms),
    summary: match summary {
      Some(summary) => Some(summary)
      None => run.summary
    },
    error: match error {
      Some(error) => Some(error)
      None => run.error
    },
  }
  self.store.save_run(updated)
  self.active_runs.remove(updated.job_id) |> ignore()
  let checkpoint = match self.checkpoints.get(updated.job_id) {
    Some(existing) =>
      CheckpointRecord::{
        ..existing,
        last_completed_at: Some(now_ms),
        last_success_at: match status {
          Succeeded => Some(now_ms)
          _ => existing.last_success_at
        },
        last_run_id: Some(updated.id),
      }
    None =>
      CheckpointRecord::{
        job_id: updated.job_id,
        last_triggered_at: updated.started_at,
        last_started_at: updated.started_at,
        last_completed_at: Some(now_ms),
        last_success_at: match status {
          Succeeded => Some(now_ms)
          _ => None
        },
        last_run_id: Some(updated.id),
      }
  }
  self.checkpoints.save_checkpoint(checkpoint)
  Some(updated)
}

///|
pub async fn RuntimeManager::mark_run_succeeded(
  self : RuntimeManager,
  run_id : String,
  now_ms : Int,
  summary? : String?,
) -> JobRun? {
  self.finish_run_with_status(
    run_id,
    RunStatus::Succeeded,
    now_ms,
    summary.unwrap_or(None),
    None,
  )
}

///|
pub async fn RuntimeManager::mark_run_failed(
  self : RuntimeManager,
  run_id : String,
  now_ms : Int,
  error : String,
  summary? : String?,
) -> JobRun? {
  self.finish_run_with_status(
    run_id,
    RunStatus::Failed,
    now_ms,
    summary.unwrap_or(None),
    Some(error),
  )
}

///|
pub async fn RuntimeManager::cancel_run(
  self : RuntimeManager,
  run_id : String,
  now_ms : Int,
  summary? : String?,
) -> JobRun? {
  self.finish_run_with_status(
    run_id,
    RunStatus::Cancelled,
    now_ms,
    summary.unwrap_or(None),
    None,
  )
}

///|
pub async fn RuntimeManager::trigger_definition(
  self : RuntimeManager,
  run_id : String,
  job_id : String,
  trigger : TriggerSource,
  now_ms : Int,
) -> Result[JobRun, String] {
  self.create_run(run_id, job_id, trigger, now_ms)
}

///|
pub async fn RuntimeManager::trigger_due_definitions(
  self : RuntimeManager,
  now_ms : Int,
  next_run_id : () -> String,
) -> Array[JobRun] {
  let created : Array[JobRun] = []
  for definition in self.due_definitions(now_ms) {
    match
      self.create_run(
        next_run_id(),
        definition.id,
        TriggerSource::Scheduled,
        now_ms,
      ) {
      Ok(run) => created.push(run)
      Err(_) => ()
    }
  }
  created
}

///|
pub fn RuntimeManager::list_active_runs(self : RuntimeManager) -> Array[JobRun] {
  let active : Array[JobRun] = []
  for run_id in self.active_runs.values() {
    match self.store.get_run(run_id) {
      Some(run) => active.push(run)
      None => ()
    }
  }
  active.sort_by(fn(left, right) { left.id.compare(right.id) })
  active
}

///|
pub fn RuntimeManager::list_recent_runs(
  self : RuntimeManager,
  limit? : Int = 20,
) -> Array[JobRun] {
  let runs = self.store.list_runs()
  runs.sort_by(fn(left, right) {
    let left_ts = left.completed_at.unwrap_or(left.started_at.unwrap_or(0))
    let right_ts = right.completed_at.unwrap_or(right.started_at.unwrap_or(0))
    right_ts.compare(left_ts)
  })
  if limit >= runs.length() {
    runs
  } else {
    runs[:limit].to_array()
  }
}

///|
pub fn RuntimeManager::due_definitions(
  self : RuntimeManager,
  now_ms : Int,
) -> Array[JobDefinition] {
  let due : Array[JobDefinition] = []
  for definition in self.store.list_definitions() {
    if !definition.enabled {
      continue
    }
    if self.is_job_active(definition.id) {
      continue
    }
    let schedule = match definition.schedule {
      Some(schedule) => schedule
      None => continue
    }
    let interval_minutes = match schedule.interval_minutes {
      Some(interval_minutes) if interval_minutes > 0 => interval_minutes
      _ => continue
    }
    let interval_ms = interval_minutes * 60 * 1000
    let checkpoint = self.checkpoints.get(definition.id)
    let last_mark = match checkpoint {
      Some(checkpoint) =>
        checkpoint.last_triggered_at.unwrap_or(
          checkpoint.last_started_at.unwrap_or(0),
        )
      None => 0
    }
    if last_mark == 0 || now_ms - last_mark >= interval_ms {
      due.push(definition)
    }
  }
  due
}
