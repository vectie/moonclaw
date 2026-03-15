///|
pub struct Coordinator {
  uuid : @uuid.Generator
  tasks : Map[String, CoordinationTask]
  max_concurrent : Int
}

///|
pub fn coordinator(
  uuid~ : @uuid.Generator,
  max_concurrent? : Int = 10,
) -> Coordinator {
  Coordinator::{ uuid, tasks: Map::new(), max_concurrent }
}

///|
pub fn Coordinator::create(
  self : Coordinator,
  parent_agent~ : String,
  subtasks~ : Array[SubTask],
  metadata? : Map[String, Json] = Map::new(),
) -> CoordinationTask {
  let coordination_id = self.uuid.v4().to_string()
  let task = coordination_task(
    coordination_id~,
    parent_agent~,
    subtasks~,
    metadata~,
  )
  self.tasks.set(coordination_id, task)
  task
}

///|
pub fn Coordinator::get(
  self : Coordinator,
  coordination_id : String,
) -> CoordinationTask? {
  self.tasks.get(coordination_id)
}

///|
pub fn Coordinator::remove(
  self : Coordinator,
  coordination_id : String,
) -> CoordinationTask? {
  let task = self.tasks.get(coordination_id)
  match task {
    Some(_) => {
      self.tasks.remove(coordination_id)
      task
    }
    None => None
  }
}

///|
pub fn Coordinator::list(self : Coordinator) -> Array[CoordinationTask] {
  self.tasks.values().to_array()
}

///|
pub fn Coordinator::list_by_status(
  self : Coordinator,
  status : CoordinationStatus,
) -> Array[CoordinationTask] {
  self.tasks.values().filter(fn(t) { t.status == status }).to_array()
}

///|
pub fn Coordinator::list_by_parent(
  self : Coordinator,
  parent_agent : String,
) -> Array[CoordinationTask] {
  self.tasks
  .values()
  .filter(fn(t) { t.parent_agent == parent_agent })
  .to_array()
}

///|
pub fn Coordinator::start_task(
  self : Coordinator,
  coordination_id : String,
) -> CoordinationTask? {
  let task = self.tasks.get(coordination_id)
  match task {
    Some(t) => {
      let started = t.start()
      self.tasks.set(coordination_id, started)
      Some(started)
    }
    None => None
  }
}

///|
pub fn Coordinator::update_subtask_status(
  self : Coordinator,
  coordination_id : String,
  task_id : String,
  status : CoordinationStatus,
  result? : Json? = None,
  error? : String? = None,
) -> CoordinationTask? {
  let task = self.tasks.get(coordination_id)
  match task {
    Some(t) => {
      let updated = t.update_subtask(task_id, status, result~, error~)
      let final_task = if updated.all_subtasks_done() {
        if updated.has_failures() {
          updated.fail()
        } else {
          updated.complete()
        }
      } else {
        updated
      }
      self.tasks.set(coordination_id, final_task)
      Some(final_task)
    }
    None => None
  }
}

///|
pub fn Coordinator::cancel_task(
  self : Coordinator,
  coordination_id : String,
) -> CoordinationTask? {
  let task = self.tasks.get(coordination_id)
  match task {
    Some(t) => {
      let cancelled = t.cancel()
      self.tasks.set(coordination_id, cancelled)
      Some(cancelled)
    }
    None => None
  }
}

///|
pub fn Coordinator::size(self : Coordinator) -> Int {
  self.tasks.length()
}

///|
pub fn Coordinator::active_count(self : Coordinator) -> Int {
  self.tasks.values().filter(fn(t) { t.status is Running }).count()
}

///|
pub fn Coordinator::can_accept_more(self : Coordinator) -> Bool {
  self.active_count() < self.max_concurrent
}

///|
pub fn Coordinator::get_pending_subtasks(
  self : Coordinator,
  coordination_id : String,
) -> Array[SubTask] {
  match self.tasks.get(coordination_id) {
    Some(task) =>
      task.subtasks.iter().filter(fn(t) { t.status is Pending }).to_array()
    None => []
  }
}

///|
pub fn Coordinator::to_json(self : Coordinator) -> Json {
  {
    "active_count": self.active_count().to_json(),
    "max_concurrent": self.max_concurrent.to_json(),
    "total_tasks": self.size().to_json(),
    "can_accept_more": self.can_accept_more().to_json(),
  }
}
