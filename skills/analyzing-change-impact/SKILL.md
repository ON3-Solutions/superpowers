---
name: analyzing-change-impact
description: Use when implementing or reviewing any feature, fix, or refactor in a codebase to discover where the change can propagate, what it can break, whether each effect is acceptable, and what action to take.
---

# Analyzing Change Impact

## When to Use

Use for every implemented feature, fix, or refactor in a codebase. New files and
new behavior still connect to existing routes, composition roots, contracts,
data, configuration, deployment, and user flows. Apply the procedure before
planning to anticipate effects, then repeat it against the actual diff as a
required post-implementation review.

## Procedure

1. Read the approved specification and the actual code. Separate confirmed facts
   from assumptions. The specification explains intent; the code proves state.
2. Locate the source and search in both directions: who calls, imports, reads, or
   persists it; and which contracts, data, events, responses, jobs,
   documentation, or operations it flows into. Continue through intermediate
   layers to observable effects, not just the first reference.
3. Investigate inputs and outputs: validation, compatibility, migration, and
   historical data; also asynchronous execution, observability, permissions,
   configuration, failures, and rollback when present.
4. Judge each discovered effect as beneficial, intended and acceptable,
   harmful, or uncertain. Explain why, then decide whether to change the
   implementation, add compatibility, add or update tests, document the effect,
   or accept it explicitly.
5. Produce the required output below. An inference must state what still needs
   confirmation; never present it as evidence.
6. Before finishing, define the test or verification that proves each decision.

## Required Output

### Impact Map

| Impact | Evidence file:line | Assessment | Decision or required change | Test |
| --- | --- | --- | --- | --- |

Provide one complete row per impact. The assessment must say whether the effect
is beneficial, intended and acceptable, harmful, or uncertain. The decision
must state what to do about it; discovery alone is not completion.

### Pending Inferences

| Inference | Missing evidence | How to confirm |
| --- | --- | --- |

Record only what was not confirmed in the code; a hypothesis is not evidence.

## Post-Diff Reconciliation

After every implementation, review the actual diff even when all files are new.
Compare it with the initial map and repeat searches for added and removed names,
types, events, registrations, routes, imports, configuration, and derived paths.
For each changed file absent from the map, explain the relationship or add the
impact. For each map row absent from the diff, mark it not applicable with
evidence, or implement the change. Reassess whether each observed effect is
acceptable, make the resulting decision, run the tests defined in the map, and
record gaps, residual risks, and compatibility decisions.

### Reconciliation Table

| Impact or changed file | Status | Evidence | Assessment | Decision or test |
| --- | --- | --- | --- | --- |

## Handoffs

After brainstorming approves the specification, hand the map to
`writing-plans`. Before review, reconcile it with the diff and hand it to the
reviewer. Before completion, verification compares the map, diff, searches, and
tests.
