///|
async test "workspace runtime prefers configured workspace and bootstraps files" {
  let dir = "/tmp/moonclaw-workspace-runtime"
  let config_path = dir |> @pathx.join("moonclaw.json")
  let workspace_root = dir |> @pathx.join("workspace-home")
  @fsx.make_directory(dir, recursive=true)
  @fsx.write_to_file(
    config_path,
    ({ "agents": { "defaults": { "workspace": workspace_root } } } : Json).stringify(),
  )

  let runtime = WorkspaceRuntime::new(home=dir, cwd=dir)
  let snapshot = runtime.snapshot()
  inspect(snapshot.root, content=workspace_root)
  inspect(snapshot.configured_from, content=config_path)
  inspect(snapshot.files.length(), content="5")
  inspect(
    snapshot.prompt_context.contains("Workspace context:"),
    content="true",
  )
}

///|
async test "workspace runtime includes extension workspace context when detected" {
  let dir = "/tmp/moonclaw-workspace-wiki-runtime"
  let config_path = dir |> @pathx.join("moonclaw.json")
  let workspace_root = dir |> @pathx.join("wiki-home")
  @fsx.make_directory(workspace_root |> @pathx.join("raw"), recursive=true)
  @fsx.make_directory(workspace_root |> @pathx.join("wiki"), recursive=true)
  @fsx.make_directory(
    workspace_root |> @pathx.join("wiki") |> @pathx.join("entities"),
    recursive=true,
  )
  @fsx.write_to_file(
    workspace_root |> @pathx.join("wiki") |> @pathx.join("index.md"),
    "# Index\n\n- [Home](./Home.md)\n- [Land](./entities/land.md)\n",
  )
  @fsx.write_to_file(
    workspace_root |> @pathx.join("wiki") |> @pathx.join("log.md"),
    "## [2026-04-05] ingest | Land Report\n\n- updated entities/land.md\n",
  )
  @fsx.write_to_file(
    config_path,
    ({ "agents": { "defaults": { "workspace": workspace_root } } } : Json).stringify(),
  )

  let runtime = WorkspaceRuntime::new(home=dir, cwd=dir)
  let snapshot = runtime.snapshot()
  inspect(
    snapshot.prompt_context.contains("Extension workspace detected:"),
    content="true",
  )
  inspect(
    snapshot.prompt_context.contains("Wiki index excerpt"),
    content="true",
  )
  inspect(
    snapshot.prompt_context.contains("wiki/entities/ available at:"),
    content="true",
  )
}
