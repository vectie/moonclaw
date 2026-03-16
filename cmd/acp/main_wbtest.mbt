///|
async test "acp add codex writes target into home moonclaw config" {
  let home = "/tmp/moonclaw-cmd-acp-home"
  let cwd = "/tmp/moonclaw-cmd-acp-cwd"
  @fsx.make_directory(home, recursive=true)
  @fsx.make_directory(cwd, recursive=true)
  add_codex_target([
    "add", "codex", "--home", home, "--cwd", cwd, "--workspace", "/tmp/workspace",
  ])
  let configured = @fsx.read_file(root_config_path(home))
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
  @fsx.write_to_file(
    root_config_path(home),
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
  let configured = @fsx.read_file(root_config_path(home))
  inspect(configured.contains("\"port\": 18123"), content="true")
  inspect(configured.contains("\"workspace\": \"/tmp/new\""), content="true")
}
