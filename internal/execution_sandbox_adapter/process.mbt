///|
priv struct AdapterProcessResult {
  status : Int
  stdout : String
}

///|
async fn run_adapter_process(
  executable : String,
  arguments : Array[String],
  stdin~ : String,
  timeout~ : Int,
  cwd~ : String,
  env~ : Map[String, String],
  stdout_limit? : Int = 16 * 1024 * 1024,
) -> AdapterProcessResult {
  guard stdout_limit > 0 && stdout_limit <= 16 * 1024 * 1024 else {
    fail("MoonFort adapter output limit is invalid")
  }
  @async.with_task_group(group => {
    let (input, input_pipe) = @process.write_to_process()
    group.spawn_bg(() => {
      defer input_pipe.close()
      input_pipe.write(stdin)
    })
    let (stdout_pipe, stdout_output) = @process.read_from_process()
    let stdout_task = group.spawn(() => {
      defer stdout_pipe.close()
      let output = @buffer.Buffer(size_hint=stdout_limit.min(8_192))
      for ;; {
        guard stdout_pipe.read_some(
            max_len=(stdout_limit - output.length() + 1).min(8_192),
          )
          is Some(chunk) else {
          break
        }
        guard output.length() + chunk.length() <= stdout_limit else {
          fail("MoonFort adapter output exceeds the transport bound")
        }
        output.write_bytes(chunk)
      }
      @encoding/utf8.decode_lossy(output.to_bytes())
    })
    let status = @async.with_timeout(timeout, () => {
      @process.run(
        executable,
        arguments,
        cwd~,
        stdin=input,
        stdout=stdout_output,
        extra_env=env,
        inherit_env=false,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
    })
    { status, stdout: stdout_task.wait() }
  })
}
