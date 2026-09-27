///|
test "image input is declared by catalog metadata rather than model name" {
  let named_vision = Model::new(
    api_key="",
    base_url="http://localhost",
    name="vision-by-name-only",
    safe_zone_tokens=0,
  )
  assert_false(named_vision.supports_image_input())
  let declared = Model::new(
    api_key="",
    base_url="http://localhost",
    name="plain-name",
    safe_zone_tokens=0,
    input_modalities=["text", "image"],
  )
  assert_true(declared.supports_image_input())
}
