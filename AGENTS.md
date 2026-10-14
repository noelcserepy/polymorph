# Polymorph

Polymorph is a LibStub animation library for World of Warcraft addons, registered as `Polymorph-1.0`. The whole library is `Polymorph.lua`. `docs/api.md` is the reference, and `README.md` is the overview.

If `.dev/AGENTS.md` exists, read it before anything else. It holds local, untracked instructions.

## Rules

- WoW runs Lua 5.1, and its `string.format("%d")` errors above 2^31. CI checks syntax on 5.1, and the tests fake the `%d` limit, so a slip fails the checks.
- While a frame is locked (`InCombatLockdown()` and `frame:IsProtected()`), the library never calls `SetPoint`, `SetSize`, `SetWidth`, `SetHeight`, `SetScale`, `Show` or `Hide` on it. A new property declares `restricted = true` when its writer is blocked in combat. It declares `native = true` when it can draw through a native animation instead.
- Every animation runs from the one driver `OnUpdate`. Add no per-animation timers or animation groups, because the game caps each addon at 500 timers and 2000 animation groups.
- A change to the public API updates `docs/api.md` and `README.md` in the same change.
- Claims about performance or game behavior in the docs must come from measurements.

## Checks

Run `lua tests/core_test.lua Polymorph.lua` on Lua 5.1 and on 5.4. CI runs both. Every behavior change adds or updates a test.

For a change to the driver's speed, compare `lua tools/bench.lua Polymorph.lua` against the base branch's copy on the same machine. It reports Lua time and game calls per track. Its game-time column is an estimate from per-call costs measured in the client, so docs quote only in-game measurements.
