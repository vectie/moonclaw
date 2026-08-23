///|
priv struct HostProcessResult {
  status : Int
  stdout : String
  stderr : String
  elapsed : Int
}

///|
async fn run_host_process(
  command : String,
  arguments : Array[String],
  stdin? : String,
  timeout? : Int,
  cwd? : String,
  env? : Map[String, String],
  inherit_env? : Bool = false,
) -> HostProcessResult {
  @async.with_task_group(group => {
    fn redirect_input(content : String) -> &@process.ProcessInput raise {
      let (input, pipe) = @process.write_to_process()
      group.spawn_bg(() => {
        defer pipe.close()
        pipe.write(content)
      })
      input
    }
    let stdin = stdin.map(redirect_input)
    fn redirect_output() raise {
      let (pipe, output) = @process.read_from_process()
      let task = group.spawn(() => {
        defer pipe.close()
        @encoding/utf8.decode_lossy(pipe.read_all().binary())
      })
      (task, output)
    }
    let stdout = redirect_output()
    let stderr = redirect_output()
    async fn run() -> Int {
      @process.run(
        command,
        arguments,
        cwd?=cwd.map(value => value[:]),
        stdin?,
        stdout=stdout.1,
        stderr=stderr.1,
        extra_env?=env,
        inherit_env~,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
    }
    let started = @clock.epoch.now()
    let status = match timeout {
      Some(timeout) => @async.with_timeout(timeout, run)
      None => run()
    }
    {
      status,
      stdout: stdout.0.wait(),
      stderr: stderr.0.wait(),
      elapsed: @clock.epoch.now().ms_since(started).to_int(),
    }
  })
}

///|
extern "c" fn trusted_getpid() -> Int = "moonbit_moonclaw_trusted_process_getpid"

///|
extern "c" fn trusted_getppid() -> Int = "moonbit_moonclaw_trusted_process_getppid"

///|
extern "c" fn trusted_kill(pid : Int, sig : Int) -> Int = "moonbit_moonclaw_trusted_process_kill"
