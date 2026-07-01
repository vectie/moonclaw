///|
async test "acp add codex writes target into home moonclaw config" {
  let home = "/tmp/moonclaw-cmd-acp-home"
  let cwd = "/tmp/moonclaw-cmd-acp-cwd"
  @fsx.make_directory(home, recursive=true)
  @fsx.make_directory(cwd, recursive=true)
  add_codex_target([
    "add", "codex", "--home", home, "--cwd", cwd, "--workspace", "/tmp/workspace",
  ])
  let configured = @fsx.read_file(preferred_config_path(home))
  inspect(configured.contains("\"codex-main\""), content="true")
  inspect(configured.contains("\"backend\": \"codex\""), content="true")
  inspect(
    configured.contains("\"workspace\": \"/tmp/workspace\""),
    content="true",
  )
}

///|
async test "acp add codex preserves unrelated config and updates an existing target" {
  let home = "/tmp/moonclaw-cmd-acp-home-merge"
  let cwd = "/tmp/moonclaw-cmd-acp-cwd-merge"
  @fsx.make_directory(home, recursive=true)
  @fsx.make_directory(cwd, recursive=true)
  @fsx.make_directory(
    @pathx.dirname(preferred_config_path(home)),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    preferred_config_path(home),
    (
      {
        "gateway": { "port": 18123 },
        "acp": {
          "targets": {
            "codex-main": { "backend": "codex", "workspace": "/tmp/old" },
          },
        },
      } : Json).stringify(),
  )
  add_codex_target([
    "add", "codex", "--home", home, "--cwd", cwd, "--workspace", "/tmp/new", "--model",
    "gpt-5",
  ])
  let configured = @fsx.read_file(preferred_config_path(home))
  inspect(configured.contains("\"port\": 18123"), content="true")
  inspect(configured.contains("\"workspace\": \"/tmp/new\""), content="true")
}

///|
async test "acp add codex prefers workspace product config over home config" {
  let home = "/tmp/moonclaw-cmd-acp-home-workspace-override"
  let cwd = "/tmp/moonclaw-cmd-acp-cwd-workspace-override"
  @fsx.make_directory(home, recursive=true)
  @fsx.make_directory(cwd, recursive=true)
  @fsx.make_directory(
    @pathx.dirname(preferred_config_path(home)),
    recursive=true,
    exists_ok=true,
  )
  @fsx.make_directory(
    @pathx.dirname(workspace_config_path(cwd)),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    preferred_config_path(home),
    (
      {
        "agents": {
          "defaults": {
            "cwd": "/tmp/home-cwd",
            "workspace": "/tmp/home-workspace",
          },
        },
        "acp": {
          "targets": {
            "home-only": { "backend": "codex", "workspace": "/tmp/home" },
          },
        },
      } : Json).stringify(),
  )
  @fsx.write_to_file(
    workspace_config_path(cwd),
    (
      {
        "agents": {
          "defaults": {
            "cwd": "/tmp/workspace-cwd",
            "workspace": "/tmp/workspace-configured",
          },
        },
      } : Json).stringify(),
  )
  add_codex_target(["add", "codex", "--home", home, "--cwd", cwd])
  let workspace_configured = @fsx.read_file(workspace_config_path(cwd))
  let home_configured = @fsx.read_file(preferred_config_path(home))
  inspect(
    workspace_configured.contains(
      "\"workspace\": \"/tmp/workspace-configured\"",
    ),
    content="true",
  )
  inspect(
    workspace_configured.contains("\"cwd\": \"/tmp/workspace-cwd\""),
    content="true",
  )
  inspect(workspace_configured.contains("\"codex-main\""), content="true")
  inspect(home_configured.contains("\"home-only\""), content="true")
  inspect(home_configured.contains("\"codex-main\""), content="false")
}

///|
async test "acp add codex defaults workspace and cwd from configured defaults" {
  let home = "/tmp/moonclaw-cmd-acp-home-config-workspace"
  let cwd = "/tmp/moonclaw-cmd-acp-cwd-config-workspace"
  @fsx.make_directory(home, recursive=true)
  @fsx.make_directory(cwd, recursive=true)
  @fsx.make_directory(
    @pathx.dirname(preferred_config_path(home)),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    preferred_config_path(home),
    (
      {
        "agents": {
          "defaults": {
            "cwd": "/tmp/config-cwd",
            "workspace": "/tmp/config-workspace",
          },
        },
      } : Json).stringify(),
  )
  add_codex_target(["add", "codex", "--home", home, "--cwd", cwd])
  let configured = @fsx.read_file(preferred_config_path(home))
  inspect(
    configured.contains("\"workspace\": \"/tmp/config-workspace\""),
    content="true",
  )
  inspect(configured.contains("\"cwd\": \"/tmp/config-cwd\""), content="true")
}
