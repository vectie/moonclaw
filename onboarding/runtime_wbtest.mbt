///|
async test "inspect reports missing setup in an empty home" {
  let home = "/tmp/moonclaw-onboarding-empty"
  let cwd = home |> @pathx.join("project")
  @fsx.make_directory(cwd, recursive=true)
  let status = collect_status(home~, cwd~)
  json_inspect(status.config_exists, content=false)
  json_inspect(status.provider_count, content=0)
  json_inspect(status.has_gateway_token, content=false)
  json_inspect(status.available_models.contains("codex/gpt-5.4"), content=true)
  json_inspect(status.issues, content=[
    "Missing moonclaw.json configuration", "No model providers configured", "No primary model configured",
    "Gateway auth token is missing",
  ])
}

///|
async test "bootstrap creates config and preserves existing settings" {
  let home = "/tmp/moonclaw-onboarding-bootstrap"
  let cwd = home |> @pathx.join("project")
  let config_path = home |> @pathx.join("moonclaw.json")
  @fsx.make_directory(cwd, recursive=true)
  @fsx.write_to_file(
    config_path,
    (
      {
        "agents": { "defaults": { "model": { "primary": "demo/model" } } },
        "channels": {
          "feishu": {
            "enabled": true,
            "appId": "app-id",
            "appSecret": "app-secret",
          },
        },
      } : Json).stringify(),
  )
  let result = bootstrap(home~, cwd~)
  json_inspect(result.status, content="updated")
  json_inspect(
    result.onboarding.primary_model.unwrap_or(""),
    content="demo/model",
  )
  json_inspect(result.onboarding.has_gateway_token, content=true)
  json_inspect(result.onboarding.workspace_files.length(), content=5)
  json_inspect(result.preserved.contains("channels"), content=true)
}

///|
async test "discover_models lists configured provider models" {
  let home = "/tmp/moonclaw-onboarding-models"
  let cwd = home |> @pathx.join("project")
  let config_path = home |> @pathx.join("moonclaw.json")
  @fsx.make_directory(cwd, recursive=true)
  @fsx.write_to_file(
    config_path,
    (
      {
        "models": {
          "providers": {
            "demo": { "models": [{ "id": "fast" }, { "id": "smart" }] },
            "alt": { "models": [{ "id": "coder" }] },
          },
        },
      } : Json).stringify(),
  )
  let models = discover_models(home~, cwd~)
  json_inspect(
    models.contains("alt/coder") &&
    models.contains("demo/fast") &&
    models.contains("demo/smart") &&
    models.contains("codex/gpt-5.4"),
    content=true,
  )
}

///|
async test "bootstrap_with_options applies explicit model workspace and channel choices" {
  let home = "/tmp/moonclaw-onboarding-options"
  let cwd = home |> @pathx.join("project")
  let config_path = home |> @pathx.join("moonclaw.json")
  let custom_workspace = home |> @pathx.join("custom-workspace")
  @fsx.make_directory(cwd, recursive=true)
  let result = bootstrap_with_options(home~, cwd~, {
    primary_model: Some("demo/smart"),
    working_directory: None,
    workspace_root: Some(custom_workspace),
    gateway_port: Some(19090),
    gateway_token: Some("fixed-token"),
    feishu_enabled: Some(true),
    feishu_app_id: Some("cli_demo"),
    feishu_app_secret: Some("secret_demo"),
  })
  let text = @fsx.read_file(config_path)
  let json = @json.parse(text)
  json_inspect(
    result.onboarding.primary_model.unwrap_or(""),
    content="demo/smart",
  )
  json_inspect(result.onboarding.gateway_port.unwrap_or(0), content=19090)
  json_inspect(result.onboarding.feishu_ready, content=true)
  json_inspect(
    result.onboarding.workspace_root,
    content=custom_workspace.to_json(),
  )
  json_inspect(json, content={
    "models": { "providers": {} },
    "agents": {
      "defaults": {
        "model": { "primary": "demo/smart" },
        "cwd": cwd,
        "workspace": custom_workspace,
      },
    },
    "commands": {
      "native": "auto",
      "nativeSkills": "auto",
      "restart": true,
      "ownerDisplay": "raw",
    },
    "session": { "dmScope": "per-channel-peer" },
    "gateway": {
      "port": 19090,
      "auth": { "mode": "token", "token": "fixed-token" },
    },
    "plugins": { "entries": {} },
    "channels": {
      "feishu": {
        "enabled": true,
        "appId": "cli_demo",
        "appSecret": "secret_demo",
      },
    },
  })
}

///|
async test "bootstrap adds configured cwd distinct from workspace" {
  let home = "/tmp/moonclaw-onboarding-cwd"
  let cwd = home |> @pathx.join("project")
  let config_path = home |> @pathx.join("moonclaw.json")
  let custom_workspace = home |> @pathx.join("custom-workspace")
  @fsx.make_directory(cwd, recursive=true)
  ignore(
    bootstrap_with_options(home~, cwd~, {
      ..default_onboarding_options(),
      workspace_root: Some(custom_workspace),
    }),
  )
  let text = @fsx.read_file(config_path)
  inspect(text.contains("\"cwd\": \"\{cwd}\""), content="true")
  inspect(
    text.contains("\"workspace\": \"\{custom_workspace}\""),
    content="true",
  )
}

///|
test "render_auth_status shows switch guidance" {
  let text = render_auth_status({
    providers: [
      {
        provider: "codex",
        authenticated: false,
        account_label: None,
        detail: Some("not logged in"),
        default_model: Some("codex/gpt-5.4"),
        available_models: ["codex/gpt-5.4", "codex/gpt-5.3-codex"],
      },
    ],
    issues: ["Codex OAuth is not connected"],
    next_steps: [
      "Run `moonclaw onboard auth codex`, then `moonclaw onboard switch codex`",
    ],
  })
  json_inspect(text.contains("moonclaw onboard auth codex"), content=true)
  json_inspect(text.contains("moonclaw onboard switch codex"), content=true)
}
