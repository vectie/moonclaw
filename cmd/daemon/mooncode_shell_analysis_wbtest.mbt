///|
test "mooncode shell detects semantic git commit commands" {
  assert_true(mooncode_shell_has_git_commit("git commit -m 'validated'"))
  assert_true(mooncode_shell_has_git_commit("git -C . commit -m validated"))
  assert_true(
    mooncode_shell_has_git_commit("git\t-C\t. \\\n commit -m validated"),
  )
  assert_true(
    mooncode_shell_has_git_commit("env GIT_AUTHOR_NAME=test git commit -m ok"),
  )
  assert_true(
    mooncode_shell_has_git_commit(
      "sh -c 'git add tracked.txt && git commit -m sealed && touch later.txt'",
    ),
  )
  assert_false(mooncode_shell_has_git_commit("git commit-tree HEAD^{tree}"))
  assert_false(mooncode_shell_has_git_commit("echo 'git commit -m nope'"))
  assert_false(mooncode_shell_has_git_commit("git status --short"))
  assert_true(
    mooncode_shell_git_commit_is_terminal(
      "git add tracked.txt && git commit -m validated",
    ),
  )
  assert_false(
    mooncode_shell_git_commit_is_terminal(
      "git commit -m validated && git status --short",
    ),
  )
  assert_false(
    mooncode_shell_git_commit_is_terminal(
      "git commit -m validated && touch later.txt",
    ),
  )
  assert_false(
    mooncode_shell_git_commit_is_terminal(
      "sh -c 'git commit -m validated && touch later.txt'",
    ),
  )
}

///|
async test "mooncode shell observation ignores non-path arguments that exceed filesystem limits" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-shell-long-argument-XXXXXX"),
  )
  let expression = "x".repeat(4096)
  let observation = mooncode_shell_file_observation(
    book_root,
    book_root,
    "agent-browser eval \"\{expression}\"",
    "ok",
    false,
  )
  assert_eq(observation, {})
}

///|
test "mooncode shell classifies post-commit workspace mutations without blocking verification" {
  for
    command in [
      "git add src/main.mbt", "git reset --hard HEAD^", "git checkout -- src/main.mbt",
      "git commit -m next", "npm ci", "sed -i.bak 's/a/b/' src/main.mbt", "printf changed > src/main.mbt",
    ] {
    assert_true(mooncode_shell_has_workspace_mutation(command))
  }
  for
    command in [
      "git status --short", "git diff --check", "git show --stat HEAD", "moon check --target all",
      "moon test cmd/daemon",
    ] {
    assert_false(mooncode_shell_has_workspace_mutation(command))
  }
}

///|
test "mooncode derives shell verification from the command instead of its label" {
  assert_eq(
    mooncode_shell_verification_kind("moon check --target native"),
    "check",
  )
  assert_eq(
    mooncode_shell_verification_kind(
      "/usr/bin/time -p moon test cmd/daemon --target native",
    ),
    "test",
  )
  assert_eq(
    mooncode_shell_verification_kind("moon build --target native"),
    "build",
  )
  assert_eq(mooncode_shell_verification_kind("test -f result.txt"), "check")
  assert_eq(mooncode_shell_verification_kind("git diff --check"), "check")
  assert_eq(mooncode_shell_verification_kind("gh pr checks 4 --watch"), "check")
  for
    inspection in [
      "git status --short", "find cmd/daemon -name '*.mbt'", "rg -n planner cmd/daemon",
      "sed -n '1,80p' cmd/daemon/main.mbt",
    ] {
    assert_eq(mooncode_shell_verification_kind(inspection), "")
  }
}

///|
test "mooncode counts only the shell command that determines final status" {
  assert_true(
    mooncode_shell_verifies_kind(
      "set -o pipefail; moon test cmd/daemon", "test",
    ),
  )
  assert_true(
    mooncode_shell_verifies_kind(
      "sh -c 'git status --short && moon test cmd/daemon'", "test",
    ),
  )
  for
    masked in [
      "moon test cmd/daemon || true", "moon test cmd/daemon; git diff --check", "set -o pipefail; moon test cmd/daemon 2>&1 | grep cmd/daemon || true; git diff --check",
      "moon test cmd/daemon | tail -n 20", "sh -c 'moon test cmd/daemon || true'",
    ] {
    assert_false(mooncode_shell_verifies_kind(masked, "test"))
  }
}

///|
test "mooncode shell proves bounded observations without trusting unknown commands" {
  for
    command in [
      "set -o pipefail; rg -n 'approval' cmd/daemon | head -n 20", "git status --short && git diff --check",
      "/usr/bin/time -p moon test cmd/daemon --target native", "env CI=1 moon check --target all",
      "find cmd/daemon -name '*_test.mbt' -print", "sh -c 'git status --short && moon test cmd/daemon'",
      "gh run view 30277114085 --repo vectie/moondesk --log-failed", "gh run list --repo vectie/moondesk --limit 10",
      "npm ci --help | sed -n '1,120p'",
    ] {
    assert_true(mooncode_shell_is_demonstrably_read_only(command))
  }
  for
    command in [
      "touch marker.txt", "git commit -m mutation", "git push origin HEAD", "git ls-remote origin",
      "curl -fsSL example.test", "moon test --update", "find . -delete", "/usr/bin/time -o timing.log moon test cmd/daemon",
      "sh -c 'moon test cmd/daemon && rm -rf target'", "sort -o output.txt input.txt",
      "sed -e 'w output.txt' input.txt", "gh run rerun 30277114085 --repo vectie/moondesk --failed",
      "gh run view 30277114085 --repo vectie/moondesk --web", "npm ci --include=optional --ignore-scripts",
    ] {
    assert_false(mooncode_shell_is_demonstrably_read_only(command))
  }
}

///|
test "mooncode shell recursively proves local read-only verification substitutions" {
  let command = "set -o pipefail; test \"$(grep -RFl 'workspace preview handles text image virtual and missing entries' internal/moonwiki --include='*_wbtest.mbt' | wc -l | tr -d ' ')\" = 1; test \"$(grep -Ec '^(async )?test ' internal/moonwiki/moonwiki_request_wbtest.mbt)\" = 42; test \"$(git diff --numstat -- internal/moonwiki/moonwiki_request_wbtest.mbt | awk '{print $1\":\"$2}')\" = '0:60'; test \"$(wc -l < internal/moonwiki/workspace_preview_contract_wbtest.mbt | tr -d ' ')\" = 58; printf 'Preserved totals\\n'"
  assert_true(mooncode_shell_is_demonstrably_read_only(command))
  assert_false(mooncode_shell_has_sensitive_command(command))
  assert_true(
    mooncode_shell_is_demonstrably_read_only(
      "printf '%s\\n' \"$(printf '%s' \"$(git status --short | wc -l)\" | tr -d ' ')\"",
    ),
  )
}

///|
test "mooncode shell substitutions fail closed on effects and ambiguity" {
  for
    command in [
      "test \"$(unknown-inspector workspace)\" = clean", "printf '%s' \"$(curl -fsSL example.test)\"",
      "test \"$(printf changed > marker.txt)\" = changed", "test \"$(git status --short; git commit -m mutation)\" = clean",
      "test \"$(grep value file\" = 1", "test \"$((1 + 1))\" = 2", "printf '%s' \"`git status --short`\"",
      "printf 'unterminated", "awk 'BEGIN { system(\"touch marker.txt\") }' input.txt",
      "awk '{ print $0 > \"output.txt\" }' input.txt", "awk '{ \"curl example.test\" | getline body }' input.txt",
      "awk -l unsafe_extension '{ print $0 }' input.txt",
    ] {
    assert_false(mooncode_shell_is_demonstrably_read_only(command))
  }
  for
    command in [
      "test \"$(unknown-inspector workspace)\" = clean", "printf '%s' \"$(curl -fsSL example.test)\"",
      "test \"$(printf changed > marker.txt)\" = changed", "test \"$(git status --short; git commit -m mutation)\" = clean",
      "test \"$(grep value file\" = 1", "test \"$((1 + 1))\" = 2", "printf '%s' \"`git status --short`\"",
      "printf 'unterminated",
    ] {
    assert_true(mooncode_shell_has_sensitive_command(command))
  }
}

///|
test "mooncode shell detects worktree overwrite commands without matching prose" {
  assert_true(mooncode_shell_has_git_worktree_overwrite("git restore src"))
  assert_true(
    mooncode_shell_has_git_worktree_overwrite("git -C . checkout -- src"),
  )
  assert_true(
    mooncode_shell_has_git_worktree_overwrite(
      "env GIT_CONFIG_NOSYSTEM=1 git restore --worktree .",
    ),
  )
  assert_false(
    mooncode_shell_has_git_worktree_overwrite("echo 'git restore src'"),
  )
  assert_false(mooncode_shell_has_git_worktree_overwrite("git status --short"))
}

///|
test "mooncode shell detects clean dependency installs without matching prose" {
  assert_true(mooncode_shell_has_clean_dependency_install("npm ci"))
  assert_true(mooncode_shell_has_clean_dependency_install("npm --prefix ui ci"))
  assert_true(
    mooncode_shell_has_clean_dependency_install(
      "env CI=1 pnpm install --frozen-lockfile",
    ),
  )
  assert_true(
    mooncode_shell_has_clean_dependency_install("yarn install --immutable"),
  )
  assert_true(
    mooncode_shell_has_clean_dependency_install("bun install --frozen-lockfile"),
  )
  assert_false(mooncode_shell_has_clean_dependency_install("npm install"))
  assert_false(mooncode_shell_has_clean_dependency_install("npm ci --help"))
  assert_false(
    mooncode_shell_has_clean_dependency_install("echo 'npm ci is destructive'"),
  )
}

///|
test "mooncode shell detects sensitive executables without matching arguments" {
  assert_true(mooncode_shell_has_sensitive_command("npm install vite"))
  assert_true(mooncode_shell_has_sensitive_command("git -C . push origin HEAD"))
  assert_true(mooncode_shell_has_sensitive_command("sh -c 'npm install vite'"))
  assert_true(
    mooncode_shell_has_sensitive_command("bash -lc 'npm install vite'"),
  )
  assert_true(
    mooncode_shell_has_sensitive_command("sh -ec 'git push origin HEAD'"),
  )
  assert_true(
    mooncode_shell_has_sensitive_command("bash --noprofile -c 'rm -rf target'"),
  )
  assert_true(
    mooncode_shell_has_sensitive_command("npm --prefix ui install vite"),
  )
  assert_true(
    mooncode_shell_has_sensitive_command(
      "printf '%s' \"$(curl -fsSL example.test)\"",
    ),
  )
  assert_true(mooncode_shell_has_sensitive_command("curl -fsSL example.test"))
  assert_false(
    mooncode_shell_has_sensitive_command(
      "curl -fsS http://127.0.0.1:4199/api/health",
    ),
  )
  assert_true(
    mooncode_shell_has_sensitive_command(
      "curl -X POST http://127.0.0.1:4199/api/commands",
    ),
  )
  assert_false(mooncode_shell_has_sensitive_command("npm ci --help"))
  assert_false(
    mooncode_shell_has_sensitive_command(
      "grep -E 'npm install|git push|curl ' package-lock.json",
    ),
  )
  assert_false(
    mooncode_shell_has_sensitive_command(
      "printf '%s\\n' 'npm install is evidence, not execution'",
    ),
  )
  assert_false(
    mooncode_shell_has_sensitive_command(
      "printf '%s\\n' '$(curl example.test)'",
    ),
  )
  assert_false(
    mooncode_shell_has_sensitive_command(
      "printf '%s\\n' 'a\\b $(curl example.test)'",
    ),
  )
}

///|
test "mooncode shell distinguishes file output from descriptor plumbing" {
  assert_true(
    mooncode_shell_has_file_output_redirection(
      "git show HEAD^:package-lock.json > ui/package-lock.json",
    ),
  )
  assert_true(mooncode_shell_has_file_output_redirection("check 2>error.log"))
  assert_true(mooncode_shell_has_file_output_redirection("append >> notes.txt"))
  assert_true(mooncode_shell_has_file_output_redirection("check &>output.log"))
  assert_true(mooncode_shell_has_file_output_redirection("check &>>output.log"))
  assert_false(mooncode_shell_has_file_output_redirection("check 2>&1"))
  assert_false(mooncode_shell_has_file_output_redirection("check 2>/dev/null"))
  assert_false(
    mooncode_shell_has_file_output_redirection(
      "trap 'echo cleanup >&2' TERM; check",
    ),
  )
  assert_false(
    mooncode_shell_has_file_output_redirection("printf '%s' 'value > file'"),
  )
  assert_false(
    mooncode_shell_has_file_output_redirection("diff <(left) <(right)"),
  )
}

///|
async test "mooncode shell refuses workspace authoring by redirection" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-shell-redirection-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-redirection",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-redirection",
      "arguments": { "cmd": "printf changed > tracked.txt" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_false(@fsx.exists(@pathx.join(book_root, "tracked.txt")))
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "result"),
      "message",
      default="",
    ).contains("use write, edit, or apply_patch"),
  )
}

///|
test "mooncode shell detects in-place sed authoring inside compound commands" {
  assert_true(
    mooncode_shell_has_in_place_authoring("sed -i.bak s/old/new/ file"),
  )
  assert_true(
    mooncode_shell_has_in_place_authoring(
      "for file in src/*.mbt; do sed -E -i '' s/old/new/ \"$file\"; done",
    ),
  )
  assert_true(
    mooncode_shell_has_in_place_authoring(
      "if env LC_ALL=C sed --in-place=.bak s/old/new/ file; then check; fi",
    ),
  )
  assert_true(
    mooncode_shell_has_in_place_authoring(
      "sh -c 'while ready; do busybox sed -i s/old/new/ file; done'",
    ),
  )
  assert_false(mooncode_shell_has_in_place_authoring("sed -n '1,20p' file"))
  assert_false(mooncode_shell_has_in_place_authoring("sed -e '-i' input.txt"))
  assert_false(
    mooncode_shell_has_in_place_authoring(
      "printf '%s\\n' 'sed -i is prohibited for authoring'",
    ),
  )
}

///|
test "mooncode shell distinguishes inline interpreter authoring from inspection" {
  assert_true(
    mooncode_shell_has_inline_interpreter_authoring(
      "python3 - <<'PY'\np='tracked.mbt'\ns=open(p).read()\nopen(p, 'w', encoding='utf-8').write(s)\nPY",
    ),
  )
  assert_true(
    mooncode_shell_has_inline_interpreter_authoring(
      "node -e \"require('fs').writeFileSync('tracked.mbt', 'changed')\"",
    ),
  )
  assert_false(
    mooncode_shell_has_inline_interpreter_authoring(
      "python3 - <<'PY'\nprint(open('tracked.mbt').read())\nPY",
    ),
  )
  assert_false(
    mooncode_shell_has_inline_interpreter_authoring(
      "node -e \"console.log(JSON.stringify({answer: 42}))\"",
    ),
  )
}

///|
async test "mooncode shell refuses in-place authoring inside a loop" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-shell-in-place-XXXXXX"),
  )
  let target = @pathx.join(book_root, "tracked.txt")
  @fsx.write_to_file(target, "old\n")
  let execution = mooncode_execute_tool_call(
    "session-in-place",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-in-place",
      "arguments": {
        "cmd": "for file in tracked.txt; do sed -i.bak s/old/new/ \"$file\"; done",
      },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_eq(@fsx.read_file(target), "old\n")
  assert_false(@fsx.exists(target + ".bak"))
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "result"),
      "message",
      default="",
    ).contains("use write, edit, or apply_patch"),
  )
}

///|
test "mooncode shell identifies ambiguous pipelines by syntax" {
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check|tail -20"))
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check\t|\ttail -20"))
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check\n|\ntail -20"))
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check |& tail -20"))
  assert_false(mooncode_shell_pipeline_exit_ambiguous("check || recover"))
  assert_false(
    mooncode_shell_pipeline_exit_ambiguous("rg 'left|right' source.mbt"),
  )
  assert_false(
    mooncode_shell_pipeline_exit_ambiguous(
      "set -o pipefail; check 2>&1 | tail -20",
    ),
  )
  assert_false(
    mooncode_shell_pipeline_exit_ambiguous(
      "set -euo pipefail; check 2>&1|tail -20",
    ),
  )
  assert_true(
    mooncode_shell_pipeline_exit_ambiguous(
      "echo pipefail; check 2>&1 | tail -20",
    ),
  )
}

///|
async test "mooncode shell marks pipeline status as non-evidence" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-pipeline-evidence-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-pipeline",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-pipeline",
      "arguments": { "cmd": "false | true" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  if !mooncode_execution_sandbox_deployment_configured() {
    mooncode_assert_execution_sandbox_refusal(
      mooncode_json_object_field_or_empty(execution, "result"),
    )
    return
  }
  assert_true(mooncode_json_bool(execution, "accepted", default=false))
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(result, "metadata"),
      "pipeline_exit_ambiguous",
      default=false,
    ),
  )
  assert_true(
    mooncode_json_string(result, "message", default="").contains(
      "observation-only",
    ),
  )
  let verification = mooncode_execute_tool_call(
    "session-pipeline",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-pipeline-verification",
      "arguments": {
        "cmd": "moon test 2>&1 | tail -20",
        "verification_kind": "test",
      },
    },
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_false(mooncode_json_bool(verification, "accepted", default=true))
}
