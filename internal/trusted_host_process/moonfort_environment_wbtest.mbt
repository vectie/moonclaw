///|
test "daemon child preserves explicit MoonFort references and registration" {
  let execution = "/operator/Moon Fort/executor.json"
  let promotion = "/operator/Moon Fort/promotion.json"
  let environment = daemon_child_environment_from_values(
    "/Users/test",
    "synthetic-instance",
    "synthetic-registration",
    moonfort_config=execution,
    moonfort_promotion_config=promotion,
  )
  assert_eq(environment.get("MOONCLAW_MOONFORT_CONFIG"), Some(execution))
  assert_eq(
    environment.get("MOONCLAW_MOONFORT_PROMOTION_CONFIG"),
    Some(promotion),
  )
  assert_eq(environment.length(), 9)
  assert_eq(
    environment["MOONCLAW_WORKER_REGISTRATION_INSTANCE"],
    "synthetic-instance",
  )
  assert_eq(
    environment["MOONCLAW_WORKER_REGISTRATION_TOKEN"],
    "synthetic-registration",
  )
  assert_eq(environment["PATH"], "/usr/bin:/bin")
  assert_false(environment.contains("OPENAI_API_KEY"))
  assert_false(environment.contains("OPENROUTER_API_KEY"))
  assert_false(environment.contains("MOONGATE_CONTROL_TOKEN"))
  assert_false(environment.contains("MOONFORT_EXECUTOR_CONFIG"))
}

///|
test "daemon child leaves absent MoonFort references absent and independent" {
  let absent = daemon_child_environment_from_values(
    "/Users/test", "id", "registration",
  )
  assert_eq(absent.length(), 7)
  assert_false(absent.contains("MOONCLAW_MOONFORT_CONFIG"))
  assert_false(absent.contains("MOONCLAW_MOONFORT_PROMOTION_CONFIG"))
  let execution = daemon_child_environment_from_values(
    "/Users/test",
    "id",
    "registration",
    moonfort_config="/operator/executor.json",
  )
  assert_eq(execution.length(), 8)
  assert_false(execution.contains("MOONCLAW_MOONFORT_PROMOTION_CONFIG"))
  let promotion = daemon_child_environment_from_values(
    "/Users/test",
    "id",
    "registration",
    moonfort_promotion_config="/operator/promotion.json",
  )
  assert_eq(promotion.length(), 8)
  assert_false(promotion.contains("MOONCLAW_MOONFORT_CONFIG"))
}

///|
test "daemon child preserves present invalid references for the existing loader" {
  for value in ["", "relative.json", "  /operator/config.json  "] {
    let environment = daemon_child_environment_from_values(
      "/Users/test",
      "id",
      "registration",
      moonfort_config=value,
      moonfort_promotion_config=value,
    )
    assert_eq(environment.get("MOONCLAW_MOONFORT_CONFIG"), Some(value))
    assert_eq(
      environment.get("MOONCLAW_MOONFORT_PROMOTION_CONFIG"),
      Some(value),
    )
  }
}

///|
test "MoonFort reference forwarding does not change daemon model arguments" {
  assert_eq(daemon_child_model_arguments(None, None), [])
  assert_eq(
    daemon_child_model_arguments(
      Some("moongate/exact-selected"),
      Some("/workspace/selected-book"),
    ),
    [
      "--model", "moongate/exact-selected", "--model-workspace", "/workspace/selected-book",
    ],
  )
}
