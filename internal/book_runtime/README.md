# MoonBook runtime resources

The ordinary MoonClaw Agent and MoonCode share this implementation for Book-local MCP configuration and installed Skill resources.

- MCP configuration prefers the explicit Book path `.moonsuite/products/moonclaw/mcp-servers.json`, with the existing MoonSuite-derived configuration as a compatibility fallback, and `{servers:[{id,url,token?,enabled?}]}`. Explicit Book-local Skill resources override the compatible suite/global catalog through the same Skill loader.
- `mcp_list_tools` discovers the actual provider schema; `mcp_call_tool` selects one enabled integration and preserves its JSON result. Existing initialization, session and protocol headers remain in use.
- `read_skill` uses the existing Skill loader and reads complete instructions or a confined relative resource. It preserves content digest and loading receipt metadata used by MoonCode.
- Installed folder IDs identify Skills independently of their validated frontmatter display names. Repeated publisher display names retain separate entries; `read_skill` accepts the folder ID or a unique display name. Catalogs expose both ID and display name, and loading receipts retain the stable ID.
- The ordinary Agent installs these tools only for a conversation whose persisted `workspace_trust` is `trusted`; restricted workflow capsules retain their existing tool surface. Book `AGENTS.md`, Skill catalog and enabled integration names are loaded for trusted turns.
- MoonDesk grants trust to the MoonFish finance Book only when the suite-owned `moonfish/moonclaw.json` explicitly says `workspace_trust: trusted`, `execution_owner: moonclaw`, and its workspace ID and canonical Book root match the selected workspace. Imported Skill documents do not establish workspace trust.

Financial calculations and data access remain in their existing MCP services. This package does not introduce another Agent loop or model provider.
