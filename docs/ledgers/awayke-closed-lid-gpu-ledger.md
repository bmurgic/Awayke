# Awayke closed-lid GPU reduction — Awayke, started 2026-08-30

**Goal (user's words):** "I want to make it so the screen gets turned off when it is closed and back on when reopened. This will be a standard feature of the closed lid mode and always just work."

**Purpose (user's words):** "It is because I don't want the GPU to be used when it is closed."

**Backups / undo:** none needed. This run has only inspected source and run existing tests. No application source or tests were changed.

**⚠️ Uncommitted state:** This ledger file is untracked at `docs/ledgers/awayke-closed-lid-gpu-ledger.md` and exists only in this checkout. The shared ledger index points to it.

**Progress: 0 implementation units → 0. Investigation has defined the physical feasibility probe that must precede design approval.**

| # | Unit | N | Status | Outcome |
|---|---|---:|---|---|
| 1 | Refresh and identify the code baseline | 1 | DONE | `origin/main` fetched and verified at `3a873f374c0fe93a991faa1dab2564efaf270cc2`. Local `HEAD` matches it; the checkout still tracks `upstream/main` and is one commit ahead. |
| 2 | Trace the existing lid-session behavior | 1 | DONE | `LidMonitor` supplies physical open and closed events. `LidSessionTracker` waits for close then reopen, or only reopen when started closed. The focused Swift tests passed. Source remains authoritative. |
| 3 | Set display scope | 1 | DONE | Brandon ruled that only the built-in laptop display is in scope. External displays must not be blanked. |
| 4 | Verify display state and GPU effect on hardware | 1 | NEXT | Obtain Brandon's approval, then capture built-in display topology and matched GPU samples before, during, and after a lid close and reopen cycle. |
| 5 | Revise and approve the bounded design | 1 | todo | Use the hardware evidence to decide whether native lid handling already removes built-in-display GPU work or whether the requirement lacks a supported implementation. |
| 6 | Select an execution route and implement | 1 | todo | No route has been selected and no implementation is authorized. |

## Rulings already made

- **R1, Brandon, 2026-08-30:** Only the built-in laptop display should turn off. External displays are excluded.
- **R2, Brandon, 2026-08-30:** The reason for turning off the built-in display is to avoid GPU use while the lid is closed.
- **R3, workflow, 2026-08-30:** This is a bounded change because the existing lid-event and closed-lid-mode flow already owns the behavior. The design approval gate remains open.

## Facts held only here

- A dark backlight does not prove that the GPU stopped rendering the built-in display. The acceptance evidence must include display topology and GPU measurements.
- Core Graphics exposes `CGDisplayIsBuiltin`, `CGDisplayIsActive`, `CGDisplayIsAsleep`, and display-reconfiguration callbacks. These can show whether the built-in display becomes inactive or asleep after lid closure.
- This Mac's `powermetrics` supports the `gpu_power` sampler and `--show-process-gpu`. The physical probe should compare matched samples and inspect WindowServer GPU time.
- The existing `PreventUserIdleDisplaySleep` assertion does not block display sleep caused by closing a portable's lid, according to Apple's IOKit documentation. Keep that assertion active during the probe so external displays retain current behavior.
- The public macOS 27 SDK search found observation APIs but no supported API that forces only the built-in display to sleep. This is an investigation result, not yet a product ruling. If the physical probe shows that native lid handling leaves the built-in display active, the remaining known mechanisms are private display APIs or all-display sleep; neither currently meets the requirement.
- The earlier wake-only draft design is superseded pending the hardware probe. Do not implement it as the final solution without the GPU evidence.

## Physical probe

1. Run the current `origin/main` build in lid-closed mode.
2. Record each display's built-in, online, active, and asleep state before closing, while closed, and after reopening.
3. Capture matched `powermetrics` windows for GPU power and per-process GPU time across those states.
4. Repeat with an external display attached. Confirm that the external display remains active.
5. Treat the result as successful only if the built-in display becomes asleep or inactive, display-driven GPU work decreases, the external display remains active, and the built-in display returns on reopen.

## Open items

- **Blocking next action:** Brandon must approve the physical probe. It requires him to close and reopen the lid on cue. `powermetrics` may require administrator access.
- **⚠️ The ledger file itself is untracked and exists only in this checkout.**
- The app can target GPU work attributable to the built-in display. It cannot guarantee zero system-wide GPU usage while other applications, compute tasks, WindowServer, or external displays remain active.
- No OpenSpec change, design file, implementation plan, branch, commit, or pull request exists for this work.

## Source pointers

- Lid events and session coordination: `Awayke/AppDelegate.swift`, `Awayke/LidMonitor.swift`, and `Awayke/LidSessionTracker.swift`.
- Wake assertions and closed-lid control: `Awayke/DisplayWakeKeeper.swift`, `Awayke/ClamshellWakeKeeper.swift`, and `Awayke/WakeModeController.swift`.
- Existing focused checks: `Tests/main.swift`.
