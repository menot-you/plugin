# Evidence and review

Distinguish Observed, Inferred and Unverified claims. An observation names the
real path and evidence; plausible reasoning, memory, a worker's conclusion and
local success do not prove delivery.

Review is independent, adversarial and read-only with respect to the work.
Required independent witnesses cannot be supplied by its author. Bind each
observation to the work and relevant policy, configuration, target, dependencies
and expiry. A changed input invalidates only the claims it can affect; unknown
reach requires investigation. Unrelated trunk movement is not changed work.
Patch-id equality alone is insufficient to preserve a verdict.

Use a coherent review boundary, not a new review for every checkpoint. Preserve
valid findings and proofs between rounds. A non-blocking finding never becomes a
commit or another round: it becomes an **nMEMORY** capsule, naming
the test that would prove it closed, and the candidate is delivered if every
required proof is present. Missing proof and unresolved behavioral failures
still block acceptance.

Keep approval, evidence validity, operation identity and observed effect
separate. An exception preserves the original failure. Never change acceptance
unilaterally, forge evidence, suppress a failing assertion or weaken a judge for
green. When creating or changing a judge, prove that it accepts the valid
control and rejects the intended defect in separate test state; mutation
deaths without an accepted control prove nothing. Reuse existing valid evidence.
Judge validation never grants authority to corrupt or republish the delivery
target.

Every declared obligation names the observation that decides it and the
runtime producer that emits it. An obligation no producer can satisfy is a
defect of the contract, not of the candidate. When the deciding observation
cannot exist in the judging environment, record the obligation with its
measurement, the `file:line` that decides it, and what would lift it; never
leave it demanding the impossible.
