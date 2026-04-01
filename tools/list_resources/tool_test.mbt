///|
async test "list_resources lists file URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      "src": {
        "main.mbt": "fn main { () }",
        "lib": { "util.mbt": "fn util { () }" },
      },
    })
    let tool = new(mock.cwd.path(), home=Some(mock.cwd.path()))
    let result = tool.call({
      "kind": "file",
      "path": "src",
      "pattern": "**/*.mbt",
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.total_resources.to_string(), content="2")
    inspect(output.resources[0].uri.contains("file://"), content="true")
  })
}

///|
async test "list_resources lists skill URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      ".moonclaw": {
        "skills": {
          "demo-skill": {
            "SKILL.md": (
              #|---
              #|name: demo-skill
              #|description: Demo skill for listing resources.
              #|---
              #|
              #|Skill body.
            ),
          },
        },
      },
    })
    let tool = new(mock.cwd.path(), home=Some(mock.cwd.path()))
    let result = tool.call({ "kind": "skill", "max_results": 20 })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output.resources.map(r => r.uri).join(",").contains("skill://demo-skill"),
      content="true",
    )
  })
}

///|
async test "list_resources truncates file resource listings" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({ "a.txt": "a", "b.txt": "b", "c.txt": "c" })
    let tool = new(mock.cwd.path(), home=Some(mock.cwd.path()))
    let result = tool.call({
      "kind": "file",
      "pattern": "*.txt",
      "max_results": 2,
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.truncated.to_json().stringify(), content="true")
    inspect(output.resources.length().to_string(), content="2")
  })
}

///|
async test "list_resources lists worktree URIs" (t : @test.Test) {
  @mock.run(t, mock => {
    let repo = mock.cwd.path()
    @git.init_(repo)
    @fsx.write_to_file(@pathx.join(repo, "README.md"), "hello")
    @git.commit("init", ["README.md"], cwd=repo)
    let handle = @worktree.plan_worktree(repo, "Inspect docs")
    ignore(@worktree.create_worktree(handle))
    let tool = new(repo)
    let result = tool.call({ "kind": "worktree" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.total_resources.to_string(), content="1")
    inspect(output.resources[0].uri, content="worktree://inspect-docs")
    @worktree.remove_worktree(handle)
  })
}
