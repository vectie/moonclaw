///|
pub struct ProcessBrowserHost {}

///|
pub fn ProcessBrowserHost::new() -> ProcessBrowserHost {
  ProcessBrowserHost::{  }
}

///|
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
