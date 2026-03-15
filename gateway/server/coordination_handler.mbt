///|
pub struct CreateCoordinationParams {
  parent_agent : String
  subtasks : Array[SubTaskParams]
  metadata : Map[String, Json]
} derive(FromJson, ToJson)

///|
pub fn create_coordination_params(
  parent_agent~ : String,
  subtasks~ : Array[SubTaskParams],
  metadata? : Map[String, Json] = Map::new(),
) -> CreateCoordinationParams {
  CreateCoordinationParams::{ parent_agent, subtasks, metadata }
}

///|
pub struct SubTaskParams {
  task_id : String
  message : String
  model : String?
  cwd : String?
} derive(FromJson, ToJson)

///|
pub fn sub_task_params(
  task_id~ : String,
  message~ : String,
  model? : String,
  cwd? : String,
) -> SubTaskParams {
  SubTaskParams::{ task_id, message, model, cwd }
}

///|
pub struct UpdateSubTaskParams {
  status : CoordinationStatus
  result : Json?
  error : String?
} derive(FromJson, ToJson)

///|
pub fn update_subtask_params(
  status~ : CoordinationStatus,
  result? : Json,
  error? : String,
) -> UpdateSubTaskParams {
  UpdateSubTaskParams::{ status, result, error }
}

///|
async fn Gateway::handle_create_coordination(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  let json = @json.parse(text) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{e}" },
      })
  }
  let params : CreateCoordinationParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid coordination params: \{e}",
        },
      })
  }
  let subtasks = params.subtasks.map(fn(p) {
    match (p.model, p.cwd) {
      (Some(m), Some(c)) =>
        sub_task(task_id=p.task_id, message=p.message, model=m, cwd=c)
      (Some(m), None) => sub_task(task_id=p.task_id, message=p.message, model=m)
      (None, Some(c)) => sub_task(task_id=p.task_id, message=p.message, cwd=c)
      (None, None) => sub_task(task_id=p.task_id, message=p.message)
    }
  })
  let task = self.coordinator.create(
    parent_agent=params.parent_agent,
    subtasks~,
    metadata=params.metadata,
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(201)
  w.write(task.to_json().stringify())
}

///|
async fn Gateway::handle_get_coordination(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  coordination_id : StringView,
) -> Unit {
  let task = match self.coordinator.get(coordination_id.to_string()) {
    Some(t) => t
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "coordination_not_found",
          "message": "Coordination not found: \{coordination_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(task.to_json().stringify())
}

///|
async fn Gateway::handle_list_coordinations(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let tasks = self.coordinator.list()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "total": tasks.length().to_json(),
    "coordinations": tasks.map(fn(t) { t.to_json() }).to_json(),
  }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_start_coordination(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  coordination_id : StringView,
) -> Unit {
  if !self.coordinator.can_accept_more() {
    raise json_error(429, "TooManyRequests", {
      "error": {
        "code": "coordination_limit_reached",
        "message": "Coordinator is at max_concurrent capacity",
      },
    })
  }
  let task = match self.coordinator.start_task(coordination_id.to_string()) {
    Some(t) => t
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "coordination_not_found",
          "message": "Coordination not found: \{coordination_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(task.to_json().stringify())
  @async.with_task_group(group => {
    group.spawn_bg(
      () => self.run_coordination(coordination_id.to_string()),
      no_wait=true,
    )
  })
}

///|
async fn Gateway::handle_cancel_coordination(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  coordination_id : StringView,
) -> Unit {
  let task = match self.coordinator.cancel_task(coordination_id.to_string()) {
    Some(t) => t
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "coordination_not_found",
          "message": "Coordination not found: \{coordination_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(task.to_json().stringify())
}

///|
async fn Gateway::handle_update_subtask(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  coordination_id : StringView,
  task_id : StringView,
) -> Unit {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  let json = @json.parse(text) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{e}" },
      })
  }
  let params : UpdateSubTaskParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid update params: \{e}",
        },
      })
  }
  let existing = match self.coordinator.get(coordination_id.to_string()) {
    Some(task) => task
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "coordination_not_found",
          "message": "Coordination not found: \{coordination_id}",
        },
      })
  }
  if !existing.has_subtask(task_id.to_string()) {
    raise json_error(404, "NotFound", {
      "error": {
        "code": "subtask_not_found",
        "message": "Subtask not found: \{coordination_id}/\{task_id}",
      },
    })
  }
  let task = match
    self.coordinator.update_subtask_status(
      coordination_id.to_string(),
      task_id.to_string(),
      params.status,
      result=params.result,
      error=params.error,
    ) {
    Some(t) => t
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "coordination_not_found",
          "message": "Coordination or subtask not found: \{coordination_id}/\{task_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(task.to_json().stringify())
}

///|
async fn Gateway::handle_coordination_results(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  coordination_id : StringView,
) -> Unit {
  let task = match self.coordinator.get(coordination_id.to_string()) {
    Some(t) => t
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "coordination_not_found",
          "message": "Coordination not found: \{coordination_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(task.aggregate_results().stringify())
}
