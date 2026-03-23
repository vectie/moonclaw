///|
fn sample_profiles_json() -> Json {
  {
    "jobs": {
      "profiles": {
        "research_controller": {
          "role": "controller",
          "priority": 100,
          "job_kind": "job.controller",
          "workflow_kind": "job.controller",
          "tags": ["research", "controller"],
          "match": {
            "any": ["research", "paper", "hypothesis"],
            "all": ["vla"],
          },
          "steps": [
            {
              "id": "collect",
              "title": "Collect evidence",
              "kind": "job.delegate",
              "request_template": "Collect evidence for: ${request}",
              "child_profile": "research_worker",
              "execution_mode": "acp",
              "execution_target": "codex-research",
              "include_parent_outputs": false,
              "max_depth": 3,
            },
            {
              "id": "evaluate",
              "title": "Evaluate evidence",
              "kind": "job.analysis",
              "prompt_template": "Evaluate collected evidence for request: ${request}",
            },
          ],
          "metadata": { "domain": "research" },
        },
      },
    },
  }
}

///|
async test "load_job_profile reads controller profile from moonclaw.jobs.json" {
  @fsx.with_temporary_directory("job-profile-load-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_profiles_json().stringify(),
    )
    let profile = match load_job_profile(dir, dir, "research_controller") {
      Some(profile) => profile
      None => fail("expected profile")
    }
    inspect(profile.role.unwrap_or(""), content="controller")
    inspect(profile.steps.length(), content="2")
    inspect(
      profile.steps[0].child_profile.unwrap_or(""),
      content="research_worker",
    )
    inspect(profile.steps[0].execution_mode.unwrap_or(""), content="acp")
    inspect(
      profile.steps[0].execution_target.unwrap_or(""),
      content="codex-research",
    )
    inspect(profile.tags.join(","), content="research,controller")
  })
}

///|
async test "suggest_job_profile_family matches configured request rules" {
  @fsx.with_temporary_directory("job-profile-match-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_profiles_json().stringify(),
    )
    inspect(
      suggest_job_profile_family(
        "Research VLA papers and form a hypothesis log.", dir, dir,
      ).unwrap_or(""),
      content="research_controller",
    )
    inspect(
      suggest_job_profile_family("Track infra incidents.", dir, dir) is None,
      content="true",
    )
  })
}
