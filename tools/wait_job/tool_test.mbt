///|
async test "wait_job reports missing job when host execution is disabled" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    let tool = @wait_job.new(manager)
    let result = tool.call({
      "job_id": 0,
      "timeout": 5000,
      "max_output_lines": 2,
    })
    guard result is Error(_, message) else {
      fail("Expected Err result but got: \{result}")
    }
    inspect(message, content="Job with ID 0 does not exist")
  })
}
