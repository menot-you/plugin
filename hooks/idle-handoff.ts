import type { Register } from "claude-code";

const MIN = 60_000;
const IDLE_DEFAULT = 50 * MIN;
const MAX_PINGS = 3;
const RETRY_MS = 30_000;
const MAX_RETRIES = 3;
const SELF = "nott";
//: The owner's own channels, and a follow-up to his UI action; `unclassified` is not
//: one: it carries the engine's idle notices and delivery receipts.
const OWNER = new Set(["composer", "bridge", "slack-ping", "channel", "auto-continuation"]);

const PING = "Reply with the single word: ok.";
const COMPACT_INSTRUCTIONS =
  "Keep the last state line (RUNNING/STOPPED/DELIVERED), the nMEMORY handoff capsule id " +
  "and the next valid action verbatim; keep open decisions and their options.";

function handoffPrompt(nonce: string): string {
  return [
    "The session has been idle and the prompt cache is about to expire.",
    "Load /nott:handoff and record the cold-readable continuation in nMEMORY",
    "(nmemory_session_finish or nmemory_capsule_ingest), then write the state line with",
    "`~/.nott/bin/state.sh set \"STOPPED: <reason> · next action: <x>\"`.",
    "Your whole answer is this exact line:",
    `HANDOFF-DONE ${nonce}`,
  ].join("\n");
}

//: Born in `register`, so each load (a session, a reload, a test) starts afresh.
type State = {
  timer: { cancel(): void } | null;
  background: Set<string>;
  pings: number;
  dormant: boolean;
  headless: boolean;
  nonce: string | null;
  handoffStarted: boolean;
  ownerSeq: number;
  seqAtFire: number;
  compactOwed: boolean;
  retries: number;
  turnOpen: boolean;
};

function fresh(): State {
  return {
    timer: null,
    background: new Set(),
    pings: 0,
    dormant: false,
    headless: false,
    nonce: null,
    handoffStarted: false,
    ownerSeq: 0,
    seqAtFire: 0,
    compactOwed: false,
    retries: 0,
    turnOpen: false,
  };
}

function cancel(s: State): void {
  s.timer?.cancel();
  s.timer = null;
}

async function arm($: any, s: State): Promise<void> {
  cancel(s);
  const raw = Number(await $.env.get("NOTT_IDLE_HANDOFF_MS"));
  const ms = Number.isFinite(raw) && raw > 0 ? raw : IDLE_DEFAULT;
  s.timer = $.clock.after(ms, () => void fire($, s));
}

function compact($: any, s: State): void {
  $.clock.after(0, () => void tryCompact($, s));
}

// ponytail: the owner check runs before the await; an owner prompt queued (not yet a
// running turn) while the summarizer works is not seen. The engine offers no lock.
async function tryCompact($: any, s: State): Promise<void> {
  if (s.ownerSeq !== s.seqAtFire) {
    s.compactOwed = false;
    return;
  }
  try {
    const result = await $.session.compact({ instructions: COMPACT_INSTRUCTIONS });
    s.compactOwed = false;
    if (result && "skip" in result && result.skip) {
      $.ui.log("idle-handoff: a hook skipped the compaction", { to: "transcript" });
    }
  } catch (err) {
    s.compactOwed = true;
    $.ui.log(`idle-handoff: compaction refused (${String(err)}); retrying`, { to: "transcript" });
    if (s.retries < MAX_RETRIES) {
      s.retries += 1;
      $.clock.after(RETRY_MS, () => void retryCompact($, s));
    }
  }
}

async function retryCompact($: any, s: State): Promise<void> {
  if (s.compactOwed && !s.turnOpen) await tryCompact($, s);
}

function handedOff($: any, s: State): void {
  s.nonce = null;
  s.handoffStarted = false;
  s.dormant = true;
  cancel(s);
  s.retries = 0;
  compact($, s);
}

async function fire($: any, s: State): Promise<void> {
  s.timer = null;
  if (s.nonce !== null) {
    //: The last handoff never ended with its marker: one per absence, so sleep until a
    //: message not its own rather than ask again.
    s.nonce = null;
    s.handoffStarted = false;
    s.dormant = true;
    return;
  }
  if (s.background.size > 0 && s.pings < MAX_PINGS) {
    s.pings += 1;
    try {
      const r = await $.model.fork({ prompt: PING });
      $.ui.log(
        r?.isAnswered
          ? `idle-handoff: keep-warm ping ${s.pings}, cache read ${r.usage.cache_read_input_tokens}`
          : `idle-handoff: keep-warm ping ${s.pings} not answered (${r?.reason ?? "no result"})`,
        { to: "debug" },
      );
    } catch (err) {
      //: A refused fork (a blocked model) must not stop the clock.
      $.ui.log(`idle-handoff: keep-warm ping ${s.pings} refused (${String(err)})`, { to: "debug" });
    }
    await arm($, s);
    return;
  }
  s.pings = 0;
  s.nonce = crypto.randomUUID();
  s.seqAtFire = s.ownerSeq;
  await $.prompt.submit({ text: handoffPrompt(s.nonce) });
}

//: The marker is the message's last line, as the prompt asks: a message that only
//: announces it mid-sentence does not end the handoff.
function marked(s: State, text: unknown): boolean {
  if (s.nonce === null || typeof text !== "string") return false;
  const body = text.trimEnd();
  const line = `HANDOFF-DONE ${s.nonce}`;
  return body === line || body.endsWith(`\n${line}`);
}

//: A blocking Stop hook continues the same turn, and its final answer then loses the
//: marker an earlier message of the turn carried. The prompt quotes the marker too,
//: so only the assistant's messages count.
async function answered($: any, s: State, e: any): Promise<boolean> {
  if (e.reason !== "answer") return false;
  if (marked(s, e.answer)) return true;
  const messages = await $.session.messages();
  return messages.some((m: any) => m.role === "assistant" && marked(s, m.text));
}

//: The id a launch left running in the background, per built-in tool; null when it
//: ran in the foreground.
function launched(tool: unknown, r: any): string | null {
  const x = r?.result;
  if (x === null || typeof x !== "object") return null;
  switch (tool) {
    case "Bash":
      return x.backgroundTaskId ?? null;
    case "Monitor":
    case "Workflow":
      return x.taskId ?? null;
    case "Agent":
      if (x.status === "async_launched") return x.agentId ?? null;
      if (x.status === "remote_launched") return x.taskId ?? null;
      return null;
    default:
      return null;
  }
}

async function onSubmit($: any, e: any, next: any, s: State) {
  const kind = e.origin?.kind;
  if (kind === "sdk") s.headless = true;
  if (kind === "task-notification" && typeof e.text === "string") {
    for (const id of s.background) if (e.text.includes(`<task-id>${id}</task-id>`)) s.background.delete(id);
  }
  if (!(kind === "plugin" && e.origin?.name === SELF)) {
    s.dormant = false;
    s.pings = 0;
  }
  if (OWNER.has(kind)) {
    s.ownerSeq += 1;
    s.nonce = null;
    s.handoffStarted = false;
    s.compactOwed = false;
  }
  return next(e);
}

async function onStart($: any, e: any, next: any, s: State) {
  cancel(s);
  s.turnOpen = true;
  //: The handoff turn starts with its own prompt: a notification ahead of it does not.
  if (s.nonce !== null && typeof e.text === "string" && e.text.includes(s.nonce)) s.handoffStarted = true;
  return next(e);
}

// ponytail: a task that ends without a notification stays recorded; MAX_PINGS bounds
// what it costs, and the next handoff runs anyway.
async function onTool($: any, e: any, next: any, s: State) {
  const r = await next(e);
  const id = launched(e.tool, r);
  if (id !== null) s.background.add(id);
  return r;
}

async function onSessionStart($: any, e: any, next: any, s: State) {
  cancel(s);
  Object.assign(s, fresh(), { headless: e.isInteractive === false });
  return next(e);
}

async function onComplete($: any, e: any, next: any, s: State) {
  if (e.agentId) return next(e);
  s.turnOpen = false;
  if (s.nonce !== null && (await answered($, s, e))) {
    handedOff($, s);
  } else if (s.handoffStarted) {
    //: The handoff ran and ended without its marker (refused, aborted, failed, or the
    //: line left out): one per absence, so sleep until a message not its own.
    s.nonce = null;
    s.handoffStarted = false;
    s.dormant = true;
  } else if (s.compactOwed && s.ownerSeq === s.seqAtFire) {
    compact($, s);
  } else if (!s.dormant && !s.headless) {
    //: Also with a handoff pending: if it never ends with its marker (a hook rewrote its
    //: prompt), the next fire finds the stale nonce and gives up instead of waiting forever.
    await arm($, s);
  }
  return next(e);
}

export const register: Register = (on) => {
  const s = fresh();
  on("prompt.submit", ($: any, e: any, next: any) => onSubmit($, e, next, s));
  on("turn.start", ($: any, e: any, next: any) => onStart($, e, next, s));
  on("tool.call", ($: any, e: any, next: any) => onTool($, e, next, s));
  on("turn.complete", ($: any, e: any, next: any) => onComplete($, e, next, s));
  on("session.start", ($: any, e: any, next: any) => onSessionStart($, e, next, s));
};
