///|
async test "reply text is published before the provider completes and is coalesced" {
  let published : Array[String] = []
  let (result, streamed) = with_mooncode_reply_stream(
    emit => {
      emit("Hello")
      emit(", ")
      @async.sleep(200)
      assert_eq(published, ["Hello, "])
      emit("World!")
      "complete"
    },
    text => published.push(text),
    enabled=true,
  )
  assert_eq(result, "complete")
  assert_true(streamed)
  assert_eq(published, ["Hello, ", "World!"])
  let (_, disabled) = with_mooncode_reply_stream(
    emit => emit("not streamed"),
    text => published.push(text),
    enabled=false,
  )
  assert_false(disabled)
  assert_eq(published.length(), 2)
}
