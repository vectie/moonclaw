///|
async test "analysis request owns live command before any terminal executor receipt" {
  @fsx.with_temporary_directory("analysis-live-owner-XXXXXX", dir => {
    let dir = @fs.realpath(dir)
    @fs.write_file(dir + "/executor.json", "{}", create_mode=CreateNew)
    let config = @execution_sandbox.local_sandbox_executor_config(
      "/usr/bin/true",
      "/usr/bin/true",
      dir + "/executor.json",
      dir,
      "fixture-workspace",
    )
    let calls = Ref(0)
    let agent = @agent.new(
      @model.Model::new(
        api_key="",
        base_url="https://example.invalid/v1",
        name="fixture-model",
        safe_zone_tokens=4096,
      ),
      cwd=dir,
      home=dir,
      user_message="Run the scoped fixture command.",
      logger=@pino.logger("live-owner-fixture", @pino.Transport::console()),
      chat_transport=(_, _) => {
        calls.val += 1
        if calls.val == 1 {
          @json.from_json({
            "id": "live-fixture",
            "model": "fixture-model",
            "choices": [
              {
                "index": 0,
                "message": {
                  "role": "assistant",
                  "content": "",
                  "tool_calls": [
                    {
                      "id": "call-1",
                      "type": "function",
                      "function": {
                        "name": "execute_command",
                        "arguments": "{\"command\":\"printf fixture\",\"run_id\":\"forged\",\"step_id\":\"forged\"}",
                      },
                    },
                  ],
                },
                "finish_reason": "tool_calls",
              },
            ],
          })
        } else {
          let outputs = @execution_sandbox.list_bound_command_live_outputs(
            config, "analysis-run",
          )
          assert_eq(outputs.length(), 1)
          assert_eq(outputs[0].step_id, "analysis-step")
          assert_true(
            @execution_sandbox.list_bound_command_live_outputs(config, "forged").is_empty(),
          )
          assert_true(
            @execution_sandbox.list_bound_command_outputs(
              config, "analysis-run", 0L,
            ).is_empty(),
          )
          // The inert publisher produces no protocol response. No executor or
          // shell command ran, yet trusted pre-dispatch ownership is durable.
          @json.from_json({
            "id": "done",
            "model": "fixture-model",
            "choices": [
              {
                "index": 0,
                "message": {
                  "role": "assistant",
                  "content": "Fixture stopped before execution.",
                },
                "finish_reason": "stop",
              },
            ],
          })
        }
      },
    )
    let request : AnalysisRequest = {
      job_id: "job-fixture",
      run_id: "analysis-run",
      step_id: "analysis-step",
      source_prompt: "fixture",
      prompt: "fixture",
      model_name: "fixture-model",
      cwd: dir,
      home: Some(dir),
      execution_mode: None,
      execution_target: None,
      system_prompt: "fixture",
      preferred_skills: [],
      enable_tools: true,
      web_search: false,
      tool_contract: AnalysisToolContract::new(
        shell=true,
        list_files=false,
        read_files=false,
        search_files=false,
        todo=false,
        file_write=false,
        web_search=false,
      ),
      step_metadata: {},
      execution_isolation: None,
      role_runtime_contract: None,
    }
    configure_analysis_agent_for_request(agent, request, sandbox_config=config)
    agent.start()
    assert_eq(calls.val, 2)
  })
}
