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
