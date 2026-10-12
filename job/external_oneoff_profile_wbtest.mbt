///|
async test "oneoff executes exact selected profile ID when configured IDs share a family" {
  @fsx.with_temporary_directory("oneoff-profile-binding-XXXXXX", async fn(
    root,
  ) {
    let app = oneoff_test_app(root)
    let profiles : Map[String, Json] = Map([])
    for id in ["analyst", "reviewer"] {
      profiles[id] = {
        "family": "research",
        "role": "worker",
        "steps": [
          {
            "id": id + "-only",
            "title": id + " contribution",
            "kind": "job.analysis",
            "prompt_template": id + " exact profile: ${request}",
            "metadata": {
              "enable_tools": false,
              "disable_adaptive": true,
              "retry_max_attempts": 1,
            },
          },
        ],
      }
    }
    @fsx.write_to_file(
      root + "/moonclaw.jobs.json",
      ({ "jobs": { "profiles": Json::object(profiles) } } : Json).stringify(),
    )
    for selected in ["reviewer", "analyst"] {
      let path = oneoff_test_packet(
        root,
        "selected-" + selected,
        "Use retained evidence",
      )
      @fsx.write_to_file(
        path,
        @fsx.read_file(path).replace(old="town_single", new=selected),
      )
      let calls : Array[String] = []
      let executor = AnalysisExecutor::new(run=fn(request) {
        calls.push(request.step_id)
        Ok({
          model_name: "local-profile-fixture",
          content: "Executed " + request.step_id,
          conversation_id: None,
          usage: None,
          metadata: {},
        })
      })
      let receipt = match
        app.start_external_oneoff_file(path, analysis_executor=Some(executor)) {
        Ok(value) => value
        Err(error) => fail(error)
      }
      assert_eq(receipt.status, "Succeeded")
      assert_eq(calls, [selected + "-only"])
      let proposal = app
        .runtime()
        .store()
        .get_job_proposal(receipt.proposal_id)
        .unwrap()
      assert_eq(proposal.profile_id, Some(selected))
      assert_eq(proposal.steps[0].id, selected + "-only")
      assert_true(
        @fsx.read_file(receipt.workspace_dir.unwrap() + "/report.md").contains(
          "Executed " + selected + "-only",
        ),
      )
      assert_true(
        @fsx.read_file(
          app.runtime().store().root_dir() +
          "/oneoff/selected-" +
          selected +
          "/binding.json",
        ).contains("\"id\":\"" + selected + "\""),
      )
    }
  })
}
