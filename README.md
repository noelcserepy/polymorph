# Polymorph

Target-state animation for World of Warcraft addons. Springs, tweens and retargeting, with combat lockdown handled for you.

```lua
local Poly = LibStub("Polymorph-1.0")

Poly(frame):to({ alpha = 1, y = 20 })                          -- spring
Poly(frame):to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
Poly(panel):hide("below")                                      -- animate out, then Hide()
```

> **Status: early.** Version 0.1, tested on the WoW Forever beta (1.60.1, interface 16001). Other game versions are untested. The API may still change.

## Why

Blizzard's animation groups play fixed clips. You can't change a clip's target while it plays, you can't animate width or height, and a translation snaps back when it ends.

With Polymorph you say what state a frame should be in. Call `:to()` again at any time, and the frame continues from where it is. A spring keeps its speed when the target changes, so a frame that follows the mouse, a bar that grows on every event, or a panel that opens and closes quickly never jumps.

## Install

Polymorph is a LibStub library in one file. Embed it like any other library.

With the [BigWigs packager](https://github.com/BigWigsMods/packager), add it to your `.pkgmeta`:

```yaml
externals:
  Libs/Polymorph:
    url: https://github.com/noelcserepy/polymorph
    tag: latest
```

Then load it after LibStub in your TOC or `embeds.xml`:

```xml
<Include file="Libs\Polymorph\lib.xml"/>
```

To copy it in by hand, `Polymorph.lua` and `lib.xml` are all you need, plus LibStub.

## What you can animate

| Property | What it changes | Notes |
| --- | --- | --- |
| `alpha` | `SetAlpha` | Clamped to 0..1. |
| `x`, `y` | `SetPoint` offsets | Offsets from the frame's first anchor, as it was when Polymorph first touched the frame. |
| `width`, `height` | `SetWidth`, `SetHeight` | One `SetSize` when both move. |
| `scale` | `SetScale` | Scale also scales anchor offsets. To grow around the center, anchor the frame at offset 0 inside a holder. |

Animate several properties in one call. Each one moves on its own track.

## Springs and tweens

Without a `duration`, `:to()` uses a spring. Presets use react-spring's names and values: `default`, `gentle`, `wobbly`, `stiff`, `slow`, `molasses`. You can also pass your own `{ stiffness, damping, mass }`.

With a `duration`, it tweens. Easings: `linear`, `inQuad`, `outQuad`, `inOutQuad`, `outCubic` (the default), `inOutCubic`, `ease`, `easeOut`, `easeInOut`. Any CSS-style cubic-bezier works too:

```lua
Poly(f):to({ x = 120 }, { duration = 0.4, ease = { 0.34, 1.56, 0.64, 1 } }) -- overshoots
```

Every call takes `delay` and `onComplete`. That covers staggered lists and chained steps:

```lua
for i, row in ipairs(rows) do
  Poly(row):to({ alpha = 1, y = 0 }, { spring = "wobbly", delay = (i - 1) * 0.03 })
end
```

## Show and hide

```lua
Poly(f):show("pop")      -- from alpha 0 and scale 0.92 to rest
Poly(f):hide("below")    -- slide down and fade, then Hide()
```

Presets name where the frame is while it's away: `fade`, `pop`, `below`, `above`, `left`, `right`. You can also pass a table such as `{ alpha = 0, x = 120 }`. When a hide finishes, every property that `show()` or `hide()` still owns is back at rest, so a plain `Show()` later looks normal. A property you take over with `to()`, `set()` or `stop()` stays the way you left it, and the hide still finishes. Calling `show()` during a `hide()` turns the frame around, and `Hide()` is never called.

## Combat

In combat, the game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames, on their parents, and on frames anchored to them. Calling one shows the player an "action blocked" error. Polymorph never makes those calls while the frame is locked:

| During combat lockdown, on a protected frame | What Polymorph does |
| --- | --- |
| `alpha` | Animates normally. |
| `x`, `y`, `scale` | Animates through paused native animations. When combat ends, the frame is anchored and scaled where it shows. |
| `width`, `height` | Waits, then animates when combat ends. |
| `hide()` | Fades, slides and shrinks now. The real `Hide()` happens when combat ends, and the faded frame still takes clicks until then. |
| `show()` on a hidden frame | Waits for combat to end. |

Everything except `scale` was tested on `SecureActionButtonTemplate` buttons in real combat, with no blocked actions. `scale` was measured out of combat so far.

## Performance

One shared `OnUpdate` drives every animation, and it switches itself off when nothing moves. Polymorph creates no timers per animation. That matters because the game caps each addon at 500 timers. In a test with 200 frames animating three properties each (600 springs at once), the driver used 0.78 ms of Lua time per frame. A typical addon animates a few dozen properties at a time.

## Reference

[`docs/api.md`](docs/api.md) has every function, option and preset.

## For coding agents

[`skills/polymorph/SKILL.md`](skills/polymorph/SKILL.md) teaches an agent to use Polymorph: setup, the rules that prevent the common bugs, the API, and patterns to copy. Agents that support skills load it on their own when addon code animates frames. Copy the `skills/polymorph` folder into your project or user skills folder:

- Claude Code: `.claude/skills/` in the addon's repository, or `~/.claude/skills/`.
- Codex and other agents that read `.agents/skills/`: that folder in the repository, or `~/.agents/skills/`.

For any other agent, paste the file into its instructions.

## License

[MIT](LICENSE)
