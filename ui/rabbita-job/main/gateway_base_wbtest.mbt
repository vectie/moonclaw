///|
test "gateway base prefers a valid host-supplied runtime endpoint" {
  inspect(
    resolve_gateway_base(
      "https://runtime.example.test/moonclaw/", "http://127.0.0.1:18123", "https://desk.example.test",
    ),
    content="https://runtime.example.test/moonclaw",
  )
}

///|
test "gateway base defaults to the current published origin" {
  inspect(
    resolve_gateway_base("", "", "http://127.0.0.1:4317"),
    content="http://127.0.0.1:4317",
  )
}

///|
test "explicit gateway override is limited to the current or loopback host" {
  inspect(
    resolve_gateway_base("", "http://localhost:18123/", "http://127.0.0.1:4317"),
    content="http://localhost:18123",
  )
  inspect(
    resolve_gateway_base(
      "", "https://untrusted.example.test", "https://desk.example.test",
    ),
    content="https://desk.example.test",
  )
}

///|
test "gateway base rejects credentials, query secrets and active schemes" {
  inspect(
    resolve_gateway_base(
      "https://user:secret@runtime.example.test", "", "https://desk.example.test",
    ),
    content="https://desk.example.test",
  )
  inspect(
    resolve_gateway_base(
      "https://runtime.example.test?token=secret", "", "https://desk.example.test",
    ),
    content="https://desk.example.test",
  )
  inspect(
    resolve_gateway_base("javascript:alert(1)", "", "http://127.0.0.1:4317"),
    content="http://127.0.0.1:4317",
  )
}
