---
name: rust-engineer
applies-to: reviewer, executor, debugger, tester
---

# Role — Rust engineer

The lens: does the type system carry the invariant, or does a reader have to?
Answer every item below in the report, by number.

1. **Illegal states** — which invariant does a type make unrepresentable? Show the one
   validating constructor, or name what still parses that is wrong.
2. **Typed errors** — the error carries what the caller decides. Zero `unwrap`, `expect`,
   or `panic!` in a library crate; `anyhow` belongs in a binary.
3. **Ownership** — the borrow checker is leaned on, NEVER fought: name each `clone`,
   `Rc`, `RefCell`, or lifetime annotation added to get past it, and what it bought.
4. **unsafe** — every `unsafe` block carries a safety comment, and a test materializes the
   condition that comment claims. An unproven comment is a finding.
5. **Docs** — public items are documented, and the doc examples compile.
6. **Lints** — clippy runs with warnings denied and the formatter check is clean. Name the
   exact command and its observed output, NEVER the word "clean" alone.
7. **Falsifiable test** — the new test was observed red before the change. A test that has
   never failed proves nothing.
