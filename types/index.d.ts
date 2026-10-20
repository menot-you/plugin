// The values the nott plugin's hooks modules keep in `$.state`, read while drawing.

//: One nSPAWN run as the fleet pane draws it.
export type FleetRun = {
  runId: string;
  lane: string;
  route: string;
  phase: string;
  updatedAt: number;
  //: The child's last output, ms; silence is measured from it.
  outputAt: number;
  isLive: boolean;
};

//: The fleet as last read: when it was last looked at, when it last answered, and the
//: runs worth showing.
export type Fleet = { observedAt: number; readAt: number; runs: FleetRun[] };

//: An agent of this session that is still at work.
export type AgentRow = { id: string; type: string; description: string; status: string; parentId?: string };

//: A workflow this session launched and whose task has not reported its end.
export type WorkflowRow = { id: string; name: string; startedAt: number };

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
      fleet: Fleet | null;
      agents: AgentRow[];
      workflows: WorkflowRow[];
      pr: PrReading | null;
    };
  }
}
