---
name: polymorph
description: Animate World of Warcraft addon frames, textures and font strings with the Polymorph-1.0 library. Use when addon Lua fades, slides, scales, resizes, shows or hides one, animates a color, a number or text being typed out, or when the addon embeds Polymorph.
---

# Polymorph

Polymorph is a LibStub library for animating WoW frames by target state. You say what a frame should look like, and it moves there:

```lua
local Poly = LibStub("Polymorph-1.0")
Poly(frame):to({ alpha = 1, y = 20 })                           -- spring
Poly(frame):to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
Poly(panel):hide("below")                                       -- animate out, then Hide()
```

`Poly()` takes a frame, a texture or a font string. Calling `to()` again at any time retargets from where the frame is now, and a spring keeps its speed. So call it from events as often as the state changes, and never wait for an animation to finish first. One shared `OnUpdate` drives everything, and it switches off when nothing moves.

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

1. **Anchor with `SetPoint`, move with `x` and `y`.** `x` and `y` add an offset to every anchor of the frame, so `x = 0, y = 0` is where its anchors put it, and a frame with two anchors slides whole. A frame with no anchors doesn't move. Any code may re-anchor the frame: a layout, a pool, a drag. Polymorph never overwrites that. The new anchors become home, with `x` and `y` at 0, and a slide in progress stops there.
2. **One writer per property.** While Polymorph animates `alpha`, `x`, `y`, `width`, `height` or `scale`, change that property through `m:to()` or `m:set()`, never with `SetAlpha`, `SetPoint`, `SetSize` or `SetScale`. `m:set()` jumps there and stops the animation. Another fader on the same frame, such as `UIFrameFadeIn` or oUF's range fade, fights Polymorph's alpha. Animate a child frame instead.
3. **`show()` and `hide()` instead of `Show()` and `Hide()`** for any frame that should animate in or out. `hide()` animates, then calls `Hide()` and resets the frame to rest while hidden, so a later plain `Show()` still looks right. `show()` during a running `hide()` turns the frame around. `show()` comes in from `away` only when the frame is hidden. On a shown frame it just returns the `away` properties to rest. A new frame from `CreateFrame` is shown, so call its `Hide()` once at creation.
4. **Read through Polymorph.** `m:get("x")` returns the drawn value. `GetPoint()`, `GetLeft()`, `GetScale()` and `GetAlpha()` miss the game's own animations, which Polymorph uses in combat and for native tweens. A native tween starts on the next frame. From then on they already return the final value.
5. **Scale grows around the anchor point and scales the anchor offset.** To grow a button around its center, anchor it by `"CENTER"` at offset 0 inside a holder frame, position the holder, and animate the button's `scale`.
6. **Protected frames in combat.** The game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames during combat lockdown, and calling one shows the player an error. Polymorph never makes those calls while a frame is locked:
   - `alpha`, `x`, `y` and `scale` keep animating,
   - `width` and `height` wait for combat to end,
   - `show()` on a hidden frame waits for combat to end,
   - `hide()` fades now and calls `Hide()` when combat ends. The faded frame still takes clicks until then.

   Your own code must not call those functions in combat either. Let Polymorph do it.
7. **`onComplete` belongs to one call.** It runs once, after every property in that call has arrived. If a later `to()`, `set()` or `stop()` takes over one of its properties, it never runs. `hide()` is the exception: it finishes once the properties it still owns arrive. Only a later `show()`, `hide()` or `stop()` with no name cancels it, or an error while Polymorph works on that frame. An error in `onComplete` goes to the game's error handler and stops nothing else. After any other error on a frame, from a game call, an ease, a writer or a hook, Polymorph starts that frame over as if it met the frame then: every animation and queued call on it is dropped, its rest values and defined values stay, and `x` and `y` read 0 where it stopped.
8. **Anything else goes through `define()`.** For a color, a number or typed-out text, define your own values on the handle once, at creation, and then animate them with `to()` like any property. Defining a name again replaces its writer and keeps its current value. Polymorph calls your writer once per update with every value defined on the handle, and `set()` calls it at once. It calls it in combat too, so the writer must never call `SetPoint`, `SetSize`, `SetScale`, `Show` or `Hide`. Use it for calls like `SetText`, `SetVertexColor`, `SetTextColor` and `SetAlphaGradient`. Don't start animations from a writer. Format numbers with `"%.0f"`, because WoW's `"%d"` errors above 2^31. A value finishes within 0.001 of its target. For a number shown whole, pass `{ precision = 0.5 }` as the third argument. Otherwise the counter keeps running for 0.63 s after its digits stop, and `onComplete` waits that long.
9. **Calls from hooks wait.** A call on a frame that arrives while Polymorph is working on that same frame, such as from a `hooksecurefunc` on its `SetPoint` or from an `ease` function, runs right after that work finishes, so the call made last wins. `get()` and `isMoving()` answer at once.

## API

| Call | Does |
| --- | --- |
| `Poly(frame)` | The frame's handle, the same one every time. Every method returns it, so calls chain. |
| `m:to(targets, opts)` | Animates each property in `targets`. |
| `m:set(values)` | Jumps to the values and stops those properties. |
| `m:stop(name)` | Stops one property where it is. With no `name`, stops all of them and cancels a running `show()` or `hide()`, which then never calls `Hide()`. |
| `m:get(name)` | `value, velocity, target`. `target` is nil when the property is still. |
| `m:isMoving(name)` | True while the property moves, or any property with no `name`. |
| `m:show(away, opts)` | Shows the frame and animates from `away` to rest. |
| `m:hide(away, opts)` | Animates to `away`, then calls `Hide()` and resets to rest. |
| `m:restAt(values)` | Changes the rest values `show()` returns to. |
| `m:define(values, write, opts)` | Adds your own values to this handle, starting at the numbers in `values`. Polymorph calls `write(frame, current)` once per update while any of them moves. `current` holds every value defined on the handle. `opts.precision` is how close a value must come to arrive, 0.001 by default. |

Properties: `alpha`, `x`, `y`, `width`, `height`, `scale`, plus the names you `define()` on that handle. Unknown names raise an error, and so does defining a built-in name.

`opts` for `to()`, `show()` and `hide()`:

| Option | Default | Meaning |
| --- | --- | --- |
| `spring` | `"default"` | `default`, `gentle`, `wobbly`, `stiff`, `slow`, `molasses`, or `{ stiffness, damping, mass }`. |
| `duration` | none | Seconds. Setting it makes a tween instead of a spring. |
| `ease` | `"outCubic"` | `linear`, `inSine`, `outSine`, `inOutSine`, `inQuad`, `outQuad`, `inOutQuad`, `outCubic`, `inOutCubic`, `ease`, `easeOut`, `easeInOut`, a cubic-bezier `{ x1, y1, x2, y2 }`, or a function from 0..1 to 0..1. |
| `delay` | 0 | Seconds before these properties start. |
| `onComplete` | none | `onComplete(frame)`, see rule 7. |

`away` is a preset or a table of values, and describes the frame while it is hidden. Every preset sets `alpha = 0`, and some move too: `fade` (only alpha), `pop` (`scale = 0.92`), `below` (`y = -16`), `above` (`y = 16`), `left` (`x = -16`) and `right` (`x = 16`). The default is `fade`. Add your own to `Poly.presets`.

**Native tweens.** A tween of `alpha`, `x` or `y` with `linear`, `inSine`, `outSine` or `inOutSine` runs as the game's own animation, with no Lua per frame. Prefer these eases when many frames fade or slide at once. Springs and the other eases run in Lua. A native tween holds its start value for one frame, then the game draws it.

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

**Number that rolls to each new total.** Define it once, then retarget on every event. The spring keeps its speed, so a burst of hits never stalls the number. Use the default spring or a tween: `wobbly`, `stiff` and `gentle` overshoot, so the number would pass the total and roll back.

```lua
local function NumberCounter(fs)
  local m = Poly(fs):define({ total = 0 }, function(text, v)
    text:SetText(("%.0f"):format(v.total)) -- never "%d": it errors above 2^31
  end, { precision = 0.5 }) -- arrives when the shown digits stop changing
  m:set({ total = 0 })
  local total = 0
  return function(amount)
    total = total + amount
    m:to({ total = total })
  end
end
```

**Color fade.** One value per channel and one writer, so a retarget mid-fade turns smoothly toward the new color. For a font string, use `GetTextColor` and `SetTextColor`.

```lua
local r, g, b = icon:GetVertexColor()
Poly(icon):define({ r = r, g = g, b = b }, function(tex, c) tex:SetVertexColor(c.r, c.g, c.b) end)
Poly(icon):to({ r = 1, g = 0.2, b = 0.2 }, { duration = 0.3, ease = "outSine" })
```

**Typewriter.** `SetAlphaGradient(start, length)` shows the first `start` characters and fades out the next `length`. The text is laid out once, so words never jump to the next line as they appear. `SetText` clears the gradient until the code that called it returns, so set the text from a timer. Polymorph then draws the gradient later in the same frame. Called straight from an `onComplete` or an `OnUpdate`, the whole text shows for a frame.

```lua
local m = Poly(fs):define({ shown = 0 }, function(text, v) text:SetAlphaGradient(v.shown, 4) end)
m:set({ shown = 0 }) -- hides the current text now
C_Timer.After(0, function()
  fs:SetText(text)
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local length = select(2, plain:gsub("[^\128-\191]", "")) -- characters, not bytes or color codes
  m:set({ shown = 0 }):to({ shown = length }, { duration = length / 40, ease = "linear",
    onComplete = function() fs:ClearAlphaGradient() end })
end)
```

**Pooled rows.** A pool gives the same frame to the next owner. Let a row leave with `hide()` and release it in `onComplete`. Also stop it in the pool's resetter, so a `hide()` still running can't hide the row's next owner.

```lua
local pool = CreateFramePool("Frame", list, nil, function(_, row)
  Poly(row):stop()
  row:Hide()
  row:ClearAllPoints()
end)

local function removeRow(row)
  Poly(row):hide("left", { onComplete = function() pool:Release(row) end })
end
```

**Steps in order.** Start the next step from `onComplete`.

```lua
Poly(f):to({ x = 100 }, { duration = 0.3, onComplete = function(frame)
  Poly(frame):to({ alpha = 0 }, { duration = 0.2 })
end })
```

## Checking your work

- `Poly.stats()` returns `frames`, `ms` (total Lua time in the driver and the native start timer), `peakTracks` and `active`. `Poly.resetStats()` clears them. Use it to report animation cost in-game.
- After a `hide()`, the frame is hidden and back at rest. After a `show()`, it is shown and at rest. If a frame stays faded but shown, look for a `Show()` or `SetAlpha()` of your own that fights Polymorph (rules 2 and 3).
