# Retained artifact downloads

Open the gateway’s own `/ui` page, select a run, and choose **Download** on a
retained artifact. Text, JSON, PDF, images and other binary content use the same
byte-preserving route. Text cards still open the viewer/editor; its decoder now
accepts the gateway’s Option-array content wire format as plain editor text, as
well as the existing bare-string/null form. Download always retrieves the
retained file, not unsaved text in the editor.
The existing text preview is a separate text reader; use Download when verifying
arbitrary binary or embedded NUL content.

If the gateway requires a token, open **Runtime & gateway access**, enter that
gateway’s token in the password field and choose **Use token**. The field is then
cleared. The token is kept only in this tab’s memory, is sent in an Authorization
header only to the exact selected gateway base and `/v1/` API path, and is cleared
by **Clear token**, reload or a gateway change. It is never written to browser
storage, query strings or logs. No token is automatically read from a local file.
Token/gateway changes cancel pending downloads and suppress stale API results.
Refresh the selected run after configuring access if it was already open.

The supported delivery path is the same-origin UI served by the gateway. Host
gateway-base overrides remain available, but cross-origin browser CORS and
credential deployment are not qualified by these download tests. This change
does not replace EventSource with an authenticated streaming client; existing
snapshot/polling reads use the shared authenticated fetch transport.

## API and identity

`GET /v1/jobs/runs/{run_id}/artifacts/{artifact_id}/download`

- Both path segments identify exact records; percent-encoded identifiers are
  decoded once. Malformed encodings, control characters and path separators are
  rejected. There is no caller-supplied file path, URL or “latest result” lookup
- The stored artifact’s run ID must match. Wrong run/ID is 404, invalid identity
  is 400, absent retained file is 410, and unreadable/oversize content is 409
- The existing gateway Bearer authorization check runs before artifact lookup
- Success returns raw bytes as `application/octet-stream`, attachment disposition
  with a sanitized UTF-8 filename, `nosniff`, and `Cache-Control: no-store`
- Downloads read a regular file through the same descriptor used for its size
  check. The current limit is 64 MiB; a changed file length is refused. Content
  is buffered by the gateway and browser. There is no range/resume protocol
- The browser reports handoff to its download mechanism, not proof that the user
  saved a file. Cancel, timeout (60 seconds), disconnect and retry do not rerun
  work or alter the artifact record. Duplicate clicks while pending are ignored
- If content is missing, restore the exact retained file from a trusted backup
  and retry. Download never executes a job as a repair step

The record ID and owning run are exact. The existing artifact schema has no
content digest/immutable-storage guarantee; out-of-band edits or mutable artifact
updates can change its bytes. This is not a tamper-proof historical export.

## Separate output surfaces

Synthetic workspace report/result previews retain their existing text-open
behavior and explicitly require a retained artifact before download. They are
not silently converted into new artifact checkpoints.

MoonFort command-output references are a separate signed-reference reader
contract. They are not ArtifactStore paths, and are not downloadable through
this endpoint unless a future authorized adapter deliberately creates a retained
MoonClaw artifact. No automatic spool mapping, command replay, output execution,
provider call, acceptance or domain promotion is performed here.

## Verification

Focused native tests cover the real Gateway HTTP/auth/response decoder, NUL and
invalid UTF-8 bytes, Unicode filename headers, text-open compatibility, exact run
ownership, absent/invalid IDs, repeated and interrupted consumption, absent-file
recovery, metadata reload, empty files and a sparse file above the size limit.
The native gateway fixture also invokes the shipped UI fetch/download transport
over real loopback HTTP using a fixture-only token. Only the DOM save boundary is
stubbed. The integration UI test is intentionally skipped standalone and is run
explicitly by the native fixture.

UI fixtures cover token scope, redirects, stale-body suppression, cancellation,
retries, object URL cleanup, download controls and retained text-open behavior.
No live browser, OS save dialog, real token, real provider or remote host was used.

Run the UI tests and the focused native tests from their respective module roots:

```text
moon test --target js
moon test --target native --strip -j 2 gateway/server/artifact_download_wbtest.mbt job/artifact_download_wbtest.mbt job/artifact_download_test.mbt
```

The native fixture requires `moon` and Node on PATH and runs the UI integration
test from the repository’s `ui/rabbita-job` directory.
