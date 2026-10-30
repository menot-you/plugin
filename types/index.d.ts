// The values the nott plugin's hooks modules keep in `$.state`, read while drawing.

//: One nSPAWN run of an entry, as the requests file carries it.
export type RequestsRun = { runId: string; phase: string; lastOutputAt: number | null };

//: One owner prompt of the session, as the node host keeps it.
export type RequestsEntry = {
  number: number;
  prompt_id: string;
  text: string;
  at: number;
  state: "open" | "done" | "accepted" | "replied";
  minutes: number | null;
  spentMin: number;
  deliver: string | null;
  note: string | null;
  alarms: string[];
  runs: RequestsRun[];
};

//: The node host's requests file v1 (harness/nott_harness/acp/schema/requests-file.v1.schema.json).
export type RequestsFile = {
  v: 1;
  observedAt: number;
  entries: RequestsEntry[];
  outside: { name: string; since: number }[];
  //: The runs the host has not attributed yet; absent in a file from an older host.
  pending?: { runId: string; phase: string; createdAt: number; alarms: string[] }[];
  unasked: { runId: string; phase: string; createdAt: number; lastOutputAt: number | null; alarms: string[] }[];
  //: The host inputs it could not read, each since when; absent in a file from an older host.
  inputErrors?: { input: "spool" | "runs" | "pulls" | "session-state"; since: number }[];
};

//: One owner prompt that session-state.sh kept: the payload's prompt_id ("" when it had none,
//: null for the clock of the previous hook) and the epoch ms.
export type OwnerPrompt = { id: string | null; at: number };

//: The pane's last reading: the file, or null when the session has none; `error` when it
//: could not be read; `isLocated` false when the session id or the runtime dir is unknown.
//: `isSpooled` when prompt-capture.py's spool is there; `spoolAt` the newest `at` of its last
//: lines that parse (0 with none, null with no spool); `spoolFirstAt` the `at` of its first line
//: (-1 when it does not parse or the spool is empty, null with no spool); `spoolIds` the
//: prompt_id of each of its last lines; `spoolBad` how many of them do not parse; `prompts` the
//: owner prompts that session-state.sh kept, judged where the requests directory is there.
export type RequestsReading = {
  file: RequestsFile | null;
  error: string | null;
  isLocated: boolean;
  isSpooled: boolean;
  spoolAt: number | null;
  spoolFirstAt: number | null;
  spoolIds: string[];
  spoolBad: number;
  prompts: OwnerPrompt[];
};

//: An agent of this session that is still at work.
export type AgentRow = { id: string; type: string; description: string; status: string; parentId?: string };

//: The pull request of the session's branch, reduced to what the band draws.
export type CampaignPr = {
  number: number;
  ok: number;
  running: number;
  failed: string[];
  review: string;
  merge: string;
};

//: The band's last reading and, when the latest gh call failed, why: the reading is then
//: an older one, or null when gh has never answered.
export type PrReading = { pr: CampaignPr | null; error: string | null };

declare module "claude-code" {
  interface PluginState {
    nott: {
      requests: RequestsReading | null;
      agents: AgentRow[];
      pr: PrReading | null;
    };
  }
}
