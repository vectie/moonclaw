///|
async test "inspect reports missing setup in an empty home" {
  let home = "/tmp/moonclaw-onboarding-empty"
  let cwd = home |> @pathx.join("project")
  @fsx.make_directory(cwd, recursive=true)
  let status = collect_status(home~, cwd~)
  json_inspect(status.config_exists, content=false)
  json_inspect(status.provider_count, content=0)
  json_inspect(status.has_gateway_token, content=false)
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
