# wiki — the canon's working vocabulary, explained

**Normative scope.** This glossary is non-normative. Uppercase normative keywords
are quoted vocabulary; the cited authority document carries each rule.

It explains terms for a cold reader; nothing here is law. On any conflict,
`decisions.md` wins, followed by `PRD.md`, `SPEC.md`, and `NOTT.md`. Kernel-lane
terms are authoritative only in the `decisions.md` closed glossary.

---

**calibration record** — the registration a personal preference needs before it becomes a standing rule: the observed trigger, the consequence, the override taken, and the condition that would revoke it. Without the record, a preference is folklore, not method. Source: [PRD.md](PRD.md) §2.

**claim ledger** — the three truth-states every meaningful claim must name ([NOTT.md](NOTT.md) §2): **Observed** — the command, test, readback, or live check was run and seen; **Inferred** — proof supports the claim but the claimed result was not directly seen; **Unverified** — a hypothesis still waiting for a differentiating check. It exists to make overclaim visible: "done" has to say which state backs it, and local green is never merged, deployed, or adopted.

**cold agent** — a reader or writer with zero tribal memory: no transcript, no folklore, no "everyone knows". Every doc, plan, and work unit in this repo is written so a cold agent can act without asking. If it needs the author present to be understood, it is not ready. Source: [NOTT.md](NOTT.md) §4, §12.

**dispatch contract** — the minimum a subagent gets before work: acceptance criteria, bounded scope, and a pointer to the source of truth (it does not inherit the conversation). The subagent reads its understanding back. Loose delegation is blocked at dispatch, not caught after. Source: [NOTT.md](NOTT.md) §10.

**doc-lint** — the repository gate that reads a document's declared normative scope and rejects hedges inside normative paragraphs. Source: [NOTT.md](NOTT.md) preamble and §11; [decisions.md](decisions.md) `d10-artifact-laws-adversarial-gate`; enforcer: `tools/doc-lint.sh`.

**drift** — acting on shared meaning that was never verified: two people (or two docs, or two agents) using one word for two things, or a plan diverging from its authority without anyone deciding that. The seven failure classes ([NOTT.md](NOTT.md) §14) are an operating and review taxonomy; repository mechanisms are named separately in [SPEC.md](SPEC.md) §6.

**falsifiability (falsificação)** — a statement is falsifiable when a concrete observation could prove it wrong. The canon demands it twice: readback statements are numbered and individually refutable — the engineer can say "number 3 is wrong" ([NOTT.md](NOTT.md) §4) — and every claimed property needs a red-test that turns red when the property is violated ([NOTT.md](NOTT.md) §11). A claim nothing could refute is decoration, not engineering.

**grant (the)** — the standing autonomy the engineer gives inside a locked result contract: NOTT plans, executes, reviews, and ships without per-step approval; destructive, public, production, financial, credential, data-loss, or merge-to-main actions still return to the engineer unless the exact action was authorized. Source: [NOTT.md](NOTT.md) §5.

**hedge** — should, could, might, maybe, ideally, possibly inside a normative clause. Hedging is how a rule stops being a rule while still looking like one; law 1 requires an unhedged imperative or removal. Source: [NOTT.md](NOTT.md) §11.

**home** — the mandatory opening of any plan, resume, status, or work graph: the ready-set plus exactly ONE next physical action, and the proof path or exact gap (what would prove the result, or what exactly is missing). When the work has structure, the home carries the diagram. It exists to take state out of the engineer's head — it is never a dashboard, guilt counter, or menu. Source: [NOTT.md](NOTT.md) §6; [PRD.md](PRD.md) §6 home law.

**LGTM** — a review's pass verdict: no blocking finding remains and the required verification is green. Never a courtesy. Source: [NOTT.md](NOTT.md) §7.

**n=1 / n=1 override** — the product-law term for engineer-specific calibration. Full rule and boundary: [PRD.md](PRD.md) §2.

**observed verification** — the claim state for a check the session ran and saw. It is not a blanket label: **Inferred** and **Unverified** remain distinct states, and none is kernel closure. Source: [NOTT.md](NOTT.md) §2; [PRD.md](PRD.md) §3.

**one source per fact (SSOT)** — every normative fact has exactly one home; anywhere else it appears is a reference, never a restatement. Duplicated law drifts the moment one copy is edited. Generated views are regenerated; hand-authored derived documents pass adversarial review. Source: [NOTT.md](NOTT.md) §11 law 4, §12.

**ready-set** — the work units whose dependencies are all met and which are therefore executable right now. The home leads with it because it answers the only urgent question: what can move at this moment. Source: [PRD.md](PRD.md) §6 (d5-docviz-first-projection-surface).

**readback** — the shared-understanding gate: the ask is restated as numbered, atomic, falsifiable statements, inferences labeled, and the engineer confirms or corrects by number. "Yes, I understood" is never claimed — the numbered list is the claim. Source: [NOTT.md](NOTT.md) §4.

**red-test** — the test that goes red when a rule is broken: a violation is materialized and its rejection asserted. "Style is not requested, it is tested; a property without a red-test is a wish." Green suites that never saw red prove nothing. Source: [NOTT.md](NOTT.md) §11, §12.

**reserved kernel terms — `outcome`, `witness`, `evidence`, `effect`, closure** — closed names whose definitions are not projected here. Authoritative definitions: [decisions.md](decisions.md) closed glossary. Session claim boundary: [PRD.md](PRD.md) §3.

**result contract** — what gets locked before autonomous work: Result, Scope, Constraints, Authority, Witness, Rollback, Stop conditions. It is the boundary the grant lives inside. Source: [NOTT.md](NOTT.md) §5.

**rung (honest rungs)** — the enforcement ladder a rule sits on: advisory voice → repo-gated (a hook or CI gate, from commit 1) → kernel-enforced (when the sovereign `trust_spine` exists). Two laws hold it honest: a rule never claims a rung its mechanism cannot hold, and the rung is visible in the letter — uppercase normative keywords are binding, lowercase is rationale or advisory. Rungs rise as machinery ships. Source: [NOTT.md](NOTT.md) preamble + §10.

**epistemic law** — the product-law boundary governing what a session may claim. Full rule: [PRD.md](PRD.md) §1 and §3. Reserved vocabulary: [decisions.md](decisions.md) closed glossary. Operating projection: [NOTT.md](NOTT.md) §2.
