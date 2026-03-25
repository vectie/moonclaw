#!/usr/bin/env python3
"""
MoonClaw robot DDS bridge starter.

This program is intentionally structured as a real adapter skeleton:
- reads one JSON request from stdin
- maps it to a typed action
- loads bridge config
- calls a backend
- writes one JSON response to stdout

Default backend is `stub`, so it works immediately.
For your own board, implement CustomDDSBackend plus DDSRuntime/BoardTransport.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass
from typing import Any


ACTION_SPECS: dict[str, dict[str, Any]] = {
    "inspect": {
        "default_params": {},
        "safety_class": "inspect_only",
        "summary": "Inspecting current robot state.",
    },
    "stand": {
        "default_params": {},
        "safety_class": "high_level_motion",
        "summary": "Standing in a stable pose.",
    },
    "wave": {
        "default_params": {"arm": "right"},
        "safety_class": "high_level_motion",
        "summary": "Waving at the operator.",
    },
    "walk": {
        "default_params": {"x": 0.2, "yaw": 0.0, "duration_ms": 3000},
        "safety_class": "high_level_motion",
        "summary": "Walking with the requested base motion.",
    },
    "turn": {
        "default_params": {"yaw": 0.5, "duration_ms": 2000},
        "safety_class": "high_level_motion",
        "summary": "Turning in place.",
    },
    "go_home": {
        "default_params": {},
        "safety_class": "high_level_motion",
        "summary": "Returning to the home pose.",
    },
    "stop": {
        "default_params": {},
        "safety_class": "high_level_motion",
        "summary": "Stopping active motion.",
    },
}


@dataclass
class BridgeRequest:
    prompt: str
    execution_mode: str
    execution_target: str
    cwd: str
    metadata: dict[str, Any]
    raw: dict[str, Any]


@dataclass
class RobotAction:
    name: str
    params: dict[str, Any]
    safety_class: str


@dataclass
class RobotBackendConfig:
    robot_id: str
    dds_domain: str
    dds_task_topic: str
    dds_status_topic: str
    board_uri: str
    dry_run: bool
    allow_motion: bool
    allowed_actions: set[str]
    board_connect_command: str
    board_safe_mode_command: str
    dds_connect_command: str
    dds_publish_command: str
    dds_wait_command: str


def action_with_defaults(
    name: str,
    params: dict[str, Any] | None = None,
    safety_class: str | None = None,
) -> RobotAction:
    spec = ACTION_SPECS.get(name)
    if spec is None:
        raise ValueError(
            f"Unknown robot action '{name}'. Allowed actions: {', '.join(sorted(ACTION_SPECS))}"
        )
    merged_params = dict(spec["default_params"])
    if isinstance(params, dict):
        merged_params.update(params)
    resolved_safety = str(safety_class or spec["safety_class"]).strip()
    if not resolved_safety:
        resolved_safety = str(spec["safety_class"])
    return RobotAction(name, merged_params, resolved_safety)


def action_summary(action: RobotAction) -> str:
    spec = ACTION_SPECS.get(action.name)
    if spec is None:
        return f"Executing '{action.name}'."
    return str(spec["summary"])


def load_request() -> BridgeRequest:
    raw_text = sys.stdin.read()
    try:
        payload = json.loads(raw_text) if raw_text.strip() else {}
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON request: {exc}") from exc
    return BridgeRequest(
        prompt=str(payload.get("prompt", "") or ""),
        execution_mode=str(payload.get("execution_mode", "") or "robot.dds"),
        execution_target=str(payload.get("execution_target", "") or "robot-main"),
        cwd=str(payload.get("cwd", "") or os.getcwd()),
        metadata=dict(payload.get("metadata", {}) or {}),
        raw=payload,
    )


def infer_action(prompt: str, metadata: dict[str, Any]) -> RobotAction:
    explicit_name = str(metadata.get("robot_action", "") or "").strip()
    explicit_params = metadata.get("robot_params", {})
    explicit_safety = str(
        metadata.get("robot_safety_class", "") or "inspect_only"
    ).strip()
    if explicit_name:
        params = explicit_params if isinstance(explicit_params, dict) else {}
        return action_with_defaults(
            explicit_name,
            params,
            explicit_safety or None,
        )
    text = prompt.lower()
    if "wave" in text:
        return action_with_defaults("wave")
    if "turn" in text:
        return action_with_defaults("turn")
    if "home" in text:
        return action_with_defaults("go_home")
    if "walk" in text:
        return action_with_defaults("walk")
    if "stop" in text:
        return action_with_defaults("stop")
    if "stand" in text:
        return action_with_defaults("stand")
    return action_with_defaults("inspect")


def load_backend_config(request: BridgeRequest) -> RobotBackendConfig:
    allowed_actions_raw = os.environ.get(
        "ROBOT_ALLOWED_ACTIONS", ",".join(sorted(ACTION_SPECS))
    )
    allowed_actions = {
        item.strip() for item in allowed_actions_raw.split(",") if item.strip()
    }
    return RobotBackendConfig(
        robot_id=request.execution_target,
        dds_domain=os.environ.get("ROBOT_DDS_DOMAIN", "17"),
        dds_task_topic=os.environ.get("ROBOT_DDS_TASK_TOPIC", "robot/task_request"),
        dds_status_topic=os.environ.get("ROBOT_DDS_STATUS_TOPIC", "robot/task_status"),
        board_uri=os.environ.get("ROBOT_BOARD_URI", "board://localhost"),
        dry_run=os.environ.get("MOONCLAW_ROBOT_DRY_RUN", "true").strip().lower() in {
            "1",
            "true",
            "yes",
        },
        allow_motion=os.environ.get("MOONCLAW_ROBOT_ALLOW_MOTION", "")
        .strip()
        .lower()
        in {"1", "true", "yes"},
        allowed_actions=allowed_actions,
        board_connect_command=os.environ.get("ROBOT_BOARD_CONNECT_COMMAND", "").strip(),
        board_safe_mode_command=os.environ.get(
            "ROBOT_BOARD_SAFE_MODE_COMMAND", ""
        ).strip(),
        dds_connect_command=os.environ.get("ROBOT_DDS_CONNECT_COMMAND", "").strip(),
        dds_publish_command=os.environ.get("ROBOT_DDS_PUBLISH_COMMAND", "").strip(),
        dds_wait_command=os.environ.get("ROBOT_DDS_WAIT_COMMAND", "").strip(),
    )


def validate_action_policy(config: RobotBackendConfig, action: RobotAction) -> None:
    if action.name not in config.allowed_actions:
        allowed = ", ".join(sorted(config.allowed_actions))
        raise ValueError(
            f"Action '{action.name}' is not allowed for this target. Allowed actions: {allowed}"
        )
    if action.safety_class == "high_level_motion" and not (
        config.dry_run or config.allow_motion
    ):
        raise ValueError(
            "High-level motion is blocked. Set MOONCLAW_ROBOT_ALLOW_MOTION=true or keep MOONCLAW_ROBOT_DRY_RUN=true."
        )


class RobotBackend:
    def execute(
        self,
        request: BridgeRequest,
        config: RobotBackendConfig,
        action: RobotAction,
    ) -> dict[str, Any]:
        raise NotImplementedError


class StubBackend(RobotBackend):
    def execute(
        self,
        request: BridgeRequest,
        config: RobotBackendConfig,
        action: RobotAction,
    ) -> dict[str, Any]:
        return {
            "status": "completed",
            "content": f"Stub bridge accepted action '{action.name}' for {config.robot_id}.",
            "metadata": {
                "bridge": "stub",
                "task_id": f"stub-{config.robot_id}-{action.name}",
                "action": action.name,
                "params": action.params,
                "safety_class": action.safety_class,
                "robot_id": config.robot_id,
                "summary": action_summary(action),
            },
        }


class DDSRuntime:
    """
    Replace this with your real DDS initialization and topic I/O.
    """

    def __init__(self, config: RobotBackendConfig) -> None:
        self.config = config

    def connect(self) -> None:
        if not self.config.dds_connect_command:
            return
        run_hook_command(
            self.config.dds_connect_command,
            {
                "kind": "dds.connect",
                "robot_id": self.config.robot_id,
                "dds_domain": self.config.dds_domain,
                "task_topic": self.config.dds_task_topic,
                "status_topic": self.config.dds_status_topic,
            },
        )

    def publish_task(self, action: RobotAction) -> None:
        if not self.config.dds_publish_command:
            raise NotImplementedError(
                "DDSRuntime.publish_task is not implemented. Set ROBOT_DDS_PUBLISH_COMMAND."
            )
        run_hook_command(
            self.config.dds_publish_command,
            {
                "kind": "dds.publish_task",
                "robot_id": self.config.robot_id,
                "dds_domain": self.config.dds_domain,
                "task_topic": self.config.dds_task_topic,
                "action": action.name,
                "params": action.params,
                "safety_class": action.safety_class,
            },
        )

    def wait_for_result(self) -> dict[str, Any]:
        if not self.config.dds_wait_command:
            raise NotImplementedError(
                "DDSRuntime.wait_for_result is not implemented. Set ROBOT_DDS_WAIT_COMMAND."
            )
        return run_hook_command(
            self.config.dds_wait_command,
            {
                "kind": "dds.wait_result",
                "robot_id": self.config.robot_id,
                "dds_domain": self.config.dds_domain,
                "status_topic": self.config.dds_status_topic,
            },
            expect_json=True,
        )


class BoardTransport:
    """
    Replace this with your board transport/session manager if needed.
    """

    def __init__(self, config: RobotBackendConfig) -> None:
        self.config = config

    def connect(self) -> None:
        if not self.config.board_connect_command:
            return
        run_hook_command(
            self.config.board_connect_command,
            {
                "kind": "board.connect",
                "robot_id": self.config.robot_id,
                "board_uri": self.config.board_uri,
            },
        )

    def ensure_safe_mode_for_action(self, action: RobotAction) -> None:
        if not self.config.board_safe_mode_command:
            return
        run_hook_command(
            self.config.board_safe_mode_command,
            {
                "kind": "board.ensure_safe_mode",
                "robot_id": self.config.robot_id,
                "board_uri": self.config.board_uri,
                "action": action.name,
                "safety_class": action.safety_class,
            },
        )


def run_hook_command(
    command: str,
    payload: dict[str, Any],
    *,
    expect_json: bool = False,
) -> dict[str, Any]:
    args = shlex.split(command)
    if not args:
        raise ValueError("Hook command is empty")
    completed = subprocess.run(
        args,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        raise RuntimeError(
            f"Hook command failed with exit code {completed.returncode}"
            + (f": {stderr}" if stderr else "")
        )
    stdout = completed.stdout.strip()
    if not expect_json:
        if not stdout:
            return {}
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            return {"stdout": stdout}
    if not stdout:
        raise RuntimeError("Hook command did not return JSON output")
    try:
        parsed = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Hook command returned invalid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("Hook command JSON output must be an object")
    return parsed


class CustomDDSBackend(RobotBackend):
    """
    This is the implementation point for your own board + DDS stack.

    Suggested integration steps:
    1. connect board transport
    2. connect DDS runtime
    3. validate safe mode
    4. publish task request
    5. wait for status/result
    6. return concise JSON to MoonClaw
    """

    def __init__(
        self,
        dds_runtime_cls: type[DDSRuntime] = DDSRuntime,
        board_transport_cls: type[BoardTransport] = BoardTransport,
    ) -> None:
        self.dds_runtime_cls = dds_runtime_cls
        self.board_transport_cls = board_transport_cls

    def execute(
        self,
        request: BridgeRequest,
        config: RobotBackendConfig,
        action: RobotAction,
    ) -> dict[str, Any]:
        if config.dry_run:
            return {
                "status": "completed",
                "content": f"Custom backend dry-run accepted '{action.name}' for {config.robot_id}.",
                "metadata": {
                    "bridge": "custom-dds",
                    "dry_run": True,
                    "task_id": f"dryrun-{config.robot_id}-{action.name}",
                    "action": action.name,
                    "params": action.params,
                    "safety_class": action.safety_class,
                    "robot_id": config.robot_id,
                    "summary": action_summary(action),
                    "dds_domain": config.dds_domain,
                    "task_topic": config.dds_task_topic,
                    "status_topic": config.dds_status_topic,
                    "board_uri": config.board_uri,
                },
            }

        board = self.board_transport_cls(config)
        dds = self.dds_runtime_cls(config)

        board.connect()
        board.ensure_safe_mode_for_action(action)
        dds.connect()
        dds.publish_task(action)
        result = dds.wait_for_result()

        return {
            "status": "completed",
            "content": str(
                result.get(
                    "summary",
                    f"Custom backend executed '{action.name}' for {config.robot_id}.",
                )
            ),
            "metadata": {
                "bridge": "custom-dds",
                "dry_run": False,
                "task_id": str(
                    result.get("task_id", f"custom-{config.robot_id}-{action.name}")
                ),
                "action": action.name,
                "params": action.params,
                "safety_class": action.safety_class,
                "robot_id": config.robot_id,
                "summary": action_summary(action),
                "dds_domain": config.dds_domain,
                "task_topic": config.dds_task_topic,
                "status_topic": config.dds_status_topic,
                "board_uri": config.board_uri,
                "result": result,
            },
        }


def select_backend() -> RobotBackend:
    backend = os.environ.get("MOONCLAW_ROBOT_BACKEND", "stub").strip().lower()
    if backend == "custom":
        return CustomDDSBackend()
    return StubBackend()


def main() -> int:
    try:
        request = load_request()
        action = infer_action(request.prompt, request.metadata)
        config = load_backend_config(request)
        validate_action_policy(config, action)
        backend = select_backend()
        response = backend.execute(request, config, action)
    except Exception as exc:  # noqa: BLE001
        response = {
            "status": "failed",
            "error": str(exc),
        }
    sys.stdout.write(json.dumps(response))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
