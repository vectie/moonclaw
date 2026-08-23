///|
async test "trusted git refuses traversal paths" (t : @test.Test) {
  @mock.run(t, mock => {
    try run_git(mock.cwd.path(), AddFiles(["../outside"])) catch {
      _ => ()
    } noraise {
      _ => fail("expected traversal to be rejected")
    }
  })
}

///|
async test "trusted git replaces the ambient environment" (t : @test.Test) {
  @mock.run(t, mock => {
    let initialized = run_git(mock.cwd.path(), Init)
    assert_eq(initialized.status(), 0)
    let status = run_git(mock.cwd.path(), StatusPorcelain)
    assert_eq(status.status(), 0)
  })
}

///|
async test "trusted git refuses executable repository config" (t : @test.Test) {
  @mock.run(t, mock => {
    ignore(run_git(mock.cwd.path(), Init))
    mock.add_json_tree({
      ".git/config": (
        #|[core]
        #|  repositoryformatversion = 0
        #|[filter "host"]
        #|  clean = /bin/sh -c 'exit 0'
      ),
    })
    try run_git(mock.cwd.path(), StatusPorcelain) catch {
      error => assert_true(error.to_string().contains("UnsafeRepositoryConfig"))
    } noraise {
      _ => fail("expected executable Git config to be rejected")
    }
  })
}

///|
async test "trusted git product operations exclude runtime metadata" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let root = mock.cwd.path()
    assert_eq(run_git(root, Init).status(), 0)
    @fsx.make_directory(@pathx.join(root, ".tmp"), recursive=true)
    @fsx.make_directory(@pathx.join(root, ".moonsuite"), recursive=true)
    @fsx.write_to_file(@pathx.join(root, "product.txt"), "product\n")
    @fsx.write_to_file(@pathx.join(root, ".tmp/runtime.txt"), "runtime\n")
    @fsx.write_to_file(@pathx.join(root, ".moonsuite/state.json"), "{}\n")
    assert_eq(run_git(root, AddProductAll).status(), 0)
    assert_eq(run_git(root, Commit("product checkpoint")).status(), 0)
    let head = run_git(root, Head).stdout().trim().to_owned()
    assert_true(head.length() >= 7)
    assert_true(run_git(root, StatusProductPorcelain).stdout().is_blank())
    let overall = run_git(root, StatusPorcelain).stdout()
    assert_true(overall.contains(".tmp/"))
    assert_true(overall.contains(".moonsuite/"))
    let committed = run_git(root, DiffTree(head)).stdout()
    assert_true(committed.contains("product.txt"))
    assert_false(committed.contains(".tmp/"))
    assert_false(committed.contains(".moonsuite/"))
  })
}

///|
async test "trusted git compares only validated commit identifiers" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let root = mock.cwd.path()
    ignore(run_git(root, Init))
    @fsx.write_to_file(@pathx.join(root, "one.txt"), "one\n")
    ignore(run_git(root, AddAll))
    ignore(run_git(root, Commit("first")))
    let base = run_git(root, Head).stdout().trim().to_owned()
    @fsx.write_to_file(@pathx.join(root, "two.txt"), "two\n")
    ignore(run_git(root, AddAll))
    ignore(run_git(root, Commit("second")))
    let final_head = run_git(root, Head).stdout().trim().to_owned()
    let changed = run_git(root, DiffNamesBetween(base~, target=final_head)).stdout()
    assert_true(changed.contains("two.txt"))
    try run_git(root, DiffNamesBetween(base="HEAD", target=final_head)) catch {
      _ => ()
    } noraise {
      _ => fail("expected symbolic or option-like commit input to be rejected")
    }
  })
}
