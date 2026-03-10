///|
pub enum PipelineStatus {
  Pending
  Running
  Completed
  Failed
  Cancelled
} derive(ToJson, FromJson, Eq, Show)

///|
pub struct PipelineStage {
  name : String
  message : String
  model : String?
  cwd : String?
  input_template : String?
  status : PipelineStatus
  result : Json?
  error : String?
  started_at : Int?
  completed_at : Int?
} derive(ToJson, FromJson, Show)

///|
pub fn pipeline_stage(
  name~ : String,
  message~ : String,
  model? : String? = None,
  cwd? : String? = None,
  input_template? : String? = None,
) -> PipelineStage {
  PipelineStage::{
    name,
    message,
    model,
    cwd,
    input_template,
    status: Pending,
    result: None,
    error: None,
    started_at: None,
    completed_at: None,
  }
}

///|
pub fn PipelineStage::start(self : PipelineStage) -> PipelineStage {
  { ..self, status: Running, started_at: Some(current_time_ms()) }
}

///|
pub fn PipelineStage::complete(
  self : PipelineStage,
  result : Json,
) -> PipelineStage {
  {
    ..self,
    status: Completed,
    result: Some(result),
    completed_at: Some(current_time_ms()),
  }
}

///|
pub fn PipelineStage::fail(
  self : PipelineStage,
  error : String,
) -> PipelineStage {
  {
    ..self,
    status: Failed,
    error: Some(error),
    completed_at: Some(current_time_ms()),
  }
}

///|
pub fn PipelineStage::is_done(self : PipelineStage) -> Bool {
  match self.status {
    Completed => true
    Failed => true
    Cancelled => true
    _ => false
  }
}

///|
pub fn PipelineStage::resolve_input(
  self : PipelineStage,
  prev_results : Map[String, Json],
) -> String {
  match self.input_template {
    Some(template) => {
      let mut result = template
      let keys = prev_results.keys().to_array()
      for key in keys {
        let value = prev_results.get(key)
        match value {
          Some(json) => {
            let placeholder = "${" + key + "}.output"
            result = result.replace(old=placeholder, new=json.stringify())
          }
          None => ()
        }
      }
      result
    }
    None => self.message
  }
}

///|
pub struct Pipeline {
  pipeline_id : String
  name : String
  stages : Array[PipelineStage]
  current_stage : Int
  status : PipelineStatus
  results : Map[String, Json]
  created_at : Int
  started_at : Int?
  completed_at : Int?
  metadata : Map[String, Json]
} derive(ToJson, FromJson, Show)

///|
pub fn pipeline(
  pipeline_id~ : String,
  name~ : String,
  stages~ : Array[PipelineStage],
  metadata? : Map[String, Json] = Map::new(),
) -> Pipeline {
  Pipeline::{
    pipeline_id,
    name,
    stages,
    current_stage: 0,
    status: Pending,
    results: Map::new(),
    created_at: current_time_ms(),
    started_at: None,
    completed_at: None,
    metadata,
  }
}

///|
pub fn Pipeline::start(self : Pipeline) -> Pipeline {
  let started_stages = self.stages.mapi(fn(i, stage) {
    if i == self.current_stage {
      stage.start()
    } else {
      stage
    }
  })
  {
    ..self,
    stages: started_stages,
    status: Running,
    started_at: Some(current_time_ms()),
  }
}

///|
pub fn Pipeline::complete(self : Pipeline) -> Pipeline {
  { ..self, status: Completed, completed_at: Some(current_time_ms()) }
}

///|
pub fn Pipeline::fail(self : Pipeline) -> Pipeline {
  { ..self, status: Failed, completed_at: Some(current_time_ms()) }
}

///|
pub fn Pipeline::cancel(self : Pipeline) -> Pipeline {
  { ..self, status: Cancelled, completed_at: Some(current_time_ms()) }
}

///|
pub fn Pipeline::is_done(self : Pipeline) -> Bool {
  match self.status {
    Completed => true
    Failed => true
    Cancelled => true
    _ => false
  }
}

///|
pub fn Pipeline::current_stage_info(self : Pipeline) -> PipelineStage? {
  if self.current_stage < self.stages.length() {
    Some(self.stages[self.current_stage])
  } else {
    None
  }
}

///|
pub fn Pipeline::has_current_stage(
  self : Pipeline,
  stage_name : String,
) -> Bool {
  match self.current_stage_info() {
    Some(stage) => stage.name == stage_name
    None => false
  }
}

///|
pub fn Pipeline::advance_stage(
  self : Pipeline,
  stage_name : String,
  result : Json,
) -> Pipeline {
  let new_stages = self.stages.mapi(fn(i, s) {
    if i == self.current_stage && s.name == stage_name {
      s.complete(result)
    } else if i == self.current_stage + 1 {
      s.start()
    } else {
      s
    }
  })
  let new_results = self.results
  new_results.set(stage_name, result)
  let next_stage = self.current_stage + 1
  let is_last = next_stage >= self.stages.length()
  {
    ..self,
    stages: new_stages,
    current_stage: next_stage,
    results: new_results,
    status: if is_last {
      Completed
    } else {
      self.status
    },
    completed_at: if is_last {
      Some(current_time_ms())
    } else {
      self.completed_at
    },
  }
}

///|
pub fn Pipeline::fail_stage(
  self : Pipeline,
  stage_name : String,
  error : String,
) -> Pipeline {
  let new_stages = self.stages.mapi(fn(i, s) {
    if i == self.current_stage && s.name == stage_name {
      s.fail(error)
    } else {
      s
    }
  })
  {
    ..self,
    stages: new_stages,
    status: Failed,
    completed_at: Some(current_time_ms()),
  }
}

///|
pub fn Pipeline::get_next_task(self : Pipeline) -> (String, String)? {
  if self.current_stage < self.stages.length() {
    let stage = self.stages[self.current_stage]
    let input = stage.resolve_input(self.results)
    Some((stage.name, input))
  } else {
    None
  }
}

///|
pub fn Pipeline::completed_stages(self : Pipeline) -> Int {
  self.stages.iter().filter(fn(s) { s.status is Completed }).count()
}

///|
pub fn Pipeline::total_stages(self : Pipeline) -> Int {
  self.stages.length()
}

///|
pub fn Pipeline::progress(self : Pipeline) -> Double {
  let total = Double::from_int(self.total_stages())
  let completed = Double::from_int(self.completed_stages())
  if total == 0.0 {
    0.0
  } else {
    completed / total
  }
}
