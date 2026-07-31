# Agent-goal adapter conformance

A release is conformant only when focused tests prove:

- exact decoding of the request and receipt schemas;
- the canonical operation and schema references match pack version `0.1.5`;
- the default public model is `gpt-5.6-sol`;
- a repeated idempotency key reconciles without a second command submission;
- restart reconciliation projects the existing goal-runtime journal;
- exact-target cancellation settles the existing goal runtime as cancelled;
- a digital-artifact result binds workspace-relative evidence and SHA-256
  digests in both the pack receipt and generic invocation receipt;
- an achieved execution receipt still says `acceptance_status=review-required`;
- expired, missing or digest-mismatched health evidence prevents invocation;
- no product or domain identifier is introduced as a second runtime.

The health probe must exercise the live MoonClaw daemon capability surface. A
fixture response or the static adapter declaration cannot satisfy live health.
