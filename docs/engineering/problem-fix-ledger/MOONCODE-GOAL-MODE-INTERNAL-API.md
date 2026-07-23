# MoonCode Goal-Mode Internal API: Detailed Problem/Fix Ledger

This document preserves the exhaustive chronological entries omitted from the short main ledger.

MoonCode authored all product changes described here. The controller made no product changes; it only removed an accidental temporary file.

## Chronological ledger

1. **Obsolete and ambiguous anchors.** Early work targeted anchors that were obsolete or ambiguous. The fix was to identify and use the current, unambiguous implementation anchors before making product changes.
2. **Cancelled broad temporary-file and `cat` approvals.** Broad approvals for temporary-file creation and `cat` were cancelled rather than expanding tool authority. The controller deleted only the accidental temporary file; MoonCode authored the product changes.
3. **Compile API drift.** Compilation exposed drift in the internal API. Call sites and declarations were brought back into agreement with the actual supported API.
4. **Hallucinated handlers, tests, time, and JSON APIs.** Proposed handlers, tests, time helpers, and JSON facilities that did not exist were rejected and replaced with repository-backed APIs and fixtures.
5. **Session-mismatch parse precedence.** Parsing originally allowed another condition to obscure a session mismatch. Validation precedence was corrected so session mismatch is reported deterministically before later interpretation.
6. **Exact tools succeeded but the aggregate receipt failed.** Individual exact tool operations completed successfully while the aggregate receipt still reported failure. Verification was based on bounded, exact outputs rather than assuming aggregate success.
7. **False-green zero-test `-f`.** An incorrect `-f` invocation selected zero tests and appeared green. The command was corrected to run the intended exact five-test file, preventing zero-test success from counting as validation.
8. **`fs.write_file` and `to_string` fixture bugs.** Test fixtures misused file-writing and string-conversion APIs. Fixtures were corrected to use their real signatures and representations.
9. **Complete corrupt journals return 409 unchanged; torn suffix repair is limited to uncommitted data.** Only uncommitted torn suffixes are ignored by GET and repaired by PUT while preserving committed records.
10. **GET ReadWrite issue.** GET opened or treated storage with unnecessary write capability. It was corrected to use read-only behavior where mutation was not required.
11. **Matrix drift.** Cross-target work encountered drift involving `create_dir`, `remove_dir`, `read_dir`, `path.join`, archived APIs, and mismatched signatures. Each matrix failure was reconciled against the APIs actually available for that target.
12. **Failed and successful Python rewrites still required correction.** Automated Python rewrites were attempted; failed rewrites changed nothing, and even apparently successful rewrites required review and correction. Final product edits were authored and verified in MoonCode rather than accepted from rewrite status alone.
13. **Stuck grep was cancelled.** An unbounded or stuck grep operation was cancelled and replaced by bounded, targeted inspection.
14. **Wrong response schema corrected.** A response was emitted using an incorrect schema. The implementation and tests were aligned with the contractually correct response shape.
15. **Security rejection for no-newline and UTF-8 cases.** Proposed handling of missing final newlines and malformed UTF-8 was rejected when it weakened security or accepted ambiguous input. Validation retained secure rejection semantics except for the specifically recoverable committed-prefix PUT path.
16. **Cancelled canonical replay regression and restoration.** A change that regressed canonical replay was cancelled. Canonical replay behavior was restored before proceeding.
17. **Local committed-prefix fix and 189/189.** The repair was localized to committed-prefix handling rather than broad parser relaxation. The resulting suite completed successfully at 189/189 tests.
18. **Deferred unlocked/probe-open TOCTOU.** The remaining unlocked/probe-open time-of-check/time-of-use concern was explicitly deferred. It remains follow-up work and was not represented as solved by the local repair.
