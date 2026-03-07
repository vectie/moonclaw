# OpenClaw Feishu Channel Reference Design Survey

This document surveys the OpenClaw Feishu channel implementation to guide the design of an extension system for Moonclaw.

## Overview

OpenClaw is a TypeScript-based AI agent framework that supports multiple messaging channels through a plugin architecture. The Feishu channel is implemented as a plugin that can be installed separately and integrates with the gateway for message routing.

## Architecture Summary

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         Gateway Server                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ WebSocket   │  │ HTTP API    │  │ Channel Manager         │  │
│  │ Control/RPC │  │ Endpoints   │  │ ┌─────────────────────┐ │  │
│  └─────────────┘  └─────────────┘  │ │ Plugin Registry     │ │  │
│                                     │ │ ┌─────────────────┐ │ │  │
│                                     │ │ │ Feishu Plugin   │ │ │  │
│                                     │ │ │ Telegram Plugin │ │ │  │
│                                     │ │ │ Discord Plugin  │ │ │  │
│                                     │ │ │ ...             │ │ │  │
│                                     │ │ └─────────────────┘ │ │  │
│                                     │ └─────────────────────┘ │  │
│                                     └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Agent Core                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Conversation│  │ Tool System │  │ Event System            │  │
│  │ Manager     │  │             │  │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Plugin System Architecture

### Plugin Definition

```typescript
// OpenClawPluginDefinition
type OpenClawPluginDefinition = {
  id?: string;
  name?: string;
  description?: string;
  version?: string;
  kind?: PluginKind;
  configSchema?: OpenClawPluginConfigSchema;
  register?: (api: OpenClawPluginApi) => void | Promise<void>;
  activate?: (api: OpenClawPluginApi) => void | Promise<void>;
};
```

### Plugin API

```typescript
type OpenClawPluginApi = {
  id: string;
  name: string;
  version?: string;
  description?: string;
  source: string;
  config: OpenClawConfig;
  pluginConfig?: Record<string, unknown>;
  runtime: PluginRuntime;
  logger: PluginLogger;
  
  // Registration methods
  registerTool: (tool, opts?) => void;
  registerHook: (events, handler, opts?) => void;
  registerHttpHandler: (handler) => void;
  registerHttpRoute: (params) => void;
  registerChannel: (registration) => void;  // Key for channel plugins
  registerGatewayMethod: (method, handler) => void;
  registerCli: (registrar, opts?) => void;
  registerService: (service) => void;
  registerProvider: (provider) => void;
  registerCommand: (command) => void;
  resolvePath: (input: string) => string;
  on: <K>(hookName: K, handler, opts?) => void;
};
```

## Channel Plugin Contract

### ChannelPlugin Type

```typescript
type ChannelPlugin<ResolvedAccount = any, Probe = unknown, Audit = unknown> = {
  id: ChannelId;
  meta: ChannelMeta;
  capabilities: ChannelCapabilities;
  defaults?: { queue?: { debounceMs?: number } };
  reload?: { configPrefixes: string[]; noopPrefixes?: string[] };
  
  // Adapters (implement what you need)
  onboarding?: ChannelOnboardingAdapter;
  config: ChannelConfigAdapter<ResolvedAccount>;
  configSchema?: ChannelConfigSchema;
  setup?: ChannelSetupAdapter;
  pairing?: ChannelPairingAdapter;
  security?: ChannelSecurityAdapter<ResolvedAccount>;
  groups?: ChannelGroupAdapter;
  mentions?: ChannelMentionAdapter;
  outbound?: ChannelOutboundAdapter;
  status?: ChannelStatusAdapter<ResolvedAccount, Probe, Audit>;
  gatewayMethods?: string[];
  gateway?: ChannelGatewayAdapter<ResolvedAccount>;
  auth?: ChannelAuthAdapter;
  elevated?: ChannelElevatedAdapter;
  commands?: ChannelCommandAdapter;
  streaming?: ChannelStreamingAdapter;
  threading?: ChannelThreadingAdapter;
  messaging?: ChannelMessagingAdapter;
  agentPrompt?: ChannelAgentPromptAdapter;
  directory?: ChannelDirectoryAdapter;
  resolver?: ChannelResolverAdapter;
  actions?: ChannelMessageActionAdapter;
  heartbeat?: ChannelHeartbeatAdapter;
  agentTools?: ChannelAgentToolFactory | ChannelAgentTool[];
};
```

### ChannelMeta

```typescript
type ChannelMeta = {
  id: ChannelId;
  label: string;
  selectionLabel: string;
  docsPath: string;
  docsLabel?: string;
  blurb: string;
  order?: number;
  aliases?: string[];
  // ... more optional fields
};
```

### ChannelCapabilities

```typescript
type ChannelCapabilities = {
  chatTypes: Array<ChatType | "thread">;  // ["direct", "group", "channel", "thread"]
  polls?: boolean;
  reactions?: boolean;
  edit?: boolean;
  unsend?: boolean;
  reply?: boolean;
  effects?: boolean;
  groupManagement?: boolean;
  threads?: boolean;
  media?: boolean;
  nativeCommands?: boolean;
  blockStreaming?: boolean;
};
```

## Feishu Plugin Implementation

### Plugin Entry Point (index.ts)

```typescript
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { feishuPlugin } from "./src/channel.js";

const plugin = {
  id: "feishu",
  name: "Feishu",
  description: "Feishu/Lark channel plugin",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    setFeishuRuntime(api.runtime);
    api.registerChannel({ plugin: feishuPlugin });
    registerFeishuDocTools(api);
    registerFeishuWikiTools(api);
    registerFeishuDriveTools(api);
    registerFeishuPermTools(api);
    registerFeishuBitableTools(api);
  },
};

export default plugin;
```

### Channel Definition (channel.ts)

```typescript
const meta: ChannelMeta = {
  id: "feishu",
  label: "Feishu",
  selectionLabel: "Feishu/Lark (飞书)",
  docsPath: "/channels/feishu",
  docsLabel: "feishu",
  blurb: "飞书/Lark enterprise messaging.",
  aliases: ["lark"],
  order: 70,
};

export const feishuPlugin: ChannelPlugin<ResolvedFeishuAccount> = {
  id: "feishu",
  meta: { ...meta },
  
  // Capabilities
  capabilities: {
    chatTypes: ["direct", "channel"],
    polls: false,
    threads: true,
    media: true,
    reactions: true,
    edit: true,
    reply: true,
  },
  
  // Pairing for DM access control
  pairing: {
    idLabel: "feishuUserId",
    normalizeAllowEntry: (entry) => entry.replace(/^(feishu|user|open_id):/i, ""),
    notifyApproval: async ({ cfg, id }) => {
      await sendMessageFeishu({ cfg, to: id, text: PAIRING_APPROVED_MESSAGE });
    },
  },
  
  // Configuration schema
  configSchema: {
    schema: {
      type: "object",
      properties: {
        enabled: { type: "boolean" },
        appId: { type: "string" },
        appSecret: { type: "string" },
        domain: { enum: ["feishu", "lark"] },
        connectionMode: { enum: ["websocket", "webhook"] },
        dmPolicy: { enum: ["open", "pairing", "allowlist"] },
        // ... more config options
      },
    },
  },
  
  // Config adapter
  config: {
    listAccountIds: (cfg) => listFeishuAccountIds(cfg),
    resolveAccount: (cfg, accountId) => resolveFeishuAccount({ cfg, accountId }),
    defaultAccountId: (cfg) => resolveDefaultFeishuAccountId(cfg),
    setAccountEnabled: ({ cfg, accountId, enabled }) => { /* ... */ },
    isConfigured: (account) => account.configured,
    describeAccount: (account) => ({ /* ... */ }),
  },
  
  // Outbound adapter (how to send messages)
  outbound: feishuOutbound,
  
  // Status adapter
  status: {
    defaultRuntime: createDefaultChannelRuntimeState(DEFAULT_ACCOUNT_ID, { port: null }),
    buildChannelSummary: ({ snapshot }) => ({ /* ... */ }),
    probeAccount: async ({ account }) => await probeFeishu(account),
    buildAccountSnapshot: ({ account, runtime, probe }) => ({ /* ... */ }),
  },
  
  // Gateway adapter (how to start the channel monitor)
  gateway: {
    startAccount: async (ctx) => {
      const { monitorFeishuProvider } = await import("./monitor.js");
      const account = resolveFeishuAccount({ cfg: ctx.cfg, accountId: ctx.accountId });
      ctx.log?.info(`starting feishu[${ctx.accountId}]`);
      return monitorFeishuProvider({
        config: ctx.cfg,
        runtime: ctx.runtime,
        abortSignal: ctx.abortSignal,
        accountId: ctx.accountId,
      });
    },
  },
};
```

### Outbound Adapter (outbound.ts)

```typescript
export const feishuOutbound: ChannelOutboundAdapter = {
  deliveryMode: "direct",
  chunker: (text, limit) => getFeishuRuntime().channel.text.chunkMarkdownText(text, limit),
  chunkerMode: "markdown",
  textChunkLimit: 4000,
  
  sendText: async ({ cfg, to, text, accountId }) => {
    const result = await sendMessageFeishu({ cfg, to, text, accountId });
    return { channel: "feishu", ...result };
  },
  
  sendMedia: async ({ cfg, to, text, mediaUrl, accountId }) => {
    // Handle text + media sending
    // ...
  },
};
```

### Monitor (monitor.ts) - Event Listener

```typescript
// WebSocket or Webhook event handling
async function monitorFeishuProvider(opts: MonitorFeishuOpts) {
  const { config, runtime, abortSignal, accountId } = opts;
  const account = resolveFeishuAccount({ cfg: config, accountId });
  
  // Create event dispatcher
  const eventDispatcher = createEventDispatcher(/* ... */);
  
  // Register handlers
  eventDispatcher.register({
    "im.message.receive_v1": async (data) => {
      const event = data as FeishuMessageEvent;
      await handleFeishuMessage({
        cfg: config,
        event,
        botOpenId: botOpenIds.get(accountId),
        runtime,
        chatHistories,
        accountId,
      });
    },
    // ... other event handlers
  });
  
  // Start WebSocket client or HTTP webhook server
  if (account.config.connectionMode === "websocket") {
    const wsClient = createFeishuWSClient(/* ... */);
    // Connect and listen
  } else {
    // Start HTTP webhook server
  }
}
```

## Key Patterns for MoonBit Implementation

### 1. Channel Trait/Interface

Define a `Channel` trait that all channel implementations must satisfy:

```moonbit
///|
pub trait Channel {
  id(Self) -> String
  capabilities(Self) -> ChannelCapabilities
  start(Self, Context) -> Unit
  stop(Self) -> Unit
  send(Self, to : String, message : Message) -> Result[SendResult, ChannelError]
  handle_event(Self, event : Json) -> Unit
}
```

### 2. Channel Registry

A central registry for all channels:

```moonbit
///|
pub struct ChannelRegistry {
  priv channels : Map[String, ChannelEntry]
}

///|
pub fn ChannelRegistry::register(self : ChannelRegistry, channel : Channel) -> Unit {
  self.channels[channel.id()] = ChannelEntry::new(channel)
}

///|
pub fn ChannelRegistry::get(self : ChannelRegistry, id : String) -> Channel? {
  self.channels[id]?.channel
}
```

### 3. Channel Dock (Lightweight Metadata)

```moonbit
///|
pub struct ChannelDock {
  id : String
  capabilities : ChannelCapabilities
  outbound : OutboundConfig?
  streaming : StreamingConfig?
}
```

### 4. Gateway Integration

The gateway should:
1. Load channel plugins at startup
2. Start channel monitors (WebSocket connections or webhook servers)
3. Route incoming messages to the agent
4. Route outgoing messages through the appropriate channel

### 5. Message Flow

```
Feishu Event → Monitor → Gateway → Agent → Tool Execution → Gateway → Outbound Adapter → Feishu API
```

## Configuration Structure

```json5
{
  channels: {
    feishu: {
      enabled: true,
      dmPolicy: "pairing",
      accounts: {
        main: {
          appId: "cli_xxx",
          appSecret: "xxx",
          botName: "My AI assistant",
        },
      },
    },
  },
}
```

## Plugin Hooks

The plugin system supports lifecycle hooks:

```typescript
type PluginHookName =
  | "before_model_resolve"
  | "before_prompt_build"
  | "before_agent_start"
  | "llm_input"
  | "llm_output"
  | "agent_end"
  | "message_received"
  | "message_sending"
  | "message_sent"
  | "before_tool_call"
  | "after_tool_call"
  | "session_start"
  | "session_end"
  | "gateway_start"
  | "gateway_stop";
```

## Recommended MoonBit Package Structure

```
maa/
├── channel/                    # Channel abstraction
│   ├── channel.mbt            # Channel trait
│   ├── registry.mbt           # Channel registry
│   ├── dock.mbt               # Channel dock (lightweight metadata)
│   ├── types.mbt              # Common types
│   └── moon.pkg
├── channels/                   # Channel implementations
│   ├── feishu/
│   │   ├── channel.mbt        # Feishu channel implementation
│   │   ├── client.mbt         # Feishu API client
│   │   ├── monitor.mbt        # Event monitor (WebSocket/Webhook)
│   │   ├── outbound.mbt       # Outbound message handler
│   │   ├── types.mbt          # Feishu-specific types
│   │   └── moon.pkg
│   ├── telegram/
│   │   └── ...
│   └── discord/
│       └── ...
├── gateway/
│   ├── server/
│   │   ├── gateway.mbt        # Gateway server (existing)
│   │   ├── channel_manager.mbt # Channel lifecycle management
│   │   └── moon.pkg
│   └── protocol/
│       └── ...
└── cmd/
    └── main/
        └── main.mbt           # Entry point
```

## Summary

The OpenClaw Feishu implementation demonstrates:

1. **Plugin Architecture**: Channels are plugins that register themselves with the gateway
2. **Adapter Pattern**: Each channel implements specific adapters (config, outbound, status, gateway)
3. **Event-Driven**: Messages flow through events from channel monitors to the agent
4. **Modular Design**: Each channel is self-contained with its own types, client, and handlers
5. **Configuration-Driven**: Channels can be enabled/disabled and configured per account
6. **Lifecycle Hooks**: Plugins can hook into various agent and gateway lifecycle events

For MoonBit implementation, we should:
1. Define a `Channel` trait with required methods
2. Create a `ChannelRegistry` for managing channels
3. Implement channel-specific packages under `channels/`
4. Integrate with the existing gateway server
5. Support both WebSocket and Webhook connection modes
