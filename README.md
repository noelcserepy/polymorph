<img src="docs/media/polymorph-logo-pixels.svg" alt="" width="64" height="64">

# Polymorph

Target-state animation for World of Warcraft addons. Springs, tweens and retargeting, with combat lockdown handled for you.

```lua
local Poly = LibStub("Polymorph-1.0")

Poly(frame):to({ alpha = 1, y = 20 })                          -- spring
Poly(frame):to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
Poly(panel):hide("below")                                      -- animate out, then Hide()
```

![A damage meter whose bars grow as damage comes in and whose rows slide into their new rank when players overtake each other](docs/media/damage-meter.gif)

A damage meter built with Polymorph. Each bar tweens to its new amount on every update, and rows move to their new rank with an `inOutCubic` tween.

> **Status: early.** Version 0.1, tested on the WoW Forever beta (1.60.1, interface 16001). Other game versions are untested. The API may still change.

## Why

Blizzard's animation groups play fixed clips. You can't change a clip's target while it plays, you can't animate width or height, and a translation snaps back when it ends.

With Polymorph you say what state a frame should be in. Call `:to()` again at any time, and the frame continues from where it is. A spring keeps its speed when the target changes, so a frame that follows the mouse, a bar that grows on every event, or a panel that opens and closes quickly never jumps.

![The same target jumps around one panel twice: first an animation group restarted on each new target, which snaps back whenever a move is interrupted, then Polymorph, which glides](docs/media/animationgroup-vs-polymorph.gif)

The same moving target, twice. First the usual animation-group approach, `Stop()` and `Play()` on each new target: every interrupted move snaps back to where the last one started. Then `Poly(sheep):to({ x = x, y = y })`, which continues from wherever the sheep is.

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

`Poly()` takes frames, textures and font strings. Combat rules follow each one's own `IsProtected()`. The icon and label of a protected button report false, so they animate every property in combat.

### Your own values

For anything else, such as a color, a number that counts up, or text that types itself out, define your own values on a handle and animate them like any property. Polymorph calls your writer once per update with every current value:

```lua
local r, g, b = icon:GetVertexColor()
Poly(icon):define({ r = r, g = g, b = b }, function(tex, c) tex:SetVertexColor(c.r, c.g, c.b) end)
Poly(icon):to({ r = 1, g = 0.2, b = 0.2 }, { duration = 0.3 })
```

Names you define belong to that one handle, so addons sharing Polymorph can't collide. [`docs/api.md`](docs/api.md#mdefinevalues-write-opts) has the rules and three examples you can copy: a number counter that rolls to each new total, a typewriter, and a color fade.

## Springs and tweens

Without a `duration`, `:to()` uses a spring. Presets use react-spring's names and values: `default`, `gentle`, `wobbly`, `stiff`, `slow`, `molasses`. You can also pass your own `{ stiffness, damping, mass }`.

With a `duration`, it tweens. Easings: `linear`, `inSine`, `outSine`, `inOutSine`, `inQuad`, `outQuad`, `inOutQuad`, `outCubic` (the default), `inOutCubic`, `ease`, `easeOut`, `easeInOut`. Any CSS-style cubic-bezier works too:

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

![A loot window that opens, rows that arrive one after another, and rows that leave as they are looted while the rows below close the gap](docs/media/loot-window.gif)

A loot window. Rows arrive 30 ms apart with `show()`. A looted row leaves with `hide()`, then the rows below and the window's bottom edge close the gap together.

## Combat

In combat, the game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames, on their parents, and on frames anchored to them. Calling one shows the player an "action blocked" error. Polymorph never makes those calls while the frame is locked:

| During combat lockdown, on a protected frame | What Polymorph does |
| --- | --- |
| `alpha` | Animates normally. |
| `x`, `y`, `scale` | Animates through paused native animations. When combat ends, the frame is anchored and scaled where it shows. |
| `width`, `height` | Waits, then animates when combat ends. |
| `hide()` | Fades, slides and shrinks now. The real `Hide()` happens when combat ends, and the faded frame still takes clicks until then. |
| `show()` on a hidden frame | Waits for combat to end. |

Everything in this table was tested on `SecureActionButtonTemplate` buttons in real combat, with no blocked actions. That includes a bar that slides in from a `PLAYER_REGEN_DISABLED` handler, as combat locks it.

## Performance

One shared `OnUpdate` drives every animation, and it switches itself off when nothing moves. Polymorph creates no timers per animation. That matters because the game caps each addon at 500 timers. In a test with 200 frames animating three properties each (600 springs at once), the driver used 0.89 ms of Lua time per frame, the median of 7 runs. A typical addon animates a few dozen properties at a time.

Tweens of `alpha`, `x` or `y` with `linear`, `inSine`, `outSine` or `inOutSine` run as the game's own animations, with no Lua per frame. These four are the curves the game has built in. Such a tween holds its start value for one frame, then one shared timer starts it. Started from an `OnUpdate` script, the game sometimes drew a sliding frame's first frames far outside its path.

## Reference

[`docs/api.md`](docs/api.md) has every function, option and preset.

## For coding agents

[`skills/polymorph/SKILL.md`](skills/polymorph/SKILL.md) teaches an agent to use Polymorph: setup, the rules that prevent the common bugs, the API, and patterns to copy. Agents that support skills load it on their own when addon code animates frames. Copy the `skills/polymorph` folder into your project or user skills folder:

- Claude Code: `.claude/skills/` in the addon's repository, or `~/.claude/skills/`.
- Codex and other agents that read `.agents/skills/`: that folder in the repository, or `~/.agents/skills/`.

For any other agent, paste the file into its instructions.

## License

[MIT](LICENSE)
