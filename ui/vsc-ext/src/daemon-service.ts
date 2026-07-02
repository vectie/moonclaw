import { setupmoonclawProcess } from "@moonclaw/core/lib/node/moonclaw-setup.js";
import { getApi } from "@moonclaw/core/lib/node/moonclaw-util.js";
import { TaskOverview } from "@moonclaw/core/lib/types.js";
import { get } from "./global-state";

export class DaemonService {
  _api: string;

  private static _instance: DaemonService;

  static async instance() {
    if (!this._instance) {
      const context = get("context")!;
      const cwd = get("cwd")!;
      const moonclawPath = context.asAbsolutePath(
        `bin/${process.platform}/moonclaw`,
      );
      const [_, error] = await setupmoonclawProcess(moonclawPath, cwd);
      if (error) {
        // TODO: Handle error properly
        throw new Error("Failed to setup moonclaw process: " + error.message);
      }
      const [api, apiError] = await getApi(cwd);
      if (apiError) {
        // TODO: Handle error properly
        throw new Error("Failed to get moonclaw API: " + apiError.message);
      }
      this._instance = new DaemonService(api);
    }
    return this._instance;
  }

  private constructor(api: string) {
    this._api = api;
  }

  private async _getTasks(): Promise<TaskOverview[]> {
    try {
      const res = await fetch(`${this._api}/tasks`, { method: "GET" });
      const data = (await res.json()) as { tasks: TaskOverview[] };
      return data.tasks;
    } catch {
      throw new Error(
        "Could not connect to daemon. Please ensure that the daemon is running.",
      );
    }
  }

  async getTaskIdOfDir(dir: string): Promise<string | undefined> {
    const tasks = await this._getTasks();

    let taskId: string | undefined = undefined;

    for (const task of tasks) {
      if (task.cwd === dir) {
        taskId = task.id;
      }
    }
    return taskId;
  }

  get api() {
    return this._api;
  }
}
