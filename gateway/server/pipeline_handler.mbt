///|
pub struct CreatePipelineParams {
  name : String
  stages : Array[PipelineStageParams]
  metadata : Map[String, Json]
} derive(FromJson, ToJson)

///|
pub fn create_pipeline_params(
  name~ : String,
  stages~ : Array[PipelineStageParams],
  metadata? : Map[String, Json] = Map::new(),
) -> CreatePipelineParams {
  CreatePipelineParams::{ name, stages, metadata }
}

///|
pub struct PipelineStageParams {
  name : String
  message : String
  model : String?
  cwd : String?
  input_template : String?
} derive(FromJson, ToJson)

///|
pub fn pipeline_stage_params(
  name~ : String,
  message~ : String,
  model? : String,
  cwd? : String,
  input_template? : String,
) -> PipelineStageParams {
  PipelineStageParams::{ name, message, model, cwd, input_template }
}

///|
pub struct AdvanceStageParams {
  stage_name : String
  result : Json
} derive(FromJson, ToJson)

///|
pub fn advance_stage_params(
  stage_name~ : String,
  result~ : Json,
) -> AdvanceStageParams {
  AdvanceStageParams::{ stage_name, result }
}

///|
pub struct FailStageParams {
  stage_name : String
  error : String
} derive(FromJson, ToJson)

///|
pub fn fail_stage_params(
  stage_name~ : String,
  error~ : String,
) -> FailStageParams {
  FailStageParams::{ stage_name, error }
}

///|
async fn Gateway::handle_create_pipeline(
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
  let params : CreatePipelineParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid pipeline params: \{e}",
        },
      })
  }
  let stages = params.stages.map(fn(p) {
    pipeline_stage(
      name=p.name,
      message=p.message,
      model=p.model,
      cwd=p.cwd,
      input_template=p.input_template,
    )
  })
  let p = self.pipeline_manager.create(
    name=params.name,
    stages~,
    metadata=params.metadata,
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(201)
  w.write(p.to_json().stringify())
}

///|
async fn Gateway::handle_get_pipeline(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
) -> Unit {
  let p = match self.pipeline_manager.get(pipeline_id.to_string()) {
    Some(p) => p
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(p.to_json().stringify())
}

///|
async fn Gateway::handle_list_pipelines(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let pipelines = self.pipeline_manager.list()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "total": pipelines.length().to_json(),
    "pipelines": pipelines.map(fn(p) { p.to_json() }).to_json(),
  }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_start_pipeline(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
) -> Unit {
  let p = match self.pipeline_manager.start_pipeline(pipeline_id.to_string()) {
    Some(p) => p
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(p.to_json().stringify())
  @async.with_task_group(group => {
    group.spawn_bg(
      () => self.run_pipeline(pipeline_id.to_string()),
      no_wait=true,
    )
  })
}

///|
async fn Gateway::handle_cancel_pipeline(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
) -> Unit {
  let p = match self.pipeline_manager.cancel_pipeline(pipeline_id.to_string()) {
    Some(p) => p
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(p.to_json().stringify())
}

///|
async fn Gateway::handle_advance_pipeline_stage(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
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
  let params : AdvanceStageParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid advance params: \{e}",
        },
      })
  }
  let existing = match self.pipeline_manager.get(pipeline_id.to_string()) {
    Some(pipeline) => pipeline
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  if !existing.has_current_stage(params.stage_name) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "invalid_stage_transition",
        "message": "Current pipeline stage does not match: \{params.stage_name}",
      },
    })
  }
  let p = match
    self.pipeline_manager.advance_stage(
      pipeline_id.to_string(),
      params.stage_name,
      params.result,
    ) {
    Some(p) => p
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(p.to_json().stringify())
}

///|
async fn Gateway::handle_fail_pipeline_stage(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
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
  let params : FailStageParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid fail params: \{e}",
        },
      })
  }
  let existing = match self.pipeline_manager.get(pipeline_id.to_string()) {
    Some(pipeline) => pipeline
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  if !existing.has_current_stage(params.stage_name) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "invalid_stage_transition",
        "message": "Current pipeline stage does not match: \{params.stage_name}",
      },
    })
  }
  let p = match
    self.pipeline_manager.fail_stage(
      pipeline_id.to_string(),
      params.stage_name,
      params.error,
    ) {
    Some(p) => p
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(p.to_json().stringify())
}

///|
async fn Gateway::handle_pipeline_next_task(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
) -> Unit {
  let p = match self.pipeline_manager.get(pipeline_id.to_string()) {
    Some(p) => p
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "pipeline_not_found",
          "message": "Pipeline not found: \{pipeline_id}",
        },
      })
  }
  let next = p.get_next_task()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = match next {
    Some((stage_name, input)) =>
      {
        "has_next": true.to_json(),
        "stage_name": stage_name.to_json(),
        "input": input.to_json(),
        "progress": p.progress().to_json(),
      }
    None => { "has_next": false.to_json(), "progress": p.progress().to_json() }
  }
  w.write(result.stringify())
}
