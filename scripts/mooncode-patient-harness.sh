#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mooncode-patient-harness.sh --url URL --request REQUEST.json
    [--evidence EVIDENCE.jsonl] [--resume]

REQUEST.json is a normal POST /v1/code/sessions/{id}/turns body. The prompt is
the source of task intent. Optional task_contract hints remain part of that
request; this harness does not prescribe milestones, files, or tool calls.

The harness submits the worker turn once, follows durable journal events
without a task timeout, resumes the runtime service after a daemon interruption,
and stops only for worker completion, failure, cancellation, or operator
approval. Worker completion is a candidate result; an independent observer must
compare its evidence with the prompt contract before the task is accepted.

Options:
  --url URL       MoonClaw daemon base URL
  --request FILE  Complete MoonCode turn request
  --evidence FILE Write command-scoped JSONL for a read-only observer
  --resume        Do not append the turn again; supervise its durable session
  -h, --help      Show this help
EOF
}

fail() {
  printf 'mooncode patient harness: %s\n' "$*" >&2
  exit 64
}

base_url=""
request_file=""
evidence_file=""
resume_only=false
retry_seconds="${MOONCODE_HARNESS_RETRY_SECONDS:-1}"
wait_ms="${MOONCODE_HARNESS_WAIT_MS:-30000}"
poll_ms="${MOONCODE_HARNESS_POLL_MS:-250}"
connect_timeout_seconds="${MOONCODE_HARNESS_CONNECT_TIMEOUT_SECONDS:-5}"
request_timeout_seconds="${MOONCODE_HARNESS_REQUEST_TIMEOUT_SECONDS:-30}"

while (($# > 0)); do
  case "$1" in
    --url)
      (($# >= 2)) || fail "--url requires a value"
      base_url="${2%/}"
      shift 2
      ;;
    --request)
      (($# >= 2)) || fail "--request requires a value"
      request_file="$2"
      shift 2
      ;;
    --evidence)
      (($# >= 2)) || fail "--evidence requires a value"
      evidence_file="$2"
      shift 2
      ;;
    --resume)
      resume_only=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$base_url" ]] || fail "--url is required"
[[ -n "$request_file" ]] || fail "--request is required"
[[ -r "$request_file" ]] || fail "cannot read request: $request_file"
command -v curl >/dev/null || fail "curl is required"
command -v jq >/dev/null || fail "jq is required"
[[ "$wait_ms" =~ ^[0-9]+$ ]] || fail "MOONCODE_HARNESS_WAIT_MS must be an integer"
[[ "$poll_ms" =~ ^[0-9]+$ ]] || fail "MOONCODE_HARNESS_POLL_MS must be an integer"
[[ "$connect_timeout_seconds" =~ ^[0-9]+$ ]] ||
  fail "MOONCODE_HARNESS_CONNECT_TIMEOUT_SECONDS must be an integer"
[[ "$request_timeout_seconds" =~ ^[0-9]+$ ]] ||
  fail "MOONCODE_HARNESS_REQUEST_TIMEOUT_SECONDS must be an integer"
[[ "$retry_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  fail "MOONCODE_HARNESS_RETRY_SECONDS must be numeric"

request_json="$(jq -c . "$request_file")" ||
  fail "request is not valid JSON: $request_file"
session_id="$(jq -er '.session_id | select(type == "string" and length > 0)' <<<"$request_json")" ||
  fail "request.session_id must be a non-empty string"
book_root="$(jq -er '.book_root | select(type == "string" and length > 0)' <<<"$request_json")" ||
  fail "request.book_root must be a non-empty string"
command_id="$(jq -er '.packet.command_id | select(type == "string" and length > 0)' <<<"$request_json")" ||
  fail "request.packet.command_id must be a non-empty string"
session_path="$(jq -nr --arg value "$session_id" '$value | @uri')"
turn_url="$base_url/v1/code/sessions/$session_path/turns"
service_url="$base_url/v1/code/sessions/$session_path/runtime-service"
stream_url="$base_url/v1/code/sessions/$session_path/stream"
resume_json="$(jq -nc --arg book_root "$book_root" '{book_root: $book_root}')"
stream_timeout_seconds="$(((wait_ms + 999) / 1000 + request_timeout_seconds))"
latest_sequence=0
command_sequence=0
approval=""
approval_id=""
target_status=""
target_detail=""

record_evidence() {
  [[ -n "$evidence_file" ]] || return
  printf '%s\n' "$1" >>"$evidence_file"
}

finish_harness() {
  local status="$1"
  local exit_code="$2"
  local detail="$3"
  record_evidence "$(
    jq -nc \
      --arg status "$status" \
      --arg session_id "$session_id" \
      --arg command_id "$command_id" \
      --arg book_root "$book_root" \
      --arg detail "$detail" \
      --argjson exit_code "$exit_code" \
      --argjson latest_sequence "$latest_sequence" '
        {
          type: "harness_summary",
          status: $status,
          exit_code: $exit_code,
          session_id: $session_id,
          command_id: $command_id,
          book_root: $book_root,
          latest_sequence: $latest_sequence,
          detail: $detail
        }
      '
  )"
  if [[ -n "$evidence_file" ]]; then
    printf 'observer evidence: %s\n' "$evidence_file"
  fi
  exit "$exit_code"
}

if [[ -n "$evidence_file" ]]; then
  evidence_parent="$(dirname "$evidence_file")"
  [[ -d "$evidence_parent" ]] ||
    fail "evidence parent directory does not exist: $evidence_parent"
  if [[ "$resume_only" == false || ! -e "$evidence_file" ]]; then
    : >"$evidence_file"
  elif [[ -s "$evidence_file" ]]; then
    evidence_state="$(
      jq -nc \
        --arg command_id "$command_id" '
          reduce inputs as $row (
            {
              latest_sequence: 0,
              command_sequence: 0,
              approval_sequence: 0,
              approval: {},
              terminal_sequence: 0,
              terminal: {}
            };
            if ($row.type // "") != "event" then
              .
            else
              ($row.event // {}) as $event
              | ($event.journal_sequence // 0) as $sequence
              | .latest_sequence = (
                  if $sequence > .latest_sequence then
                    $sequence
                  else
                    .latest_sequence
                  end
                )
              | if (
                  ($event.command_id // "") == $command_id
                  and ($event.kind // "") == "command.queued_for_runtime_turn"
                ) then
                  .command_sequence = (
                    if (
                      .command_sequence == 0
                      or $sequence < .command_sequence
                    ) then
                      $sequence
                    else
                      .command_sequence
                    end
                  )
                else
                  .
                end
              | if (
                  ($event.target_command_id // $event.command_id // "") ==
                  $command_id
                  and (
                    ($event.kind // "") == "tool.approval_requested"
                    or ($event.kind // "") == "tool.approval_approved"
                    or ($event.kind // "") == "tool.approval_rejected"
                  )
                  and $sequence >= .approval_sequence
                ) then
                  .approval_sequence = $sequence
                  | .approval = $event
                else
                  .
                end
              | if (
                  ($event.command_id // "") == $command_id
                  and (
                    ($event.kind // "") == "runtime.turn_finished"
                    or ($event.kind // "") == "runtime.turn_cancelled"
                    or ($event.kind // "") == "runtime.turn_invalid"
                  )
                  and $sequence >= .terminal_sequence
                ) then
                  .terminal_sequence = $sequence
                  | .terminal = $event
                else
                  .
                end
            end
          )
        ' "$evidence_file"
    )"
    latest_sequence="$(jq -r '.latest_sequence' <<<"$evidence_state")"
    command_sequence="$(jq -r '.command_sequence' <<<"$evidence_state")"
    approval="$(jq -rc '
      .approval
      | select(
          (.kind // "") == "tool.approval_requested"
          and (.state // "") == "pending"
        ) // empty
    ' <<<"$evidence_state")"
    approval_id="$(jq -r '.approval_id // ""' <<<"$approval")"
    terminal="$(jq -rc '.terminal | select(length > 0) // empty' <<<"$evidence_state")"
    if [[ -n "$terminal" ]]; then
      case "$(jq -r '.kind // ""' <<<"$terminal")" in
        runtime.turn_finished)
          target_status="$(jq -r '.status // ""' <<<"$terminal")"
          target_detail="$(
            jq -r '.detail // "runtime turn finished"' <<<"$terminal"
          )"
          ;;
        runtime.turn_cancelled)
          target_status="cancelled"
          target_detail="$(
            jq -r '.detail // "runtime turn cancelled"' <<<"$terminal"
          )"
          ;;
        runtime.turn_invalid)
          target_status="failed"
          target_detail="$(
            jq -r '.detail // "runtime turn is invalid"' <<<"$terminal"
          )"
          ;;
      esac
    fi
  fi
  record_evidence "$(
    jq -nc \
      --arg session_id "$session_id" \
      --arg command_id "$command_id" \
      --arg book_root "$book_root" \
      --argjson resume "$resume_only" \
      --argjson request "$request_json" '
        {
          type: "harness_start",
          session_id: $session_id,
          command_id: $command_id,
          book_root: $book_root,
          resume: $resume,
          request: $request
        }
      '
  )"
  printf 'recording observer evidence: %s\n' "$evidence_file"
fi

trap 'finish_harness "supervisor_interrupted" 130 "Supervision stopped without cancelling MoonCode."' INT TERM

post_json() {
  local url="$1"
  local body="$2"
  local raw
  local http_status
  local response
  if ! raw="$(
    curl \
      --silent \
      --show-error \
      --connect-timeout "$connect_timeout_seconds" \
      --max-time "$request_timeout_seconds" \
      --header 'Content-Type: application/json' \
      --data-binary "$body" \
      --write-out $'\n%{http_code}' \
      "$url"
  )"; then
    return 75
  fi
  http_status="${raw##*$'\n'}"
  response="${raw%$'\n'*}"
  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    printf '%s' "$response"
    return 0
  fi
  printf 'request rejected with HTTP %s: %s\n' "$http_status" "$response" >&2
  if [[ "$http_status" =~ ^5[0-9][0-9]$ ]]; then
    return 75
  fi
  return 65
}

submit_turn() {
  local response
  local result
  while true; do
    if response="$(post_json "$turn_url" "$request_json")"; then
      jq -e '.accepted == true' >/dev/null <<<"$response" ||
        fail "daemon rejected turn: $response"
      printf 'submitted command %s in session %s\n' "$command_id" "$session_id"
      return
    else
      result=$?
    fi
    if [[ "$result" == "65" ]]; then
      finish_harness "request_rejected" 65 "MoonClaw rejected the turn request."
    fi
    printf 'daemon unavailable while submitting; durable command id %s will be retried\n' \
      "$command_id" >&2
    sleep "$retry_seconds"
  done
}

resume_service() {
  local response
  local result
  if response="$(post_json "$service_url" "$resume_json")"; then
    printf 'runtime service %s\n' "$(jq -r '.status // "accepted"' <<<"$response")"
    return 0
  else
    result=$?
  fi
  if [[ "$result" == "65" ]]; then
    finish_harness "resume_rejected" 65 "MoonClaw rejected runtime resume."
  fi
  printf 'daemon unavailable while resuming; supervision will keep waiting\n' >&2
  return 1
}

read_stream() {
  local raw
  local http_status
  local response
  if ! raw="$(
    curl \
      --silent \
      --show-error \
      --connect-timeout "$connect_timeout_seconds" \
      --max-time "$stream_timeout_seconds" \
      --get \
      --data-urlencode "book_root=$book_root" \
      --data-urlencode "format=jsonl" \
      --data-urlencode "since=$since" \
      --data-urlencode "wait_ms=$wait_ms" \
      --data-urlencode "poll_ms=$poll_ms" \
      --write-out $'\n%{http_code}' \
      "$stream_url"
  )"; then
    return 75
  fi
  http_status="${raw##*$'\n'}"
  response="${raw%$'\n'*}"
  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    printf '%s' "$response"
    return 0
  fi
  printf 'stream rejected with HTTP %s: %s\n' "$http_status" "$response" >&2
  if [[ "$http_status" =~ ^5[0-9][0-9]$ ]]; then
    return 75
  fi
  return 65
}

print_event() {
  jq -r '
    [
      (.journal_sequence // 0 | tostring),
      (.kind // "event"),
      (.status // .state // ""),
      (.title // ""),
      (.detail // "")
    ] | @tsv
  ' <<<"$1"
}

if [[ "$resume_only" == false ]]; then
  submit_turn
else
  printf 'resuming supervision for command %s in session %s after journal sequence %s\n' \
    "$command_id" "$session_id" "$latest_sequence"
fi

since="$latest_sequence"
while true; do
  stream=""
  if stream="$(read_stream)"; then
    :
  else
    stream_result=$?
    if [[ "$stream_result" == "65" ]]; then
      finish_harness "stream_rejected" 65 "MoonClaw rejected the event stream request."
    fi
    printf 'daemon unavailable; MoonCode was not cancelled and supervision will retry\n' >&2
    sleep "$retry_seconds"
    continue
  fi

  next_since="$(jq -rs 'map(select(.type == "meta")) | last | .next_since // 0' <<<"$stream")"
  emitted_count="$(jq -rs 'map(select(.type == "meta")) | last | .emitted_count // 0' <<<"$stream")"
  latest_sequence="$next_since"
  if [[ "$command_sequence" == "0" ]]; then
    command_sequence="$(
      jq -rs \
        --arg command_id "$command_id" '
          [
            .[]
            | select(.type == "event")
            | .event
            | select(
                .command_id == $command_id
                and .kind == "command.queued_for_runtime_turn"
            )
            | .journal_sequence
          ]
          | min // 0
        ' <<<"$stream"
    )"
  fi
  service_status=""
  service_detail=""
  while IFS= read -r event; do
    [[ -n "$event" ]] || continue
    print_event "$event"
    kind="$(jq -r '.kind // ""' <<<"$event")"
    status="$(jq -r '.status // .state // ""' <<<"$event")"
    event_command_id="$(jq -r '.command_id // ""' <<<"$event")"
    target_command_id="$(jq -r '.target_command_id // .command_id // ""' <<<"$event")"
    if [[ "$event_command_id" == "$command_id" ||
      "$target_command_id" == "$command_id" ||
      "$kind" == runtime.service_* ]]; then
      record_evidence "$(jq -c '{type: "event", event: .}' <<<"$event")"
    fi
    case "$kind" in
      tool.approval_requested)
        if [[ "$target_command_id" == "$command_id" &&
          "$(jq -r '.state // ""' <<<"$event")" == "pending" ]]; then
          approval="$event"
          approval_id="$(jq -r '.approval_id // ""' <<<"$event")"
        fi
        ;;
      tool.approval_approved | tool.approval_rejected)
        decision_id="$(jq -r '.approval_id // ""' <<<"$event")"
        if [[ -n "$approval_id" && "$decision_id" == "$approval_id" ]]; then
          approval=""
          approval_id=""
        fi
        ;;
      runtime.turn_finished)
        if [[ "$event_command_id" == "$command_id" ]]; then
          target_status="$status"
          target_detail="$(jq -r '.detail // "runtime turn finished"' <<<"$event")"
        fi
        ;;
      runtime.turn_cancelled)
        if [[ "$event_command_id" == "$command_id" ]]; then
          target_status="cancelled"
          target_detail="$(jq -r '.detail // "runtime turn cancelled"' <<<"$event")"
        fi
        ;;
      runtime.turn_invalid)
        if [[ "$event_command_id" == "$command_id" ]]; then
          target_status="failed"
          target_detail="$(jq -r '.detail // "runtime turn is invalid"' <<<"$event")"
        fi
        ;;
      runtime.service_started)
        service_status=""
        service_detail=""
        ;;
      runtime.service_failed)
        service_status="failed"
        service_detail="$(jq -r '.detail // "runtime service failed"' <<<"$event")"
        ;;
      runtime.service_finished)
        service_status="$status"
        service_detail="$(jq -r '.detail // "runtime service finished"' <<<"$event")"
        ;;
    esac
  done < <(
    jq -c \
      --argjson command_sequence "$command_sequence" '
        select(.type == "event")
        | .event
        | select(
            $command_sequence > 0
            and (.journal_sequence // 0) >= $command_sequence
          )
      ' <<<"$stream"
  )

  since="$next_since"

  if [[ -n "$approval" ]]; then
    printf 'operator approval required:\n%s\n' "$(jq . <<<"$approval")"
    finish_harness "approval_required" 2 "The target command requires operator approval."
  fi

  case "$target_status" in
    done)
      printf 'MoonCode worker completed command %s: %s\n' "$command_id" "$target_detail"
      if [[ -n "$evidence_file" ]]; then
        printf 'observer audit required before accepting the task result\n'
      fi
      finish_harness "worker_completed" 0 "$target_detail"
      ;;
    failed)
      printf 'MoonCode failed command %s: %s\n' "$command_id" "$target_detail" >&2
      finish_harness "failed" 1 "$target_detail"
      ;;
    cancelled)
      printf 'MoonCode cancelled command %s: %s\n' "$command_id" "$target_detail" >&2
      finish_harness "cancelled" 3 "$target_detail"
      ;;
  esac

  case "$service_status" in
    failed)
      printf 'MoonCode runtime service failed: %s\n' "$service_detail" >&2
      finish_harness "service_failed" 1 "$service_detail"
      ;;
  esac

  if [[ "$emitted_count" == "0" ||
    "$service_status" == "done" ||
    "$service_status" == "waiting" ||
    "$service_status" == "cancelled" ]]; then
    resume_service || sleep "$retry_seconds"
  fi
done
