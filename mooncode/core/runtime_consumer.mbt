///|
pub fn runtime_consumer_contract_id() -> String {
  "mooncode-runtime-consumer.v1"
}

///|
pub fn runtime_consumer_contract_kind() -> String {
  "mooncode-runtime-consumer-contract"
}

///|
pub fn runtime_claim_state_kind() -> String {
  "mooncode-runtime-claim-state"
}

///|
pub fn runtime_claim_response_kind() -> String {
  "mooncode-runtime-claim"
}

///|
pub fn runtime_replay_state_kind() -> String {
  "mooncode-runtime-replay"
}

///|
pub fn runtime_claim_mode() -> String {
  "mooncode-runtime-claim"
}

///|
pub fn runtime_replay_mode() -> String {
  "mooncode-runtime-replay"
}

///|
pub fn runtime_receipt_status_accepted() -> String {
  "runtime-accepted"
}

///|
pub fn runtime_receipt_status_acknowledged() -> String {
  "runtime-acknowledged"
}

///|
pub fn runtime_receipt_status_completed() -> String {
  "runtime-completed"
}

///|
pub fn runtime_receipt_status_claimed() -> String {
  "runtime-claimed"
}

///|
pub fn runtime_receipt_status_failed() -> String {
  "failed"
}

///|
pub fn runtime_receipt_status_proof_missing() -> String {
  "proof-missing"
}

///|
pub fn runtime_receipt_status_skipped() -> String {
  "skipped"
}

///|
pub fn runtime_receipt_status_missing() -> String {
  "missing"
}

///|
pub fn runtime_receipt_status_recorded() -> String {
  "recorded"
}

///|
pub fn runtime_receipt_delivered_statuses() -> Array[String] {
  [
    runtime_receipt_status_accepted(),
    runtime_receipt_status_acknowledged(),
    runtime_receipt_status_completed(),
  ]
}

///|
pub fn runtime_receipt_status_is_delivered(status : String) -> Bool {
  runtime_receipt_delivered_statuses().contains(status)
}

///|
pub fn runtime_receipt_status_is_claimed(status : String) -> Bool {
  status == runtime_receipt_status_claimed()
}

///|
pub fn runtime_replay_ack_allowed_statuses() -> Array[String] {
  [
    runtime_receipt_status_acknowledged(),
    runtime_receipt_status_completed(),
    runtime_receipt_status_proof_missing(),
    runtime_receipt_status_accepted(),
    runtime_receipt_status_failed(),
    runtime_receipt_status_skipped(),
  ]
}

///|
pub fn runtime_replay_ack_status_is_allowed(status : String) -> Bool {
  runtime_replay_ack_allowed_statuses().contains(status)
}

///|
pub fn runtime_replay_ack_status(
  requested_status : String,
  ok~ : Bool,
) -> String {
  if runtime_replay_ack_status_is_allowed(requested_status) {
    requested_status
  } else if ok {
    runtime_receipt_status_acknowledged()
  } else {
    runtime_receipt_status_failed()
  }
}

///|
pub fn runtime_replay_ack_detail(status : String) -> String {
  if status == runtime_receipt_status_completed() {
    "Runtime replay consumer completed the command."
  } else if status == runtime_receipt_status_proof_missing() {
    "Runtime replay consumer requested completion, but required command-scoped proof events are missing or failed."
  } else if status == runtime_receipt_status_failed() {
    "Runtime replay consumer reported command failure."
  } else if status == runtime_receipt_status_skipped() {
    "Runtime replay consumer skipped the command."
  } else {
    "Runtime replay consumer acknowledged the command."
  }
}

///|
pub fn runtime_claim_status_invalid() -> String {
  "invalid"
}

///|
pub fn runtime_claim_status_delivered() -> String {
  "delivered"
}

///|
pub fn runtime_claim_status_claimed() -> String {
  "claimed"
}

///|
pub fn runtime_claim_status_blocked_tool_authorization() -> String {
  "blocked-tool-authorization"
}

///|
pub fn runtime_claim_status_claimable() -> String {
  "claimable"
}

///|
pub fn runtime_claim_status_blocked_by_prior_command() -> String {
  "blocked-by-prior-command"
}

///|
pub fn runtime_claim_statuses() -> Array[String] {
  [
    runtime_claim_status_invalid(),
    runtime_claim_status_delivered(),
    runtime_claim_status_claimed(),
    runtime_claim_status_blocked_tool_authorization(),
    runtime_claim_status_claimable(),
    runtime_claim_status_blocked_by_prior_command(),
  ]
}

///|
pub fn runtime_claim_base_status(
  valid : Bool,
  receipt_status : String,
  expired_claim : Bool,
  tool_authorization_blocked : Bool,
) -> String {
  if !valid {
    runtime_claim_status_invalid()
  } else if runtime_receipt_status_is_delivered(receipt_status) {
    runtime_claim_status_delivered()
  } else if runtime_receipt_status_is_claimed(receipt_status) && !expired_claim {
    runtime_claim_status_claimed()
  } else if tool_authorization_blocked {
    runtime_claim_status_blocked_tool_authorization()
  } else {
    runtime_claim_status_claimable()
  }
}

///|
pub fn runtime_claim_status_with_order_blocker(
  base_claim_status : String,
  order_blocker_id : String,
) -> String {
  if order_blocker_id != "" &&
    base_claim_status != runtime_claim_status_delivered() {
    runtime_claim_status_blocked_by_prior_command()
  } else {
    base_claim_status
  }
}

///|
pub fn runtime_claim_status_blocks_following(status : String) -> Bool {
  status == runtime_claim_status_invalid() ||
  status == runtime_claim_status_claimed() ||
  status == runtime_claim_status_blocked_tool_authorization()
}

///|
pub fn runtime_replay_status_blocked_invalid() -> String {
  "blocked-invalid"
}

///|
pub fn runtime_replay_status_delivered() -> String {
  "delivered"
}

///|
pub fn runtime_replay_status_blocked_tool_authorization() -> String {
  "blocked-tool-authorization"
}

///|
pub fn runtime_replay_status_expired_claim_pending_retry() -> String {
  "expired-claim-pending-retry"
}

///|
pub fn runtime_replay_status_claimed() -> String {
  "claimed"
}

///|
pub fn runtime_replay_status_missing_proof_pending_retry() -> String {
  "missing-proof-pending-retry"
}

///|
pub fn runtime_replay_status_failed_pending_retry() -> String {
  "failed-pending-retry"
}

///|
pub fn runtime_replay_status_pending() -> String {
  "pending"
}

///|
pub fn runtime_replay_status_blocked_by_prior_command() -> String {
  "blocked-by-prior-command"
}

///|
pub fn runtime_replay_statuses() -> Array[String] {
  [
    runtime_replay_status_blocked_invalid(),
    runtime_replay_status_delivered(),
    runtime_replay_status_blocked_tool_authorization(),
    runtime_replay_status_expired_claim_pending_retry(),
    runtime_replay_status_claimed(),
    runtime_replay_status_missing_proof_pending_retry(),
    runtime_replay_status_failed_pending_retry(),
    runtime_replay_status_pending(),
    runtime_replay_status_blocked_by_prior_command(),
  ]
}

///|
pub fn runtime_replay_base_status(
  valid : Bool,
  receipt_status : String,
  expired_claim : Bool,
  tool_authorization_blocked : Bool,
) -> String {
  if !valid {
    runtime_replay_status_blocked_invalid()
  } else if runtime_receipt_status_is_delivered(receipt_status) {
    runtime_replay_status_delivered()
  } else if expired_claim {
    if tool_authorization_blocked {
      runtime_replay_status_blocked_tool_authorization()
    } else {
      runtime_replay_status_expired_claim_pending_retry()
    }
  } else if tool_authorization_blocked {
    runtime_replay_status_blocked_tool_authorization()
  } else if runtime_receipt_status_is_claimed(receipt_status) {
    runtime_replay_status_claimed()
  } else if receipt_status == runtime_receipt_status_proof_missing() {
    runtime_replay_status_missing_proof_pending_retry()
  } else if receipt_status == runtime_receipt_status_failed() {
    runtime_replay_status_failed_pending_retry()
  } else {
    runtime_replay_status_pending()
  }
}

///|
pub fn runtime_replay_status_with_order_blocker(
  base_replay_status : String,
  replay_blocker_id : String,
) -> String {
  if replay_blocker_id != "" &&
    base_replay_status != runtime_replay_status_delivered() {
    runtime_replay_status_blocked_by_prior_command()
  } else {
    base_replay_status
  }
}

///|
pub fn runtime_replay_status_is_pending(status : String) -> Bool {
  status == runtime_replay_status_pending() ||
  status == runtime_replay_status_failed_pending_retry() ||
  status == runtime_replay_status_missing_proof_pending_retry() ||
  status == runtime_replay_status_expired_claim_pending_retry()
}

///|
pub fn runtime_replay_status_blocks_following(status : String) -> Bool {
  status == runtime_replay_status_blocked_invalid() ||
  status == runtime_replay_status_claimed() ||
  status == runtime_replay_status_blocked_tool_authorization()
}

///|
pub fn runtime_replay_ack_order_status_matching_claim() -> String {
  "matching-claim"
}

///|
pub fn runtime_replay_ack_order_status_consumer_mismatch() -> String {
  "consumer-mismatch"
}

///|
pub fn runtime_replay_ack_order_status_already_delivered() -> String {
  "already-delivered"
}

///|
pub fn runtime_replay_ack_order_status_retry_after_failed_receipt() -> String {
  "retry-after-failed-receipt"
}

///|
pub fn runtime_replay_ack_order_status_unclaimed_ack() -> String {
  "unclaimed-ack"
}

///|
pub fn runtime_replay_ack_order_statuses() -> Array[String] {
  [
    runtime_claim_status_blocked_by_prior_command(),
    runtime_replay_ack_order_status_matching_claim(),
    runtime_replay_ack_order_status_consumer_mismatch(),
    runtime_replay_ack_order_status_already_delivered(),
    runtime_replay_ack_order_status_retry_after_failed_receipt(),
    runtime_replay_ack_order_status_unclaimed_ack(),
  ]
}

///|
pub fn runtime_claim_endpoint(session_id : String) -> String {
  "/api/mooncode/sessions/\{native_endpoint_component(session_id)}/runtime-claim"
}

///|
pub fn runtime_replay_endpoint(session_id : String) -> String {
  "/api/mooncode/sessions/\{native_endpoint_component(session_id)}/runtime-replay"
}

///|
pub fn runtime_claim_ordering_rule() -> String {
  "MoonClaw claims valid commands in runtime-commands.jsonl order before executing them; active earlier claims and invalid earlier commands block later non-delivered rows until they are acknowledged, failed, expired, forced, or repaired."
}

///|
pub fn runtime_claim_lease_policy() -> String {
  "runtime-claimed receipts hide commands from other consumers until lease_expires_at passes; expired claims and failed runtime receipts become claimable retry work without force, while delivered receipts remain protected."
}

///|
pub fn runtime_claim_authorization_rule() -> String {
  "commands whose tool_authorization snapshot has runtime_may_execute=false, pending approvals, or rejected approvals are not claimable and block later non-delivered rows until a later command record carries an approving snapshot"
}

///|
pub fn runtime_claim_consumer_ordering_rule() -> String {
  "claim returns pending valid commands in runtime-commands.jsonl order; delivered receipts are skipped, but active claimed, invalid, or tool-authorization-blocked earlier commands block later non-delivered rows unless the active claim expires; force=true is only for lease recovery and does not bypass tool authorization"
}

///|
pub fn runtime_claim_duplicate_guard() -> String {
  "commands with delivered receipts are never claimable; active claimed receipts block later work unless force=true; expired claimed receipts and failed runtime receipts become claimable without force; blocked tool authorization never becomes claimable without an approving snapshot"
}

///|
pub fn runtime_replay_policy() -> String {
  "consume pending MoonCode code commands in runtime-commands.jsonl order; skip delivered command ids and active leases; expired runtime-claimed leases are retryable pending work"
}

///|
pub fn runtime_replay_ordering_rule() -> String {
  "prompt, steer, and cancel records remain serialized in append order, matching the MoonCode command protocol's single ordered consumer"
}

///|
pub fn runtime_replay_authorization_rule() -> String {
  "do not consume pending_commands whose tool_authorization snapshot has runtime_may_execute=false; resolve tool approvals first"
}

///|
pub fn runtime_replay_duplicate_guard() -> String {
  "skip command ids with runtime-accepted, runtime-acknowledged, runtime-completed, active runtime-claimed receipts, or blocked tool authorization; active earlier claims, invalid earlier commands, and tool-authorization-blocked earlier commands block later non-delivered rows; expired claims and failed runtime receipts are retryable"
}

///|
pub fn runtime_claim_consumer_contract_json(session_id : String) -> Json {
  {
    "kind": runtime_consumer_contract_kind(),
    "contract_id": runtime_consumer_contract_id(),
    "protocol": protocol_version(),
    "consumer": "moonclaw",
    "endpoint": runtime_claim_endpoint(session_id),
    "method": "POST",
    "request": {
      "consumer_id": "moonclaw-runtime",
      "max_count": 1,
      "force": false,
      "lease_expires_at": "optional ISO-8601 timestamp supplied by the consumer",
      "now": "optional ISO-8601 clock used to recover expired claims deterministically",
    },
    "claim_status": runtime_receipt_status_claimed(),
    "ack_endpoint": runtime_replay_endpoint(session_id),
    "authorization_rule": runtime_claim_authorization_rule(),
    "ordering_rule": runtime_claim_consumer_ordering_rule(),
    "duplicate_guard": runtime_claim_duplicate_guard(),
    "receipt_statuses": {
      "delivered": runtime_receipt_delivered_statuses(),
      "claimed": runtime_receipt_status_claimed(),
      "retryable": [
        runtime_receipt_status_failed(),
        runtime_receipt_status_proof_missing(),
      ],
    },
    "claim_statuses": runtime_claim_statuses(),
    "owner": runtime_consumer_owner_json(),
  }
}

///|
pub fn runtime_replay_consumer_contract_json(session_id : String) -> Json {
  {
    "kind": runtime_consumer_contract_kind(),
    "contract_id": runtime_consumer_contract_id(),
    "protocol": protocol_version(),
    "consumer": "moonclaw",
    "reference": "mooncode/runtime-replay",
    "stdin": "JSONL lines from pending_mooncode_jsonl or pending_commands[*].mooncode_command",
    "stdout": "MoonCode protocol JSONL runtime events normalized by Moondesk into MoonCode lanes",
    "claim": "POST \{runtime_claim_endpoint(session_id)} with {consumer_id,max_count,force,lease_expires_at,now} to atomically mark commands as runtime-claimed before execution",
    "ack": "POST \{runtime_replay_endpoint(session_id)} with {consumer_id,command_id,status,detail,events[]} or {receipts:[...]} to append runtime receipts and optional stream events",
    "session_id": session_id,
    "required_order": "one ordered queue; do not start a later prompt before earlier pending prompt/steer/cancel records are handled",
    "authorization_rule": runtime_replay_authorization_rule(),
    "duplicate_guard": runtime_replay_duplicate_guard(),
    "receipt_statuses": {
      "delivered": runtime_receipt_delivered_statuses(),
      "ack_allowed": runtime_replay_ack_allowed_statuses(),
    },
    "replay_statuses": runtime_replay_statuses(),
    "ack_order_statuses": runtime_replay_ack_order_statuses(),
    "event_sink": "\{@moonsuite.product_display_artifact("mooncode", "sessions/<session-id>/events.jsonl")} or /v1/code/sessions/<session-id>/stream",
    "owner": runtime_consumer_owner_json(),
  }
}

///|
pub fn runtime_consumer_contract_json(session_id : String) -> Json {
  {
    "kind": runtime_consumer_contract_kind(),
    "contract_id": runtime_consumer_contract_id(),
    "protocol": protocol_version(),
    "claim": runtime_claim_consumer_contract_json(session_id),
    "replay": runtime_replay_consumer_contract_json(session_id),
  }
}

///|
fn runtime_consumer_owner_json() -> Json {
  {
    "ui": "moondesk",
    "runtime": "moonclaw",
    "standalone_component": "mooncode",
  }
}
