///|
/// Describe MoonCode's engineering-planning side of the MoonFlow boundary.
/// Tool execution remains MoonClaw's responsibility.
pub fn mooncode_moonflow_adapter_capability_json() -> Json {
  {
    "adapter_id": "mooncode-v1",
    "product_id": "mooncode",
    "protocol": "moonflow.adapter.v1",
    "operations": [
      "inspect-engineering-context", "prepare-change-plan", "review-change-set",
      "request-verification", "record-review-receipt", "reconcile-engineering-result",
    ],
    "authority_classes": [
      "observe", "cognitive-maintenance", "workspace-mutation",
    ],
    "supports_cancel": true,
    "supports_reconcile": true,
    "receipt_contracts": [
      "mooncode.change-plan.v1", "mooncode.review-receipt.v1", "mooncode.verification-request.v1",
    ],
    "direct_shell_forbidden": true,
    "execution_provider": "moonclaw",
  }
}

///|
/// Describe MoonClaw's bounded execution mechanics for MoonFlow.
/// MoonClaw executes authorized work but does not judge why it matters or
/// whether the suite goal is complete.
pub fn moonclaw_moonflow_adapter_capability_json() -> Json {
  {
    "adapter_id": "moonclaw-v1",
    "product_id": "moonclaw",
    "protocol": "moonflow.adapter.v1",
    "operations": [
      "capability-probe", "submit-governed-job", "inspect-job", "cancel-job", "resume-job",
      "retry-job", "verify-job", "reconcile-job", "compensate-workspace-change",
    ],
    "authority_classes": ["observe", "sandbox-execution", "workspace-mutation"],
    "supports_cancel": true,
    "supports_reconcile": true,
    "receipt_contracts": [
      "moonclaw.job-receipt.v1", "moonclaw.tool-receipt.v1", "moonclaw.change-receipt.v1",
      "moonclaw.verification-receipt.v1",
    ],
    "idempotent_submission_required": true,
    "completion_judgment_forbidden": true,
    "authority_escalation_forbidden": true,
  }
}
