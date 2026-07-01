///|
pub fn moonclaw_product_home(home : String) -> String {
  @moonsuite.product_dir(
    @moonsuite.suite_root_for_workspace_root(home),
    "moonclaw",
  )
}

///|
pub fn moonclaw_jobs_root(home : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(home, "moonclaw", "jobs")
}
