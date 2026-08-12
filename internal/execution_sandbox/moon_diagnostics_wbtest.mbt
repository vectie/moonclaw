///|
test "typed MoonDesk diagnostics grant has a fixed moon command" {
  assert_eq(moon_diagnostics_arguments(""), [
    "check", "--output-json", "--diagnostic-limit", "1000",
  ])
  assert_eq(moon_diagnostics_arguments("native"), [
    "check", "--target", "native", "--output-json", "--diagnostic-limit", "1000",
  ])
  try moon_diagnostics_arguments("native; touch /tmp/pwn") catch {
    _ => ()
  } noraise {
    _ => fail("expected injected target to be rejected")
  }
}
