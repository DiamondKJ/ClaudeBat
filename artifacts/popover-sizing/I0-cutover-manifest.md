# I0 Atomic Cutover Manifest

The active usage-popover sizing owner has been switched as one working-tree unit on `codex/popover-sizing-fix`.

Removed active behavior:

- `UsagePopoverView.measuredUsageHeight`;
- `preferredHeight`/`recordMeasuredHeight` and the old GeometryReader reporter;
- `onPreferredHeightChange`;
- `AppDelegate.lastReportedPopoverHeight` and `PopoverLayout` fallback reuse;
- asynchronous dual writes to popover and hosting-controller preferred size;
- SwiftUI environment `dismiss()` as the X-button close path;
- the vertically flexible weekly balancing cell.

Added active behavior:

- allocation-independent normal/header-baseline/standalone roots;
- display-only deterministic clock/timezone/install seams;
- final-root background `GeometryReader` size invalidation (value discarded);
- session-token `PopoverSizeCoordinator`;
- shared `PopoverPresentationDriver` for AppDelegate and G4;
- synchronous finite preflight before show;
- one deferred/coalesced live measurement path;
- exactly one primary usage `NSPopover.contentSize` mutation sink;
- explicit close callback to the owned popover;
- stable model IDs for duplicate display labels.

The unrelated context-popover `preferredContentSize` and `contextPopover.contentSize` assignments are explicitly unchanged and out of scope. Legacy zero-consumer popup constants remain through the soak window for simple rollback.
