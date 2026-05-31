///|
async test "gateway cli defaults use configured url token workspace and model" {
  let home = "/tmp/moonclaw-cmd-gateway-home"
  let cwd = "/tmp/moonclaw-cmd-gateway-cwd"
  @fsx.make_directory(home, recursive=true)
  @fsx.make_directory(cwd, recursive=true)
  @fsx.write_to_file(
    root_config_path(home),
    (
      {
        "agents": {
          "defaults": {
            "cwd": "/tmp/configured-cwd",
            "workspace": "/tmp/configured-workspace",
            "model": { "primary": "codex/gpt-5.4" },
          },
        },
        "gateway": { "port": 19090, "auth": { "token": "secret-token" } },
      } : Json).stringify(),
  )
  let defaults = gateway_cli_defaults(["health", "--home", home, "--cwd", cwd])
  inspect(defaults.url, content="http://localhost:19090")
  inspect(defaults.token.unwrap_or(""), content="secret-token")
  inspect(defaults.cwd.unwrap_or(""), content="/tmp/configured-cwd")
  inspect(defaults.primary_model.unwrap_or(""), content="codex/gpt-5.4")
}
