import fsp from "fs/promises";
import path from "path";
import type { ResultTuple } from "../types";

type DaemonJson = {
  pid: number;
  port: number;
};

function suiteRootForWorkspaceRoot(workspaceRoot: string): string {
  const normalized = path.resolve(workspaceRoot);
  const parent = path.dirname(normalized);
  if (path.basename(parent) === "books") {
    return path.dirname(parent);
  }
  return normalized;
}

function daemonJsonPath(workspaceRoot: string): string {
  return path.join(
    suiteRootForWorkspaceRoot(workspaceRoot),
    ".moonsuite",
    "products",
    "moonclaw",
    "daemon.json",
  );
}

async function getDaemonJson(
  workspaceRoot: string,
): Promise<ResultTuple<DaemonJson>> {
  try {
    const daemonJson: DaemonJson = JSON.parse(
      await fsp.readFile(daemonJsonPath(workspaceRoot), "utf-8"),
    );
    return [daemonJson, undefined];
  } catch (error) {
    return [undefined, error as Error];
  }
}

export async function getApi(
  workspaceRoot: string,
): Promise<ResultTuple<string>> {
  const [json, error] = await getDaemonJson(workspaceRoot);
  if (error) {
    return [undefined, error];
  } else {
    return [`http://localhost:${json.port}/v1`, undefined];
  }
}

export async function shutdown(
  workspaceRoot: string,
): Promise<ResultTuple<undefined>> {
  try {
    const [api, error] = await getApi(workspaceRoot);
    if (error) {
      return [undefined, error];
    }
    const res = await fetch(`${api}/shutdown`, {
      method: "POST",
    });
    if (!res.ok) {
      return [
        undefined,
        new Error(
          `Shutdown request failed with status ${res.status}: ${res.statusText}`,
        ),
      ];
    }
    return [undefined, undefined];
  } catch (error) {
    return [undefined, error as Error];
  }
}
