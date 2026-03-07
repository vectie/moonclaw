import cp from "child_process";
import type { ResultTuple } from "../types";

let setupmoonclawPromise: Promise<ResultTuple<undefined>> | undefined = undefined;

export async function setupmoonclawProcess(
  moonclawPath: string,
  env?: NodeJS.ProcessEnv,
) {
  if (setupmoonclawPromise) {
    return await setupmoonclawPromise;
  }
  setupmoonclawPromise = doSetupmoonclawProcess(moonclawPath, env ?? process.env);
  return await setupmoonclawPromise;
}

async function doSetupmoonclawProcess(
  moonclawPath: string,
  env: NodeJS.ProcessEnv,
): Promise<ResultTuple<undefined>> {
  const exitCode = await new Promise<number | null>((resolve, reject) => {
    const moonclaw = cp.spawn(moonclawPath, ["daemon", "--port", "0", "--detach"], {
      stdio: "ignore",
      env,
    });

    moonclaw.on("error", reject);
    moonclaw.on("exit", (code) => {
      resolve(code);
    });
  });

  if (exitCode !== 0) {
    if (
      process.env["OPENAI_API_KEY"] === undefined &&
      process.env["OPENROUTER_API_KEY"] === undefined
    ) {
      return [
        undefined,
        new Error(
          "OPENAI_API_KEY or OPENROUTER_API_KEY is not set in the shell environment",
        ),
      ];
    }
    return [undefined, new Error(`moonclaw daemon exited with code ${exitCode}`)];
  }
  return [undefined, undefined];
}
