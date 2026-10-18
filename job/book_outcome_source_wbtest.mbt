///|
async test "book source actual native lifecycle retains exact text and fails closed on changed reads" {
  @fsx.with_temporary_directory("claw-book-source-XXXXXX", root => {
    let runtime = RuntimeManager::new(root~)
    runtime.register_definition({
      ..sample_definition(),
      schedule: None,
      config: {},
      workflow_id: Some("fixture-text-workflow"),
    })
    runtime.register_workflow({
      id: "fixture-text-workflow",
      kind: "local-fixture",
      steps: [
        {
          id: "write",
          kind: "fixture.write-text",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: ["report"],
    })
    let reader = ArtifactStore::new(store=runtime.store())
    ignore(runtime.create_run("run-1", "job.sample.sync", Manual, 100))
    try reader.freeze_book_outcome_source("run-1", ["text-one"]) catch {
      error => assert_true(error.to_string().contains("completed run"))
    } noraise {
      _ => fail("Pending run must not be inferred completed")
    }
    let text = "\uFEFFLocal deterministic fixture, no provider or customer claim.\n报告 <&>\u0000 retained exactly.\n"
    execute_run_lifecycle(runtime, "run-1", fn() { 200 }, fn() {
      let engine = WorkflowEngine::new(runtime~)
      engine.register_handler(
        WorkflowStepHandler::new(kind="fixture.write-text", run=async fn(ctx) {
          let record = reader.write(
            ArtifactWriteRequest::new(
              run_id=ctx.run.id,
              job_id=ctx.run.job_id,
              artifact_type="fixture.report",
              content_type="text/plain",
              content=text,
              logical_key=Some("report"),
              metadata={
                "origin": "deterministic-local-fixture",
                "provider_executed": false,
              },
            ),
            "text-one",
            150,
          )
          Ok(
            WorkflowStepResult::new(
              output={ "artifact_id": record.id },
              summary=Some(
                "Native local text fixture completed; no provider execution",
              ),
            ),
          )
        }),
      )
      engine
    })
    assert_true(runtime.store().get_run("run-1").unwrap().status is Succeeded)
    runtime.store().load()
    let first = reader.freeze_book_outcome_source("run-1", ["text-one"])
    assert_eq(reader.freeze_book_outcome_source("run-1", ["text-one"]), first)
    guard first
      is {
        "source_json": String(context),
        "artifacts": [{ "text": String(retained), .. }],
        ..
      } else {
      fail("Source shape")
    }
    assert_eq(retained, text)
    assert_true(context.contains("Succeeded"))
    let fixture_dir = @os.getenv("MOONCLAW_BOOK_FIXTURE_DIR") catch {
      _ => None
    }
    if fixture_dir is Some(fixture_dir) {
      if !@fs.exists(fixture_dir) {
        @fs.mkdir(fixture_dir, recursive=true)
      }
      @fsx.write_to_file(
        fixture_dir + "/native-source.json",
        first.stringify(indent=2),
      )
      @fsx.write_to_file(fixture_dir + "/native-original.txt", text)
    }
    let record = reader.get("text-one").unwrap()
    let original_run = runtime.store().get_run("run-1").unwrap()
    runtime
    .store()
    .save_run({
      ..original_run,
      summary: Some("Changed completed run summary"),
    })
    assert_true(
      reader.freeze_book_outcome_source("run-1", ["text-one"]) != first,
    )
    runtime.store().save_run(original_run)
    runtime.store().save_artifact({ ..record, version: record.version + 1, })
    assert_true(
      reader.freeze_book_outcome_source("run-1", ["text-one"]) != first,
    )
    runtime.store().save_artifact(record)
    assert_eq(reader.freeze_book_outcome_source("run-1", ["text-one"]), first)
    @fs.write_file(record.path, @encoding/utf8.encode(text + "changed"))
    let changed = reader.freeze_book_outcome_source("run-1", ["text-one"])
    assert_true(changed != first)
    assert_eq(retained, text)
    @fs.write_file(record.path, b"\xff\x80")
    try reader.freeze_book_outcome_source("run-1", ["text-one"]) catch {
      error => assert_true(error.to_string().contains("valid UTF-8"))
    } noraise {
      _ => fail("Must refuse non UTF-8")
    }
    @fs.remove(record.path)
    try reader.freeze_book_outcome_source("run-1", ["text-one"]) catch {
      error => assert_true(error.to_string().contains("missing"))
    } noraise {
      _ => fail("Missing source")
    }
    @fs.write_file(
      record.path,
      @encoding/utf8.encode(text),
      create_mode=CreateOrTruncate,
    )
    assert_eq(reader.freeze_book_outcome_source("run-1", ["text-one"]), first)
    for
      ids in [["text-one", "text-one"], ["synthetic:run-1:report"], ["unknown"]] {
      try reader.freeze_book_outcome_source("run-1", ids) catch {
        _ => ()
      } noraise {
        _ => fail("Invalid artifact selection accepted")
      }
    }
    try reader.freeze_book_outcome_source("other-run", ["text-one"]) catch {
      _ => ()
    } noraise {
      _ => fail("Wrong run accepted")
    }
    ignore(
      reader.write(
        ArtifactWriteRequest::new(
          run_id="run-1",
          job_id="job.sample.sync",
          artifact_type="binary",
          content_type="application/pdf",
          content="looks like text",
        ),
        "binary",
        160,
      ),
    )
    try reader.freeze_book_outcome_source("run-1", ["binary"]) catch {
      error => assert_true(error.to_string().contains("UTF-8 text only"))
    } noraise {
      _ => fail("Binary type accepted")
    }
    let large = @fs.open(record.path, mode=ReadWrite)
    large.write_at(b"x", position=8388608L)
    large.close()
    try reader.freeze_book_outcome_source("run-1", ["text-one"]) catch {
      error => assert_true(error.to_string().contains("8 MiB"))
    } noraise {
      _ => fail("Oversize accepted")
    }
  })
}
