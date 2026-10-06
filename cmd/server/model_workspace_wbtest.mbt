///|
async test "server model flags preserve owning suite discovery outside isolated execution cwd" {
  @fsx.with_temporary_directory("moonclaw-child-route-XXXXXX", root => {
    let suite = @pathx.join(root, "suite")
    let book = @pathx.join(suite, "books/selected")
    let linked_book = @pathx.join(suite, "books/selected-link")
    let external_book = @pathx.join(root, "external-book")
    let linked_suite = @pathx.join(root, "suite-alias")
    let worker_cwd = @pathx.join(
      suite, ".moonsuite/products/moonclaw/jobs/supervisor-workers/digest",
    )
    @fsx.make_directory(book, recursive=true, exists_ok=true)
    @fsx.make_directory(worker_cwd, recursive=true, exists_ok=true)
    @fsx.make_directory(external_book, recursive=true, exists_ok=true)
    @model_workspace_fs.symlink(target=external_book, linked_book)
    @model_workspace_fs.symlink(target=suite, linked_suite)
    @fsx.write_to_file(
      @pathx.join(suite, ".moonsuite/suite-status.json"),
      (
        {
          "contract": "moon.suite.status.v2",
          "service": "moongate",
          "ready": true,
          "manifest": {
            "contract": "moon.suite.service.v1",
            "service": "moongate",
            "baseUrl": "http://injected-gate.invalid",
            "defaultModel": "configured/exact-id",
          },
        } : Json).stringify(),
    )
    assert_true(
      @moongate.discover_from_suite_status_for_workspace_root(worker_cwd)
      is None,
    )
    assert_true(
      @moongate.discover_from_suite_status_for_workspace_root(external_book)
      is None,
    )
    // Exercise the real serializer and CLI extraction for both initial launch
    // and persisted stopped-worker resume. Neither path starts a child/server.
    for owner in [book, suite, linked_book, linked_suite] {
      for resume in [false, true] {
        let selector = "moongate/configured/exact-id"
        let args = @trusted_host_process.daemon_child_model_arguments(
          Some(selector),
          Some(owner),
        )
        if resume {
          args.append(["--resume", "00000000-0000-0000-0000-000000000001"])
        }
        let (model_workspace, remaining) = server_model_workspace_arguments(
          args,
        )
        assert_eq(model_workspace, Some(owner))
        assert_eq(remaining[0], "--model")
        assert_eq(remaining[1], selector)
        assert_eq(remaining.length(), if resume { 4 } else { 2 })
        let resolved = server_resolve_model(
          suite,
          Some(remaining[1]),
          model_workspace,
          resolve=(home, workspace, requested) => {
            assert_eq(home, suite)
            assert_eq(workspace, Some(owner))
            let client = @moongate.discover_from_suite_status_for_workspace_root(
              workspace.unwrap(),
            ).unwrap()
            assert_eq(client.base_url(), "http://injected-gate.invalid")
            let catalog = @moongate.moongate_models_from_json({
              "models": [{ "id": "configured/exact-id" }],
            }).unwrap()
            let entry = catalog[0]
            assert_eq(requested, Some("moongate/" + entry.id()))
            Some(
              @model.Model::new(
                api_key="",
                base_url=client.base_url() + "/openclaw/v1",
                name=requested.unwrap(),
                model_name=entry.id(),
                safe_zone_tokens=1000,
              ),
            )
          },
        ).unwrap()
        assert_eq(resolved.selector(), selector)
        assert_eq(resolved.base_url, "http://injected-gate.invalid/openclaw/v1")
        assert_true(@fsx.exists(worker_cwd))
      }
    }
  })
}

///|
async test "server model root option leaves legacy model loading context unchanged" {
  let ordinary_args = [
    "--name", "ordinary task", "--port", "0", "--web-search", "--serve", "/tmp/ui",
  ]
  let (ordinary_workspace, ordinary_remaining) = server_model_workspace_arguments(
    ordinary_args,
  )
  assert_true(ordinary_workspace is None)
  assert_eq(ordinary_remaining, ordinary_args)
  assert_eq(@trusted_host_process.daemon_child_model_arguments(None, None), [])
  ignore(
    server_resolve_model("/tmp/legacy-home", None, None, resolve=(
      home,
      cwd,
      selector,
    ) => {
      assert_eq(home, "/tmp/legacy-home")
      assert_true(cwd is None)
      assert_true(selector is None)
      None
    }),
  )
  let args = @trusted_host_process.daemon_child_model_arguments(
    Some("codex/gpt-5.4"),
    None,
  )
  let (workspace, remaining) = server_model_workspace_arguments(args)
  assert_true(workspace is None)
  assert_eq(remaining, ["--model", "codex/gpt-5.4"])
  ignore(
    server_resolve_model("/tmp/legacy-home", Some(remaining[1]), workspace, resolve=(
      home,
      cwd,
      selector,
    ) => {
      assert_eq(home, "/tmp/legacy-home")
      assert_true(cwd is None)
      assert_eq(selector, Some("codex/gpt-5.4"))
      None
    }),
  )
  for
    args in [
      ["--model-workspace"],
      ["--model-workspace", "relative"],
      ["--model-workspace", "/"],
      ["--model-workspace", "/tmp/book", "--model-workspace", "/tmp/other"],
    ] {
    try server_model_workspace_arguments(args) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid model root option to fail")
    }
  }
}
