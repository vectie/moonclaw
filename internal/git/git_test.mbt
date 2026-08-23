///|
async test "clone fails closed without an ExecutionSandbox grant" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let result = Ok(
      @git.clone(
        "https://github.com/vectie/moonclaw.git",
        to=mock.cwd.path(),
        depth=1,
      ),
    ) catch {
      error => Err(error)
    }
    guard result is Err(error) else {
      @test.fail("expected git clone to fail closed")
    }
    assert_true(error.to_string().contains("ExecutionSandbox grant required"))
  })
}

///|
async test "commit" (t : @test.Test) {
  if @os.getenv("CI") is None {
    @mock.run(t, mock => {
      @git.init_(mock.cwd.path())
      mock.add_json_tree({ "file.txt": "Hello, Moonbit!" })
      @git.commit("Initial commit", ["file.txt"], cwd=mock.cwd.path())
    })
  }
}

///|
async test "generate_git_diff" (t : @test.Test) {
  @mock.run(t, _ => {
    let original =
      #|line 1
      #|line 2
      #|line 3
    let modified =
      #|line 1
      #|line 2 modified
      #|line 3
      #|line 4 added
    let diff = @git.generate_git_diff(original~, modified~)
    inspect(
      diff
      .split("\n")
      .drop_while(line => !line.contains("@@"))
      .collect()
      .join("\n"),
      content=(
        #|@@ -1,3 +1,4 @@
        #| line 1
        #|-line 2
        #|-line 3
        #|\ No newline at end of file
        #|+line 2 modified
        #|+line 3
        #|+line 4 added
        #|\ No newline at end of file
      ),
    )
  })
}

///|
async test "clone_with_invalid_depth" (t : @test.Test) {
  @mock.run(t, mock => {
    try {
      @git.clone(
        "https://github.com/vectie/moonclaw.git",
        to=mock.cwd.path(),
        depth=0,
      )
      @test.fail("Expected error for invalid depth")
    } catch {
      error => {
        let error_str = error.to_string()
        if !error_str.contains("depth must be a positive integer") {
          @test.fail(
            "Expected 'depth must be a positive integer' error, got: \{error_str}",
          )
        }
      }
    }
  })
}
