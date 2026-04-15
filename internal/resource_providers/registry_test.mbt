///|
async test "load_resource_providers prefers cwd manifest over home manifest" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let home_dir = mock.cwd.path() |> @pathx.join("home")
    @fsx.make_directory(
      mock.cwd.path() |> @pathx.join(".moonclaw"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      home_dir |> @pathx.join(".moonclaw"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      home_dir |> @pathx.join(".moonclaw") |> @pathx.join("providers.json"),
      (
        #|[
        #|  {
        #|    "name": "slides-main",
        #|    "title": "Home Slides",
        #|    "description": "Home provider",
        #|    "kind": "renderer"
        #|  }
        #|]
      ),
    )
    @fsx.write_to_file(
      mock.cwd.path()
      |> @pathx.join(".moonclaw")
      |> @pathx.join("providers.json"),
      (
        #|[
        #|  {
        #|    "name": "slides-main",
        #|    "title": "Workspace Slides",
        #|    "description": "Workspace provider",
        #|    "kind": "renderer",
        #|    "endpoint": "https://slides.example/api"
        #|  },
        #|  {
        #|    "name": "research-kb",
        #|    "title": "Research KB",
        #|    "description": "Knowledge source",
        #|    "kind": "knowledge_base"
        #|  }
        #|]
      ),
    )
    let providers = load_resource_providers(
      mock.cwd.path(),
      home=Some(home_dir),
    )
    inspect(providers.length().to_string(), content="2")
    inspect(providers[0].title, content="Workspace Slides")
    inspect(providers[1].name, content="research-kb")
  })
}

///|
async test "load_resource_providers discovers parent workspace manifests" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let workspace_root = mock.cwd.path() |> @pathx.join("workspace")
    let run_dir = workspace_root
      |> @pathx.join("moonclaw-jobs")
      |> @pathx.join("run-1")
    @fsx.make_directory(
      workspace_root |> @pathx.join(".moonclaw"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(run_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      workspace_root
      |> @pathx.join(".moonclaw")
      |> @pathx.join("providers.json"),
      (
        #|[
        #|  {
        #|    "name": "wiki-main",
        #|    "title": "Workspace Wiki",
        #|    "description": "Parent workspace provider",
        #|    "kind": "extension",
        #|    "capabilities": ["provider.task"]
        #|  }
        #|]
      ),
    )
    let providers = load_resource_providers(run_dir, home=None)
    inspect(providers.length().to_string(), content="1")
    inspect(providers[0].name, content="wiki-main")
  })
}
