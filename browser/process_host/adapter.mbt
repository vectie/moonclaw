///|
pub struct ProcessBrowserHost {}

///|
#warnings("-unnecessary_annotation")
pub fn ProcessBrowserHost::new() -> ProcessBrowserHost {
  ProcessBrowserHost::{  }
}

///|
#warnings("-unused_async")
pub async fn ProcessBrowserHost::execute(
  _self : ProcessBrowserHost,
  _command : @browser.BrowserHostCommand,
  timeout_ms? : Int = 30000,
) -> Result[@browser.BrowserHostResult, String] {
  ignore(timeout_ms)
  Err(
    "ExecutionSandbox grant required: direct browser host process execution is disabled",
  )
}
