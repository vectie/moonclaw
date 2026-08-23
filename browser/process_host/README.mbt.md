# Process browser-host adapter

`ProcessBrowserHost` is quarantined until browser-host commands are carried by
an approved `ExecutionSandbox` grant. Its public API deliberately has no
executable, argument, environment, or working-directory selector, and every
execution request fails closed.

The host—not MoonClaw and never the page—must capture before/after state digests
and optional screenshots from the same visible session. The worker validates
session, action, code revision, authority envelope, receipt identity, semantic
target resolution, and expected replay state before accepting the result.

Do not restore direct process spawning here. A future implementation must use
the grant-aware ExecutionSandbox adapter and bind the returned sandbox receipt
to the browser evidence receipt.
