# MoonBit language notes

Use installed API documentation and compiler diagnostics for exact signatures.
These notes cover common mistakes rather than a language tutorial.

- Expressions return their last value. Write `fn main { ... }`, without an
  empty argument list. Separate top-level declarations with `///|`.
- Error-raising functions use `raise`; ordinary calls propagate checked errors.
  Catch only where recovery is possible. Async functions already propagate
  errors and require no `await` keyword.
- Arrays and maps are mutable reference values. A `let` binding need not be
  `mut` to update its contents; `mut` is needed when reassigning the binding.
- `StringView` and `ArrayView` are borrowed ranges. Keep ranges as views until
  ownership is needed, then use `.to_owned()`. A view can start inside a larger
  value. Use `moon ide doc StringView` to check slicing and offset APIs.
- Prefer pattern matching to manual indexing when it expresses the operation.
  String indexing exposes UTF-16 code units; iterate over characters for
  Unicode character semantics.
- Methods are declared with `Type::method`. Qualify package operations with
  their configured `@alias`; file names are not namespaces.
- `_test.mbt` files exercise public APIs through the tested package alias.
  `_wbtest.mbt` files can access package internals. Use a focused existing test
  for a regression when possible.
- Derive `Debug` for diagnostic output and use `debug_inspect`; `Show` is for
  deliberate user-facing formatting. Stable correctness checks use assertions.

Look up specific APIs instead of copying a generic example into the project:
`moon ide doc <query>`, `moon ide peek-def <symbol>`, or
`moon ide find-references <symbol>`.
