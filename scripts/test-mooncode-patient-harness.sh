#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/bin"

request="$fixture_root/request.json"
evidence="$fixture_root/evidence.jsonl"
marker="$fixture_root/curl-args"

printf '%s\n' \
  '{"session_id":"session-test","book_root":"/book","packet":{"command_id":"cmd-test"}}' \
  >"$request"
printf '%s\n' \
  '{"type":"event","event":{"journal_sequence":"5","command_id":"cmd-test","kind":"command.queued_for_runtime_turn"}}' \
  '{"type":"event","event":{"journal_sequence":"98","target_command_id":"cmd-test","kind":"tool.approval_requested","state":"pending","approval_id":"approval-test"}}' \
  '{"type":"event","event":{"journal_sequence":"239","target_command_id":"cmd-test","kind":"tool.approval_approved","state":"approved","approval_id":"approval-test"}}' \
  '{"type":"event","event":{"journal_sequence":"239","command_id":"cmd-test","kind":"runtime.turn_checkpointed","status":"running","detail":"patient fixture remains active"}}' \
  >"$evidence"

cat >"$fixture_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$HARNESS_TEST_MARKER"
if [[ "$*" != *"since=239"* ]]; then
  printf 'expected numeric resume cursor since=239, got: %s\n' "$*" >&2
  exit 1
fi
printf '%s\n' \
  '{"type":"meta","next_since":"240","emitted_count":"1"}' \
  '{"type":"event","event":{"journal_sequence":"240","command_id":"cmd-test","kind":"runtime.turn_finished","status":"done","detail":"fixture complete"}}' \
  '{"type":"done","next_since":"240","emitted_count":"1"}' \
  '200'
EOF
chmod +x "$fixture_root/bin/curl"

output="$(
  PATH="$fixture_root/bin:$PATH" \
    HARNESS_TEST_MARKER="$marker" \
    MOONCODE_HARNESS_WAIT_MS=0 \
    "$repo_root/scripts/mooncode-patient-harness.sh" \
      --url http://fixture.invalid \
      --request "$request" \
      --evidence "$evidence" \
      --resume
)"

[[ "$output" == *"after journal sequence 239"* ]]
[[ "$output" == *"fixture complete"* ]]
[[ "$output" != *"operator approval required"* ]]
[[ -s "$marker" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "5")] | length' "$evidence")" == "1" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "98")] | length' "$evidence")" == "1" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "239")] | length' "$evidence")" == "2" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "240")] | length' "$evidence")" == "1" ]]

terminal_evidence="$fixture_root/terminal-evidence.jsonl"
rm -f "$marker"
printf '%s\n' \
  '{"type":"event","event":{"journal_sequence":"5","command_id":"cmd-test","kind":"command.queued_for_runtime_turn"}}' \
  '{"type":"event","event":{"journal_sequence":"238","command_id":"cmd-test","kind":"runtime.commit_created","status":"done","commit_sha":"ccf291e8"}}' \
  '{"type":"event","event":{"journal_sequence":"239","command_id":"cmd-test","kind":"runtime.turn_checkpointed","status":"running"}}' \
  '{"type":"event","event":{"journal_sequence":"240","command_id":"cmd-test","kind":"finish","status":"done","tool":"finish","detail":"finished"}}' \
  '{"type":"event","event":{"journal_sequence":"241","command_id":"cmd-test","kind":"runtime.turn_finished","status":"done","detail":"committed fixture complete"}}' \
  >"$terminal_evidence"

terminal_output="$(
  PATH="$fixture_root/bin:$PATH" \
    HARNESS_TEST_MARKER="$marker" \
    MOONCODE_HARNESS_WAIT_MS=0 \
    "$repo_root/scripts/mooncode-patient-harness.sh" \
      --url http://fixture.invalid \
      --request "$request" \
      --evidence "$terminal_evidence" \
      --resume
)"

[[ "$terminal_output" == *"committed fixture complete"* ]]
[[ "$terminal_output" == *"observer audit required"* ]]
[[ ! -e "$marker" ]]
[[ "$(jq -s '[.[] | select(.type == "harness_summary" and .status == "worker_completed")] | length' "$terminal_evidence")" == "1" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and (.event.kind == "moon_cmd.finished" or .event.kind == "runtime.planner_started"))] | length' "$terminal_evidence")" == "0" ]]

quota_evidence="$fixture_root/quota-evidence.jsonl"
quota_marker="$fixture_root/quota-marker"
printf '%s\n' \
  '{"type":"event","event":{"journal_sequence":"5","command_id":"cmd-test","kind":"command.queued_for_runtime_turn"}}' \
  '{"type":"event","event":{"journal_sequence":"6","command_id":"cmd-test","kind":"runtime.turn_checkpointed","status":"paused","state":"planner-transport-paused","detail":"HTTP 429 AccountQuotaExceeded; reset at 2099-08-10 00:00:00 +0800 CST"}}' \
  '{"type":"event","event":{"journal_sequence":"7","command_id":"cmd-test","kind":"runtime.service_finished","status":"done"}}' \
  >"$quota_evidence"

cat >"$fixture_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"runtime-service"* ]]; then
  printf 'unexpected runtime-service restart\n' >>"$HARNESS_TEST_MARKER"
  exit 1
fi
printf '%s\n' \
  '{"type":"meta","next_since":"7","emitted_count":"0"}' \
  '{"type":"done","next_since":"7","emitted_count":"0"}' \
  '200'
EOF
chmod +x "$fixture_root/bin/curl"

cat >"$fixture_root/bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'quota-wait=%s\n' "$1" >>"$HARNESS_TEST_MARKER"
kill -TERM "$PPID"
exit 0
EOF
chmod +x "$fixture_root/bin/sleep"

set +e
quota_output="$(
  PATH="$fixture_root/bin:$PATH" \
    HARNESS_TEST_MARKER="$quota_marker" \
    MOONCODE_HARNESS_WAIT_MS=0 \
    "$repo_root/scripts/mooncode-patient-harness.sh" \
      --url http://fixture.invalid \
      --request "$request" \
      --evidence "$quota_evidence" \
      --resume 2>&1
)"
quota_status=$?
set -e

[[ "$quota_status" == "130" ]]
[[ "$quota_output" == *"waiting 60s without restarting runtime service"* ]]
[[ "$(cat "$quota_marker")" == "quota-wait=60" ]]
[[ "$quota_output" != *"runtime service"* ]]

printf 'patient harness terminal freeze tests passed\n'
