///|
/// Deprecated compatibility projection for callers that used the old
/// MoonCode-named capability advertisement. MoonCode is now a role/profile of
/// MoonClaw's sole runtime, never a product-owned adapter or second runtime.
pub fn mooncode_moonflow_adapter_capability_json() -> Json {
  {
    "contract_id": "moonclaw.agent-role-profile.v1",
    "deprecated_compatibility_name": "mooncode_moonflow_adapter_capability_json",
    "adapter_id": "moonclaw-agent-goal-v1",
    "product_id": "moonclaw",
    "pack_id": "moonclaw",
    "pack_version": "0.1.5",
    "protocol": "moonflow.adapter.v2",
    "operation_ref": "moonclaw/agent.goal.execute@0.1.5",
    "input_schema_ref": "moonclaw/agent-goal-execution-request@1.0.0",
    "output_schema_ref": "moonclaw/agent-goal-execution-receipt@1.0.0",
    "role": "mooncode",
    "default_model": "gpt-5.6-sol",
    "supports_cancel": true,
    "supports_reconcile": true,
    "runtime_owner": "moonclaw",
    "separate_runtime": false,
    "human_acceptance_implied": false,
  }
}

///|
/// Host declaration for the one manifest-owned agent-goal operation.
pub fn moonclaw_agent_goal_adapter_declaration_json() -> Json {
  {
    "contract_id": "moonflow.adapter-declaration.v1",
    "adapter_id": "moonclaw-agent-goal-v1",
    "product_id": "moonclaw",
    "pack_id": "moonclaw",
    "pack_version": "0.1.5",
    "protocol": "moonflow.adapter.v2",
    "operations": [
      {
        "operation_id": "agent.goal.execute",
        "claim_ceiling": "digital-artifact",
        "supports_cancel": true,
        "supports_reconcile": true,
      },
    ],
  }
}

///|
/// Build a short-lived health attestation from retained live-probe evidence.
/// The caller must write and verify the exact evidence bytes before publishing
/// the attestation into a MoonFlow capability source bundle.
pub fn moonclaw_agent_goal_health_attestation_json(
  checked_at~ : String,
  valid_until~ : String,
  evidence_ref~ : String,
  evidence_digest~ : String,
) -> Json {
  {
    "contract_id": "moonflow.adapter-health.v1",
    "adapter_id": "moonclaw-agent-goal-v1",
    "product_id": "moonclaw",
    "pack_id": "moonclaw",
    "pack_version": "0.1.5",
    "protocol": "moonflow.adapter.v2",
    "status": "healthy",
    "checked_at": checked_at,
    "valid_until": valid_until,
    "operation_refs": ["moonclaw/agent.goal.execute@0.1.5"],
    "evidence_ref": evidence_ref,
    "evidence_digest": evidence_digest,
  }
}

///|
/// Describe MoonClaw's generic host seam for executable capability truth.
///
/// This object is deliberately not an adapter declaration and advertises no
/// product operations. Executable operations come only from a compiled
/// `moonflow.capability-catalog.v1`, backed by an active installed pack,
/// `moonflow.adapter-declaration.v1`, and expiring health evidence.
pub fn moonclaw_moonflow_adapter_capability_json() -> Json {
  {
    "contract_id": "moonclaw.pack-capability-host.v1",
    "host_id": "moonclaw",
    "product_id": "moonclaw",
    "protocol": "moonflow.adapter.v2",
    "adapter_declaration_contract": "moonflow.adapter-declaration.v1",
    "adapter_health_contract": "moonflow.adapter-health.v1",
    "capability_catalog_contract": "moonflow.capability-catalog.v1",
    "invocation_contract": "moonclaw.capability-invocation.v1",
    "receipt_contract": "moonclaw.capability-invocation-receipt.v1",
    "operations": [],
    "operations_source": "compiled-installed-pack-catalog",
    "manifest_derived_operations_only": true,
    "exact_versioned_schema_refs_required": true,
    "expiring_health_evidence_required": true,
    "authority_classes": [
      "observe", "cognitive-maintenance", "sandbox-execution", "workspace-mutation",
      "external-effect", "physical-effect",
    ],
    "supports_reconcile": true,
    "idempotent_submission_required": true,
    "unknown_effect_reexecution_forbidden": true,
    "completion_judgment_forbidden": true,
    "authority_escalation_forbidden": true,
    "domain_policy_forbidden": true,
  }
}
