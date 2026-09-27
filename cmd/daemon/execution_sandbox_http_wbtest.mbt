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
test "MoonDesk Moon IDE request rejects traversal and unsupported actions" {
  let valid : Json = {
    "protocol_version": 1,
    "instance_id": "0123456789abcdef0123456789abcdef",
    "request_id": "desk-0123456789abcdef0123456789abcdef",
    "workspace_id": "book",
    "module_directory": "packages/app",
    "module_path": "src/main.mbt",
    "action": "definition",
    "symbol": "Widget",
    "line": 8,
    "column": 13,
  }
  let parsed = moondesk_sandbox_parse_ide_request(valid)
  assert_eq(parsed.module_path, "src/main.mbt")
  assert_eq(parsed.symbol, "Widget")
  for
    bad in [
      mooncode_json_object_with_field(
        valid,
        "module_path",
        "../secret.mbt".to_json(),
      ),
      mooncode_json_object_with_field(
        valid,
        "module_path",
        "/tmp/secret.mbt".to_json(),
      ),
      mooncode_json_object_with_field(valid, "action", "shell".to_json()),
      mooncode_json_object_with_field(valid, "symbol", "Widget;rm".to_json()),
      mooncode_json_object_with_field(valid, "line", (0).to_json()),
    ] {
    try moondesk_sandbox_parse_ide_request(bad) catch {
      _ => continue
    } noraise {
      _ => fail("expected invalid Moon IDE request to be rejected")
    }
  }
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

///|
async test "MoonDesk Moon IDE reaches MoonFort as one typed moon command" {
  @fsx.with_temporary_directory("moondesk-ide-positive-XXXXXX", async fn(root) {
    mooncode_with_fake_moonfort(async fn(base_config, capture_path) {
      let module_root = @pathx.join(root, "packages/app")
      @fsx.make_directory(@pathx.join(module_root, "src"), recursive=true)
      @fsx.write_to_file(
        @pathx.join(module_root, "src/main.mbt"),
        "pub fn Widget() {}\n",
      )
      let route_config = @moondesk_sandbox_config.Config::{
        protocol_version: 1,
        instance_id: "0123456789abcdef0123456789abcdef",
        auth_token: "a".repeat(64),
        workspace_id: "book",
        workspace_root: @fsx.resolve(root),
      }
      let request = moondesk_sandbox_parse_ide_request({
        "protocol_version": 1,
        "instance_id": route_config.instance_id,
        "request_id": "desk-0123456789abcdef0123456789abcdef",
        "workspace_id": route_config.workspace_id,
        "module_directory": "packages/app",
        "module_path": "src/main.mbt",
        "action": "definition",
        "symbol": "Widget",
        "line": 1,
        "column": 8,
      })
      let response = execute_moondesk_moon_ide(
        { ..base_config, enforcement_requirement: RequireEnforced, },
        route_config,
        request,
      )
      assert_eq(
        mooncode_json_string(response, "operation", default=""),
        "moon_ide",
      )
      let capture = @json.parse(@fsx.read_file(capture_path)).stringify()
      assert_true(capture.contains("peek-def"))
      assert_true(capture.contains("src/main.mbt:1:8"))
      assert_false(capture.contains("shell"))
    })
  })
}
