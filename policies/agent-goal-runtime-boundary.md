# Agent-goal runtime boundary

The `agent.goal.execute` capability provides durable agent execution up to a
`digital-artifact` claim because its terminal receipt binds durable artifact
references and observed SHA-256 digests. A terminal `achieved` goal means the MoonClaw runtime
completed its criteria protocol; it never means a human, customer, Bookkeeper
or downstream pack accepted the deliverable.

The operation may observe and mutate only its explicitly authorized workspace.
It cannot grant itself authority, change MoonFlow policy, publish externally,
perform physical effects, or embed finance, media, robotics or other product
policy. Those effects remain separate pack capabilities with their own
authority and review receipts.

The manifest marks this operation `review_required`. MoonFlow must retain the
exact versioned review receipt used to authorize it and must independently
gate downstream acceptance-dependent stages; the runtime's achieved state is
never that downstream acceptance receipt.

The adapter must:

- derive one stable command identity from the MoonFlow idempotency key;
- reconcile an uncertain prior submission instead of submitting it again;
- cancel only the exact active command for the same session;
- preserve the session journal, goal-runtime records, checkpoints and receipts;
- report `unknown` when evidence cannot establish a safe terminal result;
- leave final acceptance to a separate reviewed capability.

`planner_max_steps` and `max_turns` are local, resumable execution quanta. They
must not become aggregate goal budgets or silently settle the goal.
