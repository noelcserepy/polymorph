# Polymorph

Polymorph is a LibStub animation library for World of Warcraft addons, registered as `Polymorph-1.0`. The whole library is `Polymorph.lua`. `docs/api.md` is the reference, and `README.md` is the overview.

If `.dev/AGENTS.md` exists, read it before anything else. It holds local, untracked instructions.

## Rules

- WoW runs Lua 5.1, and its `string.format("%d")` errors above 2^31. CI checks syntax on 5.1, and the tests fake the `%d` limit, so a slip fails the checks.
- While a frame, texture or font string is locked (`InCombatLockdown()` and its own `IsProtected()`), the library never calls `SetPoint`, `SetSize`, `SetWidth`, `SetHeight`, `SetScale`, `Show` or `Hide` on it. A new property declares `restricted = true` when its writer is blocked in combat. It declares `native = true` when it can draw through a native animation instead. Values from `define()` are never restricted: their writer is the developer's, and the docs tell them to keep it to calls the game allows in combat.
- Lua animations run from the one driver `OnUpdate`, and native tweens need no Lua at all. Add no per-animation timers, and make animation groups once per frame and property, then reuse them. Native tweens start only from the one shared start timer, never from an `OnUpdate` script, where a Translation's first frames were recorded drawing against the old anchor. The game caps each addon at 500 timers and 2000 animation groups, so native groups stop at `MAX_NATIVE_GROUPS`.
- A change to the public API updates `docs/api.md`, `README.md` and `skills/polymorph/SKILL.md` in the same change. To test the skill, give a fresh agent only `SKILL.md` and the brief at the top of `tools/skill_check.lua`, then run `lua tools/skill_check.lua Polymorph.lua answer.lua` on its answer. `tools/skill_check_selftest.lua` proves the checker rejects answers that break the brief. Add a case there when you find one it lets through.
- Claims about performance or game behavior in the docs must come from measurements.

## Checks

Run `lua tests/core_test.lua Polymorph.lua` on Lua 5.1 and on 5.4. CI runs both. Every behavior change adds or updates a test.

For a change to the driver's speed, compare `lua tools/bench.lua Polymorph.lua` against the base branch's copy on the same machine. It reports Lua time and game calls per track. Its game-time column is an estimate from per-call costs measured in the client, so docs quote only in-game measurements.
