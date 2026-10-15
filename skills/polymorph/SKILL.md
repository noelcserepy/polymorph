---
name: polymorph
description: Animate World of Warcraft addon frames with the Polymorph-1.0 library. Use when addon Lua fades, slides, scales, resizes, shows or hides a frame, or when the addon embeds Polymorph.
---

# Polymorph

Polymorph is a LibStub library for animating WoW frames by target state. You say what a frame should look like, and it moves there:

```lua
local Poly = LibStub("Polymorph-1.0")
Poly(frame):to({ alpha = 1, y = 20 })                           -- spring
Poly(frame):to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
Poly(panel):hide("below")                                       -- animate out, then Hide()
```

Calling `to()` again at any time retargets from where the frame is now, and a spring keeps its speed. So call it from events as often as the state changes, and never wait for an animation to finish first. One shared `OnUpdate` drives everything, and it switches off when nothing moves.

The full reference is `docs/api.md` in the Polymorph repository: https://github.com/noelcserepy/polymorph/blob/main/docs/api.md. Read it when a case below doesn't cover what you need.

## Setup

Embed it like any LibStub library. With the BigWigs packager, add it to the addon's `.pkgmeta`:

```yaml
externals:
  Libs/Polymorph:
    url: https://github.com/noelcserepy/polymorph
    tag: latest
```

Load it after LibStub, in the TOC or `embeds.xml`:

```xml
<Include file="Libs\Polymorph\lib.xml"/>
```

Copied by hand, `Polymorph.lua` and `lib.xml` are all it needs, plus LibStub.

## Rules

Each rule prevents a bug that is easy to write and hard to see.

1. **Anchor first.** `x` and `y` are offsets from the frame's first anchor as it was when `Poly(frame)` first ran. Call `SetPoint` before the first `Poly(frame)`, then move the frame only through Polymorph. A later `SetPoint` of your own is overwritten the next time Polymorph moves `x` or `y`.
2. **One writer per property.** While Polymorph animates `alpha`, `x`, `y`, `width`, `height` or `scale`, change that property through `m:to()` or `m:set()`, never with `SetAlpha`, `SetPoint`, `SetSize` or `SetScale`. `m:set()` jumps there and stops the animation.
3. **`show()` and `hide()` instead of `Show()` and `Hide()`** for any frame that should animate in or out. `hide()` animates, then calls `Hide()` and resets the frame to rest while hidden, so a later plain `Show()` still looks right. `show()` during a running `hide()` turns the frame around. `show()` comes in from `away` only when the frame is hidden. On a shown frame it just returns the `away` properties to rest. A new frame from `CreateFrame` is shown, so call its `Hide()` once at creation.
4. **Read through Polymorph.** `m:get("x")` returns the drawn value. `GetPoint()`, `GetLeft()` and `GetScale()` miss the native animations Polymorph uses in combat.
5. **Scale grows around the anchor point and scales the anchor offset.** To grow a button around its center, anchor it by `"CENTER"` at offset 0 inside a holder frame, position the holder, and animate the button's `scale`.
6. **Protected frames in combat.** The game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames during combat lockdown, and calling one shows the player an error. Polymorph never makes those calls while a frame is locked:
   - `alpha`, `x`, `y` and `scale` keep animating,
   - `width` and `height` wait for combat to end,
   - `show()` on a hidden frame waits for combat to end,
   - `hide()` fades now and calls `Hide()` when combat ends. The faded frame still takes clicks until then.

   Your own code must not call those functions in combat either. Let Polymorph do it.
7. **`onComplete` belongs to one call.** It runs once, after every property in that call has arrived. If a later `to()`, `set()` or `stop()` takes over one of its properties, it never runs. `hide()` is the exception: it finishes once the properties it still owns arrive.

## API

| Call | Does |
| --- | --- |
| `Poly(frame)` | The frame's handle, the same one every time. Every method returns it, so calls chain. |
| `m:to(targets, opts)` | Animates each property in `targets`. |
| `m:set(values)` | Jumps to the values and stops those properties. |
| `m:stop(name)` | Stops one property where it is, or all of them when `name` is nil. |
| `m:get(name)` | `value, velocity, target`. `target` is nil when the property is still. |
| `m:isMoving(name)` | True while the property moves, or any property with no `name`. |
| `m:show(away, opts)` | Shows the frame and animates from `away` to rest. |
| `m:hide(away, opts)` | Animates to `away`, then calls `Hide()` and resets to rest. |
| `m:restAt(values)` | Changes the rest values `show()` returns to. |

Properties: `alpha`, `x`, `y`, `width`, `height`, `scale`. Unknown names raise an error.

`opts` for `to()`, `show()` and `hide()`:

| Option | Default | Meaning |
| --- | --- | --- |
| `spring` | `"default"` | `default`, `gentle`, `wobbly`, `stiff`, `slow`, `molasses`, or `{ stiffness, damping, mass }`. |
| `duration` | none | Seconds. Setting it makes a tween instead of a spring. |
| `ease` | `"outCubic"` | `linear`, `inQuad`, `outQuad`, `inOutQuad`, `outCubic`, `inOutCubic`, `ease`, `easeOut`, `easeInOut`, a cubic-bezier `{ x1, y1, x2, y2 }`, or a function from 0..1 to 0..1. |
| `delay` | 0 | Seconds before these properties start. |
| `onComplete` | none | `onComplete(frame)`, see rule 7. |

`away` is a preset or a table of values, and describes the frame while it is hidden. Every preset sets `alpha = 0`, and some move too: `fade` (only alpha), `pop` (`scale = 0.92`), `below` (`y = -16`), `above` (`y = 16`), `left` (`x = -16`) and `right` (`x = 16`). The default is `fade`. Add your own to `Poly.presets`.

Rest values are recorded on first touch: alpha, scale, width and height as they are, `x = 0`, `y = 0`. A frame first touched at alpha 0 rests at alpha 1.

## Patterns

Pick the closest pattern and adapt it.

**Panel that opens and closes.** Keep your own flag. `show()` and `hide()` are safe to repeat and to interrupt, so a fast double click just turns the panel around.

```lua
local open = false
toggleButton:SetScript("OnClick", function()
  open = not open
  if open then
    Poly(panel):show("pop")
  else
    Poly(panel):hide("pop", { duration = 0.15, ease = "inQuad" })
  end
end)
```

**Toast that slides in and leaves.**

```lua
toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
toast:Hide() -- once, at creation: show() slides in only from hidden
Poly(toast):show("above", { spring = "stiff" })
C_Timer.After(3, function() Poly(toast):hide("above") end)
```

Don't use a `to()` with a `delay` as a timer. A delayed property holds where it is until the delay ends, so it would freeze the fade-in.

**Staggered list.**

```lua
for i, row in ipairs(rows) do
  Poly(row):set({ alpha = 0, y = -8 }):to({ alpha = 1, y = 0 }, { spring = "gentle", delay = (i - 1) * 0.03 })
end
```

**Bar that follows a value.** Retarget on every event. The spring keeps its speed.

```lua
frame:SetScript("OnEvent", function()
  Poly(bar):to({ width = maxWidth * UnitHealth("player") / UnitHealthMax("player") })
end)
```

**Button that grows on hover**, anchored as rule 5 says.

```lua
local holder = CreateFrame("Frame", nil, parent)
holder:SetSize(40, 40)
holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
local button = CreateFrame("Button", nil, holder)
button:SetSize(40, 40)
button:SetPoint("CENTER", holder, "CENTER", 0, 0)
button:SetScript("OnEnter", function(b) Poly(b):to({ scale = 1.1 }, { spring = "stiff" }) end)
button:SetScript("OnLeave", function(b) Poly(b):to({ scale = 1 }, { spring = "stiff" }) end)
```

**Steps in order.** Start the next step from `onComplete`.

```lua
Poly(f):to({ x = 100 }, { duration = 0.3, onComplete = function(frame)
  Poly(frame):to({ alpha = 0 }, { duration = 0.2 })
end })
```

## Checking your work

- `Poly.stats()` returns `frames`, `ms` (total driver Lua time), `peakTracks` and `active`. `Poly.resetStats()` clears them. Use it to report animation cost in-game.
- After a `hide()`, the frame is hidden and back at rest. After a `show()`, it is shown and at rest. If a frame stays faded but shown, look for a `Show()` or `SetAlpha()` of your own that fights Polymorph (rules 2 and 3).
