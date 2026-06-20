# Autonomous Loop Goal Protocol

This reference explains where a fully automatic loop goal belongs inside `gpt-pro-review-loop` and how to convert divergent candidate thinking into a bounded, evidence-producing Codex loop.

Use this reference when the user explicitly asks for any of these patterns:

- `全自动 loop`
- autonomous loop
- bold candidate first
- candidate-first prototype
- rapid visual/playable/test-line candidate
- keep cycling until a real blocker
- do not wait for perfect assets or final architecture

This protocol does **not** make Codex unbounded. It gives Codex a stronger local execution target while preserving the existing project-total guard, Human Gate, protected-operation pauses, and Done Gate.

## Placement In The Skill Chain

The autonomous loop goal should sit between the local expert council and the action/evidence layer:

```text
Project Understanding
-> Capability Scan
-> Local Expert Council Brainstorm
-> Candidate-First Rule Gate
-> Goal Backlog / Goal Slices
-> NextLocalAction / Action Contract
-> Outer Codex local implementation
-> RecordProgress / Evidence
-> NextDecision
-> DoneGate / FinalClosure
```

Do **not** place it directly inside GPT Pro review, browser automation, or final closure. GPT Pro can review candidate evidence, but it must not become the executor or final judge.

## Why This Position Works

`Local Expert Council` is already the skill's divergent-thinking module: it records brainstorm ideas first and evaluates later. The missing link for fully automatic loops is not more brainstorming. The missing link is a rule gate that turns divergent ideas into one bold but bounded local candidate.

`Action Contract` and `Evidence` are already the proof layer. They are deliberately conservative and should not become an unrestricted business-code executor. The outer Codex agent may implement the selected local candidate in the project, then use `RecordProgress` to bind proof back to gates, blockers, or slices.

`NextDecision` is already the continuation engine. A running loop with `continuation_required=true` must not be treated as a final answer.

## Candidate-First Rule Gate

When this protocol is active, the local council's brainstorm output must be filtered through these labels:

| Label | Meaning | Loop behavior |
|---|---|---|
| `CANDIDATE` | Usable now, not final | May be promoted into `goal_backlog` or a goal slice |
| `PLACEHOLDER` | Temporary substitute | Allowed only with a replacement note and evidence gap |
| `RISK` | Usable but tracked | May proceed if reversible and documented |
| `BLOCKER` | Prevents local execution | Must become a blocker queue item or Human Gate |
| `VERIFIED` | Tested with evidence | Can support Done Gate only when bound to a contract gate |
| `REJECTED` | Tried and failed | Keep reason and next fallback |

The gate selects the **boldest safe candidate** that satisfies all of these conditions:

1. It stays inside the current declared scope, such as `test_line`, `task`, or `milestone`.
2. It does not claim project-total completion.
3. It is reversible or isolated.
4. It can produce visible, runnable, or testable evidence.
5. It can be recorded as a progress artifact.
6. It does not require push, publish, deploy, merge, deletion, reset, credentials, payment, permission changes, or a Human Gate.
7. It has a fallback action if the preferred route fails.

If multiple candidates pass, choose the one with the highest demo/proof value, not the one with the cleanest architecture.

## Module Responsibility Table

| Module | Responsibility for autonomous loop goals |
|---|---|
| `Project Understanding` | Extract the user goal, scope, authority sources, explicit completion gates, and protected boundaries. |
| `Capability Scan` | Recommend available tool/skill/plugin routes; do not install, expose, or authorize them. |
| `Local Expert Council` | Generate many candidate moves without early judgment. |
| `Candidate-First Rule Gate` | Convert ideas into `CANDIDATE`, `PLACEHOLDER`, `RISK`, `BLOCKER`, `VERIFIED`, or `REJECTED`. |
| `Goal Backlog` | Store candidate goals without silently expanding scope. |
| `Goal Slices` | Break the promoted candidate into the smallest evidence-producing slice. |
| `NextLocalAction` | Select the next concrete local action from blocker/slice state. |
| `Action Contract` | Record expected artifacts, safety status, allowed operations, forbidden operations, and evidence target. |
| `Outer Codex local implementation` | Apply safe project changes inside the declared test line or local scope. |
| `RecordProgress` | Bind artifacts, screenshots, commands, reports, or ledger evidence to a gate/blocker/slice. |
| `NextDecision` | Continue, ask for evidence, pivot, pause, or escalate based on evidence and gates. |
| `DoneGate` | Prevent false project-total completion. |

## Autonomous Loop Target Contract

A user can activate this mode with a goal contract like this:

```text
Use autonomous loop goal mode.
Scope: test_line.
Priority: bold candidate first.
Boundary: do not merge, publish, deploy, delete protected assets, or claim project_total complete.
Target: produce the smallest runnable/visible/playable candidate with evidence.
Evidence required: run command, screenshot or output artifact, asset/report ledger, known failures, next minimal action.
Verdict vocabulary: CANDIDATE_PASS, CANDIDATE_PARTIAL, CANDIDATE_BLOCKED, CANDIDATE_REJECTED.
Continue automatically while NextDecision is CONTINUE, NEEDS_EVIDENCE, or NEEDS_PROCESS_FIX.
Pause only for NEEDS_HUMAN_DECISION, BLOCKED, protected operations, missing credentials/login/CAPTCHA/payment, or explicit user stop.
```

This contract should be treated as a scoped goal, not as a project-total completion source.

## Loop Execution Rule

Inside an explicitly authorized autonomous loop:

```text
If NextDecision says CONTINUE:
  execute the selected local action or next candidate slice.

If NextDecision says NEEDS_EVIDENCE:
  collect local proof, RecordProgress, then continue.

If NextDecision says NEEDS_PROCESS_FIX:
  fix the process bottleneck, regenerate the action contract/evidence, then continue.

If NextDecision says GOAL_ACHIEVED for task/milestone/test_line:
  record subgoal achievement and assess the parent/project goal; do not stop as project_total.

If NextDecision says NEEDS_HUMAN_DECISION or BLOCKED:
  pause with exact blocker, attempted actions, missing evidence, and smallest unblock step.
```

The operator must not stop merely because one round produced a report, a local council file, or a subgoal PASS.

## Evidence Requirements

Every autonomous loop iteration must try to produce at least one of these:

- command output
- smoke test result
- screenshot/contact sheet path
- local build/export path
- changed-file summary
- asset ledger
- generated report
- action contract
- evidence JSONL entry
- explicit failure artifact

The preferred proof chain is:

```text
candidate decision
-> local implementation
-> screenshot/command/build artifact
-> RecordProgress with RelatedGate/RelatedBlockerId/RelatedSliceId when possible
-> NextDecision
```

Evidence that is not bound to a gate, blocker, or slice is still useful but weaker.

## Forbidden Shortcuts

Autonomous loop goals must not:

- declare `COMPLETE`, `DONE`, `RELEASE READY`, or `PROJECT COMPLETE` unless project-total Done Gate passes.
- treat GPT Pro approval as direct completion.
- treat screenshots alone as project-total completion.
- bypass Human Gate or explicit authorization.
- convert capability recommendations into assumed callable tools.
- keep sending GPT prompts when `should_send_to_gpt=false`.
- stop after ordinary `CONTINUE`, `NEEDS_EVIDENCE`, or `NEEDS_PROCESS_FIX`.
- spin on the same action without new evidence.

## Recommended Verdicts

For scoped autonomous loop candidates, use only:

- `CANDIDATE_PASS`
- `CANDIDATE_PARTIAL`
- `CANDIDATE_BLOCKED`
- `CANDIDATE_REJECTED`

Map them into the existing local practice verdicts like this:

| Candidate verdict | Existing loop verdict |
|---|---|
| `CANDIDATE_PASS` for `test_line` / `task` / `milestone` | `GOAL_ACHIEVED` for that scope only; continue upward |
| `CANDIDATE_PARTIAL` | `CONTINUE` or `NEEDS_EVIDENCE` |
| `CANDIDATE_BLOCKED` | `BLOCKED` or `NEEDS_HUMAN_DECISION` depending on blocker type |
| `CANDIDATE_REJECTED` | `NEEDS_PROCESS_FIX` with fallback candidate |

Do not add new project-total completion semantics for these candidate verdicts.

## Builder B Style Application

For a game/visual prototype such as a Builder B test line, the autonomous loop target belongs in this chain:

```text
GoalScope=test_line
-> Capability Scan: game/playtest/browser/visual routes
-> Local Council: generate asset/interface/playtest candidates
-> Candidate-First Rule Gate: select bold safe visual slice
-> Goal Backlog: store candidate route and fallback
-> Outer Codex: implement isolated test-line changes
-> Evidence: Web/local run path, screenshots, asset ledger, build/test report
-> NextDecision: continue until candidate pass/partial/blocker
-> DoneGate: prevent project_total completion claim
```

The correct final statement is a candidate verdict such as `BUILDER_B_CANDIDATE_PARTIAL`, not project completion.

## Minimal Report Shape

Autonomous loop reports should include:

```text
- scope
- selected candidate
- rejected candidates
- candidate gate result
- exact local action performed
- changed files or generated artifacts
- run command / link / path
- screenshots or output evidence
- related gate/blocker/slice binding
- failure and fallback
- next narrow target
- non-completion statement for project_total
```

## Maintenance Notes

This protocol is intentionally documentation-first. The PowerShell action executor remains conservative. It records ledger, plan, council, and evidence artifacts; it does not become a general-purpose project-code writer.

Future implementation work can add a dedicated `CandidateGate` action, but it should still write ledger artifacts first and keep business-code edits in the outer Codex execution layer.
