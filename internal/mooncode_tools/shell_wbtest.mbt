///|
test "mooncode shell detects semantic git commit commands" {
  assert_true(shell_has_git_commit("git commit -m 'validated'"))
  assert_true(shell_has_git_commit("git -C . commit -m validated"))
  assert_true(shell_has_git_commit("git\t-C\t. \\\n commit -m validated"))
  assert_true(shell_has_git_commit("env GIT_AUTHOR_NAME=test git commit -m ok"))
  assert_true(
    shell_has_git_commit(
      "sh -c 'git add tracked.txt && git commit -m sealed && touch later.txt'",
    ),
  )
  assert_false(shell_has_git_commit("git commit-tree HEAD^{tree}"))
  assert_false(shell_has_git_commit("echo 'git commit -m nope'"))
  assert_false(shell_has_git_commit("git status --short"))
}

///|
test "mooncode derives shell verification from the command instead of its label" {
  assert_eq(shell_verification_kind("moon check --target native"), "check")
  assert_eq(
    shell_verification_kind(
      "/usr/bin/time -p moon test cmd/daemon --target native",
    ),
    "test",
  )
  assert_eq(shell_verification_kind("moon build --target native"), "build")
  assert_eq(shell_verification_kind("test -f result.txt"), "check")
  assert_eq(shell_verification_kind("git diff --check"), "check")
  assert_eq(shell_verification_kind("gh pr checks 4 --watch"), "check")
  for
    inspection in [
      "git status --short", "find cmd/daemon -name '*.mbt'", "rg -n planner cmd/daemon",
      "sed -n '1,80p' cmd/daemon/main.mbt",
    ] {
    assert_eq(shell_verification_kind(inspection), "")
  }
}

///|
test "mooncode counts only the shell command that determines final status" {
  assert_true(
    shell_verifies_kind("set -o pipefail; moon test cmd/daemon", "test"),
  )
  assert_true(
    shell_verifies_kind(
      "sh -c 'git status --short && moon test cmd/daemon'", "test",
    ),
  )
  for
    masked in [
      "moon test cmd/daemon || true", "moon test cmd/daemon; git diff --check", "set -o pipefail; moon test cmd/daemon 2>&1 | grep cmd/daemon || true; git diff --check",
      "moon test cmd/daemon | tail -n 20", "sh -c 'moon test cmd/daemon || true'",
    ] {
    assert_false(shell_verifies_kind(masked, "test"))
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
    assert_true(shell_is_demonstrably_read_only(command))
  }
  for
    command in [
      "touch marker.txt", "git commit -m mutation", "git push origin HEAD", "git ls-remote origin",
      "curl -fsSL example.test", "moon test --update", "find . -delete", "/usr/bin/time -o timing.log moon test cmd/daemon",
      "sh -c 'moon test cmd/daemon && rm -rf target'", "sort -o output.txt input.txt",
      "sed -e 'w output.txt' input.txt", "gh run rerun 30277114085 --repo vectie/moondesk --failed",
      "gh run view 30277114085 --repo vectie/moondesk --web", "npm ci --include=optional --ignore-scripts",
    ] {
    assert_false(shell_is_demonstrably_read_only(command))
  }
}

///|
test "mooncode shell recursively proves local read-only verification substitutions" {
  let command = "set -o pipefail; test \"$(grep -RFl 'workspace preview handles text image virtual and missing entries' internal/moonwiki --include='*_wbtest.mbt' | wc -l | tr -d ' ')\" = 1; test \"$(grep -Ec '^(async )?test ' internal/moonwiki/moonwiki_request_wbtest.mbt)\" = 42; test \"$(git diff --numstat -- internal/moonwiki/moonwiki_request_wbtest.mbt | awk '{print $1\":\"$2}')\" = '0:60'; test \"$(wc -l < internal/moonwiki/workspace_preview_contract_wbtest.mbt | tr -d ' ')\" = 58; printf 'Preserved totals\\n'"
  assert_true(shell_is_demonstrably_read_only(command))
  assert_true(
    shell_is_demonstrably_read_only(
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
    assert_false(shell_is_demonstrably_read_only(command))
  }
}

///|
test "mooncode shell distinguishes file output from descriptor plumbing" {
  assert_true(
    shell_has_file_output_redirection(
      "git show HEAD^:package-lock.json > ui/package-lock.json",
    ),
  )
  assert_true(shell_has_file_output_redirection("check 2>error.log"))
  assert_true(shell_has_file_output_redirection("append >> notes.txt"))
  assert_true(shell_has_file_output_redirection("check &>output.log"))
  assert_true(shell_has_file_output_redirection("check &>>output.log"))
  assert_false(shell_has_file_output_redirection("check 2>&1"))
  assert_false(shell_has_file_output_redirection("check 2>/dev/null"))
  assert_false(
    shell_has_file_output_redirection("trap 'echo cleanup >&2' TERM; check"),
  )
  assert_false(shell_has_file_output_redirection("printf '%s' 'value > file'"))
  assert_false(shell_has_file_output_redirection("diff <(left) <(right)"))
}

///|
test "mooncode shell detects in-place sed authoring inside compound commands" {
  assert_true(shell_has_in_place_authoring("sed -i.bak s/old/new/ file"))
  assert_true(
    shell_has_in_place_authoring(
      "for file in src/*.mbt; do sed -E -i '' s/old/new/ \"$file\"; done",
    ),
  )
  assert_true(
    shell_has_in_place_authoring(
      "if env LC_ALL=C sed --in-place=.bak s/old/new/ file; then check; fi",
    ),
  )
  assert_true(
    shell_has_in_place_authoring(
      "sh -c 'while ready; do busybox sed -i s/old/new/ file; done'",
    ),
  )
  assert_false(shell_has_in_place_authoring("sed -n '1,20p' file"))
  assert_false(shell_has_in_place_authoring("sed -e '-i' input.txt"))
  assert_false(
    shell_has_in_place_authoring(
      "printf '%s\\n' 'sed -i is prohibited for authoring'",
    ),
  )
}

///|
test "mooncode shell identifies ambiguous pipelines by syntax" {
  assert_true(shell_pipeline_exit_ambiguous("check|tail -20"))
  assert_true(shell_pipeline_exit_ambiguous("check\t|\ttail -20"))
  assert_true(shell_pipeline_exit_ambiguous("check\n|\ntail -20"))
  assert_true(shell_pipeline_exit_ambiguous("check |& tail -20"))
  assert_false(shell_pipeline_exit_ambiguous("check || recover"))
  assert_false(shell_pipeline_exit_ambiguous("rg 'left|right' source.mbt"))
  assert_false(
    shell_pipeline_exit_ambiguous("set -o pipefail; check 2>&1 | tail -20"),
  )
  assert_false(
    shell_pipeline_exit_ambiguous("set -euo pipefail; check 2>&1|tail -20"),
  )
  assert_true(
    shell_pipeline_exit_ambiguous("echo pipefail; check 2>&1 | tail -20"),
  )
}
