///|
fn worker_registration_test_registrations(
  now_ms : Int64,
  instance_id : String,
  token : String,
) -> Map[String, PendingTaskRegistration] {
  let registrations : Map[String, PendingTaskRegistration] = Map([])
  let queue = @aqueue.Queue(kind=Unbounded)
  registrations[instance_id] = {
    queue,
    instance_id,
    token,
    expires_at_ms: now_ms + 100L,
  }
  registrations
}

///|
test "worker registration rejects wrong token without consuming capability" {
  let instance_id = "00000000-0000-0000-0000-000000000001"
  let token = "a".repeat(72)
  let registrations = worker_registration_test_registrations(
    0L, instance_id, token,
  )
  try
    authorize_task_registration(
      registrations,
      {
        "x-moonclaw-worker-registration-instance": instance_id,
        "x-moonclaw-worker-registration-token": "b".repeat(72),
      },
      0L,
    )
  catch {
    HttpError(code~, body~, ..) => {
      assert_eq(code, 401)
      assert_false(body.contains(instance_id))
      assert_false(body.contains(token))
    }
  } noraise {
    _ => fail("expected wrong-token refusal")
  }
  ignore(
    authorize_task_registration(
      registrations,
      {
        "x-moonclaw-worker-registration-instance": instance_id,
        "x-moonclaw-worker-registration-token": token,
      },
      0L,
    ),
  )
}

///|
test "worker registration capability is single use and instance bound" {
  let instance_id = "00000000-0000-0000-0000-000000000001"
  let token = "a".repeat(72)
  let registrations = worker_registration_test_registrations(
    0L, instance_id, token,
  )
  let headers = {
    "x-moonclaw-worker-registration-instance": instance_id,
    "x-moonclaw-worker-registration-token": token,
  }
  ignore(authorize_task_registration(registrations, headers, 0L))
  try authorize_task_registration(registrations, headers, 0L) catch {
    HttpError(code~, ..) => assert_eq(code, 401)
  } noraise {
    _ => fail("expected replay refusal")
  }
}

///|
test "worker registration rejects wrong instance without consuming capability" {
  let instance_id = "00000000-0000-0000-0000-000000000001"
  let token = "a".repeat(72)
  let registrations = worker_registration_test_registrations(
    0L, instance_id, token,
  )
  try
    authorize_task_registration(
      registrations,
      {
        "x-moonclaw-worker-registration-instance": "00000000-0000-0000-0000-000000000002",
        "x-moonclaw-worker-registration-token": token,
      },
      0L,
    )
  catch {
    HttpError(code~, body~, ..) => {
      assert_eq(code, 401)
      assert_false(body.contains(instance_id))
      assert_false(body.contains(token))
    }
  } noraise {
    _ => fail("expected wrong-instance refusal")
  }
  ignore(
    authorize_task_registration(
      registrations,
      {
        "x-moonclaw-worker-registration-instance": instance_id,
        "x-moonclaw-worker-registration-token": token,
      },
      0L,
    ),
  )
}

///|
test "worker registration refuses expired capability and removes it" {
  let instance_id = "00000000-0000-0000-0000-000000000001"
  let token = "a".repeat(72)
  let registrations = worker_registration_test_registrations(
    0L, instance_id, token,
  )
  try
    authorize_task_registration(
      registrations,
      {
        "x-moonclaw-worker-registration-instance": instance_id,
        "x-moonclaw-worker-registration-token": token,
      },
      101L,
    )
  catch {
    HttpError(code~, ..) => assert_eq(code, 401)
  } noraise {
    _ => fail("expected expired capability refusal")
  }
  assert_false(registrations.contains(instance_id))
}
