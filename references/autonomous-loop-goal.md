# Autonomous Loop Goal Protocol

This reference explains where a fully automatic loop goal belongs inside `gpt-pro-review-loop` and how to make Codex move faster in an explicitly isolated test line.

Use this reference when the user explicitly asks for any of these patterns:

- `全自动 loop`
- autonomous loop
- bold candidate first
- candidate-first prototype
- rapid visual/playable/test-line candidate
- keep cycling until a real blocker
- do not wait for perfect assets or final architecture

## Core Idea

In a bold test line, Codex should not behave like it is preparing a formal release.

It should behave like a prototype builder:

```text
pick the strongest usable candidate
build the smallest visible slice
capture evidence
continue
```

The goal is not to prove the final project is complete. The goal is to create an isolated, visible, runnable candidate as fast as possible.

## Only Three Hard Rails

When the user has explicitly authorized a bold test line, keep only these hard rails:

1. **Isolation rail**: stay in the declared test scope, branch, sandbox, or candidate path. Do not merge into formal release scope by yourself.
2. **Irreversible-action rail**: pause for merge, publish, deploy, destructive deletion, reset, credentials, payment, permission changes, or explicit Human Gate.
3. **Evidence rail**: leave enough proof to inspect the candidate: run path, command output, screenshot, report, asset ledger, diff summary, or failure artifact. Do not claim project-total completion unless project-total Done Gate passes.

Everything else is a preference, not a blocker.

If the action is reversible, isolated, and evidence-producing, prefer doing it over discussing it.

## Placement In The Skill Chain

The autonomous loop goal sits between local brainstorming and evidence capture:

```text
Project Understanding
-> Capability Scan
-> Local Expert Council Brainstorm
-> Bold Candidate Pick
-> Goal Backlog / Goal Slices
-> Outer Codex local implementation
-> RecordProgress / Evidence
-> NextDecision
-> DoneGate / FinalClosure
```

Do **not** put this inside GPT Pro review, browser automation, or final closure. GPT Pro can review the candidate, but it is not the executor.

## Why This Position Works

`Local Expert Council` is already the divergent-thinking module. It generates possibilities.

The missing link for automatic loops is not more process. The missing link is permission to pick one strong candidate and build.

`RecordProgress`, `Evidence`, and `NextDecision` already provide the proof and continuation system. Use them after the work, not as excuses to delay the work.

## Bold Candidate Pick

When this protocol is active, do not require a heavy candidate table unless the project is genuinely ambiguous.

Use this lightweight decision:

```text
Best usable candidate:
- what will be built now
- why it is usable now
- what evidence it should produce
- fallback if it fails
```

Pick the candidate with the highest demo/proof value.

Prefer:

- visible over abstract
- playable over architecturally pure
- real asset over placeholder
- placeholder over stopping
- screenshot over explanation
- runnable path over long report
- next slice over perfect plan

## Fast Loop

Inside an explicitly authorized autonomous loop:

```text
1. Pick a bold candidate.
2. Build the smallest visible/runnable slice.
3. Capture evidence.
4. Record progress.
5. Ask NextDecision.
6. Continue unless there is a real pause condition.
```

Real pause conditions:

- `NEEDS_HUMAN_DECISION`
- `BLOCKED`
- merge / publish / deploy
- destructive deletion or reset
- credential, payment, permission, login, CAPTCHA
- explicit user stop

Do **not** stop just because one report was written, one council file exists, one screenshot exists, or a scoped test-line candidate passes.

## Minimal Evidence

One strong proof is enough for an iteration.

Examples:

- a working local/Web run path
- a screenshot/contact sheet
- smoke test output
- build/export output
- asset ledger
- changed-file summary
- failure artifact with fallback

Preferred proof chain:

```text
candidate picked
-> local implementation
-> screenshot / command / build artifact
-> RecordProgress when useful
-> NextDecision
```

Evidence should be useful, not ceremonial.

## Candidate Verdicts

For scoped autonomous loop candidates, use:

- `CANDIDATE_PASS`
- `CANDIDATE_PARTIAL`
- `CANDIDATE_BLOCKED`
- `CANDIDATE_REJECTED`

Mapping:

| Candidate verdict | Existing loop verdict |
|---|---|
| `CANDIDATE_PASS` for `test_line` / `task` / `milestone` | `GOAL_ACHIEVED` for that scope only; continue upward |
| `CANDIDATE_PARTIAL` | `CONTINUE` or `NEEDS_EVIDENCE` |
| `CANDIDATE_BLOCKED` | `BLOCKED` or `NEEDS_HUMAN_DECISION` depending on blocker type |
| `CANDIDATE_REJECTED` | `NEEDS_PROCESS_FIX` with fallback candidate |

Do not add new project-total completion semantics for candidate verdicts.

## Builder B Style Application

For a game/visual prototype such as a Builder B test line, use this chain:

```text
GoalScope=test_line
-> Capability Scan: game/playtest/browser/visual routes
-> Local Council: generate asset/interface/playtest candidates
-> Bold Candidate Pick: choose the most visible safe slice
-> Outer Codex: implement isolated test-line changes
-> Evidence: Web/local run path, screenshots, asset ledger, build/test report
-> NextDecision: continue until candidate pass/partial/blocker
-> DoneGate: prevent project_total completion claim
```

Builder B should optimize for visible playable progress:

- homepage with real background beats perfect menu architecture
- one moving character beats ten planned character systems
- one battle screen mock with real assets beats a design essay
- one exported Web path beats a theoretical build plan
- one clear screenshot sequence beats a long explanation

Correct final statements are candidate statements such as:

```text
BUILDER_B_CANDIDATE_PASS
BUILDER_B_CANDIDATE_PARTIAL
BUILDER_B_CANDIDATE_BLOCKED
```

Not:

```text
PROJECT COMPLETE
RELEASE READY
DONE
```

## Minimal Report Shape

For bold test mode, keep the report short:

```text
- scope
- built candidate
- run path / command
- evidence paths
- what failed
- next bold target
- project_total not claimed
```

## Maintenance Notes

This protocol is documentation-first. The PowerShell action executor remains conservative by design. The outer Codex agent performs safe local implementation in the declared test scope, then binds evidence back through `RecordProgress` and `NextDecision`.

A future `CandidateGate` action should stay lightweight. It should not become a bureaucracy layer. Its purpose is to pick and move.
