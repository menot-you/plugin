// The plugin's one hooks module: the engine loads a single module per plugin.
import type { Register } from "claude-code";

import { register as idleHandoff } from "./idle-handoff.ts";

export const register: Register = (on, options) => {
  idleHandoff(on, options);
};
