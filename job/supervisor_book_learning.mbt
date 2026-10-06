///|
fn supervisor_learning_alias(
  metadata : Json,
  key : String,
  alias : String,
) -> String {
  guard metadata is Object(fields) else { return "" }
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() =>
      return value.trim().to_owned()
    _ => ()
  }
  match fields.get(alias) {
    Some(String(value)) => value.trim().to_owned()
    _ => ""
  }
}

///|
fn supervisor_learning_binding(
  request : SupervisorDelegateIntentRequestV1,
) -> @book_learning.Binding {
  {
    workspace_id: supervisor_learning_alias(
      request.task.metadata,
      "workspace_id",
      "workspaceId",
    ),
    book_id: supervisor_learning_alias(
      request.task.metadata,
      "book_id",
      "bookId",
    ),
    source_root: request.task.cwd,
    request_digest: request.envelope.request_digest,
  }
}

///|
fn supervisor_learning_from_definition(
  definition : JobDefinition,
  request : SupervisorDelegateIntentRequestV1,
  claimed : Json?,
) -> Result[@book_learning.Snapshot, String] {
  let binding = supervisor_learning_binding(request)
  guard definition.config is Object(fields) else {
    return Err("durable worker config is invalid")
  }
  guard fields.get("intent") ==
    Some(
      supervisor_delegate_intent_payload_v1(
        request.supervisor_id,
        request.instruction,
        request.task,
        request.scope,
      ),
    ) else {
    return Err("durable worker definition intent mismatch")
  }
  match fields.get("book_learning_input") {
    None => {
      let legacy = @book_learning.empty(binding, "legacy_not_captured", 0)
      guard fields.get("book_learning_input_contract") is None &&
        (claimed is None || claimed == Some(@book_learning.summary(legacy))) else {
        return Err("claimed captured Book learning is missing")
      }
      Ok(legacy)
    }
    Some(value) => {
      let snapshot : @book_learning.Snapshot = @json.from_json(value) catch {
        _ => return Err("captured Book learning is corrupt")
      }
      match @book_learning.validate(snapshot, binding) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      guard fields.get("book_learning_input_contract") ==
        Some("moonclaw.book-learning-input.v1".to_json()) else {
        return Err("captured Book learning contract is missing")
      }
      if claimed is Some(expected) &&
        expected != @book_learning.summary(snapshot) {
        return Err("captured Book learning journal mismatch")
      }
      Ok(snapshot)
    }
  }
}

///|
/// Reads disk under the existing store lock, not a possibly stale runtime map.
async fn SystemStore::reload_supervisor_worker_store(
  self : SystemStore,
) -> Unit {
  self.with_store_lock(async fn() {
    self.reload_definitions_unlocked()
    let runs = self.load_runs_index_best_effort()
    clear_map(self.runs)
    clear_map(self.steps)
    for run in runs.runs {
      self.runs[run.id] = run
    }
    for step in runs.steps {
      self.steps["\{step.run_id}:\{step.step_id}"] = step
    }
  })
}

///|
async fn SystemStore::reload_worker_definition(
  self : SystemStore,
  id : String,
) -> JobDefinition? {
  self.reload_supervisor_worker_store()
  self.get_definition(id)
}

///|
/// Supports the definition-before-journal crash window without new provider IDs.
pub async fn SupervisorRuntime::worker_definition_provider_id(
  self : SupervisorRuntime,
  request : SupervisorDelegateIntentRequestV1,
) -> Result[String?, String] {
  self.with_lock(async fn() {
    let id = "moonclaw.supervisor-worker." +
      request.envelope.request_digest[7:31].to_owned()
    match self.runtime.store().reload_worker_definition(id) {
      None => Ok(None)
      Some(definition) => {
        match supervisor_learning_from_definition(definition, request, None) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match definition.config {
          { "provider_task_id": String(id), .. } => Ok(Some(id))
          _ => Err("durable worker provider identity missing")
        }
      }
    }
  })
}

///|
pub async fn SupervisorRuntime::worker_learning_input(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
) -> Result[@book_learning.Snapshot, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let request = match self.worker_intent(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let edge = match self.worker_edge(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let definition = match
      self.runtime.store().reload_worker_definition(edge.worker_job_id) {
      Some(value) => value
      None => return Err("durable worker definition missing")
    }
    let claimed = match self.worker_source_event(supervisor_id, worker_run_id) {
      Ok(event) =>
        match event.payload {
          Object(fields) => fields.get("book_learning_input")
          _ => None
        }
      Err(error) => return Err(error)
    }
    supervisor_learning_from_definition(definition, request, claimed)
  })
}

///|
/// Public job views keep the host-owned learned bytes and source path private.
pub fn JobDefinition::public_json(self : JobDefinition) -> Json {
  guard self.config is Object(config) && config.contains("book_learning_input") else {
    return self.to_json()
  }
  let fields : Map[String, Json] = {}
  if self.config is Object(config) {
    for key, value in config {
      if key == "book_learning_input" {
        continue
      }
      fields[key] = value
    }
    if config.get("book_learning_input") is Some(snapshot) {
      let parsed : @book_learning.Snapshot? = Some(@json.from_json(snapshot)) catch {
        _ => None
      }
      fields["book_learning_input"] = match parsed {
        Some(value) => @book_learning.summary(value)
        None => { "status": "integrity_error" }
      }
    }
  }
  let public_definition = { ..self, config: Json::object(fields), }
  public_definition.to_json()
}

///|
/// A redacted GET/PUT preserves private input; callers cannot create or replace it.
async fn SystemStore::prepare_public_definition(
  self : SystemStore,
  definition : JobDefinition,
) -> Result[JobDefinition, String] {
  self.reload_supervisor_worker_store()
  self.merge_public_definition(definition)
}

///|
fn SystemStore::merge_public_definition(
  self : SystemStore,
  definition : JobDefinition,
) -> Result[JobDefinition, String] {
  let incoming = match definition.config {
    Object(fields) => fields
    _ =>
      match self.get_definition(definition.id) {
        Some(previous) if previous.config is Object(fields) &&
          fields.contains("book_learning_input") =>
          return Err(
            "captured Book learning requires object config for a preserving update",
          )
        _ => return Ok(definition)
      }
  }
  match self.get_definition(definition.id) {
    Some(previous) if previous.config is Object(saved) &&
      saved.contains("book_learning_input") => {
      let public_fields = match previous.public_json() {
        { "config": Object(fields), .. } => fields
        _ => return Err("invalid public worker definition")
      }
      if incoming.get("book_learning_input") is Some(value) &&
        Some(value) != public_fields.get("book_learning_input") {
        return Err("captured Book learning is host-owned and immutable")
      }
      if incoming.get("book_learning_input_contract") is Some(value) &&
        Some(value) != saved.get("book_learning_input_contract") {
        return Err("captured Book learning contract is immutable")
      }
      let fields = incoming.copy()
      fields["book_learning_input"] = saved["book_learning_input"]
      fields["book_learning_input_contract"] = saved["book_learning_input_contract"]
      Ok({ ..definition, config: Json::object(fields), })
    }
    _ =>
      if incoming.contains("book_learning_input") ||
        incoming.contains("book_learning_input_contract") {
        Err("captured Book learning can only be created by native delegation")
      } else {
        Ok(definition)
      }
  }
}

///|
/// Public merge and persistence share the same lock; no capture can be lost in a
/// read-modify-write gap or by an independently loaded gateway's stale index.
pub async fn SystemStore::save_public_definition(
  self : SystemStore,
  definition : JobDefinition,
) -> Result[JobDefinition, String] {
  self.with_store_lock(async fn() {
    self.reload_definitions_unlocked()
    match self.merge_public_definition(definition) {
      Err(error) => Err(error)
      Ok(saved) => {
        self.definitions[saved.id] = saved
        self.save_definitions_index_unlocked()
        Ok(saved)
      }
    }
  })
}
