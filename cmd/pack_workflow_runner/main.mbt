///|
async fn main {
  let args = @os.args()
  let arguments = args[1:]
  if arguments is ["--help" | "-h"] {
    @stdio.stdout.write(pack_workflow_runner_usage())
    return
  }
  let options = match parse_pack_workflow_runner_args(arguments) {
    Ok(options) => options
    Err(error) => {
      let result = pack_workflow_runner_argument_error(error)
      @stdio.stdout.write(result.to_json().stringify() + "\n")
      @os.exit(2)
    }
  }
  let stdin_text = if options.uses_stdin() {
    @stdio.stdin.read_all().text()
  } else {
    ""
  }
  let result = execute_pack_workflow_runner(options, stdin_text~)
  @stdio.stdout.write(result.to_json().stringify() + "\n")
  if !result.ok {
    @os.exit(1)
  }
}
