///|
fn installed_fixture_manifest() -> @pack.MoonPackManifest {
  {
    id: "fixture-host",
    version: "1.0.0",
    display_name: "Fixture Host Pack",
    product_id: "fixture-host",
    kind: DomainPack,
    required_runtime_extensions: ["moonclaw"],
    book_templates: [],
    schemas: [
      @pack.contract_ref("request", "1.0.0", "schemas/request.json"),
      @pack.contract_ref("snapshot", "1.0.0", "schemas/snapshot.json"),
      @pack.contract_ref("result", "1.0.0", "schemas/result.json"),
    ],
    tools: [
      @pack.tool_declaration(
        "fixture.acquire",
        "fixture-host",
        "request",
        "snapshot",
        Observe,
      ),
      @pack.tool_declaration(
        "fixture.transform",
        "fixture-host",
        "snapshot",
        "result",
        SandboxExecution,
        evidence_outputs=["records/results"],
      ),
    ],
    workflows: [@pack.contract_ref("daily", "1.0.0", "workflows/daily.json")],
    skills: [],
    policies: [],
    provider_ports: [],
    schedules: [],
    app_entrypoints: [],
    migrations: [],
    evaluations: [
      @pack.contract_ref("fixture-tool", "1.0.0", "bin/fixture_tool"),
      @pack.contract_ref("acquire-input", "1.0.0", "inputs/acquire.json"),
      @pack.contract_ref("transform-input", "1.0.0", "inputs/transform.json"),
    ],
    uninstall_contract: Some(
      @pack.contract_ref("uninstall", "1.0.0", "UNINSTALL.md"),
    ),
  }
}

///|
fn installed_fixture_workflow() -> PackWorkflowDeclaration {
  {
    contract: "moonsuite.pack-workflow.v1",
    pack_id: "fixture-host",
    product_id: "fixture-host",
    id: "daily",
    version: "1.0.0",
    steps: [
      {
        id: "acquire",
        tool_id: "fixture.acquire",
        config: {
          "contract": "moonsuite.pack-tool-command.v1",
          "executable": "bin/fixture_tool",
          "input": "inputs/acquire.json",
          "arguments": [],
          "timeout_ms": 1000,
        },
        retry_policy: None,
      },
      {
        id: "transform",
        tool_id: "fixture.transform",
        config: {
          "contract": "moonsuite.pack-tool-command.v1",
          "executable": "bin/fixture_tool",
          "input": "inputs/transform.json",
          "arguments": [],
          "timeout_ms": 1000,
        },
        retry_policy: None,
      },
    ],
    output_bindings: ["transform"],
  }
}

///|
async fn write_installed_fixture_source(root : String) -> Unit {
  @fsx.make_directory(@pathx.join(root, "schemas"), recursive=true)
  @fsx.make_directory(@pathx.join(root, "workflows"), recursive=true)
  @fsx.make_directory(@pathx.join(root, "bin"), recursive=true)
  @fsx.make_directory(@pathx.join(root, "inputs"), recursive=true)
  @fsx.write_to_file(
    @pathx.join(root, "pack.json"),
    @pack.encode_manifest(installed_fixture_manifest()),
  )
  for schema in ["request", "snapshot", "result"] {
    @fsx.write_to_file(
      @pathx.join(root, "schemas/\{schema}.json"),
      "{\"type\":\"object\"}\n",
    )
  }
  @fsx.write_to_file(
    @pathx.join(root, "workflows/daily.json"),
    installed_fixture_workflow().to_json().stringify(),
  )
  @fsx.write_to_file(
    @pathx.join(root, "bin/fixture_tool"),
    (
      #|#!/bin/sh
      #|payload=$(cat)
      #|case "$payload" in
      #|  *'"tool_id":"fixture.acquire"'*'"seed":41'*)
      #|    printf '%s\n' '{"contract":"moonsuite.pack-tool-result.v1","pack_id":"fixture-host","run_id":"run-installed-1","tool_id":"fixture.acquire","ok":true,"output":{"value":41},"summary":"acquired"}'
      #|    ;;
      #|  *'"tool_id":"fixture.transform"'*'"increment":1'*)
      #|    printf '%s\n' '{"contract":"moonsuite.pack-tool-result.v1","pack_id":"fixture-host","run_id":"run-installed-1","tool_id":"fixture.transform","ok":true,"output":{"value":42},"summary":"transformed"}'
      #|    ;;
      #|  *)
      #|    printf '%s\n' '{"contract":"moonsuite.pack-tool-result.v1","ok":false,"error":"unexpected invocation"}'
      #|    ;;
      #|esac
      #|
    ),
  )
  @fsx.write_to_file(
    @pathx.join(root, "inputs/acquire.json"),
    "{\"seed\":41}\n",
  )
  @fsx.write_to_file(
    @pathx.join(root, "inputs/transform.json"),
    "{\"increment\":1}\n",
  )
  @fsx.write_to_file(
    @pathx.join(root, "UNINSTALL.md"),
    "Preserve durable records.\n",
  )
}

///|
fn installed_fixture_policy() -> InvocationPolicy {
  {
    granted_authorities: [Observe, SandboxExecution],
    reviewed_tool_ids: [],
    max_attempts: 1,
    timeout_ms: 30000,
    remaining_budget_micros: 100,
  }
}

///|
async test "installed pack workflow is intaken executed and durable after reload" {
  @fsx.with_temporary_directory("packtool-installed-host-XXXXXX", dir => {
    let source = @pathx.join(dir, "source")
    let workspace = @pathx.join(dir, "workspace")
    @fsx.make_directory(source, recursive=true)
    @fsx.make_directory(workspace, recursive=true)
    write_installed_fixture_source(source)
    @installer.install_authorized(source, workspace, {
      contract: "moonsuite.pack-host-profile.v1",
      runtime_extensions: ["moonclaw"],
      granted_authorities: [Observe, SandboxExecution],
    })
    |> ignore

    let clock = Ref::Ref(1000)
    let now = fn() {
      clock.val = clock.val + 1
      clock.val
    }
    let hosted = run_installed_command_workflow(
      workspace~,
      pack_id="fixture-host",
      workflow_id="daily",
      run_id="run-installed-1",
      policy=installed_fixture_policy(),
      now~,
    )
    assert_true(hosted.execution.run.status is Succeeded)
    guard hosted.execution.outputs.get("acquire")
      is Some({ "value": Number(acquired, ..), .. }) else {
      fail("expected acquired command output")
    }
    assert_eq(acquired.to_int(), 41)
    guard hosted.execution.outputs.get("transform")
      is Some({ "value": Number(value, ..), .. }) else {
      fail("expected transformed output")
    }
    assert_eq(value.to_int(), 42)

    let reloaded = @job.RuntimeManager::new(
      root=@job.moonclaw_jobs_root(workspace),
    )
    reloaded.load()
    let job_id = hosted.intake.definition.id
    let workflow_id = hosted.intake.workflow.id
    assert_true(reloaded.store().get_definition(job_id) is Some(_))
    assert_true(reloaded.store().get_workflow(workflow_id) is Some(_))
    guard reloaded.store().get_run("run-installed-1") is Some(run) else {
      fail("expected durable installed workflow run")
    }
    assert_true(run.status is Succeeded)
    assert_eq(reloaded.store().list_step_runs(run.id).length(), 2)
    guard reloaded.checkpoints().get(job_id) is Some(checkpoint) else {
      fail("expected durable installed workflow checkpoint")
    }
    assert_true(checkpoint.last_success_at is Some(_))
  })
}
