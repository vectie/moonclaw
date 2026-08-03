#!/usr/bin/env python3
import json
import sys


def infer_action(prompt: str, metadata: dict) -> str:
    explicit = str(metadata.get("robot_action", "") or "").strip()
    if explicit:
        return explicit
    text = prompt.lower()
    if "wave" in text:
        return "wave"
    if "turn" in text:
        return "turn"
    if "home" in text:
        return "go_home"
    if "walk" in text:
        return "walk"
    if "stop" in text:
        return "stop"
    return "inspect"


def main() -> int:
    raw = sys.stdin.read()
    try:
        request = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError as exc:
        sys.stdout.write(
            json.dumps(
                {
                    "status": "failed",
                    "error": f"Invalid JSON request: {exc}",
                }
            )
        )
        return 0

    prompt = str(request.get("prompt", "") or "")
    metadata = request.get("metadata", {})
    if not isinstance(metadata, dict):
        metadata = {}
    target = str(request.get("execution_target", "") or "robot-main")
    action = infer_action(prompt, metadata)

    response = {
      "status": "completed",
      "content": f"Stub bridge accepted action '{action}' for {target}.",
      "metadata": {
        "bridge": "stub",
        "action": action,
        "robot_params": metadata.get("robot_params", {}),
        "robot_safety_class": metadata.get("robot_safety_class", "inspect_only"),
        "robot_id": target,
      },
    }
    sys.stdout.write(json.dumps(response))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
