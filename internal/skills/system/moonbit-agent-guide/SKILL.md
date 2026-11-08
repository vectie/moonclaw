---
name: moonbit-agent-guide
description: MoonBit package, API navigation, testing and build conventions for work that needs language or tooling guidance.
license: Apache-2.0
allowed-tools: moon_cmd moon_ide
---

# MoonBit work

Adapted for MoonClaw from `moonbitlang/moonbit-agent-guide` (Apache-2.0).

- `moon.mod` owns module metadata and dependencies; each `moon.pkg` owns package
  imports/options. Source files do not define namespaces. Separate top-level
  declarations with `///|` and call imported packages through `@alias`.
- Use `moon ide doc` for installed APIs and `moon ide outline`, `peek-def` or
  `find-references` for semantic navigation. Read source ranges for the actual
  implementation. Compiler diagnostics resolve uncertainty about syntax/APIs.
- Use `.mbtx` for authored automation, with `@shell.Cmd` from
  `moonbitlang/async/shell` for process orchestration.
- Keep changes in the relevant package. A `StringView` may refer to a slice of
  another string; preserve its boundaries rather than assuming an offset of zero.
- Use `moon check` and focused `moon test` while iterating. Before delivery run
  the required project checks, `moon info` and `moon fmt`; review generated `.mbti` changes.
- Use assertions for stable results and `Debug`/`debug_inspect` for diagnostic
  snapshots. Update snapshots only for reviewed, intended output changes.

References:

- [Language fundamentals](references/moonbit-language-fundamentals.md): unfamiliar
  error handling, views, mutation, methods or test visibility.
- [Build configuration](references/advanced-moonbit-build.md): imports, backend
  selection or Native stubs.
