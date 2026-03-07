# moonclaw Node.js Examples

This directory contains example usage of the moonclaw Node.js SDK.

## Running the example

1. Install dependencies:

   ```bash
   npm install
   ```

2. Run the example:

   ```bash
   npm start
   ```

## Example: main.ts

This example demonstrates how to use the moonclaw SDK to interact with the agent:

- Starts a moonclaw agent with a prompt
- Listens for events from the agent
- Handles two types of events:
  - `moonclaw.agent.request_completed`: Prints the assistant's response
  - `moonclaw.agent.post_tool_call`: Prints tool call information and output

The example shows how to parse and display tool calls and their results in a formatted way.
