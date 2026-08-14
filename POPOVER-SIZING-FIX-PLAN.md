# ClaudeBat Popover Sizing Fix Plan

Status: Revised after three adversarial rounds (36 reviews), then executed locally. F0, local G1-G4, I0, and local I1 are green. The local test build passed hands-on review. Packaging `v1.0.17` exposed an Xcode 15.4 compatibility failure before any GitHub Release was created; the tag remains immutable, and a focused macOS 14 compatibility correction is proceeding as `v1.0.18`. The incomplete E0-R runtime/display matrix remains recorded as accepted release risk, not passing evidence.

## Status dashboard

This table is the sole authoritative status source. A skipped test or missing runner never counts as passed.

| Stage | Status | Depends on | Required evidence | Owner | Approver | Failure action |
|---|---|---|---|---|---|---|
| E0 Local environment readiness | **passed** | — | `artifacts/popover-sizing/E0-environment.md` | Implementer | Maintainer | Repair local toolchain/GUI runner |
| E0-R Runtime/display matrix | **blocked** | E0 | appended E0 runner evidence | Maintainer | Maintainer | Acquire/assign missing GUI runners |
| F0 Deterministic fixtures | **passed** | E0 | `artifacts/popover-sizing/F0-fixture-contract.md` | Implementer | Reviewer | Fix clocks, seams, and isolation |
| G1 Root fitting | **passed locally** | F0 | `artifacts/popover-sizing/G1-root-fit.json` + summary | Implementer | Maintainer | Revise root policy |
| G2 Live invalidation signal | **passed locally; E0-R pending** | G1 | `artifacts/popover-sizing/G2-signal-results.json` + OS/CPU matrix | Implementer | Maintainer | Reject candidate signal |
| G3 Coordinator | **passed** | G1 measurement contract | `artifacts/popover-sizing/G3-coordinator-summary.md` | Implementer | Reviewer | Revise API/state machine |
| G4 Candidate lifecycle | **passed locally** | G1 + G2 + G3 | `artifacts/popover-sizing/G4-lifecycle-ledger.md` | Implementer | Maintainer | Do not authorize cutover |
| D3/D4 Scope decisions | **passed locally; display evidence pending** | F0 + G1 + G4 | `artifacts/popover-sizing/D3-model-identity.md`, `D4-overflow-decision.md` | Maintainer | Maintainer | Expand or narrow patch explicitly |
| I0 Shipping-path implementation | **implemented locally** | G1-G4 + D3/D4 passed | `artifacts/popover-sizing/I0-cutover-manifest.md` | Implementer | Maintainer | Fix or revert I0 |
| I1 Real-app integration | **passed locally; E0-R/soak pending** | I0 | `artifacts/popover-sizing/I1-local-verification.md` | Implementer | Maintainer | Fix or revert I0 |
| T1 Local test installation | **passed; running** | local I1 + user approval | `artifacts/popover-sizing/T1-local-test-install.md` | Implementer | User | Restore retained backup |
| R1 Merge/release | **v1.0.17 packaging failed; v1.0.18 correction authorized** | I1 + maintainer risk acceptance | final-SHA build/test/source-audit report | Maintainer | User | Stop on failed checks |
| R2 Released-app installation | **pending R1** | R1 | explicit user approval | User | User | Keep verified test build installed |

Local E0 is green with per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`: Xcode 26.6, 157 regular tests, all opt-in G1-G4 suites, Debug and Release builds, and one live 2x AppKit display pass. The machine-wide `xcode-select` remains unchanged by design.

Current next action: prove the final-root geometry observer on the local GUI harness and on the GitHub macOS 14 build gate, then publish the corrected release as a new immutable `v1.0.18` tag. Missing macOS 15, Intel, physical 1x, and long-soak evidence remain unresolved follow-up work and must not be represented as passed.

## Decision register

| ID | Decision | Candidates | Status | Evidence |
|---|---|---|---|---|
| D1 | Synchronous measurement | forced layout + preferred value; finite `sizeThatFits` | selected: native tracking off + finite `sizeThatFits` | `artifacts/popover-sizing/G4-lifecycle-ledger.md` |
| D2 | Live invalidation signal | native callback; final-root geometry/preference; other proven signal | selected locally: final-root background `GeometryReader` size observer | `artifacts/popover-sizing/G2-signal-results.json` |
| D3 | Duplicate model identity | retain; stable API/index identity | selected: API model ID + deterministic fallback | `artifacts/popover-sizing/D3-model-identity.md` |
| D4 | Overflow handling | defer beyond envelope; include clamp/scroll | defer beyond envelope; E0-R small-display evidence pending | `artifacts/popover-sizing/D4-overflow-decision.md` |
| D5 | Supported runtime/hardware matrix | macOS/architecture/display tuples | local 2x arm64 recorded; E0-R pending | `artifacts/popover-sizing/E0-environment.md` |

Characterization may add deterministic fixtures, a standalone GUI harness, tests, and exact but **unwired** production-support primitives. It may not connect a new signal/coordinator to the shipping AppDelegate or change the active popover sizing path before I0 authorization.

## Problem

ClaudeBat can show different popover heights and unexpectedly large vertical gaps after account-specific usage content changes. Some variation is legitimate because accounts can return different model-limit rows, Extra Usage state, cached-data banners, or terminal states. The defect is that a height allocated for one content shape can be measured, stored, and reused as though it were the next shape's intrinsic height.

The current feedback path is:

1. `UsagePopoverView` stores `measuredUsageHeight` in SwiftUI `@State`.
2. A background `GeometryReader` measures the size already allocated by the hosting popover.
3. `AppDelegate` copies that value into `lastReportedPopoverHeight`.
4. Reopening the popover explicitly reapplies the copied height.
5. If the next account needs less content, the old height can survive; SwiftUI receives the stale proposal and flexible descendants can absorb the surplus.
6. `NormalUsageView` contains a concrete amplifier: the weekly row's balancing `Color.clear.frame(width: 50)` has no vertical constraint. Under an oversized proposal, that `HStack` can grow vertically and make the weekly section look as though its declared gaps changed.

Relevant code:

- `ClaudeBat/Views/UsagePopoverView.swift:15-38, 92-136`
- `ClaudeBatApp/ClaudeBatApp.swift:32-36, 101-123, 193-195`
- `ClaudeBat/Views/PopoverStates/NormalUsageView.swift:80-133`
- `ClaudeBat/Views/PopoverStates/NormalUsageView.swift:56-78`

## Goals

- Make the current rendered content the sole persistent source of truth for popover height.
- Resize correctly when account-specific content grows or shrinks.
- Preserve a 392-point baseline/minimum for loading, error, reconnect, offline, recovering, and Game Over screens while allowing unavoidable text growth.
- Preserve the prior protections against resize feedback loops and main-thread spin.
- Eliminate duplicated remembered-height state and duplicated popover metrics.
- Avoid exact-height formulas that repeat the structure of SwiftUI views.
- Present the correct size on the first visible frame after hidden content changes.

## Non-goals

- Redesigning the visual hierarchy or spacing system.
- Making every screen intrinsically sized; terminal/loading screens rely on flexible spacers for intentional vertical centering.
- Changing API decoding, authentication, polling, or account selection.
- Adding account identifiers or persisting per-account window sizes.
- Solving screen-height overflow/scrolling in the first sizing patch; track it separately unless a characterization fixture proves it blocks this fix.
- Adding Dynamic Type support, localization, Reduce Motion, or contrast changes. Those are separate accessibility tasks; this fix must still avoid clipping current supported strings.
- Fixing the newly identified unscoped cross-account usage cache. That is a separate privacy bug and must be tracked before claiming end-to-end multi-account isolation.

## Layout invariants

- Popover width remains 320 points.
- Normal usage content uses its natural vertical size.
- Declared 16- and 20-point gaps remain those sizes; spare host height must not inflate them.
- Baseline states remain visually centered at a shared 392-point outer minimum.
- The canonical short, no-banner, no-Extra-Usage Game Over fixture is 392 points tall; 392 is a minimum for variable variants.
- A cached banner lives inside the Game Over chrome. It consumes flexible Game Over space first; the outer root grows beyond 392 only when the supported fixed content would otherwise clip. There is no guessed banner-total constant.
- A compact -> expanded -> compact content transition returns to the original compact height within a small layout tolerance.
- Closing and reopening does not change the height for unchanged content.
- Size updates do not create a synchronous SwiftUI/AppKit feedback loop.
- The width constraint is established at 320 points before any ideal-height query.
- `NSPopover.contentSize` is the only AppKit sizing sink; measured values are never written back into the hosting controller.

## Proposed design

### 1. Characterize the root policies first

After E0/F0 pass, add exact but unwired production-support primitives. This relaxes the earlier “test-only” wording without changing the active app path:

- `CBPopoverMetrics`;
- `NormalPopoverRoot`;
- `HeaderBaselinePopoverRoot` for error/reconnect/offline and Game Over;
- `StandaloneBaselinePopoverRoot` for loading/recovering, preserving their base background and lack of header/footer;
- behavior-preserving `WeeklyUsageRow` extraction with semantic anchors.

Gate tests instantiate these exact types with the actual state views and current padding. Test-local replicas do not authorize production use. The current defect may remain recorded as a known issue until the runtime cutover.

The candidate allocation-independent modifiers are:

```swift
normalChrome
    .padding(CBSpacing.popupPadding)
    .frame(width: CBPopoverMetrics.width)
    .fixedSize(horizontal: false, vertical: true)

headerOrStandaloneBaselineRoot
    .padding(CBSpacing.popupPadding)
    .frame(width: CBPopoverMetrics.width)
    .frame(minHeight: CBPopoverMetrics.baselineHeight)
    .fixedSize(horizontal: false, vertical: true)
```

The second expression intentionally applies `.fixedSize` after the minimum-height frame. The previous `.frame(width: 320, minHeight: 392)` example was invalid Swift and is removed. Each root must preserve its production chrome rather than sharing one generic baseline composition.

For each characterization host, set `host.sizingOptions = [.preferredContentSize]` before loading `host.view`, establish the outer width at 320, then force layout. A zero/non-finite preferred size is a harness failure. Characterize both:

- forced `host.view.layoutSubtreeIfNeeded()` followed by reading `host.preferredContentSize`; and
- `host.sizeThatFits(in:)` with exact proposals of `(320, 392)`, `(320, 1000)`, and `(320, 10_000)`.

G1 found both values equivalent for the allocation-independent roots. G4 then found that leaving `.preferredContentSize` tracking enabled lets AppKit resize an attached popover outside the coordinator. The production decision is therefore `host.sizingOptions = []` plus a finite `(320, 10_000)` `sizeThatFits(in:)` query. The preferred-value arm remains characterization evidence only.

Create one host per initial allocation of 392, 472, 1000, and 10,000 and compare them pairwise. Separately, reuse one retained host while changing allocation low -> high -> low and high -> low -> high. Preferred-value and fitting results must agree within 1 point after normalization. Centering is measured inside the remaining state region, not against the header-weighted whole root.

Gate 1 passes only if every exact root returns a finite allocation-independent width-320 size; canonical baseline content returns 392; taller supported fixed content grows; compact -> expanded -> compact returns within 1 point; and post-cutover reruns against the actual `UsagePopoverView` match the primitive evidence. Select one synchronous `measureCurrentSize()` only from this evidence. Never use `CGFloat.greatestFiniteMagnitude` with a flexible root.

### 2. Prove a live invalidation signal

Round two established that `NSHostingController.preferredContentSize` is a useful readable value, but not a proven notification API. On the current runtime, override `didSet`, KVO, and parent `preferredContentSizeDidChange(for:)` probes produced conflicting or zero callbacks. Therefore the plan no longer commits to a native preferred-size observer.

In a real shown `NSPopover`, characterize exactly one live signal for model rows, banner, Extra Usage, Game Over, and baseline transitions. Candidate signals include native callbacks, hosting-view intrinsic invalidation, `.onGeometryChange`, or a stateless `PreferenceKey`. A SwiftUI signal must observe the final root after the fixed/minimum policy; placing it outside a host-sized wrapper can recreate the original allocation measurement. It may use `CGSize` internally for Equatable change detection, but the action discards that value and forwards only “remeasure current content.”

Do not use `viewDidLayout`, `viewWillLayout`, or `updateViewConstraints` unless instrumentation proves bounded callback cost under the 0.08-second loading timeline. Count raw callbacks separately: hidden or stable hosts may produce them, but they must cause zero inactive/stable invalidations, enqueues, drains, measurements, and writes after settling.

Gate 2 uses one release-built, side-effect-free GUI harness with an ordered-front anchor window, production popover behavior/animation settings, retained host, identical mutation script, and machine-readable counters. Failure to obtain `popoverDidShow` within two seconds is a failed/unresolved environment, never a pass. Headless CI cannot pass Gate 2.

Required E0 runner matrix: latest patched macOS 14, macOS 15, and current supported macOS on Apple Silicon; plus Intel on the oldest supported runtime while universal Intel releases remain supported. Actual 1x/2x display coverage is assigned separately. Gate 2 passes only when one candidate catches every genuine height change within 250 ms/two run-loop turns across 100 cycles, misses no transitions, applies no captured stale height, produces no sustained feedback, and satisfies the canonical benchmark protocol. Until then, live observation remains a characterization question.

### 3. Make root composition explicit

Split `popupChrome(fitsContent:)` into exact roots. Header-baseline composition for error/reconnect/offline and Game Over is:

```text
outer 320-point root, minimum 392
└── 20-point padding
    ├── header
    ├── 20-point declared gap
    ├── optional cached banner + 12-point gap
    ├── centered state region
    ├── 12-point gap
    └── freshness footer when present
```

Standalone loading/recovering composition preserves the current base background, corner radius, and lack of header/banner/freshness. Its state region receives the full padded minimum-height area. Neither baseline root may add or remove production chrome merely to share an abstraction.

The state region receives remaining flexible slack. Its region midpoint—not the whole header-weighted root—is the centering oracle. If supported fixed children exceed 392, the allocation-independent root grows. The canonical short/no-banner/no-Extra Game Over fixture is exactly 392; variable variants are at least 392. No branch receives a guessed banner-total height.

Extract the weekly `HStack` behavior-preservingly before Gate 1 so exact primitives and tests share an internal `WeeklyUsageRow` with semantic anchors. The active layout remains unchanged until I0. During I0, replace `Color.clear.frame(width: 50)` with a balancing element that cannot expand vertically.

### 4. Use an explicit presentation coordinator

Add an **unwired** `@MainActor public final class PopoverSizeCoordinator` to `ClaudeBatCore` before Gate 3 so its real type can be tested. Public initializer/method/signature types are visible to the executable target. The public initializer installs a guaranteed deferred MainActor scheduler; an internal `@testable` initializer accepts a manual scheduler. Inline scheduling is forbidden.

Minimum public API:

```swift
@MainActor
public final class PopoverSizeCoordinator {
    public struct Session: Hashable, Sendable {
        fileprivate let rawValue: UInt64
    }

    public typealias Measurer = @MainActor @Sendable () -> CGSize?
    public typealias CurrentSizeReader = @MainActor @Sendable () -> CGSize?
    public typealias SizeSink = @MainActor @Sendable (CGSize) -> Bool

    public func beginPresentation() -> Session?
    public func prepareForShow(in session: Session) -> Bool
    public func markShown(in session: Session)
    public func contentMayHaveChanged(in session: Session)
    public func endPresentation(_ session: Session)
    public func shutdown()
}
```

Every session-scoped ingress takes the opaque token; delegate or signal callbacks from an old presentation cannot be relabeled as current.

The lifecycle is:

```text
inactive -> opening(session) -> shown(session) -> closing/inactive
                                      \-> terminal
```

Required behavior:

- `beginPresentation()` supersedes any nonterminal session and returns a new opening token;
- `prepareForShow(in:)` suppresses signals, measures, clears signals emitted during measurement, synchronously applies the normalized size, and returns `false` on invalid measurement or sink failure so presentation aborts;
- `markShown(in:)` enables invalidations only for the matching successfully prepared opening;
- `endPresentation(_:)` invalidates matching work; stale/repeated ends are no-ops;
- `shutdown()` is absorbing and runs before view-model shutdown;
- `contentMayHaveChanged(in:)` is accepted only for the matching shown session, coalesces a signal, then remeasures current content at drain time.

Every pending item and scheduled closure carries immutable session and task tokens. A stale closure returns without clearing newer state. A drain removes only its own pending/scheduled slot before invoking the sink and performs no coordinator-state cleanup after the sink returns; a reentrant signal therefore schedules a new bounded turn instead of being lost.

Normalize pre-show/live heights to the nearest 0.5 point using `(height * 2).rounded() / 2`; validate finite/positive both before and after normalization so tiny or overflowing values cannot become zero/infinite. Normalize current and target height before comparison. Compare actual current width independently and correct 319 -> 320 even if height matches. Apply only primary usage `NSPopover.contentSize`; never assign the measured result to the usage host's `preferredContentSize`.

Stable-shape zero-work is a Gate 2 signal-source requirement. Gate 3 instead requires 10,000 same-burst invalidations to coalesce to exactly one drain/measurement and zero writes when size is unchanged. One-shot measurer/sink reentrancy may take at most two drain turns; an always-reentrant adversary is outside the proven signal contract and must trip a debug/test cycle guard rather than claim generic convergence.

Gate 3 passes when stale external calls, invalid prepare, reentrant measurer/sink, out-of-order tasks, A -> B -> A bursts, close/reopen, malformed normalization, and shutdown match the transition table. Terminal calls are no-op/false/nil; wrong-session calls never alter current state.

### 5. Make presentation ordering contractual

Replace the SwiftUI environment `dismiss()` path with an explicit `onCloseRequested` callback that weakly reaches AppDelegate and calls the owned primary popover's `performClose(nil)`. A directly hosted root's `dismiss()` did not close `NSPopover` in the round-three probe.

AppDelegate stores `activeSession` and `closingSession`; delegate notifications contain only the popover and cannot recover session provenance. The owned open path performs, without an `await` or run-loop yield:

1. `viewModel.onPopoverOpen()`;
2. obtain/store `session = coordinator.beginPresentation()`;
3. guard `coordinator.prepareForShow(in: session)` succeeds;
4. `popover.show(...)`;
5. guard `popover.isShown` (AppKit may silently refuse an invisible anchor);
6. call `coordinator.markShown(in: session)` immediately before returning to the run loop.

On invalid measurement, sink failure, or show failure: end that session, clear active storage, and balance exactly one `viewModel.onPopoverClose()` without marking shown. Remove duplicate view-model open mutation from `popoverWillShow`; will/did-show callbacks are observation/assertion points only. `popoverDidShow` is too late to define first-frame correctness.

`popoverWillClose` atomically moves active -> closing and ends that exact token before an old drain can write. `popoverDidClose` clears only the matching closing token and performs exactly one view-model close. Header, status-toggle, outside-click, and forced-close paths must all produce the same ledger.

`applicationWillTerminate` sets an `isTerminating` fence, shuts down the coordinator, retires/ends active presentation bookkeeping, then shuts down the view model. Late close callbacks cannot restart polling.

G4 is candidate-lifecycle proof, not final product equivalence. It passes only when hidden A -> B opens at B on the first frame; pre-show, will-show, did-show, show-return, and next-turn heights agree within 0.5; there are zero corrective writes; old sessions cannot affect reopened state; abort paths balance; 100 rapid cycles retain one host; and teardown releases harness objects. I1 repeats the ledger against actual AppDelegate/status-item wiring after I0.

### 6. Add inert metrics without breaking old consumers

Add `ClaudeBat/Theme/CBPopoverMetrics.swift`:

```swift
import CoreGraphics

public enum CBPopoverMetrics {
    public static let width: CGFloat = 320
    public static let baselineHeight: CGFloat = 392
}
```

Add this behavior-neutral type before G1 so exact primitives compile. Keep legacy `AppDelegate.PopoverLayout` and all `CBSpacing.popup*` members through I0 and the first stable release even after they reach zero consumers; this preserves a simple cutover revert. Keep `popupPadding`. Legacy removal is a separate cleanup/release decision, not part of the runtime fix.

### 7. Preserve runtime atomicity with reviewable commits

Preparatory commits are allowed to compile inert code without changing runtime ownership:

1. deterministic fixtures and disposable AppKit harness;
2. metrics, exact unwired roots/signal/coordinator, and behavior-preserving weekly-row extraction;
3. Gates G1-G4 tests/evidence against those exact types.

After implementation authorization, one smaller I0 behavior commit must land together:

- split normal and baseline roots with the proven modifier order;
- fix/extract the weekly row;
- wire the one proven live invalidation signal;
- wire synchronous pre-show reconciliation and the coordinator lifecycle;
- remove `GeometryReader`, `measuredUsageHeight`, `preferredHeight`, `recordMeasuredHeight`, `onPreferredHeightChange`, `lastReportedPopoverHeight`, fallbacks, and host preferred-size feedback writes;
- retain exactly one measurement owner and one `NSPopover.contentSize` sink.

No intermediate runtime state may contain both bridges. AppDelegate strongly owns popover, typed host, and coordinator; NSPopover also owns its content controller. The invariant is no reverse strong edge: root/signal callbacks weakly reference AppDelegate/coordinator; coordinator measure/read/sink closures weakly reference host/popover; scheduled work is invalidated on shutdown.

Construction order: create/configure popover; create root close/signal callbacks that tolerate an unset coordinator; create/store typed host without loading its view; create/store coordinator with weak host/popover closures; enable the proven sizing option; assign `contentViewController` last; then install lifecycle routing.

Rerun the entire matrix against actual `UsagePopoverView` and AppDelegate at I1. A harness result alone does not prove production wiring. Keep the I0 commit boundary intact for review/revert; legacy cleanup occurs only after a stable-release soak.

### 8. Make F0 and scope escalation explicit

- F0 publishes literal fixture values, fixed dates/reference time, explicit timezone strategy, exact Extra Usage numbers, ASCII supported labels plus Unicode robustness probes, every current branch, deterministic Claude-installed state, and expected relational contracts. Do not freeze guessed non-baseline pixel heights before G1 records them.
- Timezone variants run in isolated processes with `TZ` set before `ClaudeBatCore` loads unless an approved clock/formatter seam is added. Dates remain safely away from minute/day boundaries; exact countdown text is not asserted without clock control.
- Detached content never proves a “600-point screen” budget or 1x/2x behavior. Real-popover runners record `visibleFrame`, anchor position, shown window/content bounds, backing scale, arrow/non-content clearance, and AppKit repositioning. Missing hardware is blocked evidence.
- If any supported-envelope fixture clips or extends outside the real available content budget, D4 chooses clamp/scroll as blocking work. Beyond-envelope Unicode/long/unbounded model-list cases are robustness probes, not current guarantees.
- Duplicate model labels are a named characterization gate. If they reproduce stale rows, stable API/indexed identity enters the atomic patch; otherwise retain the passing regression and defer the cleanup.
- Track the unscoped `UsageCache` separately as a privacy bug. The sizing patch must not claim cross-account data isolation.

## Implementation sequence

1. E0: record full-Xcode toolchain and assign GUI macOS/architecture/1x/2x runners. Current environment remains blocked.
2. F0: publish/approve literal fixtures, clock/timezone strategy, deterministic install/screen-state seams, side-effect budgets, and real-screen evidence method.
3. Add independently compiling inert primitives/metrics/harness; leave the active sizing path untouched.
4. G1: characterize exact roots and select D1 measurement.
5. G2: characterize candidate signals on assigned GUI runners and select D2.
6. G3: pass public coordinator API/state-machine tests using the G1 contract.
7. G4: compose G1-G3 in the disposable real-popover harness and pass the candidate lifecycle ledger.
8. Resolve D3 duplicate identity and D4 overflow. Only then authorize I0.
9. I0: atomically switch the live sizing owner and remove the old bridge in one behavior commit.
10. I1: rerun root, signal, lifecycle, source-audit, ownership, and benchmark evidence against actual AppDelegate/UsagePopoverView.
11. R1: run final-SHA tests/builds/soak and obtain explicit push/tag/release approval.
12. R2: obtain separate explicit approval before replacing `/Applications/ClaudeBat.app`.

Implementation dependency graph:

```text
E0 -> F0 -> exact inert roots/metrics -> G1
                                      ├-> G2
                                      └-> G3 (using G1 measurement contract)
G1 + G2 + G3 -> G4 candidate lifecycle
G1-G4 + D3/D4 -> I0 implementation authorization
I0 atomic cutover -> I1 real-app integration -> R1 merge/release -> R2 installed app
```

If a gate fails, revise that seam in characterization. Do not compensate by adding a second measurement owner.

## Regression tests

### Test boundaries

The existing `ClaudeBatTests` target imports only `ClaudeBatCore`; private `AppDelegate` behavior in the executable cannot be covered there. Use four layers:

1. `PopoverIntrinsicLayoutTests` in Core: real `UsagePopoverView` with one reused, width-constrained host.
2. `PopoverSizeCoordinatorTests` in Core: injected manual scheduler/measurer/current-size reader/sink; no WindowServer.
3. A targeted AppKit characterization harness: real shown `NSPopover`, retained host, candidate live signals, first-frame lifecycle, and counters. If kept as permanent CI coverage, extract only the needed bridge into an importable app-support target rather than testing private `AppDelegate` indirectly.
4. Manual app smoke test: actual status-item anchor, show/close spam, ownership, first-frame sizing, and CPU/signpost observation.

All Core layout tests use `@Suite(.serialized)` and `@MainActor`, bootstrap `NSApplication.shared` if needed, call `FontRegistration.registerFonts()`, and assert `NSFont(name: "PressStart2P-Regular", size: 10) != nil`.

One `makeLayoutViewModel()` factory spells every initializer argument explicitly, uses `startImmediately: false`, synthetic `AppBuildInfo`/token/data, and in-memory fakes only. Expected constructor budgets: token snapshot read once; cache read once; recovery-state read once; all writes zero; API/budget/OAuth/CLI/reachability zero for pure layout. Lifecycle monitor events go only to an expected in-memory fake. No default concrete service, `UserDefaults.standard`, `MonitorService`, real credential material, unified/file log, or process/global environment mutation is allowed.

Inject Claude-installed state instead of letting `NoAuthView` inspect `/usr/local/bin`, `/opt/homebrew/bin`, or real `PATH`. Place any private recovery/screen-state fixture source in test/harness support or an inert injected seam; do not alter release behavior before I0. Mutate the same view model/host for retained-state coverage.

Real-popover tests run in one dedicated serialized GUI process. Teardown order: coordinator shutdown; balanced VM close/shutdown; close popover; order out/close anchor; detach host/root; cancel tokens; release strong references; drain at most two run-loop turns; assert weak deallocation and zero pending work. Never terminate/activate the installed app, add global monitors, use pasteboard/openURL, call real API/Keychain/CLI, or run packaging/signing/install commands.

### Reused-host layout matrix

Use two protocols: one host per initial allocation (392/472/1000/10,000) for pairwise allocation independence, plus one retained host for every mutation round trip and low/high allocation-order sequence. Blocking matrix:

1. zero model rows -> two rows -> zero rows;
2. Extra Usage off -> on -> off;
3. cached banner absent -> longest current reason -> absent;
4. normal -> canonical Game Over -> normal;
5. every baseline branch: loading; generic/auth error; setup/reconnect × installed/not installed; offline variants; every recovery message; session/weekly/both-depleted Game Over;
6. compact/expanded mutation while detached, followed by the selected production `measureCurrentSize()` preflight;
7. normal -> recovering -> different-account-shaped normal content in one main-queue burst through the test state source;
8. duplicate display names and row reordering as the named identity gate.

After the blocking matrix is green, run the full supported envelope from section 8, including every banner reason, 0-4 modern/legacy rows, long supported strings, Extra Usage combinations, and 1x/2x scale normalization.

Required assertions:

- width equals 320 points;
- intrinsic normal fixtures that add natural content grow by more than 1 point; baseline variants may consume slack without growing;
- round-trip error is at most 1 point after half-point normalization;
- the same fixture fitted from 392, 472, 1000, and 10,000 initial allocations differs by at most 1 point;
- after `WeeklyUsageRow` is extracted, its height and every named 16/20-point semantic gap remain within 0.5 point across initial allocations;
- each baseline state-region midpoint differs from its assigned remaining-region midpoint by at most 1 point;
- every required semantic landmark remains inside root bounds;
- canonical short/no-banner/no-Extra Game Over equals 392 points; all variable Game Over fixtures are at least 392;
- a short fitting banner remains at 392 by consuming flexible slack; a supported overflowing variant grows only as recorded by characterization;
- duplicate/reordered labels either pass or trigger the explicit stable-identity cutover gate.

Do not inspect private `Spacer` coordinates or use screenshots as the primary regression. Use named semantic anchors/accessibility frames on extracted components. Supplement with one manual visual comparison.

### Coordinator ordering matrix

Use a manual scheduler and reentrant fake measurer/sink:

1. A -> B -> A invalidations before drain remeasure current A and apply at most once;
2. Gate 2 produces zero invalidations for stable shape; separately, 10,000 same-burst invalidations coalesce to exactly one drain/measurement and zero writes when measured size is unchanged;
3. 10,000 signals in one changing burst keep at most one pending item, schedule at most one drain, and apply at most one current measurement;
4. measurer and sink each perform one-shot reentrant invalidation; at most two drain turns occur and final current size wins; an always-reentrant fake trips the test cycle guard;
5. execute stale/current scheduled tasks out of FIFO order; stale tasks neither write nor clear current-session state;
6. old task pending -> close -> reopen/preflight -> new signal; only the new session may apply;
7. shutdown with a pending task, then send a late signal; zero subsequent writes;
8. reject NaN, infinity, zero, and negative measurements; do not invent an arbitrary maximum while overflow is deferred;
9. verify `(height * 2).rounded() / 2` boundary tables at 1x/2x and correct width 319 -> 320 even when height matches.
10. exercise stale external session calls, prepare failure, repeated end/begin, and all calls after terminal.

Count live signals, enqueues, scheduled drains, drain executions, measurements, and sink writes. `TimelineView` may legitimately re-evaluate, but a stable shape must schedule zero coordinator work after settling.

### Existing CPU-loop protection

Exercise the former reset-boundary/main-thread-spin path. Use debug-only in-memory counters or signposts; never emit each measurement to `monitor.jsonl`.

Performance gates on target hardware:

- stable displayed content: zero invalidations/enqueues/drains/measurements/writes after settling; raw callbacks are recorded separately;
- hidden popover: zero coordinator work during a 10-second window after a 2-second grace period; harmless raw callbacks are allowed and measured;
- one burst: at most one scheduled drain and one write;
- sizing bridge CPU: process user+system CPU divided by wall time, normalized to one core, using the canonical paired protocol below;
- supported-heavy preflight: each batch p95 at most 16.7 ms and pooled p99.9 at most 50 ms; raw max is diagnostic;
- one host/controller allocation across repeated close/reopen cycles, with constant retained object counts.

Canonical benchmark protocol: one Release fixture binary with bridge off/on; identical allocation-free counters; 12 fresh-process paired trials per scenario in seeded balanced AB/BA order; 10-second warm-up plus 60-second sample; AC power, Low Power Mode off, no debugger, nominal thermal state, and predeclared environmental invalidation rules. If paired baseline median is at least 0.25% of one core, the one-sided 95% bootstrap upper bound of relative overhead must be at most 5%; below that baseline, the absolute-overhead upper bound must be at most 0.10 percentage points. Preflight uses 100 warm-ups plus three fresh-process batches of 1,000 `ContinuousClock` samples. Live latency uses 1,000 isolated changes and must meet p95 33.4 ms/p99.9 100 ms. Every required OS/hardware tuple passes independently.

Emit raw JSONL and deterministic summary JSON with protocol version, SHA, seed, environment, counters, CPU/wall samples, timings, quantiles, confidence bounds, thresholds, pass/fail, and checksums. Missing metadata or selective reruns are failures. Export only after sampling; never use `monitor.jsonl`.

## Verification

1. Run `swift test` with a full Xcode developer directory that provides the Swift `Testing` module. Prefer per-command `DEVELOPER_DIR`; do not change global `xcode-select`. The selected environment currently lacks that module, so this is an explicit prerequisite, not a silently runnable check.
2. Run `swift build`.
3. Synthetic tests/builds may coexist with the installed app because their external-call counts are zero. Before any real app launch, perform a read-only process/bundle check and abort with instructions if installed ClaudeBat is running; never terminate it automatically.
4. Verify normal usage with zero, one, multiple, and duplicate-name model rows.
5. Verify Extra Usage, every cached banner, long current strings, and Game Over combinations.
6. Verify unchanged close/reopen plus hidden compact <-> expanded changes. Pre-show, `popoverDidShow`, and next-run-loop sizes must agree within 0.5 point, with zero post-show corrective writes.
7. Repeatedly toggle while state changes and a prior-session task is pending; verify no late write and constant host/controller counts.
8. Exercise actual controllable Timeline ticks for every timeline-bearing branch and record signal/enqueue/drain/write counters.
9. Run the defined CPU and preflight signpost gates; a hang, sustained resize activity, or threshold failure blocks release.
10. Smoke test the supported envelope on assigned real 1x/2x displays and the real-popover available-height calculation. Any clipping inside the envelope makes overflow handling blocking.
11. Source-audit the **primary usage popover**: removed height symbols have no consumers; its old GeometryReader reporter is gone; no usage host writes `preferredContentSize`; every remaining primary `contentSize` mutation is reviewed and the coordinator is the sole ongoing sink. Explicitly allow/list the unrelated context-popover sizing code.
12. Characterization may run only `swift test`/`swift build` and the synthetic fixture binary. Do not run `scripts/build-app.sh`, DMG/signing/xattr/install, package clean/reset, Keychain/security, CLI, browser/openURL, Homebrew, or broad cleanup commands.
13. Only after separate explicit approvals, package, push, tag/release, update Homebrew, or replace `/Applications/ClaudeBat.app`.

## Acceptance criteria

- No persistent remembered content height remains; the coordinator stores only a pending invalidation/session token and remeasures current content at drain time.
- Every intrinsic normal fixture expected to add natural content grows by more than 1 point and returns within 1 point; baseline variants satisfy recorded slack/containment expectations without forced growth.
- The screenshot's inflated weekly/model gaps cannot be reproduced.
- Named 16/20-point normal-usage gaps are within 0.5 point; each baseline state region is centered within 1 point of its remaining-region midpoint.
- Canonical Game Over is 392 points; supported variable variants are at least 392 and satisfy the consume-flex-before-grow contract.
- Every supported-envelope landmark stays inside root bounds; if not, overflow handling becomes part of this patch.
- Hidden changes are correct before show: pre-show, did-show, and next-run-loop heights agree within 0.5 point with zero corrective writes.
- `NSPopover.contentSize` is the only sizing sink; the host's measured preferred size is never overwritten.
- Rapid A -> B -> A invalidations finish at current A with at most one pending item, one drain, and one write per burst.
- Stable Timeline ticks cause zero scheduled drains and zero `NSPopover.contentSize` mutations after settling.
- Close/reopen and shutdown invalidate prior-session work; stale tasks cannot clear or mutate current state.
- The sizing bridge meets the documented CPU, preflight-latency, and ownership bounds.
- No resize loop, main-thread spin, supported-envelope clipping, or reopen flicker is introduced.
- Tests cover reused-host layout plus the actual coordinator ordering policy.
- Product sizing tests perform no real auth, cache, API, CLI, credential, or monitor side effects.

## Git, review, release, and rollback safeguards

- Current implementation branch is `codex/popover-sizing-fix`, created from `main` at `78c7b4e`. Do not stage with `git add -A` or absorb unrelated user changes; stage explicit paths only if a commit is later authorized.
- Preparatory commits and I0 each compile independently. Preserve the I0 runtime-cutover boundary; if repository policy squash-merges, record the resulting merge hash as the rollback unit.
- Before each commit: inspect `git status --short`, `git diff --check`, staged diff/stat, and generated/secret artifacts. If user changes overlap, stop; do not stash/reset/checkout/clean automatically.
- Per preparatory commit: focused tests -> full tests under recorded full-Xcode `DEVELOPER_DIR` -> debug build. I0/I1 additionally require source audit, full suite, debug/release builds, synthetic GUI harness, and final-SHA rerun.
- Scope the source allowlist to the primary usage popover. Legitimate context-popover `preferredContentSize`/`contentSize` assignments are explicitly out of scope.
- Required primary-popover removal audit: `measuredUsageHeight`, `preferredHeight`, `recordMeasuredHeight`, `onPreferredHeightChange`, `lastReportedPopoverHeight`, and `popupHeightWithBanner` have zero active bridge consumers; the old usage GeometryReader reporter is gone; no usage host writes preferred size; all remaining primary content-size mutations are reviewed.
- Synthetic soak before release: at least 1,000 close/reopen/state transitions plus a 30-minute shown/hidden run with stable object counts and zero stable-state writes. Record SHA, environments, fixtures, counters, CPU/latency, ownership, and scrubbed evidence.
- Pushing any `v*` tag immediately triggers public release automation, which currently lacks a test job. Never tag merely to test CI. Add/require green test evidence first, then obtain separate explicit approval for push, tag, GitHub release, and Homebrew update.
- Keep legacy zero-consumer constants through the first stable release. Cleanup is a separate commit/PR after soak.

Rollback is additive and non-destructive. If I0 is unstable, revert later cleanup first (if any), then `git revert` the recorded I0/merge commit on a new rollback branch, rerun the same suite/audits, and merge normally. Never reset, force-push, move/delete/reuse a tag, or overwrite an installed app as rollback. If a bad version is public, publish a new tested patch version and Homebrew SHA rather than rewriting history.

Characterization artifacts contain synthetic labels/counts only. Raw JSONL/screenshots/traces live in a validated UUID temp directory outside the repository; export only scrubbed intentional summaries, remove temp data on success, and never record tokens, account data, user paths, or environment secrets.

## Review history

The 36-pass adversarial history, dispositions, and current verdict are preserved in [POPOVER-SIZING-REVIEW-LOG.md](./POPOVER-SIZING-REVIEW-LOG.md). The status dashboard at the top of this plan is authoritative.
