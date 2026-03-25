#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from typing import Any


def load_payload() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("Hook payload must be a JSON object")
    return payload


def main() -> int:
    payload = load_payload()
    kind = str(payload.get("kind", "") or "")
    robot_id = str(payload.get("robot_id", "") or "robot-main")
    action = str(payload.get("action", "") or "inspect")

    if kind == "board.connect":
        sys.stdout.write(json.dumps({"status": "connected", "robot_id": robot_id}))
        return 0
    if kind == "board.ensure_safe_mode":
        sys.stdout.write(
            json.dumps(
                {
                    "status": "ok",
                    "robot_id": robot_id,
                    "safety_class": payload.get("safety_class", "inspect_only"),
                }
            )
        )
        return 0
    if kind == "dds.connect":
        sys.stdout.write(json.dumps({"status": "connected"}))
        return 0
    if kind == "dds.publish_task":
        sys.stdout.write(
            json.dumps(
                {
                    "status": "published",
                    "task_id": f"example-{robot_id}-{action}",
                }
            )
        )
        return 0
    if kind == "dds.wait_result":
        sys.stdout.write(
            json.dumps(
                {
                    "task_id": f"example-{robot_id}",
                    "summary": f"Example hook completed for {robot_id}.",
                    "status": "completed",
                }
            )
        )
        return 0

    sys.stdout.write(json.dumps({"status": "ignored", "kind": kind}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
