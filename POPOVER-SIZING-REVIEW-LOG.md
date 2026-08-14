# ClaudeBat Popover Sizing Adversarial Review Log

This log preserves the three read-only adversarial review rounds for `POPOVER-SIZING-FIX-PLAN.md`. The plan's status dashboard is authoritative; this file is historical evidence, not an implementation checklist.

No reviewer edited product source. Across 36 passes, no P0 was found.

## Round one

1. SwiftUI layout: unresolved width constraints, Game Over policy, hidden-host behavior, optional coalescing.
2. AppKit lifecycle: stale ABA queue race and required synchronous pre-show sizing.
3. Minimalism: challenged the custom preference bridge and proposed native hosting sizing.
4. Tests: Core-only target could not exercise private AppDelegate behavior.
5. State ordering: usage/recovering/banner bursts could leave stale queued height.
6. Accessibility/display: variable strings, font fallback, backing scale, and multiple displays.
7. Native API: hosting sizing availability plus the need for an explicit NSPopover sink.
8. Safety/privacy: test side effects and separate unscoped cross-account usage-cache leak.
9. Performance: deterministic write counters; no monitor-log instrumentation.
10. Failure modes: malformed sizes, duplicate identity, first-frame, and display transitions.
11. Implementation readiness: exact seams, deletion ordering, and Game Over/banner contract.
12. Red team: vertically flexible weekly balancing cell and competing measurement systems.

Disposition: revise. The plan adopted characterization-first sizing, the weekly-row fix, one measurement owner/sink, explicit Game Over semantics, and side-effect-free tests.

## Round two

1. SwiftUI proof: invalid frame overload, flexible baseline fitting, and missing row observation seam.
2. Native bridge: exact height proposal and setup/open ordering.
3. Coordinator: preflight/sink reentrancy, stale cleanup, close invalidation, normalization.
4. Test seams: public Core APIs, dependency isolation, font/AppKit setup, landmarks.
5. Game Over: bounded fit can clip; unbounded fit can adopt proposal; fixed-after-minimum candidate.
6. Compiler/API: visibility, initializer, actor, and sendability requirements.
7. Scope: characterization only; atomic runtime cutover.
8. Lifecycle: opening/shown/closing/terminal sessions, close fencing, shutdown.
9. Specification: canonical-vs-variable Game Over, supported envelope, numeric thresholds.
10. Performance: preferred-size notification unproven; high-frequency layout hooks unsafe.
11. Dependencies: premature constant deletion, dual owners, observer proof, ownership cycles.
12. Red team: preferred size readable but notification unproven; architecture became empirical gates.

Disposition: characterization GO, product implementation NO-GO. The plan added G1-G4, explicit root policies, invalidation-only live events, session-scoped coordination, and atomic cutover.

## Round three

1. Plan/API: missing hosting sizing option, symbol ordering, stable-signal contradiction, declaration order.
2. G1: three faithful roots, multiple hosts, state-region centering, deterministic fixtures.
3. G2: final-root signal placement, GUI runners, raw callback separation, production timelines, A/B evidence.
4. G3: opaque ingress sessions, prepare failure, deferred scheduling, invalid transitions, normalization, bounded reentrancy.
5. Cutover/DAG: exact inert primitives, serial dependencies, AppDelegate construction, ownership, reviewable commits.
6. Fixtures: clock/timezone, Unicode/numeric bounds, missing branches, real screen/backing-scale evidence.
7. G4: environment dismiss failure, explicit close callback, abort handling, tokens, show timing, termination fence.
8. Safety/toolchain: fully synthetic dependencies, deterministic installation state, GUI teardown, tooling/destructive boundaries.
9. Handoff: authoritative dashboard, artifacts, decisions, separate authorization states.
10. Benchmarking: paired CPU trials, near-zero fallback, exact samples, metadata, machine-readable evidence.
11. Review/release: scoped audits, branch/staging discipline, cutover boundary, soak, additive rollback, approvals.
12. Red team: blocked E0, deterministic F0, candidate-vs-shipping split, I1 production proof, end-to-end DAG.

Disposition: executable characterization downgraded to blocked pending E0/F0. The operational plan now distinguishes planning, characterization, shipping implementation, integration, release, and installed-app authorization.

## Current verdict

- E0/F0 planning: GO.
- Executable characterization: NO-GO until E0 and F0 pass.
- Shipping-path implementation: NO-GO until G1-G4 and D3/D4 pass.
- Merge/release: NO-GO until I1 and R1 pass.
- Installed-app replacement: NO-GO without explicit user approval.
