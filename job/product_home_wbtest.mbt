///|
test "moonclaw jobs root uses moonsuite product home" {
  let suite_root = "/tmp/moonclaw-suite"
  let home = suite_root + "/books/research-demo"
  assert_eq(
    moonclaw_product_home(home),
    "/tmp/moonclaw-suite/.moonsuite/products/moonclaw",
  )
  assert_eq(
    moonclaw_jobs_root(home),
    "/tmp/moonclaw-suite/.moonsuite/products/moonclaw/jobs",
  )
  assert_eq(
    detached_run_input_dir(home),
    "/tmp/moonclaw-suite/.moonsuite/products/moonclaw/jobs/detached-inputs",
  )
  assert_false(
    moonclaw_jobs_root(home).contains("/books/research-demo/.moonsuite"),
  )
}
