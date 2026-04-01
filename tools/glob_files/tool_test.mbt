///|
async test "glob_files matches recursive paths" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      "src": {
        "main.mbt": "fn main { () }",
        "lib": { "util.mbt": "fn util { () }", "util.txt": "note" },
      },
    })
    let tool = new(mock.cwd.path())
    let result = tool.call({ "path": "src", "pattern": "**/*.mbt" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    json_inspect(output, content={
      "root": "src",
      "pattern": "**/*.mbt",
      "matches": ["lib/util.mbt", "main.mbt"],
      "total_matches": 2,
      "truncated": false,
      "respect_gitignore": false,
    })
  })
}

///|
async test "glob_files respects gitignore when available" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({
      ".gitignore": "ignored/*.mbt\n",
      "visible": { "keep.mbt": "fn keep { () }" },
      "ignored": { "skip.mbt": "fn skip { () }" },
    })
    let tool = new(mock.cwd.path())
    let result = tool.call({ "pattern": "**/*.mbt" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.matches.join(","), content="visible/keep.mbt")
  })
}

///|
async test "glob_files can include directories" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({ "docs": { "guide": { "index.md": "# Guide" } } })
    let tool = new(mock.cwd.path())
    let result = tool.call({
      "pattern": "**/guide",
      "include_directories": true,
      "respect_gitignore": false,
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.matches.join(","), content="docs/guide")
  })
}
