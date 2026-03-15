///|
pub struct PipelineManager {
  uuid : @uuid.Generator
  pipelines : Map[String, Pipeline]
}

///|
pub fn pipeline_manager(uuid~ : @uuid.Generator) -> PipelineManager {
  PipelineManager::{ uuid, pipelines: Map::new() }
}

///|
pub fn PipelineManager::create(
  self : PipelineManager,
  name~ : String,
  stages~ : Array[PipelineStage],
  metadata? : Map[String, Json] = Map::new(),
) -> Pipeline {
  let pipeline_id = self.uuid.v4().to_string()
  let p = pipeline(pipeline_id~, name~, stages~, metadata~)
  self.pipelines.set(pipeline_id, p)
  p
}

///|
pub fn PipelineManager::get(
  self : PipelineManager,
  pipeline_id : String,
) -> Pipeline? {
  self.pipelines.get(pipeline_id)
}

///|
pub fn PipelineManager::remove(
  self : PipelineManager,
  pipeline_id : String,
) -> Pipeline? {
  let p = self.pipelines.get(pipeline_id)
  match p {
    Some(_) => {
      self.pipelines.remove(pipeline_id)
      p
    }
    None => None
  }
}

///|
pub fn PipelineManager::list(self : PipelineManager) -> Array[Pipeline] {
  self.pipelines.values().to_array()
}

///|
pub fn PipelineManager::list_by_status(
  self : PipelineManager,
  status : PipelineStatus,
) -> Array[Pipeline] {
  self.pipelines.values().filter(fn(p) { p.status == status }).to_array()
}

///|
pub fn PipelineManager::start_pipeline(
  self : PipelineManager,
  pipeline_id : String,
) -> Pipeline? {
  let p = self.pipelines.get(pipeline_id)
  match p {
    Some(pipeline) => {
      let started = pipeline.start()
      self.pipelines.set(pipeline_id, started)
      Some(started)
    }
    None => None
  }
}

///|
pub fn PipelineManager::advance_stage(
  self : PipelineManager,
  pipeline_id : String,
  stage_name : String,
  result : Json,
) -> Pipeline? {
  let p = self.pipelines.get(pipeline_id)
  match p {
    Some(pipeline) => {
      let advanced = pipeline.advance_stage(stage_name, result)
      self.pipelines.set(pipeline_id, advanced)
      Some(advanced)
    }
    None => None
  }
}

///|
pub fn PipelineManager::fail_stage(
  self : PipelineManager,
  pipeline_id : String,
  stage_name : String,
  error : String,
) -> Pipeline? {
  let p = self.pipelines.get(pipeline_id)
  match p {
    Some(pipeline) => {
      let failed = pipeline.fail_stage(stage_name, error)
      self.pipelines.set(pipeline_id, failed)
      Some(failed)
    }
    None => None
  }
}

///|
pub fn PipelineManager::cancel_pipeline(
  self : PipelineManager,
  pipeline_id : String,
) -> Pipeline? {
  let p = self.pipelines.get(pipeline_id)
  match p {
    Some(pipeline) => {
      let cancelled = pipeline.cancel()
      self.pipelines.set(pipeline_id, cancelled)
      Some(cancelled)
    }
    None => None
  }
}

///|
pub fn PipelineManager::size(self : PipelineManager) -> Int {
  self.pipelines.length()
}

///|
pub fn PipelineManager::running_count(self : PipelineManager) -> Int {
  self.pipelines.values().filter(fn(p) { p.status is Running }).count()
}

///|
pub fn PipelineManager::to_json(self : PipelineManager) -> Json {
  {
    "total_pipelines": self.size().to_json(),
    "running_count": self.running_count().to_json(),
  }
}
