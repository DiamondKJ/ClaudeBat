# G3 Coordinator Summary

Result: pass.

`PopoverSizeCoordinator` is public, MainActor-isolated, session-token scoped, and still independently testable. Its public scheduler always defers live work; its manual scheduler is internal to the test target.

The 11 focused tests prove:

- synchronous preflight with forced width and half-point height normalization;
- malformed/nil/tiny/overflow measurement rejection;
- 10,000 stable invalidations coalescing to one measurement and zero writes;
- newest-content measurement at drain time;
- stale queued work cannot consume or clear a newer session in FIFO or out-of-order execution;
- stale external session calls cannot affect the current session;
- sink reentrancy schedules a fresh drain without losing it;
- preflight suppresses measurement/sink reentrancy;
- failed preflight cannot transition to shown;
- close and shutdown fence queued and late work;
- the production scheduler never drains inline.

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter PopoverSizeCoordinatorTests
```

All 11 tests passed. No AppKit window, credential, network, cache, defaults, monitor, or filesystem service is used by this suite.
