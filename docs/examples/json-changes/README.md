# Explicit JSON snapshot comparison

In an existing Work thread, write an ordinary task such as “Explain the selected exported observations. Do not infer that a runtime report is accepted work.” Open **Compare explicitly chosen JSON locations**.

1. Choose `jsonl` for each side, then import `before.jsonl` as old and `after.jsonl` as new. Imports alone select nothing.
2. You have independently identified alpha as old document 1 and new document 2. Enter those document numbers and `/count` on both sides. Inspect, then choose the change. The exact numbers remain `9007199254740993` and `9007199254740994`.
3. Keep those document numbers; inspect `/retired` on both sides. Old is present null; new is absent. Choose the removed value if relevant.
4. Inspect `/receipt` on both sides. Old is absent; new is present null. Choose this addition if relevant. A null receipt is not proof of execution or acceptance.
5. Optionally inspect old document 2 `/attempt` and new document 1 `/attempt`: `1e0` → `1.0` is an exact-token change, not a claim that the mathematical value changed.
6. Describe the purpose, preview the complete task, then put the preview in the ordinary draft. Unselected private notes and state fields are omitted. No provider is called. Ordinary planning and approval controls remain in charge.

JSON Pointer is a location, not record identity. Changing array order or JSON Lines order never automatically pairs entities. Empty pointer selects an entire document; objects and arrays include their complete subtrees. Type, number spelling, string escapes and whitespace all participate in exact comparison. Both absent and unchanged pairs are inspectable but cannot be selected as changes. Duplicate keys are rejected by the existing parser.

A successful replacement import clears unsent pairs; a failed import keeps existing pairs but invalidates the preview. Editing either location, purpose, budget or task draft requires a new preview. Context/gateway changes clear imported snapshots. Clear affects unsent preparation; Remove comparison block affects only that block in the task draft. Preparation is not persisted across reloads.
