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
async test "built-in robot routine profile exposes MoonClaw policy lane" {
  @fsx.with_temporary_directory("job-profile-robot-builtin-XXXXXX", async fn(
    dir,
  ) {
    let profile = match load_job_profile(dir, dir, "robot_routine") {
      Some(profile) => profile
      None => fail("expected built-in robot profile")
    }
    inspect(profile.role.unwrap_or(""), content="robot")
    inspect(profile.steps.length(), content="1")
    inspect(profile.steps[0].kind, content="robot.routine.run")
    inspect(
      profile.steps[0].execution_target.unwrap_or(""),
      content="/v1/robot/routine/run",
    )
    inspect(
      profile.metadata.stringify().contains("\"policy_owner\":\"moonclaw\""),
      content="true",
    )
  })
}

///|
async test "suggest_job_profile_family matches built-in robot lane" {
  @fsx.with_temporary_directory("job-profile-robot-match-XXXXXX", async fn(
    dir,
  ) {
    inspect(
      suggest_job_profile_family(
        "Ask the robot to inspect the Moonrobo physical gateway.", dir, dir,
      ).unwrap_or(""),
      content="robot_routine",
    )
  })
}

///|
async test "configured profile overrides built-in robot routine profile" {
  @fsx.with_temporary_directory("job-profile-robot-override-XXXXXX", async fn(
    dir,
  ) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      (
        #|{
        #|  "jobs": {
        #|    "profiles": {
        #|      "robot_routine": {
        #|        "family": "robot_routine",
        #|        "role": "robot",
        #|        "priority": 220,
        #|        "tags": ["robot", "custom"],
        #|        "steps": [
        #|          {
        #|            "id": "custom_robot_step",
        #|            "title": "Custom robot policy step",
        #|            "kind": "robot.routine.custom"
        #|          }
        #|        ]
        #|      }
        #|    }
        #|  }
        #|}
      ),
    )
    let profile = match load_job_profile(dir, dir, "robot_routine") {
      Some(profile) => profile
      None => fail("expected configured robot profile")
    }
    inspect(profile.priority, content="220")
    inspect(profile.steps[0].kind, content="robot.routine.custom")
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

///|
fn sample_wiki_profiles_json() -> Json {
  {
    "jobs": {
      "profiles": {
        "wiki_ingest_controller": {
          "family": "wiki_ingest_controller",
          "role": "controller",
          "priority": 130,
          "tags": ["wiki", "maintainer", "ingest"],
          "match": { "all": ["wiki"], "any": ["ingest", "source", "integrate"] },
          "steps": [
            {
              "id": "inspect_source",
              "title": "Inspect raw source and current wiki state",
              "kind": "job.analysis",
              "prompt_template": "Inspect wiki state for: ${request}",
              "metadata": {
                "preferred_skills": ["wiki-maintainer"],
                "enable_tools": true,
              },
            },
            {
              "id": "apply_revisions",
              "title": "Apply wiki revisions",
              "kind": "job.delegate",
              "request_template": "Apply wiki edits for: ${request}",
              "child_profile": "wiki_revision_worker",
              "include_parent_outputs": true,
              "max_depth": 3,
            },
          ],
        },
      },
    },
  }
}

///|
async test "suggest_job_profile_family matches wiki maintainer profile rules" {
  @fsx.with_temporary_directory("job-profile-wiki-match-XXXXXX", async fn(dir) {
    @fsx.write_to_file(
      @pathx.join(dir, "moonclaw.jobs.json"),
      sample_wiki_profiles_json().stringify(),
    )
    inspect(
      suggest_job_profile_family(
        "Ingest this source into the wiki and revise the relevant pages.", dir, dir,
      ).unwrap_or(""),
      content="wiki_ingest_controller",
    )
    inspect(
      suggest_job_profile_family("Ingest this source into notes.", dir, dir)
      is None,
      content="true",
    )
  })
}
