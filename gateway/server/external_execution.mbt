///|
priv struct ExternalExecutionBackend {
  id : String
  run_analysis : async (@job.AnalysisRequest) -> Result[
    @job.AnalysisExecution?,
    String,
  ]
  run_child : async (@job.ChildRunExecutionRequest) -> Result[
    @job.ChildRunExecutionResult?,
    String,
  ]
}

///|
fn ExternalExecutionBackend::new(
  id~ : String,
  run_analysis~ : async (@job.AnalysisRequest) -> Result[
    @job.AnalysisExecution?,
    String,
  ],
  run_child~ : async (@job.ChildRunExecutionRequest) -> Result[
    @job.ChildRunExecutionResult?,
    String,
  ],
) -> ExternalExecutionBackend {
  ExternalExecutionBackend::{ id, run_analysis, run_child }
}

///|
fn normalized_external_execution_mode(mode : String?) -> String? {
  match mode {
    Some(mode) => {
      let trimmed = mode.trim().to_string()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
fn unsupported_external_execution_mode(mode : String) -> String {
  "Unsupported external execution mode: \{mode}"
}

///|
fn Gateway::external_execution_backends(
  self : Gateway,
) -> Array[ExternalExecutionBackend] {
  [
    ExternalExecutionBackend::new(
      id="acp",
      run_analysis=async fn(request) {
        if normalized_external_execution_mode(request.execution_mode) !=
          Some("acp") {
          return Ok(None)
        }
        match self.execute_analysis_via_acp(request) {
          Ok(result) => Ok(Some(result))
          Err(error) => Err(error)
        }
      },
      run_child=async fn(request) {
        if normalized_external_execution_mode(request.config.execution_mode) !=
          Some("acp") {
          return Ok(None)
        }
        match self.execute_child_run_via_acp(request) {
          Ok(result) => Ok(Some(result))
          Err(error) => Err(error)
        }
      },
    ),
  ]
}

///|
async fn Gateway::execute_analysis_via_external_backend(
  self : Gateway,
  request : @job.AnalysisRequest,
) -> Result[@job.AnalysisExecution?, String] {
  match normalized_external_execution_mode(request.execution_mode) {
    None => Ok(None)
    Some(mode) => {
      for backend in self.external_execution_backends() {
        if backend.id == mode {
          return (backend.run_analysis)(request)
        }
      }
      Err(unsupported_external_execution_mode(mode))
    }
  }
}

///|
async fn Gateway::execute_child_run_via_external_backend(
  self : Gateway,
  request : @job.ChildRunExecutionRequest,
) -> Result[@job.ChildRunExecutionResult?, String] {
  match normalized_external_execution_mode(request.config.execution_mode) {
    None => Ok(None)
    Some(mode) => {
      for backend in self.external_execution_backends() {
        if backend.id == mode {
          return (backend.run_child)(request)
        }
      }
      Err(unsupported_external_execution_mode(mode))
    }
  }
}
