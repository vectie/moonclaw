///|
async test "read_resource reads file URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({ "notes.txt": "hello from resource tool" })
    let tool = new(mock.cwd.path(), home=Some(mock.moon_home))
    let result = tool.call({ "uri": "file://notes.txt" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.kind.to_json().stringify(), content="\"File\"")
    inspect(output.text, content="hello from resource tool")
  })
}

///|
async test "read_resource reads skill URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    let skill_dir = mock.cwd.path()
      |> @pathx.join(".moonsuite")
      |> @pathx.join("products")
      |> @pathx.join("moonclaw")
      |> @pathx.join("skills")
      |> @pathx.join("demo-skill")
    @fsx.make_directory(skill_dir, recursive=true)
    @fsx.write_to_file(
      skill_dir |> @pathx.join("SKILL.md"),
      (
        #|---
        #|name: demo-skill
        #|description: Demo skill for resource reading.
        #|---
        #|
        #|This is the demo skill body.
      ),
    )
    let tool = new(mock.cwd.path(), home=Some(mock.moon_home))
    let result = tool.call({ "uri": "skill://demo-skill" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.kind.to_json().stringify(), content="\"Skill\"")
    inspect(output.metadata.stringify().contains("demo-skill"), content="true")
    inspect(output.text.contains("demo skill body"), content="true")
  })
}

///|
async test "read_resource truncates text" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({ "long.txt": "abcdefghijklmnopqrstuvwxyz" })
    let tool = new(mock.cwd.path(), home=Some(mock.moon_home))
    let result = tool.call({ "uri": "file://long.txt", "max_chars": 100 })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.truncated.to_json().stringify(), content="false")
    inspect(output.text, content="abcdefghijklmnopqrstuvwxyz")
  })
}

///|
async test "read_resource reads worktree URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    let repo = mock.cwd.path()
    @git.init_(repo)
    @fsx.write_to_file(@pathx.join(repo, "README.md"), "hello")
    @git.commit("init", ["README.md"], cwd=repo)
    let handle = @worktree.plan_worktree(repo, "Inspect docs")
    ignore(@worktree.create_worktree(handle))
    let tool = new(repo)
    let result = tool.call({ "uri": "worktree://inspect-docs" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.kind.to_json().stringify(), content="\"Worktree\"")
    inspect(
      output.metadata.stringify().contains("moonclaw/inspect-docs"),
      content="true",
    )
    @worktree.remove_worktree(handle)
  })
}

///|
async test "read_resource reads provider URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    let manifest_path = @moonsuite.product_artifact_for_workspace_root(
      mock.cwd.path(),
      "moonclaw",
      "providers.json",
    )
    @fsx.make_directory(
      @pathx.dirname(manifest_path),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(
      manifest_path,
      (
        #|[
        #|  {
        #|    "name": "slides-main",
        #|    "title": "Slides Main",
        #|    "description": "Presentation renderer",
        #|    "kind": "renderer",
        #|    "endpoint": "https://slides.example/api",
        #|    "docs_uri": "https://slides.example/docs"
        #|  }
        #|]
      ),
    )
    let tool = new(mock.cwd.path(), home=Some(mock.moon_home))
    let result = tool.call({ "uri": "provider://slides-main" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.kind.to_json().stringify(), content="\"Provider\"")
    inspect(
      output.text.contains("Endpoint: https://slides.example/api"),
      content="true",
    )
  })
}
