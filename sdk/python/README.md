# moonclaw-python

Async Python bindings for the bundled `sdk.exe` moonclaw agent. The package wraps the
CLI executable with a small JSON-RPC client and exposes a high-level `moonclaw`
class for streaming assistant responses.

## Quick start

```python
import asyncio
from moonclaw_python import moonclaw

async def main() -> None:
    moonclaw = moonclaw()
    async for event in moonclaw.stream("Hello, moonclaw!"):
        print(event)

asyncio.run(main())
```

The iterator yields structured events describing assistant messages and tool
calls emitted by the executable.

## Packaging the executable

Run `python scripts/bundle_moonclaw_python.py` from the repository root to copy the
built `sdk.exe` into the package before building or publishing the wheel.
