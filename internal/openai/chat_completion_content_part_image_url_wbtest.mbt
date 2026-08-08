///|
test "chat completion image URL content part round trips" {
  let part = image_url_content_part(
    "data:image/png;base64,iVBORw0KGgo=",
    detail="high",
  )
  let encoded = part.to_json()
  assert_true(encoded.stringify().contains("\"type\":\"image_url\""))
  let decoded : ChatCompletionContentPartParam = @json.from_json(encoded)
  assert_eq(decoded.to_json(), encoded)
}
