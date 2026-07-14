///|
/// Reports process health without loading models or probing optional services.
async fn Daemon::health(self : Daemon, w : @httpx.ResponseWriter) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(moonclaw_health_json(self.port).stringify())
}

///|
fn moonclaw_health_json(port : Int) -> Json {
  {
    "ok": true,
    "status": "ready",
    "service": "moonclaw",
    "version": @buildinfo.version,
    "port": port,
  }
}
