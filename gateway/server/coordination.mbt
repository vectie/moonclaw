///|
pub enum CoordinationStatus {
  Pending
  Running
  Completed
  Failed
  Cancelled
} derive(ToJson, FromJson, Eq, Show)

///|
pub struct SubTask {
  task_id : String
  message : String
  model : String?
  cwd : String?
  status : CoordinationStatus
  result : Json?
  error : String?
  created_at : Int
  started_at : Int?
  completed_at : Int?
} derive(ToJson, FromJson, Show)

///|
pub fn sub_task(
  task_id~ : String,
  message~ : String,
  model? : String,
  cwd? : String,
) -> SubTask {
  SubTask::{
    task_id,
    message,
    model,
    cwd,
    status: Pending,
    result: None,
    error: None,
    created_at: current_time_ms(),
    started_at: None,
    completed_at: None,
  }
}

///|
pub fn SubTask::start(self : SubTask) -> SubTask {
  { ..self, status: Running, started_at: Some(current_time_ms()) }
}

///|
pub fn SubTask::complete(self : SubTask, result : Json) -> SubTask {
  {
    ..self,
    status: Completed,
    result: Some(result),
    completed_at: Some(current_time_ms()),
  }
}

///|
pub fn SubTask::fail(self : SubTask, error : String) -> SubTask {
  {
    ..self,
    status: Failed,
    error: Some(error),
    completed_at: Some(current_time_ms()),
  }
}

///|
pub fn SubTask::is_done(self : SubTask) -> Bool {
  match self.status {
    Completed => true
    Failed => true
    Cancelled => true
    _ => false
  }
}

///|
pub struct CoordinationTask {
  coordination_id : String
  parent_agent : String
  subtasks : Array[SubTask]
  status : CoordinationStatus
  results : Map[String, Json]
  created_at : Int
  started_at : Int?
  completed_at : Int?
  metadata : Map[String, Json]
} derive(ToJson, FromJson, Show)

///|
pub fn coordination_task(
  coordination_id~ : String,
  parent_agent~ : String,
  subtasks~ : Array[SubTask],
  metadata? : Map[String, Json] = Map::new(),
) -> CoordinationTask {
  CoordinationTask::{
    coordination_id,
    parent_agent,
    subtasks,
    status: Pending,
    results: Map::new(),
    created_at: current_time_ms(),
    started_at: None,
    completed_at: None,
    metadata,
  }
}

///|
pub fn CoordinationTask::start(self : CoordinationTask) -> CoordinationTask {
  { ..self, status: Running, started_at: Some(current_time_ms()) }
}

///|
pub fn CoordinationTask::complete(self : CoordinationTask) -> CoordinationTask {
  { ..self, status: Completed, completed_at: Some(current_time_ms()) }
}

///|
pub fn CoordinationTask::fail(self : CoordinationTask) -> CoordinationTask {
  { ..self, status: Failed, completed_at: Some(current_time_ms()) }
}

///|
pub fn CoordinationTask::cancel(self : CoordinationTask) -> CoordinationTask {
  { ..self, status: Cancelled, completed_at: Some(current_time_ms()) }
}

///|
pub fn CoordinationTask::is_done(self : CoordinationTask) -> Bool {
  match self.status {
    Completed => true
    Failed => true
    Cancelled => true
    _ => false
  }
}

///|
pub fn CoordinationTask::pending_count(self : CoordinationTask) -> Int {
  self.subtasks.iter().filter(fn(t) { t.status is Pending }).count()
}

///|
pub fn CoordinationTask::completed_count(self : CoordinationTask) -> Int {
  self.subtasks.iter().filter(fn(t) { t.status is Completed }).count()
}

///|
pub fn CoordinationTask::failed_count(self : CoordinationTask) -> Int {
  self.subtasks.iter().filter(fn(t) { t.status is Failed }).count()
}

///|
pub fn CoordinationTask::has_subtask(
  self : CoordinationTask,
  task_id : String,
) -> Bool {
  self.subtasks.iter().any(fn(t) { t.task_id == task_id })
}

///|
pub fn CoordinationTask::update_subtask(
  self : CoordinationTask,
  task_id : String,
  status : CoordinationStatus,
  result? : Json? = None,
  error? : String? = None,
) -> CoordinationTask {
  let new_subtasks = self.subtasks.map(fn(t) {
    if t.task_id == task_id {
      let updated = match status {
        Running => t.start()
        Completed =>
          match result {
            Some(r) => t.complete(r)
            None => t
          }
        Failed =>
          match error {
            Some(e) => t.fail(e)
            None => t
          }
        Cancelled =>
          { ..t, status: Cancelled, completed_at: Some(current_time_ms()) }
        Pending => t
      }
      updated
    } else {
      t
    }
  })
  let new_results = match result {
    Some(r) => {
      let new_map = self.results
      new_map.set(task_id, r)
      new_map
    }
    None => self.results
  }
  { ..self, subtasks: new_subtasks, results: new_results }
}

///|
pub fn CoordinationTask::all_subtasks_done(self : CoordinationTask) -> Bool {
  self.subtasks.iter().all(fn(t) { t.is_done() })
}

///|
pub fn CoordinationTask::has_failures(self : CoordinationTask) -> Bool {
  self.subtasks.iter().any(fn(t) { t.status is Failed })
}

///|
pub fn CoordinationTask::aggregate_results(self : CoordinationTask) -> Json {
  {
    "coordination_id": self.coordination_id.to_json(),
    "status": self.status.to_json(),
    "total_subtasks": self.subtasks.length().to_json(),
    "completed": self.completed_count().to_json(),
    "failed": self.failed_count().to_json(),
    "results": self.results.to_json(),
  }
}
