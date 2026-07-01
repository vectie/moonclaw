///|
pub fn moonclaw_product_home(home : String) -> String {
  home
  |> @pathx.join(".moonsuite")
  |> @pathx.join("products")
  |> @pathx.join("moonclaw")
}

///|
pub fn moonclaw_jobs_root(home : String) -> String {
  moonclaw_product_home(home) |> @pathx.join("jobs")
}
