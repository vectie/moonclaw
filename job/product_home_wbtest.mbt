///|
test "moonclaw jobs root uses moonsuite product home" {
  let home = "/tmp/moonclaw-home"
  assert_eq(
    moonclaw_product_home(home),
    "/tmp/moonclaw-home/.moonsuite/products/moonclaw",
  )
  assert_eq(
    moonclaw_jobs_root(home),
    "/tmp/moonclaw-home/.moonsuite/products/moonclaw/jobs",
  )
  assert_eq(
    detached_run_input_dir(home),
    "/tmp/moonclaw-home/.moonsuite/products/moonclaw/jobs/detached-inputs",
  )
}
