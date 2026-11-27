///|
#derive(FromJson, ToJson)
pub struct CreatePipelineParams {
  name : String
  stages : Array[PipelineStageParams]
  metadata : Map[String, Json]
}

///|
pub fn create_pipeline_params(
  name~ : String,
  stages~ : Array[PipelineStageParams],
  metadata~ : Map[String, Json] = Map([], capacity=0),
) -> CreatePipelineParams {
  { name, stages, metadata, }
}

///|
#derive(FromJson, ToJson)
pub struct PipelineStageParams {
  name : String
  message : String
  model : String?
  cwd : String?
  input_template : String?
}

///|
pub fn pipeline_stage_params(
  name~ : String,
  message~ : String,
  model? : String,
  cwd? : String,
  input_template? : String,
) -> PipelineStageParams {
  { name, message, model, cwd, input_template, }
}

///|
#derive(FromJson, ToJson)
pub struct AdvanceStageParams {
  stage_name : String
  result : Json
}

///|
pub fn advance_stage_params(
  stage_name~ : String,
  result~ : Json,
) -> AdvanceStageParams {
  { stage_name, result, }
}

///|
#derive(FromJson, ToJson)
pub struct FailStageParams {
  stage_name : String
  error : String
}

///|
pub fn fail_stage_params(
  stage_name~ : String,
  error~ : String,
) -> FailStageParams {
  { stage_name, error, }
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
  w.write(ToJson::to_json(p).stringify())
}

///|
async fn Gateway::handle_get_pipeline(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
) -> Unit {
  let p = match self.pipeline_manager.get(pipeline_id.to_owned()) {
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
  w.write(ToJson::to_json(p).stringify())
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
    "total": ToJson::to_json(pipelines.length()),
    "pipelines": Json::array(pipelines.map(fn(p) { ToJson::to_json(p) })),
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
  let p = match self.pipeline_manager.start_pipeline(pipeline_id.to_owned()) {
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
  w.write(ToJson::to_json(p).stringify())
  @async.with_task_group(group => {
    group.spawn_bg(
      () => self.run_pipeline(pipeline_id.to_owned()),
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
  let p = match self.pipeline_manager.cancel_pipeline(pipeline_id.to_owned()) {
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
  w.write(ToJson::to_json(p).stringify())
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
  let existing = match self.pipeline_manager.get(pipeline_id.to_owned()) {
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
      pipeline_id.to_owned(),
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
  w.write(ToJson::to_json(p).stringify())
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
  let existing = match self.pipeline_manager.get(pipeline_id.to_owned()) {
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
      pipeline_id.to_owned(),
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
  w.write(ToJson::to_json(p).stringify())
}

///|
async fn Gateway::handle_pipeline_next_task(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  pipeline_id : StringView,
) -> Unit {
  let p = match self.pipeline_manager.get(pipeline_id.to_owned()) {
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
        "has_next": Json::boolean(true),
        "stage_name": Json::string(stage_name),
        "input": Json::string(input),
        "progress": Json::number(p.progress()),
      }
    None =>
      {
        "has_next": Json::boolean(false),
        "progress": Json::number(p.progress()),
      }
  }
  w.write(result.stringify())
}
