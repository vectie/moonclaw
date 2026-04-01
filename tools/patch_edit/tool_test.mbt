///|
async test "patch_edit previews patch changes" {
  let tool = new("/tmp")
  let patch =
    #|*** Begin Patch
    #|*** Add File: hello.txt
    #|+hello
    #|*** End Patch
  let result = tool.call({ "mode": "preview", "patch": patch })
  guard result is Ok(output) else {
    fail("Expected Ok result but got: \{result}")
  }
  inspect(output.mode.to_json().stringify(), content="\"Preview\"")
  inspect(output.file_count.to_string(), content="1")
  inspect(output.added.join(","), content="hello.txt")
}

///|
async test "patch_edit applies patch changes" (t : @test.Test) {
  @mock.run(t, mock => {
    let tool = new(mock.cwd.path())
    let patch =
      #|*** Begin Patch
      #|*** Add File: hello.txt
      #|+hello
      #|*** End Patch
    let result = tool.call({ "mode": "apply", "patch": patch })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.mode.to_json().stringify(), content="\"Apply\"")
    inspect(
      @fsx.read_file(mock.cwd.path() |> @pathx.join("hello.txt")),
      content="hello\n",
    )
  })
}
