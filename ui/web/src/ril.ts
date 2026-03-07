import * as ral from "@moonclaw/core/lib/ral.ts";
import type { WebRAL } from "@moonclaw/core/lib/types.js";

const _ril: WebRAL = {
  platform: "web",
};

export function install(): void {
  ral.install(_ril);
}
