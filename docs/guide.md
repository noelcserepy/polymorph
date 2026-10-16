# Polymorph crash course

Polymorph animates a frame by target state. You say where the frame should end up, and Polymorph moves it there from wherever it is now. You can change the target at any time, and the motion carries on instead of restarting. That one rule explains most of the API.

This page covers what to use when, with examples. [`api.md`](api.md) has every rule and edge case.

## The handle

```lua
local Poly = LibStub("Polymorph-1.0")
local m = Poly(frame)                          -- the same handle every time for the same frame
Poly(f):set({ alpha = 0 }):to({ alpha = 1 })   -- every method returns the handle, so calls chain
```

`Poly()` takes a frame, a texture or a font string. You don't need to keep the handle. Calling `Poly(frame)` again returns the same one.

## What you can animate

| Property | Writes | Note |
| --- | --- | --- |
| `alpha` | `SetAlpha` | Clamped to 0..1. |
| `x`, `y` | `SetPoint` | An offset from the frame's own anchors, not a screen position. |
| `width`, `height` | `SetWidth`, `SetHeight`, or one `SetSize` when both move | |
| `scale` | `SetScale` | Grows around the anchor point, and also scales the anchor offset. |

The `x` and `y` model matters most. You place the frame with `SetPoint` as usual, and that spot is home, where `x = 0, y = 0`. Polymorph adds the offset to every anchor, so a frame anchored at two corners slides whole instead of stretching. A frame with no anchors doesn't move. If a layout, a pool or a drag re-anchors the frame, the new anchors become home, and Polymorph never overwrites them.

Anything else, such as a color, a number or typed-out text, goes through [`define()`](#your-own-values).

## `to()`: springs and tweens

```lua
m:to({ alpha = 1, x = 120 })                                           -- spring, the default
m:to({ x = 120 }, { spring = "wobbly" })                               -- spring preset
m:to({ width = 300 }, { duration = 0.25, ease = "outCubic" })          -- tween
m:to({ x = 120 }, { duration = 0.4, ease = { 0.34, 1.56, 0.64, 1 } })  -- CSS cubic-bezier, overshoots
```

The options are `spring`, `duration`, `ease`, `delay` and `onComplete`. Setting `duration` makes the call a tween.

**Spring or tween?**

- Use a spring, with no `duration`, for anything that follows changing input. Health bars, a frame chasing the mouse and hover effects are springs. A spring keeps its speed when you retarget, so it never jerks. The presets are `default`, `gentle`, `wobbly`, `stiff`, `slow` and `molasses`, or pass `{ stiffness = 170, damping = 26 }`.
- Use a tween, with a `duration`, for a fixed-length move where timing matters. A 0.2 s fade and a row moving to its new rank are tweens. A retargeted tween starts a new tween from the current value, so its speed resets.

Retargeting is the main feature. Call `to()` from events as often as the state changes, and don't wait for the last animation to finish:

```lua
frame:SetScript("OnEvent", function()
  Poly(bar):to({ width = maxWidth * UnitHealth("player") / UnitHealthMax("player") })
end)
```

**Steps in order.** Start the next step from `onComplete`:

```lua
Poly(f):to({ x = 100 }, { duration = 0.3, onComplete = function(frame)
  Poly(frame):to({ alpha = 0 }, { duration = 0.2 })
end })
```

`onComplete` belongs to its call. If a later `to()`, `set()` or `stop()` takes over one of its properties, it never runs.

**Staggered lists.** Use `delay`:

```lua
for i, row in ipairs(rows) do
  Poly(row):set({ alpha = 0, y = -8 }):to({ alpha = 1, y = 0 }, { spring = "gentle", delay = (i - 1) * 0.03 })
end
```

Don't use `delay` as a timer. A delayed property holds where it is until the delay ends. For "do this in 3 seconds", use `C_Timer.After`.

## `show()` and `hide()`

Use these instead of `Show()` and `Hide()` on any frame that should animate in or out.

```lua
m:show("pop")                                         -- from alpha 0 and scale 0.92
m:hide("below", { duration = 0.3, ease = "inQuad" })  -- slide down and fade, then Hide()
m:show({ alpha = 0, x = 120 }, { spring = "gentle" }) -- your own away state
```

The argument says where the frame is while it's hidden. The presets are `fade`, the default, `pop`, `below`, `above`, `left` and `right`.

- `hide()` animates out, calls `Hide()`, then resets the frame to its rest values while it's hidden. A later plain `Show()` still looks normal.
- `show()` during a running `hide()` turns the frame around, and `Hide()` never fires. An animation group whose `OnFinished` calls `Hide()` still hides a frame the player just reopened.
- `show()` comes in from the away state only when the frame is hidden. `CreateFrame` returns a shown frame, so call `frame:Hide()` once at creation.

A panel with a toggle button:

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

A toast:

```lua
toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
toast:Hide() -- once, at creation
Poly(toast):show("above", { spring = "stiff" })
C_Timer.After(3, function() Poly(toast):hide("above") end)
```

Polymorph records rest values the first time it touches a frame: its alpha, scale and size, with `x = 0, y = 0`. A frame first touched at alpha 0 rests at alpha 1. Change them with `m:restAt({ alpha = 0.8 })`.

## The small methods

| Call | Use it when |
| --- | --- |
| `m:set(values)` | You need to jump now, for example to a start state before `to()`. It also stops those properties. |
| `m:stop(name)` | You need to freeze one property, or every property with no name. With no name it also cancels a running `show()` or `hide()`. |
| `m:get(name)` | You need the drawn value. It returns `value, velocity, target`. |
| `m:isMoving(name)` | You need to know whether a property, or with no name anything, is still moving. |
| `m:restAt(values)` | You want to change where `show()` returns to. |

Read values with `get()`, not `GetPoint()`, `GetAlpha()` or `GetScale()`. Those miss the game's own animations, which Polymorph uses in combat and for some tweens.

## Your own values

Define names on a handle once, where you create the frame. After that, `to()`, `set()`, `show()` and `hide()` take them like built-in properties. Polymorph calls your writer once per update with every defined value.

A color fade:

```lua
local r, g, b = icon:GetVertexColor()
Poly(icon):define({ r = r, g = g, b = b }, function(tex, c) tex:SetVertexColor(c.r, c.g, c.b) end)
Poly(icon):to({ r = 1, g = 0.2, b = 0.2 }, { duration = 0.3, ease = "outSine" })
```

A number that rolls to each new total:

```lua
local counter = Poly(fs):define({ total = 0 }, function(text, v)
  text:SetText(("%.0f"):format(v.total)) -- never "%d", which errors above 2^31 in WoW
end, { precision = 0.5 })                 -- arrives when the shown digits stop changing
counter:to({ total = 1500 })
```

Rules for the writer:

- Polymorph calls it in combat too. Never call `SetPoint`, `SetSize`, `SetScale`, `Show` or `Hide` from it. Keep to calls like `SetText`, `SetVertexColor` and `SetAlphaGradient`.
- Don't start animations inside it. Use `onComplete`.
- For a counter, use the default spring or a tween. `wobbly`, `stiff` and `gentle` overshoot, so the number would pass the total and roll back.

[`api.md`](api.md#examples) also has a typewriter built on `SetAlphaGradient`. `SetText` clears the gradient at a bad moment, and that example works around it, so copy it rather than writing your own.

## Combat

During combat lockdown, the game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames. Polymorph never makes those calls while a frame is locked:

- `alpha` animates normally.
- `x`, `y` and `scale` animate through the game's own animations, and hand back to real anchors and scale when combat ends.
- `width` and `height` wait until combat ends.
- `hide()` fades now and calls the real `Hide()` after combat. The faded frame still takes clicks until then.
- `show()` on a hidden frame waits for combat to end.

Each of these ran on `SecureActionButtonTemplate` buttons in real combat with no blocked actions. Your part is to not call those functions yourself in combat.

## Performance

One shared `OnUpdate` drives every animation, and it turns itself off when nothing moves. Polymorph makes no timers per animation.

A tween of `alpha`, `x` or `y` with `linear`, `inSine`, `outSine` or `inOutSine` runs as the game's own animation, with no Lua per frame. Use those eases when many frames fade or slide at once. With 300 frames tweening `x` in the client, Polymorph used 0.65 to 0.71 ms of Lua per frame when the tweens ran in Lua. Native, it spent 2.1 ms once to start all 300, and no Lua after that. Springs, the other eases, `scale` and size always run in Lua.

`Poly.stats()` reports the driver's time in-game, and `Poly.resetStats()` clears it.

## Mistakes to avoid

1. **Two writers on one property.** While Polymorph animates `alpha`, don't also call `SetAlpha` or run `UIFrameFadeIn` on that frame. Animate a child frame instead.
2. **Scaling around the wrong point.** To grow around the center, anchor the frame by `"CENTER"` at offset 0 inside a holder frame. Position the holder, and animate the inner frame's `scale`.
3. **Pooled frames.** Call `Poly(row):stop()` in the pool's resetter, or release the row from `hide()`'s `onComplete`. Otherwise an old `hide()` can hide the row's next owner.
4. **Typos.** Unknown property, ease, spring and preset names raise an error at your call, so they fail loudly.

## Which call to use

| You want | Use |
| --- | --- |
| A value that tracks game state | `to()` with a spring, called on every event |
| A fixed fade or slide | `to()` with a `duration` and a sine or linear ease, so it can run natively |
| A panel or toast that comes and goes | `show(preset)` and `hide(preset)` |
| A start state, then an animation | `set(...):to(...)` |
| Steps one after another | `onComplete`, then the next `to()` |
| A color, a counter or a text reveal | `define()` once, then `to()` |
| Where the frame is drawn now | `get("x")`, not `GetPoint()` |
