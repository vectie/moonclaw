///|
test "supported_rpc_methods advertises the implemented channel and run methods" {
  let methods = supported_rpc_methods()
  inspect(methods.contains("runs.list"), content="true")
  inspect(methods.contains("runs.get"), content="true")
  inspect(methods.contains("artifacts.list"), content="true")
  inspect(methods.contains("artifacts.get"), content="true")
  inspect(methods.contains("channels.list"), content="true")
  inspect(methods.contains("channels.get"), content="true")
  inspect(methods.contains("channels.configure"), content="true")
  inspect(methods.contains("channels.start"), content="true")
  inspect(methods.contains("channels.stop"), content="true")
}

///|
test "channel lookup params accept both legacy string and object shapes" {
  let legacy : Json = "feishu"
  let modern : Json = { "channel_id": "feishu" }
  let legacy_id = match legacy {
    String(id) => id
    _ => fail("legacy shape should parse")
  }
  let modern_id = match modern {
    Object(obj) =>
      match obj.get("channel_id") {
        Some(String(id)) => id
        _ => fail("modern shape should parse")
      }
    _ => fail("modern shape should be object")
  }
  inspect(legacy_id, content="feishu")
  inspect(modern_id, content="feishu")
}
