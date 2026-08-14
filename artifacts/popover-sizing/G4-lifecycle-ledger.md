# G4 Lifecycle Ledger

Result: local pass using the exact `PopoverPresentationDriver` now owned by AppDelegate.

The synthetic GUI suite uses a real shown `NSPopover`, an ordered-front nonactivating anchor window, the production coordinator, the selected final-root signal, finite `sizeThatFits`, and native preferred-size tracking disabled.

Verified transactions:

1. compact preflight applies 320 × 327 before `show`;
2. `willShow`, `didShow`, `show` return, and the next settled frame agree;
3. no corrective sink write occurs after the preflight for stable content;
4. a live expanded shape resizes through the coordinator to 320 × 471;
5. explicit close ends the active session before `didClose` bookkeeping;
6. hidden compact mutation schedules/drains/writes zero coordinator work;
7. reopen preflights compact at 320 × 327 on the first frame;
8. a windowless anchor is rejected before AppKit `show` (the unguarded call throws `NSInvalidArgumentException` on this runtime);
9. invalid measurement and sink failure abort before show and balance exactly one presentation-open callback with one close callback;
10. successful open/close/reopen has exactly balanced presentation callback counts;
11. shutdown is absorbing and fences a pending live resize.

An earlier candidate with `host.sizingOptions = [.preferredContentSize]` was rejected because AppKit resized the attached popover directly, bypassing the coordinator sink. The shipped candidate uses `sizingOptions = []` and a finite 320 × 10,000 fitting proposal; the allocation-independent roots make that proposal safe.

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CB_RUN_APPKIT_LIFECYCLE_TESTS=1 \
  swift test --filter PopoverLifecycleCharacterizationTests
```

All four GUI lifecycle tests passed. The installed ClaudeBat app was not launched or replaced.
