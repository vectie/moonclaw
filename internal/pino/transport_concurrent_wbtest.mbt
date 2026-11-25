///|
async test "Transport::file serializes concurrent async writes without panicking" {
  let tmp_dir = @os.tmpdir()
  let path = @pathx.join(tmp_dir, "moonclaw-pino-concurrent-wbtest.jsonl")
  if @fs.exists(path) {
    @fs.remove(path)
  }
  let transport = Transport::file(path)
  let log = logger("concurrent", transport)
  @async.with_task_group(group => {
    for i in 0..<16 {
      let idx = i
      group.spawn_bg(() => {
        log.info("concurrent line \{idx}", data={ "index": idx })
      })
    }
  })
  transport.close()
  let content = @fs.read_file(path).text()
  @fs.remove(path)
  let mut line_count = 0
  for line in content.split("\n") {
    if !line.trim().is_empty() {
      line_count += 1
    }
  }
  assert_eq(line_count, 16)
}
