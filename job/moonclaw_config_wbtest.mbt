///|
async test "configured_primary_model ignores legacy home config" {
  @fsx.with_temporary_directory("job-moonclaw-config-XXXXXX", dir => {
    let cwd = dir |> @pathx.join("book")
    @fsx.make_directory(cwd, recursive=true, exists_ok=true)
    let legacy_config = dir |> @pathx.join("moonclaw.json")
    let product_config = @moonsuite.product_artifact_for_workspace_root(
      dir, "moonclaw", "moonclaw.json",
    )
    @fsx.make_directory(@pathx.dirname(product_config), recursive=true)
    @fsx.write_to_file(
      legacy_config,
      (
        { "agents": { "defaults": { "model": { "primary": "legacy/model" } } } } :
        Json).stringify(),
    )
    inspect(configured_primary_model(cwd, Some(dir)).unwrap_or(""), content="")
    @fsx.write_to_file(
      product_config,
      (
        {
          "agents": { "defaults": { "model": { "primary": "product/model" } } },
        } : Json).stringify(),
    )

    inspect(
      configured_primary_model(cwd, Some(dir)).unwrap_or(""),
      content="product/model",
    )
  })
}

///|
async test "configured_primary_model prefers workspace product config over home product config" {
  @fsx.with_temporary_directory("job-moonclaw-config-project-XXXXXX", dir => {
    let cwd = dir |> @pathx.join("book")
    let home = dir |> @pathx.join("home")
    @fsx.make_directory(cwd, recursive=true, exists_ok=true)
    let workspace_config = @moonsuite.product_artifact_for_workspace_root(
      cwd, "moonclaw", "moonclaw.json",
    )
    let home_config = @moonsuite.product_artifact_for_workspace_root(
      home, "moonclaw", "moonclaw.json",
    )
    @fsx.make_directory(@pathx.dirname(workspace_config), recursive=true)
    @fsx.make_directory(@pathx.dirname(home_config), recursive=true)
    @fsx.write_to_file(
      workspace_config,
      (
        {
          "agents": {
            "defaults": { "model": { "primary": "workspace/model" } },
          },
        } : Json).stringify(),
    )
    @fsx.write_to_file(
      home_config,
      (
        { "agents": { "defaults": { "model": { "primary": "home/model" } } } } :
        Json).stringify(),
    )

    inspect(
      configured_primary_model(cwd, Some(home)).unwrap_or(""),
      content="workspace/model",
    )
  })
}
