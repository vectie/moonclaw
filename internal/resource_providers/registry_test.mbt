///|
async test "load_resource_providers prefers workspace product manifest over home manifest" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let home_dir = mock.cwd.path() |> @pathx.join("home")
    let home_manifest = @moonsuite.product_artifact_for_workspace_root(
      home_dir, "moonclaw", "providers.json",
    )
    let workspace_manifest = @moonsuite.product_artifact_for_workspace_root(
      mock.cwd.path(),
      "moonclaw",
      "providers.json",
    )
    @fsx.make_directory(
      @pathx.dirname(home_manifest),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.dirname(workspace_manifest),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      home_manifest,
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
      workspace_manifest,
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
async test "load_resource_providers ignores legacy home manifest" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let home_dir = mock.cwd.path() |> @pathx.join("home")
    let product_manifest = @moonsuite.product_artifact_for_workspace_root(
      home_dir, "moonclaw", "providers.json",
    )
    @fsx.make_directory(
      home_dir |> @pathx.join(".moonclaw"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.dirname(product_manifest),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      home_dir |> @pathx.join(".moonclaw") |> @pathx.join("providers.json"),
      (
        #|[
        #|  {
        #|    "name": "slides-main",
        #|    "title": "Legacy Home Slides",
        #|    "kind": "renderer"
        #|  }
        #|]
      ),
    )
    @fsx.write_to_file(
      product_manifest,
      (
        #|[
        #|  {
        #|    "name": "slides-main",
        #|    "title": "Product Home Slides",
        #|    "kind": "renderer"
        #|  }
        #|]
      ),
    )

    let providers = load_resource_providers(
      mock.cwd.path(),
      home=Some(home_dir),
    )
    inspect(providers.length().to_string(), content="1")
    inspect(providers[0].title, content="Product Home Slides")
  })
}

///|
async test "load_resource_providers discovers parent workspace manifests" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let workspace_root = mock.cwd.path() |> @pathx.join("workspace")
    @fsx.make_directory(workspace_root, recursive=true, exists_ok=true)
    let run_dir = @job.moonclaw_jobs_root(workspace_root)
      |> @pathx.join("run-1")
    @fsx.make_directory(
      @pathx.dirname(
        @moonsuite.product_artifact_for_workspace_root(
          workspace_root, "moonclaw", "providers.json",
        ),
      ),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(run_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      @moonsuite.product_artifact_for_workspace_root(
        workspace_root, "moonclaw", "providers.json",
      ),
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

///|
async test "load_resource_providers resolves suite book workspace provider home" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let suite_root = mock.cwd.path() |> @pathx.join("suite")
    let book_root = suite_root
      |> @pathx.join("books")
      |> @pathx.join("research-book")
    let code_dir = book_root |> @pathx.join("code")
    let manifest = @moonsuite.product_artifact_for_workspace_root(
      book_root, "moonclaw", "providers.json",
    )
    @fsx.make_directory(
      @pathx.dirname(manifest),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(code_dir, recursive=true, exists_ok=true)
    @fsx.write_to_file(
      manifest,
      (
        #|[
        #|  {
        #|    "name": "book-provider",
        #|    "title": "Suite Book Provider",
        #|    "kind": "extension"
        #|  }
        #|]
      ),
    )
    @fsx.make_directory(
      book_root |> @pathx.join(".moonclaw"),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      book_root |> @pathx.join(".moonclaw") |> @pathx.join("providers.json"),
      (
        #|[
        #|  {
        #|    "name": "legacy-provider",
        #|    "title": "Legacy Book Provider",
        #|    "kind": "extension"
        #|  }
        #|]
      ),
    ) catch {
      _ => ()
    }
    let providers = load_resource_providers(code_dir, home=None)
    inspect(providers.length().to_string(), content="1")
    inspect(providers[0].name, content="book-provider")
  })
}

///|
async test "load_resource_providers separates book targets from model providers" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let suite_root = mock.cwd.path() |> @pathx.join("suite")
    let book_root = suite_root
      |> @pathx.join("books")
      |> @pathx.join("research-book")
    let model_manifest = @moonsuite.product_artifact_for_workspace_root(
      suite_root, "moonclaw", "providers.json",
    )
    let resource_manifest = @pathx.join(book_root, ".moonsuite")
      |> @pathx.join("resource-providers.json")
    @fsx.make_directory(
      @pathx.dirname(model_manifest),
      recursive=true,
      exists_ok=true,
    )
    @fsx.make_directory(
      @pathx.dirname(resource_manifest),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      model_manifest,
      (
        {
          "providers": {
            "moongate": {
              "baseUrl": "http://127.0.0.1:15721/v1",
              "models": [{ "id": "gpt-5.5" }],
            },
          },
        } : Json).stringify(),
    )
    @fsx.write_to_file(
      resource_manifest,
      (
        #|[
        #|  {
        #|    "name": "moonbook",
        #|    "title": "Book-local provider",
        #|    "kind": "task-provider",
        #|    "capabilities": ["extension.task"],
        #|    "metadata": {"workspace_root": "BOOK_ROOT"}
        #|  }
        #|]
      )
      .replace(old="BOOK_ROOT", new=book_root)
      .to_string(),
    )
    let providers = load_resource_providers(book_root, home=Some(suite_root))
    assert_eq(providers.length(), 1)
    assert_eq(providers[0].name, "moonbook")
    assert_true(
      match providers[0].metadata {
        { "workspace_root": String(root), .. } => root == book_root
        _ => false
      },
    )
  })
}
