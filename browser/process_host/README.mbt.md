# Process browser-host adapter

`ProcessBrowserHost` is the production transport boundary between MoonClaw's
governed browser worker and a narrow native browser host. It sends exactly one
typed JSON command to an executable's stdin and accepts exactly one typed JSON
result from stdout. A non-zero exit, timeout, malformed JSON, or malformed
result is an error and cannot become accepted browser evidence.

The host—not MoonClaw and never the page—must capture before/after state digests
and optional screenshots from the same visible session. The worker validates
session, action, code revision, authority envelope, receipt identity, semantic
target resolution, and expected replay state before accepting the result.

This adapter intentionally does not invoke a shell. Executable and arguments
are passed separately. External navigation remains outside the default effect
set.

