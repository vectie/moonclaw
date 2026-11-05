///|
test "mooncode advertised endpoints are unique" {
  let endpoints = mooncode_native_capability_endpoints()
  for i, endpoint in endpoints {
    for j = i + 1; j < endpoints.length(); j = j + 1 {
      if endpoint == endpoints[j] {
        fail("duplicate endpoint: \{endpoint}")
      }
    }
  }
}
