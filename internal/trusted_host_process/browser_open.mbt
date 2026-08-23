///|
fn validate_browser_url(url : String) -> Unit raise TrustedHostProcessError {
  if url.is_blank() || url.length() > 8192 || url.contains("\u0000") {
    raise InvalidParameter(
      "browser URL is empty or exceeds the deployment limit",
    )
  }
  if !url.has_prefix("https://") && !url.has_prefix("http://") {
    raise InvalidParameter("browser URL must use http or https")
  }
}

///|
fn browser_open_environment() -> Map[String, String] {
  { "PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C" }
}

///|
/// Open a validated HTTP(S) URL using a fixed platform UX utility. Callers
/// cannot select an executable, argument vector, environment, or working
/// directory. Failure is returned so OAuth may continue with a printed URL.
pub async fn open_browser_url(
  url : String,
  timeout_ms? : Int = 10000,
) -> Bool raise TrustedHostProcessError {
  validate_browser_url(url)
  if timeout_ms < 1 || timeout_ms > 30000 {
    raise InvalidParameter("browser-open timeout exceeds the trusted limit")
  }
  let candidates = ["/usr/bin/open", "/usr/bin/xdg-open"]
  for executable in candidates {
    let available = @fsx.exists(executable) catch { _ => false }
    if available {
      let result = run_host_process(
        executable,
        [url],
        timeout=timeout_ms,
        env=browser_open_environment(),
        inherit_env=false,
      ) catch {
        _ => continue
      }
      if result.status == 0 {
        return true
      }
    }
  }
  false
}
