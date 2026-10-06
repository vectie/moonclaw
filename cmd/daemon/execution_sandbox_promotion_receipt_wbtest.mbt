///|
async test "return receipt recovers a lost acknowledgement twice without another promotion" {
  @fsx.with_temporary_directory("return-receipt-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    let starts = Ref(0)
    let invoke = async fn() {
      starts.val += 1
      moondesk_test_promotion_response(request)
    }
    // The transport loses this response after its durable record is written.
    ignore(moondesk_promotion_with_receipt(request, root, invoke))
    for id in ["receipt-lookup-0001", "receipt-lookup-0002"] {
      let lookup = { ..request, request_id: id, }
      let result = moondesk_promotion_read_receipt(lookup, root)
      assert_true(result.stringify().contains("reviewed/result.txt"))
      assert_true(result.stringify().contains(id))
      assert_true(result.stringify().contains("applied-durable"))
    }
    // Even a repeated original POST returns its saved terminal outcome.
    ignore(moondesk_promotion_with_receipt(request, root, invoke))
    assert_eq(starts.val, 1)
    let saved = moondesk_promotion_load_checkpoint(
      moondesk_promotion_checkpoint_path(root, request),
    ).unwrap()
    assert_eq(saved.response, moondesk_test_promotion_response(request))
    assert_true(saved.request.items == request.items)
  })
}

///|
async test "return receipt preserves exact selection and execution binding" {
  @fsx.with_temporary_directory("return-binding-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    ignore(
      moondesk_promotion_with_receipt(request, root, async fn() {
        moondesk_test_promotion_response(request)
      }),
    )
    let path = moondesk_promotion_checkpoint_path(root, request)
    let before = @fs.read_file(path).binary()
    let mismatches : Array[MoonDeskPromotionRequest] = [
      { ..request, command_digest: "c".repeat(64), },
      { ..request, approval_digest: "d".repeat(64), },
      { ..request, workspace_id: "other-workspace", },
      { ..request, instance_id: "other-instance", },
      {
        ..request,
        items: [
          {
            source_relative: "unselected.txt",
            destination_relative: "reviewed/result.txt",
          },
        ],
      },
      {
        ..request,
        items: [
          {
            source_relative: "reports/result.txt",
            destination_relative: "another/result.txt",
          },
        ],
      },
    ]
    for changed in mismatches {
      try moondesk_promotion_read_receipt(changed, root) catch {
        _ => ()
      } noraise {
        _ => fail("Mismatched receipt lookup was accepted")
      }
    }
    assert_eq(@fs.read_file(path).binary(), before)
  })
}

///|
async test "return receipt missing or incomplete record remains unresolved without mutation" {
  @fsx.with_temporary_directory("return-unavailable-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    try moondesk_promotion_read_receipt(request, root) catch {
      _ => ()
    } noraise {
      _ => fail("Missing receipt became success")
    }
    assert_eq(@fs.readdir(root).length(), 0)
    let path = moondesk_promotion_checkpoint_path(root, request)
    @fs.write_file(path, "{partial", create_mode=CreateNew)
    try moondesk_promotion_read_receipt(request, root) catch {
      _ => ()
    } noraise {
      _ => fail("Partial receipt became success")
    }
    assert_eq(@fs.read_file(path).text(), "{partial")
  })
}

///|
async test "return receipt keeps safe refusal retryable but recovery outcomes read only" {
  @fsx.with_temporary_directory("return-refusal-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    let applied = moondesk_test_promotion_response(request)
    let starts = Ref(0)
    ignore(
      moondesk_promotion_with_receipt(request, root, async fn() {
        starts.val += 1
        {
          ..applied,
          workspace_id: "",
          approval_digest: "",
          command_digest: "",
          promoted_paths: [],
          destination_outcome: "not-applied",
          completed: false,
          error: Some({ code: "promotion-refused", message: "private detail", }),
        }
      }),
    )
    assert_true(
      moondesk_promotion_read_receipt(request, root)
      .stringify()
      .contains("not-applied"),
    )
    ignore(
      moondesk_promotion_with_receipt(request, root, async fn() {
        starts.val += 1
        {
          ..applied,
          promoted_paths: [],
          destination_outcome: "recovery-required",
          uncertain_paths: ["reviewed/result.txt"],
          completed: false,
          error: Some({
            code: "promotion-recovery-required",
            message: "private detail",
          }),
        }
      }),
    )
    let result = moondesk_promotion_with_receipt(request, root, async fn() {
      starts.val += 1
      applied
    })
    assert_eq(starts.val, 2)
    assert_true(result.stringify().contains("recovery-required"))
    assert_false(result.stringify().contains("private detail"))
  })
}

///|
async test "return receipt write failure cannot claim a saved acknowledgement" {
  @fsx.with_temporary_directory("return-save-failure-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    let path = moondesk_promotion_checkpoint_path(root, request)
    @fs.mkdir(path + ".pending")
    let starts = Ref(0)
    try
      moondesk_promotion_with_receipt(request, root, async fn() {
        starts.val += 1
        moondesk_test_promotion_response(request)
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("Receipt write failure was hidden")
    }
    try moondesk_promotion_read_receipt(request, root) catch {
      _ => ()
    } noraise {
      _ => fail("Absent receipt was invented")
    }
    assert_eq(starts.val, 1)
  })
}

///|
async test "return retry pending checkpoint supersedes the earlier safe refusal" {
  @fsx.with_temporary_directory("return-retry-pending-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    let response = moondesk_test_promotion_response(request)
    ignore(
      moondesk_promotion_with_receipt(request, root, async fn() {
        {
          ..response,
          workspace_id: "",
          approval_digest: "",
          command_digest: "",
          promoted_paths: [],
          destination_outcome: "not-applied",
          completed: false,
          error: Some({ code: "promotion-refused", message: "fixture refusal", }),
        }
      }),
    )
    let path = moondesk_promotion_checkpoint_path(root, request)
    let refusal = @fs.read_file(path).binary()
    let starts = Ref(0)
    // A failed pending write must leave the previous refusal valid because the
    // next Fort invocation has not started.
    @fs.mkdir(path + ".starting")
    try
      moondesk_promotion_with_receipt(request, root, async fn() {
        starts.val += 1
        response
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("Pending write failure was hidden")
    }
    assert_eq(starts.val, 0)
    assert_eq(@fs.read_file(path).binary(), refusal)
    assert_true(
      moondesk_promotion_read_receipt(request, root)
      .stringify()
      .contains("not-applied"),
    )
    @fs.rmdir(path + ".starting")
    // The pending record is already durable during invocation. Neither an
    // interrupted call nor a repeated POST may expose the previous refusal.
    try
      moondesk_promotion_with_receipt(request, root, async fn() {
        starts.val += 1
        try moondesk_promotion_read_receipt(request, root) catch {
          _ => ()
        } noraise {
          _ => fail("In-flight retry recovered the previous refusal")
        }
        fail("Fixture transport ended after possible mutation")
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("Interrupted attempt was hidden")
    }
    let pending = @fs.read_file(path).binary()
    assert_true(pending != refusal)
    for _ in 0..<2 {
      try moondesk_promotion_read_receipt(request, root) catch {
        _ => ()
      } noraise {
        _ => fail("Interrupted retry recovered the previous refusal")
      }
      try
        moondesk_promotion_with_receipt(request, root, async fn() {
          starts.val += 1
          response
        })
      catch {
        _ => ()
      } noraise {
        _ => fail("Pending attempt became retryable")
      }
    }
    assert_eq(starts.val, 1)
    assert_eq(@fs.read_file(path).binary(), pending)
  })
}

///|
async test "return retry final write failure cannot revive an earlier safe refusal" {
  @fsx.with_temporary_directory("return-retry-save-XXXXXX", async fn(root) {
    let request = moondesk_test_promotion_request()
    let response = moondesk_test_promotion_response(request)
    ignore(
      moondesk_promotion_with_receipt(request, root, async fn() {
        {
          ..response,
          workspace_id: "",
          approval_digest: "",
          command_digest: "",
          promoted_paths: [],
          destination_outcome: "not-applied",
          completed: false,
          error: Some({ code: "promotion-refused", message: "fixture refusal", }),
        }
      }),
    )
    let path = moondesk_promotion_checkpoint_path(root, request)
    @fs.mkdir(path + ".pending")
    let starts = Ref(0)
    try
      moondesk_promotion_with_receipt(request, root, async fn() {
        starts.val += 1
        response
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("Final write failure was hidden")
    }
    assert_eq(starts.val, 1)
    for _ in 0..<2 {
      try
        moondesk_promotion_read_receipt(
          { ..request, request_id: "retry-read", },
          root,
        )
      catch {
        _ => ()
      } noraise {
        _ => fail("Final write failure recovered the previous refusal")
      }
      try
        moondesk_promotion_with_receipt(request, root, async fn() {
          starts.val += 1
          response
        })
      catch {
        _ => ()
      } noraise {
        _ => fail("Final write failure became retryable")
      }
    }
    assert_eq(starts.val, 1)
  })
}
