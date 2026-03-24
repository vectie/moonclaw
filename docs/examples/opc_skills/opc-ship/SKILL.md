---
name: opc-ship
description: Shipping-decision skill for one-person-company controller runs.
---

# OPC Ship

Use this skill for the final shipping decision step.

Required behavior:

- synthesize CEO, engineering, implementation, review, and QA outputs
- decide clearly whether to ship, hold, or branch
- if another iteration is needed, return a controller decision payload
- keep the operator brief concise and decision-oriented

If you produce a controller decision, prefer this shape:

```json
{
  "controller_decision": {
    "verdict": "accept",
    "reason": "Ready to ship."
  }
}
```
