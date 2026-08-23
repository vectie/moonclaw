///|
test "MoonDesk diagnostics request is typed and traversal-free" {
  let parsed = moondesk_sandbox_parse_request({
    "protocol_version": 1,
    "instance_id": "0123456789abcdef0123456789abcdef",
    "request_id": "desk-0123456789abcdef0123456789abcdef",
    "workspace_id": "book",
    "module_directory": "packages/app",
    "target": "",
  })
  assert_eq(parsed.module_directory, "packages/app")
  for bad in ["../outside", "/tmp/outside", "packages//app", "packages/app/"] {
    assert_false(moondesk_sandbox_safe_relative_directory(bad))
  }
  assert_true(moondesk_sandbox_constant_time_equal("aabbcc", "aabbcc"))
  assert_false(moondesk_sandbox_constant_time_equal("aabbcc", "aabbcd"))
  assert_false(moondesk_sandbox_constant_time_equal("aabb", "aabbcc"))
  assert_false(moondesk_sandbox_constant_time_equal("aabbccdd", "aabbcc"))
}

///|
async test "MoonDesk diagnostics directory is bound below registered workspace" {
  @fsx.with_temporary_directory("moondesk-route-workspace-XXXXXX", async fn(
    root,
  ) {
    let module_root = @pathx.join(root, "packages/app")
    @fsx.make_directory(module_root, recursive=true)
    let config = @moondesk_sandbox_config.Config::{
      protocol_version: 1,
      instance_id: "0123456789abcdef0123456789abcdef",
      auth_token: "a".repeat(64),
      workspace_id: "book",
      workspace_root: @fsx.resolve(root),
    }
    assert_eq(
      moondesk_sandbox_directory(config, "packages/app"),
      @fsx.resolve(module_root),
    )
    try moondesk_sandbox_directory(config, "../outside") catch {
      _ => ()
    } noraise {
      _ => fail("expected traversal to be rejected")
    }
  })
}

///|
async test "MoonDesk diagnostics reaches MoonFort with an enforced receipt" {
  @fsx.with_temporary_directory("moondesk-route-positive-XXXXXX", async fn(
    root,
  ) {
    mooncode_with_fake_moonfort(async fn(base_config, capture_path) {
      let executor_config = {
        ..base_config,
        enforcement_requirement: RequireEnforced,
      }
      let route_config = @moondesk_sandbox_config.Config::{
        protocol_version: 1,
        instance_id: "0123456789abcdef0123456789abcdef",
        auth_token: "a".repeat(64),
        workspace_id: "book",
        workspace_root: @fsx.resolve(root),
      }
      let request = moondesk_sandbox_parse_request({
        "protocol_version": 1,
        "instance_id": route_config.instance_id,
        "request_id": "desk-0123456789abcdef0123456789abcdef",
        "workspace_id": route_config.workspace_id,
        "module_directory": "",
        "target": "",
      })
      let response = execute_moondesk_moon_diagnostics(
        executor_config, route_config, request,
      )
      assert_eq(
        mooncode_json_string(response, "operation", default=""),
        "moon_diagnostics",
      )
      assert_false(
        mooncode_json_bool(response, "output_truncated", default=true),
      )
      let capture = @json.parse(@fsx.read_file(capture_path))
      let grant = mooncode_json_object_field_or_empty(capture, "grant")
      let command = grant.stringify()
      assert_true(command.contains("output-json"))
      assert_true(command.contains("diagnostic-limit"))
      assert_false(command.contains("shell"))
    })
  })
}
