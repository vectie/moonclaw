///|
fn fixture_skills(loader : @skills.Loader) -> Map[String, @skills.Skill] {
  loader
  .skills()
  .filter(fn(_, skill) { !skill.location.contains("/skills/.system/") })
}

///|
async test "load" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      ".moonsuite": {
        "products": {
          "moonclaw": {
            "skills": {
              "pdf-processing": {
                "SKILL.md": (
                  #|---
                  #|name: pdf-processing
                  #|description: A skill to process PDF documents.
                  #|version: 1.0.0
                  #|---
                  #|
                  #|Use this skill to extract text from PDF files.
                ),
              },
            },
          },
        },
      },
      "cwd": {
        ".git": {},
        ".moonsuite": {
          "products": {
            "moonclaw": {
              "skills": {
                "text-summarization": {
                  "SKILL.md": (
                    #|---
                    #|name: text-summarization
                    #|description: A skill to summarize text documents.
                    #|version: 1.0.0
                    #|---
                    #|
                    #|Use this skill to generate summaries of text content.
                  ),
                },
              },
            },
          },
        },
      },
    })
    let home = mock.cwd.path()
    let cwd = @pathx.join(home, "cwd")
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    json_inspect(mock.json(fixture_skills(loader)), content={
      "pdf-processing": {
        "id": "pdf-processing",
        "name": "pdf-processing",
        "description": "A skill to process PDF documents.",
        "allowed_tools": [],
        "location": "(mock:cwd)/.moonsuite/products/moonclaw/skills/pdf-processing/SKILL.md",
      },
      "text-summarization": {
        "id": "text-summarization",
        "name": "text-summarization",
        "description": "A skill to summarize text documents.",
        "allowed_tools": [],
        "location": "(mock:cwd)/cwd/.moonsuite/products/moonclaw/skills/text-summarization/SKILL.md",
      },
    })
    let messages = [
      @ai.system_message(content="You are an AI assistant."),
      @ai.user_message(content="Please help me process this PDF document."),
    ]
    loader.load_and_apply(messages)
    guard messages is [System(content), ..] else {
      fail(
        "Messages have wrong structure, expecting [System(content), ..], got \{messages.to_json().stringify(indent=2)}",
      )
    }
    assert_true(content.has_prefix("You are an AI assistant."))
    assert_true(content.contains("<available_skills>"))
    assert_true(content.contains("<id>pdf-processing</id>"))
    assert_true(content.contains("<id>text-summarization</id>"))
  })
}

///|
async test "load/empty" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      ".moonsuite": { "products": { "moonclaw": { "skills": {} } } },
      "cwd": {
        ".git": {},
        ".moonsuite": { "products": { "moonclaw": { "skills": {} } } },
      },
    })
    let home = mock.cwd.path()
    let cwd = @pathx.join(home, "cwd")
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    let messages = [
      @ai.system_message(content="You are an AI assistant."),
      @ai.user_message(content="Please help me process this PDF document."),
    ]
    loader.load_and_apply(messages)
    guard messages is [System(content), ..] else {
      fail(
        "Messages have wrong structure, expecting [System(content), ..], got \{messages.to_json().stringify(indent=2)}",
      )
    }
    assert_true(content.has_prefix("You are an AI assistant."))
    assert_true(content.contains("<available_skills>"))
    assert_true(fixture_skills(loader).is_empty())
  })
}

///|
async test "load/lowercase" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      ".moonsuite": {
        "products": {
          "moonclaw": {
            "skills": {
              "pdf-processing": {
                "skill.md": (
                  #|---
                  #|name: pdf-processing
                  #|description: A skill to process PDF documents.
                  #|version: 1.0.0
                  #|---
                  #|
                  #|Use this skill to extract text from PDF files.
                ),
              },
            },
          },
        },
      },
    })
    let home = mock.cwd.path()
    // Add a `.git` marker so the loader stops walking up before reaching `home`.
    let cwd = @pathx.join(home, "cwd")
    mock.add_json_tree({ "cwd": { ".git": {} } })
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    let messages = [
      @ai.system_message(content="You are an AI assistant."),
      @ai.user_message(content="Please help me process this PDF document."),
    ]
    loader.load_and_apply(messages)
    guard messages is [System(content), ..] else {
      fail(
        "Messages have wrong structure, expecting [System(content), ..], got \{messages.to_json().stringify(indent=2)}",
      )
    }
    assert_true(content.has_prefix("You are an AI assistant."))
    assert_true(content.contains("<available_skills>"))
    assert_true(fixture_skills(loader).contains("pdf-processing"))
  })
}

///|
async test "load/invalid-skill" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      ".moonsuite": {
        "products": {
          "moonclaw": {
            "skills": {
              "invalid-skill": {
                "SKILL.md": (
                  #|---
                  #|name: invalid-skill
                  #|---
                  #|
                  #|This skill has an invalid format.
                ),
              },
            },
          },
        },
      },
    })
    let home = mock.cwd.path()
    let cwd = @pathx.join(home, "cwd")
    mock.add_json_tree({ "cwd": { ".git": {} } })
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    let messages = [
      @ai.system_message(content="You are an AI assistant."),
      @ai.user_message(content="Please help me process this PDF document."),
    ]
    loader.load_and_apply(messages)
    guard messages is [System(content), ..] else {
      fail(
        "Messages have wrong structure, expecting [System(content), ..], got \{messages.to_json().stringify(indent=2)}",
      )
    }
    assert_true(content.has_prefix("You are an AI assistant."))
    assert_true(content.contains("<available_skills>"))
    assert_true(fixture_skills(loader).is_empty())
  })
}

///|
async test "reload" (t : @test.Test) {
  @mock.run(t, mock => {
    let skills = mock
      .add_directory(".moonsuite")
      .add_directory("products")
      .add_directory("moonclaw")
      .add_directory("skills")
    let pdf_processing = skills.add_directory("pdf-processing")
    let pdf_processing_skill = pdf_processing.add_file("SKILL.md")
    pdf_processing_skill.write_string(
      (
        #|---
        #|name: pdf-processing
        #|description: A skill to process PDF documents.
        #|version: 1.0.0
        #|---
        #|
        #|Use this skill to extract text from PDF files.
      ),
    )
    let home = mock.cwd.path()
    let cwd = @pathx.join(home, "cwd")
    // Mark `cwd` as a git repo so the loader stops there.
    mock.add_json_tree({ "cwd": { ".git": {} } })
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    json_inspect(mock.json(fixture_skills(loader)), content={
      "pdf-processing": {
        "id": "pdf-processing",
        "name": "pdf-processing",
        "description": "A skill to process PDF documents.",
        "allowed_tools": [],
        "location": "(mock:cwd)/.moonsuite/products/moonclaw/skills/pdf-processing/SKILL.md",
      },
    })
    // Update the skill
    pdf_processing_skill.write_string(
      (
        #|---
        #|name: pdf-processing
        #|description: An updated skill to process PDF documents.
        #|version: 1.1.0
        #|---
        #|
        #|Use this skill to extract text from PDF files with improved accuracy.
      ),
    )
    skills.add_json_tree({
      "text-summarization": {
        "SKILL.md": (
          #|---
          #|name: text-summarization
          #|description: A skill to summarize text documents.
          #|version: 1.0.0
          #|---
          #|
          #|Use this skill to generate summaries of text content.
        ),
      },
    })
    loader.load()
    json_inspect(mock.json(fixture_skills(loader)), content={
      "pdf-processing": {
        "id": "pdf-processing",
        "name": "pdf-processing",
        "description": "An updated skill to process PDF documents.",
        "allowed_tools": [],
        "location": "(mock:cwd)/.moonsuite/products/moonclaw/skills/pdf-processing/SKILL.md",
      },
      "text-summarization": {
        "id": "text-summarization",
        "name": "text-summarization",
        "description": "A skill to summarize text documents.",
        "allowed_tools": [],
        "location": "(mock:cwd)/.moonsuite/products/moonclaw/skills/text-summarization/SKILL.md",
      },
    })
  })
}

///|
async test "load/parent-directories" (t : @test.Test) {
  @mock.run(t, mock => {
    // Directory layout:
    // (home)
    //   .moonsuite/products/moonclaw/skills/global
    //   project/.moonsuite/products/moonclaw/skills/project
    //   project/sub/.moonsuite/products/moonclaw/skills/sub
    //   project/sub/deep (cwd)
    // and `project` is marked as a git repo root.
    mock.add_json_tree({
      ".moonsuite": {
        "products": {
          "moonclaw": {
            "skills": {
              "global-skill": {
                "SKILL.md": (
                  #|---
                  #|name: global-skill
                  #|description: Global skill.
                  #|version: 1.0.0
                  #|---
                  #|
                  #|Global instructions.
                ),
              },
            },
          },
        },
      },
      "project": {
        ".git": {},
        ".moonsuite": {
          "products": {
            "moonclaw": {
              "skills": {
                "project-skill": {
                  "SKILL.md": (
                    #|---
                    #|name: project-skill
                    #|description: Project skill.
                    #|version: 1.0.0
                    #|---
                    #|
                    #|Project instructions.
                  ),
                },
              },
            },
          },
        },
        "sub": {
          ".moonsuite": {
            "products": {
              "moonclaw": {
                "skills": {
                  "sub-skill": {
                    "SKILL.md": (
                      #|---
                      #|name: sub-skill
                      #|description: Sub skill.
                      #|version: 1.0.0
                      #|---
                      #|
                      #|Sub instructions.
                    ),
                  },
                },
              },
            },
          },
          "deep": {},
        },
      },
    })
    let home = mock.cwd.path()
    let cwd = @pathx.join(home, "project/sub/deep")
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    // If inside a git repo, load skills from the repo root and all
    // ancestors down to cwd. That means project + sub, and still global.
    json_inspect(mock.json(fixture_skills(loader)), content={
      "global-skill": {
        "id": "global-skill",
        "name": "global-skill",
        "description": "Global skill.",
        "allowed_tools": [],
        "location": "(mock:cwd)/.moonsuite/products/moonclaw/skills/global-skill/SKILL.md",
      },
      "project-skill": {
        "id": "project-skill",
        "name": "project-skill",
        "description": "Project skill.",
        "allowed_tools": [],
        "location": "(mock:cwd)/project/.moonsuite/products/moonclaw/skills/project-skill/SKILL.md",
      },
      "sub-skill": {
        "id": "sub-skill",
        "name": "sub-skill",
        "description": "Sub skill.",
        "allowed_tools": [],
        "location": "(mock:cwd)/project/sub/.moonsuite/products/moonclaw/skills/sub-skill/SKILL.md",
      },
    })
  })
}

///|
async test "load/no-git-loads-cwd-and-home" (t : @test.Test) {
  @mock.run(t, mock => {
    // Directory layout:
    // (home)
    //   .moonsuite/products/moonclaw/skills/global
    //   cwd/.moonsuite/products/moonclaw/skills/local
    // and there is NO `.git` anywhere.
    mock.add_json_tree({
      ".moonsuite": {
        "products": {
          "moonclaw": {
            "skills": {
              "global-skill": {
                "SKILL.md": (
                  #|---
                  #|name: global-skill
                  #|description: Global skill.
                  #|version: 1.0.0
                  #|---
                  #|
                  #|Global instructions.
                ),
              },
            },
          },
        },
      },
      "cwd": {
        ".moonsuite": {
          "products": {
            "moonclaw": {
              "skills": {
                "local-skill": {
                  "SKILL.md": (
                    #|---
                    #|name: local-skill
                    #|description: Local skill.
                    #|version: 1.0.0
                    #|---
                    #|
                    #|Local instructions.
                  ),
                },
              },
            },
          },
        },
      },
    })
    let home = mock.cwd.path()
    let cwd = @pathx.join(home, "cwd")
    let loader = @skills.Loader::new(home~, cwd~)
    loader.load()
    json_inspect(mock.json(fixture_skills(loader)), content={
      "global-skill": {
        "id": "global-skill",
        "name": "global-skill",
        "description": "Global skill.",
        "allowed_tools": [],
        "location": "(mock:cwd)/.moonsuite/products/moonclaw/skills/global-skill/SKILL.md",
      },
      "local-skill": {
        "id": "local-skill",
        "name": "local-skill",
        "description": "Local skill.",
        "allowed_tools": [],
        "location": "(mock:cwd)/cwd/.moonsuite/products/moonclaw/skills/local-skill/SKILL.md",
      },
    })
  })
}
