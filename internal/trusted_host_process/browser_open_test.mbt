///|
async test "browser open rejects non-web schemes before host execution" {
  let result = Ok(open_browser_url("file:///etc/passwd")) catch {
    error => Err(error)
  }
  guard result is Err(InvalidParameter(message)) else {
    fail("expected invalid browser URL")
  }
  assert_eq(message, "browser URL must use http or https")
}

///|
async test "browser open rejects excessive timeout before host execution" {
  let result = Ok(
    open_browser_url("https://example.invalid/", timeout_ms=30001),
  ) catch {
    error => Err(error)
  }
  guard result is Err(InvalidParameter(message)) else {
    fail("expected invalid browser-open timeout")
  }
  assert_eq(message, "browser-open timeout exceeds the trusted limit")
}
