///|
pub fn moonclaw_product_home(home : String) -> String {
  @moonsuite.product_dir(home, "moonclaw")
}

///|
pub fn moonclaw_jobs_root(home : String) -> String {
  @moonsuite.product_artifact(home, "moonclaw", "jobs")
}
