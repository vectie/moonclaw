# Retained command output

Open a run's Artifacts panel, then Command output. Available command outputs have a
Download retained output action. Size, terminal state and exit outcome are readable; run/output IDs and
the retained SHA-256 stay under Output details. Downloads use the gateway's
existing authenticated transport and can be canceled/retried without rerunning work.

The card preserves the original receipt's truncation flag and limit reason.
When a command hit its approved output ceiling, it explicitly says that only the
bytes retained up to that ceiling are downloadable and later output was not
captured. A shortened or decoded model preview is distinguished from that limit.

The trusted operator configures `command_output_reader_path` in the existing
`MOONCLAW_MOONFORT_CONFIG` file to the deployed MoonFort `read-command-output`
binary. Its executor policy remains in `executor_config_path`. No signing key,
policy file, host path, signed reference, or copied command credential is requested
from the browser. The configured receipt directory must remain operator-owned,
outside command-writable workspaces, as for all existing Fort audits.

The analysis runner carries its own run and step IDs into the execute-command
tool constructor. After the real receipt and audit are persisted, it records an
immutable owner link to the audit hash. One Fort execution can belong to one Claw
run/step. It is not a tool argument and cannot be asserted by a UI request.

GET `/v1/jobs/runs/{run}/command-outputs/{output}/download` resolves that retained
link and the exact audit; it passes the original signed reference, Fort run ID,
approval digest and command digest to the fixed reader. Fort verifies its own
signature/spool, then Claw checks exported size/hash and serves an attachment.
The native capture is Bytes throughout, including invalid UTF-8 and NUL bytes.

Old runs with no owner link cannot be reconstructed. Executions with no original
signed output reference are displayed unavailable. Expired, missing and changed
records have distinct readable messages; retrieving never extends retention,
executes a command, promotes files, or falls back to arbitrary file reads.

New local Fort receipts retain a verified signed terminal spool when the text
projection differs from raw bytes, including small binary output. Non-UTF-8 uses
`application/octet-stream`. Existing UTF-8 signed references remain readable.
Older or remote producers that provided only a String cannot recover previously
lost raw bytes; their retained artifact is the exact retained text, not a promise
about pre-projection command bytes.

Tests use synthetic backend observations with real Fort retention/signatures and
its native read-only CLI, a real loopback Claw gateway, and the shipped JS download
transport. Only the browser save-file boundary is stubbed. They do not claim a
real provider, production credentials, live browser or supported OS execution backend.
