# moonclaw-nodejs

Async Node.js/TypeScript bindings for the bundled `sdk.exe` moonclaw agent. The package wraps the
CLI executable with a small JSON-RPC client and exposes a high-level `moonclaw`
class for streaming assistant responses.

## Quick start

```typescript
import { moonclaw } from "moonclaw";

async function main() {
  const moonclaw = new moonclaw();
  
  for await (const event of moonclaw.start("Hello, moonclaw!")) {
    console.log(event);
  }
}

main().catch(console.error);
```

The async iterator yields structured events describing assistant messages and tool
calls emitted by the executable.

## Installation

```bash
npm install moonclaw
```

## Requirements

- Node.js >= 18.0.0
- TypeScript >= 5.0.0 (for TypeScript users)

## Packaging the executable

Run the appropriate bundling script from the repository root to copy the
built `sdk.exe` into the package before building or publishing.

## License

Apache License 2.0
