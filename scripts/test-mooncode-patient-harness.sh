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
  '{"type":"event","event":{"journal_sequence":"98","command_id":"cmd-test","kind":"runtime.turn_cancelled","status":"cancelled","detail":"stale terminal"}}' \
  '{"type":"event","event":{"journal_sequence":"239","target_command_id":"cmd-test","kind":"tool.approval_approved","state":"approved","approval_id":"approval-test"}}' \
  '{"type":"event","event":{"journal_sequence":"239","command_id":"cmd-test","kind":"runtime.turn_finished","status":"done","detail":"fixture complete"}}' \
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
[[ "$output" != *"stale terminal"* ]]
[[ -s "$marker" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "5")] | length' "$evidence")" == "1" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "98")] | length' "$evidence")" == "2" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "239")] | length' "$evidence")" == "2" ]]
[[ "$(jq -s '[.[] | select(.type == "event" and .event.journal_sequence == "240")] | length' "$evidence")" == "1" ]]

printf 'patient harness resume cursor test passed\n'
