///|
test "MoonGate text-only capability reaches model and survives JSON roundtrip" {
  let catalog = @moongate.MoonGateModel::from_json({
    "id": "gemini-4-neon",
    "input_modalities": ["text"],
    "moongate": { "text_only": true },
  }).unwrap()
  let model = model_from_moongate_catalog("http://127.0.0.1", catalog)
  assert_true(model.text_only)
  let restored : Model = @json.from_json(model.to_json())
  assert_true(restored.text_only)
  let ordinary = @moongate.MoonGateModel::from_json({ "id": "gemini-4-neon" }).unwrap()
  assert_false(
    model_from_moongate_catalog("http://127.0.0.1", ordinary).text_only,
  )
}
