///|
test "supported_rpc_methods advertises the implemented channel and run methods" {
  let methods = supported_rpc_methods()
  inspect(methods.contains("runs.list"), content="true")
  inspect(methods.contains("runs.get"), content="true")
  inspect(methods.contains("artifacts.list"), content="true")
  inspect(methods.contains("artifacts.get"), content="true")
  inspect(methods.contains("workspace.get"), content="true")
  inspect(methods.contains("plugins.list"), content="true")
  inspect(methods.contains("plugins.get"), content="true")
  inspect(methods.contains("memories.list"), content="true")
  inspect(methods.contains("memories.get"), content="true")
  inspect(methods.contains("memories.create"), content="true")
  inspect(methods.contains("memories.search"), content="true")
  inspect(methods.contains("jobs.list"), content="true")
  inspect(methods.contains("jobs.get"), content="true")
  inspect(methods.contains("jobs.create"), content="true")
  inspect(methods.contains("jobs.update"), content="true")
  inspect(methods.contains("jobs.run"), content="true")
  inspect(methods.contains("jobs.cancel"), content="true")
  inspect(methods.contains("jobs.force_cancel"), content="true")
  inspect(methods.contains("jobs.runs.list"), content="true")
  inspect(methods.contains("jobs.runs.get"), content="true")
  inspect(methods.contains("jobs.ui.get"), content="true")
  inspect(methods.contains("jobs.ui.events"), content="true")
  inspect(methods.contains("jobs.ask"), content="true")
  inspect(methods.contains("channels.list"), content="true")
  inspect(methods.contains("channels.get"), content="true")
  inspect(methods.contains("channels.configure"), content="true")
  inspect(methods.contains("channels.start"), content="true")
  inspect(methods.contains("channels.stop"), content="true")
  inspect(methods.contains("acp.targets.list"), content="true")
  inspect(methods.contains("acp.targets.get"), content="true")
  inspect(methods.contains("acp.sessions.list"), content="true")
  inspect(methods.contains("acp.sessions.get"), content="true")
  inspect(methods.contains("acp.sessions.create"), content="true")
  inspect(methods.contains("acp.sessions.reset"), content="true")
  inspect(methods.contains("acp.sessions.run"), content="true")
  inspect(methods.contains("acp.runs.list"), content="true")
  inspect(methods.contains("acp.runs.get"), content="true")
  inspect(methods.contains("acp.runs.cancel"), content="true")
  inspect(methods.contains("acp.ui.get"), content="true")
  inspect(methods.contains("acp.ui.events"), content="true")
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
