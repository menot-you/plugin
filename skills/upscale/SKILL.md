---
name: upscale
description: >-
  Rewrite a prompt so that it asks for a deeper version of the same task, not a
  bigger one. Use when the owner asks to upscale or deepen a prompt, and before
  you send a non-mechanical brief to a subagent, an nSPAWN run or a workflow
  agent. Not for doing the task.
---

# Upscale

Make the task deeper, not bigger.

## Modes

<!-- nott:upscale:owner -->
Owner mode: the owner asks for an upscale of a prompt. Give the four answers and the rewritten prompt, then stop. Do not do the task unless the owner asks for it.

<!-- nott:upscale:brief -->
Brief mode: you are about to send a non-mechanical brief to another agent. Apply the procedure to your brief and send the rewritten brief. Do not show the four answers to the owner and do not ask for approval: the method is the team's decision. A mechanical brief, such as a rename, a format change or one command to run, does not need an upscale.

## Procedure

<!-- nott:upscale:procedure -->
1. Find the field of the task. If the prompt does not name the field, state your assumption in one line.
2. If the task is about this workspace or a system that you can read, look at it before you answer. Read only. Use the real paths, logs, data and commands that you find.
3. Answer these four questions. Make each answer specific to this task. A generic answer such as "test it well" or "use best practices" is not an answer.
   1. What does a top professional in this field do here that the prompt does not ask for?
   2. What is the rawest material that they start from, instead of the digest that the prompt already has? For example: source code, not its docs. Raw logs, not a dashboard. The primary dataset, not a report. The original spec, not a summary.
   3. Which specific methods and tools do they use? Prefer the tools that this environment has. Mark a tool that this environment does not have as "not installed".
   4. What, other than the model or the owner, shows that the result is correct? Name an external check: a test, a measurement, a reference implementation, a standard, real data or a third party. Say how to run it or read it.
4. Rewrite the prompt so that it asks for exactly that.

## Rewrite

<!-- nott:upscale:rewrite -->
- Keep the same result and the same scope. Add no new deliverable.
- Each new instruction comes from one of the four answers. Remove an instruction that does not.
- Put the external check from answer 4 in the prompt as its acceptance condition.
- Keep the constraints, names, paths and numbers of the prompt exactly.
- Write the rewrite in the language of the original prompt. If that language is English, write short sentences in the active voice, with one instruction in each sentence.

## Output in owner mode

<!-- nott:upscale:output -->
1. The four answers, in the language of the owner, two or three lines each.
2. The rewritten prompt in one code block, ready to paste.
