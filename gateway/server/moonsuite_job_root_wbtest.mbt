///|
async test "Gateway uses moonsuite product home for job runtime root" {
  @fsx.with_temporary_directory("gateway-moonsuite-jobs-XXXXXX", dir => {
    let home = dir + "/home"
    let cwd = dir + "/workspace"
    @fsx.make_directory(cwd, recursive=true, exists_ok=true) catch {
      error => abort("failed to create gateway cwd: \{error}")
    }
    let gateway = Gateway::new(port=0, cwd=cwd[:], home=home[:], auth={
      token: Some("test-token"),
      _password: None,
    })
    let root = gateway.job_runtime().store().root_dir()
    assert_eq(root, @job.moonclaw_jobs_root(home))
    assert_true(
      !root.has_suffix("/jobs") ||
      root.contains("/.moonsuite/products/moonclaw/jobs"),
    )
    assert_true(!(@fsx.exists(home + "/jobs") catch { _ => false }))
  })
}
