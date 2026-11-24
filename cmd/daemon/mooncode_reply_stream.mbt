///|
// Use the canonical assistant_delta journal lane. Coalesce short token bursts
// so streaming does not turn into a synchronous disk append per token.
async fn[T] with_mooncode_reply_stream(
  run : async ((String) -> Unit) -> T,
  publish : async (String) -> Unit,
  enabled~ : Bool,
) -> (T, Bool) {
  if !enabled {
    return (run(_ => ()), false)
  }
  let chunks : @aqueue.Queue[String?] = @aqueue.Queue(kind=Unbounded)
  let mut streamed = false
  let result = @async.with_task_group(group => {
    group.spawn_bg(() => {
      let mut done = false
      while !done {
        match chunks.get() {
          None => break
          Some(first) => {
            let batch = StringBuilder()
            batch.write_string(first)
            @async.sleep(75)
            while chunks.try_get() is Some(next) {
              match next {
                None => {
                  done = true
                  break
                }
                Some(text) => batch.write_string(text)
              }
            }
            let text = batch.to_string()
            if text != "" {
              publish(text)
              streamed = true
            }
          }
        }
      }
    })
    let result = run(text => {
      if text != "" {
        // A failed/cancelled producer must not crash in a callback after teardown.
        ignore(chunks.try_put(Some(text))) catch {
          _ => ()
        }
      }
    })
    chunks.put(None)
    result
  })
  (result, streamed)
}
