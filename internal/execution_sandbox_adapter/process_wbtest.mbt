///|
async test "adapter terminates output that exceeds its transport bound" {
  @fsx.with_temporary_directory("moonfort-adapter-bound-XXXXXX", async fn(cwd) {
    try
      run_adapter_process(
        "/usr/bin/yes",
        [],
        stdin="",
        timeout=5_000,
        cwd~,
        env={},
        stdout_limit=1_024,
      )
    catch {
      error => assert_true("\{error}".contains("output exceeds"))
    } noraise {
      _ => fail("unbounded adapter output was accepted")
    }
  })
}
