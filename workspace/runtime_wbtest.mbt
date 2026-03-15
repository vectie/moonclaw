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
