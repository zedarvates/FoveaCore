# FoveaEngine Research Log

## Experiment gate

An autonomous experiment starts only after goal, numeric metric, measurement command, extraction rule, direction, scope, constraints, budget, and baseline are recorded. Without them, research remains a non-destructive proposal.

## Entry template

```markdown
## R-XXXX — Title

- State: PROPOSED | RUNNING | RETAINED | REJECTED | BLOCKED
- Goal:
- Hypothesis:
- Scope / exclusions:
- Metric / unit / direction:
- Measurement command and extraction:
- Constraints and budget:
- Baseline:
- Change:
- Result:
- Decision:
- Evidence paths:
```

## R-0001 — Autowiki evidence hierarchy

- **State:** RETAINED
- **Goal:** reduce misleading or contradictory FoveaEngine documentation claims.
- **Hypothesis:** preferring implementation and current validation over historical plans will reveal actionable conflicts.
- **Scope:** documentation and source inspection only; no runtime edits.
- **Metric:** unresolved authoritative documentation conflicts; lower is better.
- **Baseline:** not previously tracked, so no autonomous optimization loop was started.
- **Execute:** inspected project configuration, public node, manager/subsystems, `.fovea` readers/writers, CI, tests, feature status, architecture, roadmap, and format plans.
- **Evaluate:** identified two P1 conflicts: `.fovea` v2 layout and stale public API signatures.
- **Iterate:** froze the current `.fovea` v2 contract, reclassified the incompatible compact format as a v3 proposal, and introduced evidence states, a source precedence policy, a canonical Wiki index, and roadmap exit criteria.
- **Decision:** retain the documentation structure; establish a measured baseline only after a conflict checker or curated registry exists.

## Proposed benchmark families

- `.fovea` compression: bytes/splat, encode/decode time, peak RAM/VRAM, PSNR, SSIM.
- Rendering: average/P95/P99 frame time, visible splats, sort time, cull time, draw submissions.
- VR: missed frames, motion-to-photon latency, thermal stability, gaze fallback behavior.
- Reconstruction: end-to-end duration, failure rate, output completeness, geometric and visual quality.
