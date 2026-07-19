///|
test "Codex auth and switch shorthand use exact 5.6-sol selector" {
  inspect(normalize_switch_target("codex"), content="codex/gpt-5.6-sol")
  inspect(
    normalize_switch_target("codex/gpt-5.6-sol"),
    content="codex/gpt-5.6-sol",
  )
  inspect(normalize_switch_target("codex/gpt-5.4"), content="codex/gpt-5.4")
}
