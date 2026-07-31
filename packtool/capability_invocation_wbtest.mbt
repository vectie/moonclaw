///|
fn capability_fixture_manifest() -> @pack.MoonPackManifest {
  {
    id: "fixture-capability",
    version: "1.2.3",
    display_name: "Fixture Capability",
    product_id: "fixture-capability",
    kind: DomainPack,
    required_runtime_extensions: ["moonclaw"],
    book_templates: [],
    schemas: [
      @pack.contract_ref("request", "1.0.0", "schemas/request.json"),
      @pack.contract_ref("result", "2.0.0", "schemas/result.json"),
    ],
    tools: [
      @pack.tool_declaration(
        "fixture.execute",
        "fixture-capability",
        "request",
        "result",
        WorkspaceMutation,
        evidence_outputs=["records/results"],
        review_required=true,
      ),
    ],
    workflows: [],
    skills: [],
    policies: [],
    provider_ports: [],
    schedules: [],
    app_entrypoints: [],
    migrations: [],
    evaluations: [],
    uninstall_contract: Some(
      @pack.contract_ref("uninstall", "1.0.0", "UNINSTALL.md"),
    ),
  }
}

///|
async fn write_capability_fixture(root : String) -> Unit {
  @fsx.make_directory(@pathx.join(root, "schemas"), recursive=true)
  @fsx.write_to_file(
    @pathx.join(root, "pack.json"),
    @pack.encode_manifest(capability_fixture_manifest()),
  )
  @fsx.write_to_file(
    @pathx.join(root, "schemas/request.json"),
    "{\"type\":\"object\"}\n",
  )
  @fsx.write_to_file(
    @pathx.join(root, "schemas/result.json"),
    "{\"type\":\"object\"}\n",
  )
  @fsx.write_to_file(
    @pathx.join(root, "UNINSTALL.md"),
    "Preserve durable capability receipts.\n",
  )
}

///|
fn capability_test_digest(text : String) -> String {
  sha256_digest(@utf8.encode(text))
}

///|
async fn capability_fixture_catalog(
  workspace : String,
  health_valid_until? : String = "2026-08-02T00:00:00Z",
) -> Json {
  let health_ref = "health/fixture-capability.json"
  let health_text = "{\"healthy\":true,\"probe\":\"fixture.execute\"}\n"
  @fsx.make_directory(@pathx.join(workspace, "health"), recursive=true)
  @fsx.write_to_file(@pathx.join(workspace, health_ref), health_text)
  (
    {
      "contract_id": "moonflow.capability-catalog.v1",
      "catalog_id": "fixture-catalog-2026-07-31",
      "compiled_at": "2026-07-31T00:00:00Z",
      "conformant": true,
      "products": [
        {
          "product_id": "fixture-capability",
          "pack_id": "fixture-capability",
          "pack_version": "1.2.3",
        },
      ],
      "operations": [
        {
          "operation_ref": "fixture-capability/fixture.execute@1.2.3",
          "product_id": "fixture-capability",
          "pack_id": "fixture-capability",
          "pack_version": "1.2.3",
          "tool_id": "fixture.execute",
          "adapter_id": "fixture-pack-adapter-v1",
          "protocol": "moonflow.adapter.v2",
          "authority": "workspace-mutation",
          "input_schema_ref": "fixture-capability/request@1.0.0",
          "output_schema_ref": "fixture-capability/result@2.0.0",
          "claim_ceiling": "execution-result",
          "idempotent": true,
          "review_required": true,
          "supports_cancel": true,
          "supports_reconcile": true,
          "health_checked_at": "2026-07-31T00:00:00Z",
          "health_valid_until": health_valid_until,
          "health_evidence_ref": health_ref,
          "health_evidence_digest": capability_test_digest(health_text),
        },
      ],
      "issues": [],
    } : Json)
}

///|
async fn capability_fixture_invocation(
  workspace : String,
) -> CapabilityInvocationV1 {
  let artifact = "inputs/request.json"
  @fsx.make_directory(@pathx.join(workspace, "inputs"), recursive=true)
  @fsx.write_to_file(@pathx.join(workspace, artifact), "{\"value\":41}\n")
  let input_digest = declared_artifact_digest(workspace, [artifact])
  {
    contract_id: "moonclaw.capability-invocation.v1",
    adapter_id: "fixture-pack-adapter-v1",
    evaluated_at: "2026-07-31T01:00:00Z",
    recorded_at: "2026-07-31T01:00:01Z",
    attempt: 1,
    request: {
      request_id: "request-run-1-work-1-a1",
      run_id: "run-1",
      book_id: "book-1",
      work_item_id: "work-1",
      declaration_id: "declaration-1",
      attempt_id: "attempt-work-1-1",
      idempotency_key: "run-1/work-1/1/" + input_digest,
      product_id: "fixture-capability",
      operation: "fixture-capability/fixture.execute@1.2.3",
      requested_authority: "workspace-mutation",
      acceptance_criteria: ["result is durable"],
      input_contracts: ["fixture-capability/request@1.0.0"],
      output_contracts: ["fixture-capability/result@2.0.0"],
      required_claim: "execution-result",
      input_digest,
      input_artifacts: [artifact],
      timeout_ms: 30000,
      created_at: "2026-07-31T00:59:59Z",
    },
    config: { "mode": "fixture" },
    input: { "value": 41 },
  }
}

///|
fn capability_fixture_policy() -> CapabilityInvocationPolicyV1 {
  {
    granted_authorities: ["workspace-mutation"],
    reviewed_operation_refs: ["fixture-capability/fixture.execute@1.2.3"],
    max_attempts: 2,
    timeout_ms: 30000,
    remaining_budget_micros: 1000,
  }
}

///|
async fn install_capability_fixture(
  root : String,
) -> (String, Json, CapabilityInvocationV1) {
  let source = @pathx.join(root, "source")
  let workspace = @pathx.join(root, "workspace")
  @fsx.make_directory(source, recursive=true)
  @fsx.make_directory(workspace, recursive=true)
  write_capability_fixture(source)
  @installer.install_authorized(source, workspace, {
    contract: "moonsuite.pack-host-profile.v1",
    runtime_extensions: ["moonclaw"],
    granted_authorities: [WorkspaceMutation],
  })
  |> ignore
  let catalog = capability_fixture_catalog(workspace)
  let invocation = capability_fixture_invocation(workspace)
  (workspace, catalog, invocation)
}

///|
async test "capability invocation is exact durable and idempotent" {
  @fsx.with_temporary_directory("packtool-capability-XXXXXX", root => {
    let (workspace, catalog, invocation) = install_capability_fixture(root)
    let absent = inspect_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
    )
    assert_true(absent is None)
    let calls = Ref::Ref(0)
    let executor = PackToolExecutor::new(
      run=request => {
        calls.val += 1
        let artifact = request.evidence_path
        @fsx.make_directory(
          @pathx.dirname(@pathx.join(workspace, artifact)),
          recursive=true,
        )
        @fsx.write_to_file(@pathx.join(workspace, artifact), "{\"value\":42}\n")
        Ok(
          PackToolExecutionResult::new(
            output={ "value": 42 },
            summary=Some("fixture completed"),
            output_artifacts=[artifact],
          ),
        )
      },
      reconcile=Some(request => {
        Ok({
          status: "succeeded",
          result: Some(
            PackToolExecutionResult::new(output={ "value": 42 }, output_artifacts=[
              request.evidence_path,
            ]),
          ),
          error_kind: "",
        })
      }),
    )
    let first = execute_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
      executor~,
      policy=capability_fixture_policy(),
    )
    assert_eq(first.receipt.status, "succeeded")
    assert_true(capability_digest(first.receipt.output_digest))
    assert_false(first.replayed)
    assert_eq(calls.val, 1)
    assert_true(@fsx.exists_as_file(@pathx.join(workspace, first.receipt_ref)))
    let inspected = inspect_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
    )
    guard inspected is Some(inspected) else {
      fail("expected the durable capability receipt to be inspectable")
    }
    assert_true(inspected.replayed)
    assert_eq(inspected.receipt.result_id, first.receipt.result_id)

    let repeated = execute_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
      executor~,
      policy=capability_fixture_policy(),
    )
    assert_true(repeated.replayed)
    assert_eq(repeated.receipt.result_id, first.receipt.result_id)
    assert_eq(calls.val, 1)

    let conflicting = {
      ..invocation,
      request: { ..invocation.request, request_id: "different-request" },
    }
    try
      execute_installed_capability_v1(
        workspace~,
        catalog_json=catalog,
        invocation=conflicting,
        executor~,
        policy=capability_fixture_policy(),
      )
    catch {
      error =>
        assert_true(
          "\{error}".contains(
            "idempotency key conflicts with a different capability attempt",
          ),
        )
    } noraise {
      _ => fail("expected conflicting idempotency identity to be rejected")
    }
  })
}

///|
async test "uncertain checkpoint reconciles without repeating the effect" {
  @fsx.with_temporary_directory("packtool-reconcile-XXXXXX", root => {
    let (workspace, catalog, invocation) = install_capability_fixture(root)
    let installed = load_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      operation_ref=invocation.request.operation,
      evaluated_at=invocation.evaluated_at,
    )
    let receipt_ref = capability_receipt_ref(invocation.request.idempotency_key)
    let receipt_path = @pathx.join(workspace, receipt_ref)
    @fsx.make_directory(
      @pathx.dirname(receipt_path),
      recursive=true,
      exists_ok=true,
    )
    write_capability_receipt(
      receipt_path,
      receipt_for_status(
        "fixture-catalog-2026-07-31", installed, invocation, "submitted",
      ),
    )
    let runs = Ref::Ref(0)
    let reconciliations = Ref::Ref(0)
    let executor = PackToolExecutor::new(
      run=_ => {
        runs.val += 1
        Err("must not rerun")
      },
      reconcile=Some(request => {
        reconciliations.val += 1
        let artifact = request.evidence_path
        @fsx.make_directory(
          @pathx.dirname(@pathx.join(workspace, artifact)),
          recursive=true,
        )
        @fsx.write_to_file(
          @pathx.join(workspace, artifact),
          "{\"reconciled\":true}\n",
        )
        Ok({
          status: "succeeded",
          result: Some(
            PackToolExecutionResult::new(output={ "reconciled": true }, output_artifacts=[
              artifact,
            ]),
          ),
          error_kind: "",
        })
      }),
    )
    let outcome = execute_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
      executor~,
      policy=capability_fixture_policy(),
    )
    assert_true(outcome.replayed)
    assert_eq(outcome.receipt.status, "succeeded")
    assert_eq(runs.val, 0)
    assert_eq(reconciliations.val, 1)
  })
}

///|
async test "submitted capability cancels through the same durable attempt" {
  @fsx.with_temporary_directory("packtool-cancel-XXXXXX", root => {
    let (workspace, catalog, invocation) = install_capability_fixture(root)
    let runs = Ref::Ref(0)
    let cancellations = Ref::Ref(0)
    let executor = PackToolExecutor::new(
      run=_ => {
        runs.val += 1
        Ok(
          PackToolExecutionResult::new(
            output={ "queued": true },
            status="submitted",
            external_job_id="job-1",
          ),
        )
      },
      reconcile=Some(_ => {
        Ok({ status: "running", result: None, error_kind: "" })
      }),
      cancel=Some(_ => {
        cancellations.val += 1
        Ok({
          status: "cancelled",
          result: Some(
            PackToolExecutionResult::new(
              output={ "cancelled": true },
              status="cancelled",
              external_job_id="job-1",
            ),
          ),
          error_kind: "",
        })
      }),
    )
    let submitted = execute_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
      executor~,
      policy=capability_fixture_policy(),
    )
    assert_eq(submitted.receipt.status, "submitted")
    assert_eq(runs.val, 1)
    let cancelled = cancel_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
      executor~,
      policy=capability_fixture_policy(),
    )
    assert_eq(cancelled.receipt.status, "cancelled")
    assert_eq(cancellations.val, 1)
    assert_eq(runs.val, 1)
    let replayed = cancel_installed_capability_v1(
      workspace~,
      catalog_json=catalog,
      invocation~,
      executor~,
      policy=capability_fixture_policy(),
    )
    assert_true(replayed.replayed)
    assert_eq(cancellations.val, 1)
  })
}

///|
async test "expired health and schema drift fail before adapter execution" {
  @fsx.with_temporary_directory("packtool-health-XXXXXX", root => {
    let (workspace, _, invocation) = install_capability_fixture(root)
    let expired = capability_fixture_catalog(
      workspace,
      health_valid_until="2026-07-31T00:30:00Z",
    )
    let calls = Ref::Ref(0)
    let executor = PackToolExecutor::new(run=_ => {
      calls.val += 1
      Err("must not execute")
    })
    try
      execute_installed_capability_v1(
        workspace~,
        catalog_json=expired,
        invocation~,
        executor~,
        policy=capability_fixture_policy(),
      )
    catch {
      error =>
        assert_true(
          "\{error}".contains("health attestation is invalid or expired"),
        )
    } noraise {
      _ => fail("expected expired health to fail closed")
    }
    assert_eq(calls.val, 0)

    let healthy = capability_fixture_catalog(workspace)
    let drifted = {
      ..invocation,
      request: {
        ..invocation.request,
        input_contracts: ["fixture-capability/request@9.9.9"],
      },
    }
    try
      execute_installed_capability_v1(
        workspace~,
        catalog_json=healthy,
        invocation=drifted,
        executor~,
        policy=capability_fixture_policy(),
      )
    catch {
      error =>
        assert_true(
          "\{error}".contains(
            "request schemas do not exactly match capability schemas",
          ),
        )
    } noraise {
      _ => fail("expected schema drift to fail closed")
    }
    assert_eq(calls.val, 0)

    let excessive_claim = {
      ..invocation,
      request: { ..invocation.request, required_claim: "physical-readiness" },
    }
    try
      execute_installed_capability_v1(
        workspace~,
        catalog_json=healthy,
        invocation=excessive_claim,
        executor~,
        policy=capability_fixture_policy(),
      )
    catch {
      error =>
        assert_true(
          "\{error}".contains("required claim exceeds capability claim ceiling"),
        )
    } noraise {
      _ => fail("expected excessive claim to fail closed")
    }
    assert_eq(calls.val, 0)
  })
}
