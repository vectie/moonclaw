///|
test "MoonDesk sandbox config control root is outside workspaces" {
  assert_eq(
    control_root_from_environment("/private/app-data", "/Users/demo"),
    "/private/app-data/control/execution-sandbox",
  )
  assert_eq(
    control_root_from_environment("", "/Users/demo"),
    "/Users/demo/Library/Application Support/app.vectie.moondesk/control/execution-sandbox",
  )
}
