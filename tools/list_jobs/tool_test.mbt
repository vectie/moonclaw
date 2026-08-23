///|
async test "list_jobs is empty when background host execution is disabled" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    let tool = @list_jobs.new(manager)
    let result = tool.call({})
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(mock.show(output), content="")
  })
}
