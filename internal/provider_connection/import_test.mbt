///|
async test "invalid descriptor is rejected before service lookup" {
  assert_true(
    @provider_connection.import_connection("/unused", Json::empty_object())
    is Err(InvalidDescriptor),
  )
}
