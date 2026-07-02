///|
fn moonclaw_product_id() -> String {
  "moonclaw"
}

///|
pub fn moonclaw_product_home(home : String) -> String {
  @moonsuite.product_home_for_workspace_root(home, moonclaw_product_id()).state_path
}

///|
fn moonclaw_product_tmp_dir(home : String) -> String {
  @moonsuite.product_home_for_workspace_root(home, moonclaw_product_id()).tmp_path
}

///|
pub fn moonclaw_jobs_root(home : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    home,
    moonclaw_product_id(),
    "jobs",
  )
}
