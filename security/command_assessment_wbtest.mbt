///|
test "assess_shell_command classifies read-only commands as low risk" {
  let assessment = assess_shell_command(
    "cat file.txt",
    "/tmp/workspace",
    Some("/tmp/workspace"),
  )
  inspect(assessment.intent, content="Binary")
  inspect(assessment.risk_level, content="Low")
  inspect(assessment.requires_approval, content="false")
  inspect(assessment.predicted_effects.join("|"), content="read-files")
}

///|
test "assess_shell_command marks file-modifying shell commands as high risk" {
  let assessment = assess_shell_command(
    "echo hello > out.txt",
    "/tmp/workspace",
    Some("/tmp/workspace"),
  )
  inspect(assessment.intent, content="Shell")
  inspect(assessment.risk_level, content="High")
  inspect(assessment.requires_approval, content="true")
}

///|
test "assess_shell_command blocks privilege escalation commands" {
  let assessment = assess_shell_command(
    "sudo rm -rf /",
    "/tmp/workspace",
    Some("/tmp/workspace"),
  )
  inspect(assessment.risk_level, content="Blocked")
  inspect(assessment.allowed_by_policy, content="false")
}
