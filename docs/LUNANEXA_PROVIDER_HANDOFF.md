# LunaNexa desktop provider handoff

MoonClaw owns the authenticated desktop operation that turns a LunaNexa
one-time code into a local MoonGate provider. The browser and MoonDesk native
host never receive the resulting inference secret.

## Runtime path

```text
enterprise portal fragment
  → MoonDesk same-origin POST /api/desktop/provider-handoff
  → authenticated MoonClaw POST /v1/provider-handoff
  → pinned LunaNexa POST /v1/client-handoffs:redeem
  → authenticated MoonGate provider + binding install
  → MoonCode model moongate/<leased-model>
```

MoonClaw accepts the `moonclaw.provider-handoff.v1` envelope with only
`client_id` and `handoff_code`. It validates strict sizes and syntax, redeems
the code once, verifies the client, expiry, quota, model aliases, HTTPS origin
(or exact loopback HTTP in development), and requires the returned API base to
equal the pinned issuer plus `/v1`.

The installed MoonGate provider is `lunanexa-lease`, uses app type `openclaw`,
API format `openai_chat`, and binds to the MoonClaw client. LunaNexa remains the
authority for model scope, request quota, contract state, and lease expiry on
every inference request.

## Required configuration

Set these values in the MoonDesk application launch environment or managed
desktop policy:

```sh
MOONDESK_LUNANEXA_ISSUER=https://management.example/user
MOONGATE_CONTROL_TOKEN=<the local MoonGate control token>
```

MoonDesk forwards only these two allowlisted values into its clean managed
MoonClaw environment. Never put the lease-scoped `lnx_...` secret in desktop
configuration; it is obtained once by MoonClaw and sent directly to MoonGate.
The issuer may be the bare HTTPS origin or the exact `/user` base path; the
redeemed API URL must match that base plus `/v1` exactly.

The ordinary MoonCode path uses MoonGate chat completions and needs no optional
Responses feature flag. If an operator explicitly enables MoonCode's Responses
transport, MoonGate must also start with
`MOONGATE_OPENCLAW_RESPONSES_ENABLED=true`.

## Verification

Run from the MoonClaw repository:

```sh
moon check cmd/daemon plugin/moongate --target native --deny-warn
moon test cmd/daemon/daemon_provider_handoff_wbtest.mbt --target native --deny-warn
moon test cmd/daemon/moondesk_control_auth_wbtest.mbt --target native --deny-warn
moon test plugin/moongate --target native --deny-warn
```

The network integration test starts mock LunaNexa and MoonGate servers and
asserts the exact `redeem → provider list → provider install → binding` order,
control-token authentication, provider format, secret containment, and the
absence of the reusable inference secret from the public response.
