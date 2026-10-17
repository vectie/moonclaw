# Compare snapshots and plan from changed passages

MoonClaw's Work source panel can now locate exact line changes before the operator
prepares a follow-on task. This is a bounded slice of MC-W02 and MOONCLAW-B04/B10:
inspect exact artifact/source snapshots and retain producing-run references.
It does not qualify complete checkpoint recovery or release acceptance.

## Ordinary workflow

1. Open a Work thread and write the next objective in its normal composer.
2. In **Choose focused source excerpts**, import two local UTF-8 text snapshots,
   inspect two distinct retained outputs from its linked terminal run, or mix one
   of each. Existing file/count/byte limits still apply.
3. Select **Before snapshot** and **After snapshot**, then **Compare imported
   snapshots**. This order is supplied by you; the UI does not infer chronology,
   ancestry, semantic correctness, or acceptance.
4. Browse **Changed passage**. Added, removed and replaced contiguous ranges show
   source line numbers and exact quoted text. Quotes expose CRLF/LF, whitespace,
   BOM and final-newline differences. Two nearby context lines on each side help
   orientation and are not part of the selected range.
5. Choose **Inspect before lines in excerpt editor** or **Inspect after lines in
   excerpt editor**. An insertion has no selectable before range; a deletion has
   no after range. The action only fills the ordinary source/range fields and
   clears the relevance note. It neither adds an excerpt nor changes the task.
6. Inspect/edit the range, supply a relevance note and choose **Add excerpt**.
   Repeat for other useful changes, optionally including a before passage to
   explain a deletion. Existing overlap, eight-excerpt and selected-byte budgets
   apply. Preview the entire source brief and explicitly apply it to the draft.
7. Use normal **Plan**, **Preview**, **Promote** and **Confirm**. A source change
   is input data, not an instruction, accepted knowledge, or execution authority.

## Identity and interruption behavior

- Two source identities are required. Local file names and retained artifact
  identities occupy distinct namespaces, including when their visible names
  match. Both sources' full SHA-256 fingerprints appear beside the comparison.
- The working set keeps one snapshot per local name or retained artifact key.
  Comparing old/new versions of one key concurrently is not supported. Use two
  distinct retained artifact records or explicitly selected local files with
  distinct names. No hidden historical-version endpoint is introduced.
- Local snapshots remain frozen tab-local imports; disk freshness is unverified.
  Each selected retained source is reread through the existing read-only exact
  run/artifact endpoints before comparison and again before range selection.
  Existing preview/apply rereads remain in place. These checks describe their
  individual reads, not a promise that the remote source stays current afterward.
- A changed source key, content/revision fingerprint, source choice, owner thread,
  folder or gateway access invalidates comparison controls. Changed remote bytes,
  missing records or a nonterminal run prevent range selection and keep the draft.
- Cancel, close, navigation and disposal prevent late reads from modifying the
  editor. Repeated pending clicks do not start a second operation. Any comparison
  preparation invalidates a previously prepared main source-brief preview.
- Comparisons and unsent imports are tab-local and disappear on reload.

## Bounded exact comparison

The deterministic line-LCS algorithm compares exact strings, including original
line endings. Shared prefixes/suffixes are removed before allocation. Each input
is limited to 2,000 lines and the remaining matrix to 1,000,000 cells (at most
2 MB of typed-array cells). Inputs exceeding either limit fail visibly without
truncation or an approximate fallback. The existing manual passage picker stays
available. Repeated identical lines have a deterministic alignment; this is not a
semantic diff, an edit application tool or a guarantee of unique alignment.

## Verification

Run from any directory:

    bash /absolute/source/scripts/test-source-comparison.sh

The focused check executes production JavaScript, the existing DOM-controller
fixtures, exact retained read/revalidation fixtures, cancellation/ownership races,
byte/line bounds and deterministic generated reconstruction cases, plus all
existing job UI JavaScript regressions. The optional native Book CLI/receipt fixture is
skipped when MOONCLAW_BOOK_RECEIPT_DIR is not configured. No actual browser layout/accessibility check,
production Vite/MoonBit build, native/provider execution, host lifecycle or release
qualification is implied.
