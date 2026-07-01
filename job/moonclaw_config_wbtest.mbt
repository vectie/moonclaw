///|
async test "configured_primary_model prefers product config over legacy home config" {
  @fsx.with_temporary_directory("job-moonclaw-config-XXXXXX", dir => {
    let cwd = dir |> @pathx.join("book")
    @fsx.make_directory(cwd, recursive=true, exists_ok=true)
    let legacy_config = dir |> @pathx.join("moonclaw.json")
    let product_config = @moonsuite.product_artifact(
      dir, "moonclaw", "moonclaw.json",
    )
    @fsx.make_directory(@pathx.dirname(product_config), recursive=true)
    @fsx.write_to_file(
      legacy_config,
      (
        { "agents": { "defaults": { "model": { "primary": "legacy/model" } } } } :
        Json).stringify(),
    )
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
async test "configured_primary_model still lets project config override product config" {
  @fsx.with_temporary_directory("job-moonclaw-config-project-XXXXXX", dir => {
    let cwd = dir |> @pathx.join("book")
    @fsx.make_directory(cwd, recursive=true, exists_ok=true)
    let project_config = cwd |> @pathx.join("moonclaw.json")
    let product_config = @moonsuite.product_artifact(
      dir, "moonclaw", "moonclaw.json",
    )
    @fsx.make_directory(@pathx.dirname(product_config), recursive=true)
    @fsx.write_to_file(
      project_config,
      (
        {
          "agents": { "defaults": { "model": { "primary": "project/model" } } },
        } : Json).stringify(),
    )
    @fsx.write_to_file(
      product_config,
      (
        {
          "agents": { "defaults": { "model": { "primary": "product/model" } } },
        } : Json).stringify(),
    )

    inspect(
      configured_primary_model(cwd, Some(dir)).unwrap_or(""),
      content="project/model",
    )
  })
}
