import { moonclaw } from "moonclaw";

async function main() {
  const moonclaw = new moonclaw();

  for await (const event of moonclaw.start("Hello?")) {
    if (event.method === "moonclaw.agent.request_completed") {
      const content = event.params.message.content;
      if (content !== null) {
        console.log(content);
      }
    } else if (event.method === "moonclaw.agent.post_tool_call") {
      const toolCall = event.params.tool_call;
      const toolName = toolCall.function.name;
      const toolArgs = toolCall.function.arguments;

      try {
        const parsedArgs = JSON.parse(toolArgs);
        console.log(`% ${toolName} ${JSON.stringify(parsedArgs, null, 2)}`);
      } catch {
        console.log(`% ${toolName} ${toolArgs}`);
      }

      for (const line of event.params.text.split("\n")) {
        console.log(`> ${line}`);
      }
    }
  }
}

main().catch(console.error);
