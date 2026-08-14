# FoveaEngine Agent Contracts

## Current state

**PROPOSED:** no authoritative implementation of dedicated Nemotron/LLM audit, fix, or performance agents was found in the active FoveaCore product path during the initial compilation. The roles below are contracts for future implementation, not claims of an operational autonomous pipeline.

## Roles

| Role | Read scope | Write scope | Required output |
| --- | --- | --- | --- |
| Wiki compiler | Repository, tests, CI, docs | `docs/autowiki/` | Evidence ledger and affected Wiki delta |
| Audit agent | Task-approved code and validation output | Findings only unless fixes are requested | Prioritized findings with file anchors |
| Fix agent | Explicitly approved files | Smallest coherent fix plus tests | Patch, validation, residual risk |
| Performance agent | Explicit experiment scope | Experiment branch/scope only | Baseline, metric, trials, retained result |

## Proposed run envelope

```json
{
  "schema_version": "1.0",
  "run_id": "uuid",
  "project": "FoveaEngine",
  "role": "wiki|audit|fix|performance",
  "task": "string",
  "scope": {
    "read": ["path"],
    "write": ["path"],
    "exclude": ["path"]
  },
  "evidence": [
    {"state": "VALIDATED|IMPLEMENTED_UNVALIDATED|EXPERIMENTAL|PROPOSED|CONFLICT", "path": "path", "claim": "string"}
  ],
  "changes": ["path"],
  "validation": [
    {"command": "string", "status": "passed|failed|skipped|blocked", "result": "string"}
  ],
  "metrics": [
    {"name": "string", "value": 0, "unit": "string", "baseline": 0, "direction": "lower|higher"}
  ],
  "findings": [
    {"priority": "P0|P1|P2|P3", "path": "path", "summary": "string"}
  ]
}
```

## Safety gates

- Preserve dirty worktrees and exclude unrelated files.
- Do not modify runtime code for an audit-only request.
- Require explicit metric, command, extraction, direction, scope, constraints, and budget before performance experiments.
- Do not commit, reset, publish, install dependencies, or call external systems without task authority.
- Never convert an unvalidated result into a readiness claim.

## Acceptance criteria for implementation

- JSON Schema and parser tests exist.
- Each role enforces read/write scopes.
- Every action is logged with evidence and validation state.
- Fixes are reviewable patches with rollback behavior.
- Performance loops retain only metric improvements that preserve constraints.
