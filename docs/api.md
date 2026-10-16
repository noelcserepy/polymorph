# Polymorph API

```lua
local Poly = LibStub("Polymorph-1.0")
local m = Poly(frame)   -- the frame's motion handle, created on first use
```

`frame` can be a frame, a texture or a font string. See [Textures and font strings](#textures-and-font-strings).

`Poly(frame)` always returns the same handle for the same frame. Every method below returns the handle, so calls chain:

```lua
Poly(f):set({ alpha = 0 }):to({ alpha = 1 })
```

## Properties

| Name | Reads | Writes | Precision |
| --- | --- | --- | --- |
| `alpha` | `GetAlpha` | `SetAlpha`, clamped to 0..1 | 0.001 |
| `x`, `y` | Polymorph's offset from the frame's anchors | `SetPoint` on every anchor of the frame | 0.05 |
| `width`, `height` | `GetWidth`, `GetHeight` | `SetWidth`, `SetHeight`, or one `SetSize` when both move | 0.05 |
| `scale` | `GetScale` | `SetScale` | 0.0005 |

`x` and `y` move every anchor of the frame by the same offset, so a frame with two anchors slides instead of stretching. At `x = 0` and `y = 0` the frame sits on its own anchors. If other code re-anchors the frame between animations, the new anchors are its home from then on (see [Using Polymorph with other code](#using-polymorph-with-other-code)). A frame without anchors has nothing to offset, so Polymorph doesn't anchor it.

`scale` also scales the frame's anchor offsets. To grow a frame around its center, anchor it at offset 0 inside a holder frame and position the holder.

A property is finished when it's within its precision of the target. For springs, its speed must also be below 10x the precision per second. It then snaps exactly to the target.

The client stores alpha in steps of 1/255. Measured in WoW Forever 1.60.1, `SetAlpha(0.5)` reads back as 0.50196. So `m:get("alpha")` on a still frame can differ from the value you set by up to 0.002. While alpha moves, `get()` returns Polymorph's own value.

Unknown property names raise an error at the line that made the call. To animate anything else, such as a color, a number or how much text shows, define your own values with [`m:define()`](#mdefinevalues-write-opts).

## `m:to(targets, opts)`

Animates each property in `targets` toward its value.

```lua
m:to({ alpha = 1, x = 120 })                                   -- default spring
m:to({ x = 120 }, { spring = "wobbly" })
m:to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
```

| Option | Default | Meaning |
| --- | --- | --- |
| `spring` | `"default"` | Preset name, or `{ stiffness = n, damping = n, mass = n }`. `mass` defaults to 1. Ignored when `duration` is set. |
| `duration` | none | Seconds. Setting it makes this a tween instead of a spring. |
| `ease` | `"outCubic"` | Tween easing: a name, `{ x1, y1, x2, y2 }` for a cubic-bezier, or a function from progress 0..1 to eased 0..1. |
| `delay` | 0 | Seconds before these properties start moving. |
| `onComplete` | none | `onComplete(frame)` runs once, when every property in this call has arrived. |

**Retargeting.** Calling `to()` for a property that is already moving changes its target. The value continues from where it is. A spring keeps its velocity. A tween starts a new tween from the current value, so its velocity resets.

**Callbacks and takeovers.** If a later call takes over one of a call's properties, that earlier call's `onComplete` never runs. `hide()` is the exception, described below. Callbacks run after the frame's update. A callback can safely start new animations.

**Errors.** An error in an `onComplete` goes to the game's error handler, `geterrorhandler()`, once, and stops nothing. An error while Polymorph works on a frame, from a game call, an `ease`, a `define()` writer or a hook, first starts that frame over, as if `Poly(frame)` met it for the first time then. The frame keeps only its rest values and the values `define()` made, where they stopped. If a call such as `to()`, `set()` or `get()` was running, the error then goes to that call's caller. Otherwise it goes to the error handler once: during an update, a native tween's start or end, the hand-over when combat ends, or a call that waited for the frame (see [Hooks](#hooks)). Other frames keep animating. Every animation on the frame stops, even if a hook on `Stop()` of one of Polymorph's animation groups throws. Polymorph reports the first such error too, and ignores any call that hook makes on the frame. Nothing queued for it runs: no `onComplete`, and no `show()` or `hide()` waiting for combat, so neither calls `Show()` or `Hide()`. No later call writes a value staged before the error. The frame then shows the values last set on it: a Lua animation stays where it last drew, a native Translation tween shows its end value, and a protected frame in combat goes back to the anchors and scale it had before combat. `x` and `y` read 0 there. Whether stopping a native Alpha tween restores the frame's own alpha, and therefore shows its end value after a halt, is not yet verified in the client.

## `m:set(values)`

Jumps to the values immediately and stops those properties. During combat lockdown, on protected frames, restricted values are applied when combat ends (see [Combat](#combat)).

## `m:stop(name)`

Stops one property where it is, or every property when `name` is nil. `onComplete` callbacks don't run for stopped properties.

With no `name`, it also cancels a running `show()` or `hide()`. The hide never calls `Hide()` or its `onComplete`, and a `show()` waiting for combat to end never runs. Call it before a frame goes back to a pool (see [Pools](#pools)).

## `m:get(name)`

Returns `value, velocity, target`. `target` is nil when the property isn't moving.

## `m:isMoving(name)`

True while the property is animating, or with no `name`, while any property is.

## `m:define(values, write, opts)`

Adds your own values to this handle. Each name in `values` becomes a property that `to()`, `set()`, `stop()`, `get()`, `show()` and `hide()` take like the built-in ones. It starts at the number given. Springs, tweens, retargeting, `delay` and `onComplete` all work the same.

```lua
Poly(fs):define({ total = 0 }, function(fs, v) fs:SetText(("%.0f"):format(v.total)) end, { precision = 0.5 })
Poly(fs):to({ total = 1500 })
```

- **One writer call per update.** The handle keeps every value defined on it in one table, `current`. In every update where any of a writer's values moved, Polymorph calls `write(frame, current)` once, so several values that belong together, such as `r`, `g` and `b`, reach the game in one call. `current` is the same table every time. Read it, and don't keep or change it.
- **Names belong to the handle.** A name means something only on the handle you defined it on, so two addons can't collide through a shared list. A built-in name raises an error. Defining a name again replaces its writer and keeps its current value. A writer that still owns other names keeps reading this one's current value.
- **Rest values.** For `show()` and `hide()`, a defined value rests at the number it was first defined with. `m:restAt()` changes it.
- **Precision.** A defined value is finished within `opts.precision` of its target, 0.001 by default. A spring then snaps to the target. For a number shown as a whole number, pass `{ precision = 0.5 }`. At 0.001, the default spring rolls on for 0.63 s after the shown digits stop changing, whatever the distance, so `onComplete` and `isMoving()` come that much late. That is the library's spring stepped at 60 fps, from 0 to 1,234, 1.5 million and 3 billion. Tweens finish on time either way.
- **Always Lua.** Defined values never run as native animations.
- **Combat.** Polymorph calls `write` in combat too, and never waits for combat to end. So a writer must call only what the game allows in combat. Never call `SetPoint`, `SetSize`, `SetWidth`, `SetHeight`, `SetScale`, `Show` or `Hide` from it. Animate position, size and scale with the built-in properties, which handle combat. In a real fight, `SetText`, `SetVertexColor` and `SetAlphaGradient` on textures and font strings of protected buttons raised no blocked actions. `SetTextColor` hasn't been tested in combat.
- **No animation calls inside `write`.** It runs inside the driver's update. Start the next animation from `onComplete` instead.
- **Numbers above 2^31.** WoW's `string.format("%d")` errors above 2^31. Format with `"%.0f"`.

`define()` returns the handle. Call it once, where you create the frame.

### Examples

Each example runs in the offline tests, `tests/core_test.lua`, against the fake client.

**Number counter.** A total that rolls to each new value. Every hit retargets the spring, which keeps its speed, so a burst of hits never makes the number stall or jump. The default spring's damping ratio is 0.997, so it overshoots by less than 10^-17 of the distance, and the number never passes the total. `wobbly`, `stiff` and `gentle` overshoot, and the number would roll back.

```lua
local Poly = LibStub("Polymorph-1.0")

-- Returns add(amount). Call it on every hit, as often as hits come.
local function NumberCounter(fs)
  local m = Poly(fs):define({ total = 0 }, function(text, v)
    text:SetText(("%.0f"):format(v.total)) -- "%.0f", since "%d" errors above 2^31
  end, { precision = 0.5 }) -- arrives when the shown digits stop changing
  m:set({ total = 0 })
  local total = 0
  return function(amount)
    total = total + amount
    m:to({ total = total })
  end
end
```

**Typewriter.** Reveals a font string's text from the left. It uses `FontString:SetAlphaGradient(start, length)`, the call Blizzard's quest frame uses to type out quest text: the first `start` characters show, and the next `length` fade out. Because the whole text is set at once, lines wrap where they finally will, and words never jump to the next line as they grow. Slicing the string instead would reflow on every step and needs care with UTF-8 and color codes.

```lua
local Poly = LibStub("Polymorph-1.0")

-- Returns typeText(text), which reveals `speed` characters per second. A new text starts over.
local function Typewriter(fs, speed)
  local m = Poly(fs):define({ shown = 0 }, function(text, v)
    text:SetAlphaGradient(v.shown, 4)
  end)
  return function(text)
    m:set({ shown = 0 }) -- hides the current text now
    -- SetText clears the gradient until the code that called it returns. From a timer,
    -- Polymorph draws the gradient later in the same frame, before the text shows.
    C_Timer.After(0, function()
      fs:SetText(text)
      local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      local length = select(2, plain:gsub("[^\128-\191]", "")) -- characters, not bytes or color codes
      m:set({ shown = 0 }):to({ shown = length }, {
        duration = length / speed, ease = "linear",
        onComplete = function() fs:ClearAlphaGradient() end,
      })
    end)
  end
end
```

Measured in the client:
- `start` counts characters. A UTF-8 character such as `ö` counts once, and `|c` color codes don't count.
- On wrapped text, `start` counts on into the next lines. The space where a line wraps doesn't count, so the reveal runs one character ahead per wrapped line. `onComplete` clears the gradient, so it always ends with the whole text.
- `SetText` clears the gradient, even when the text is the same, and a gradient set later in the same function doesn't show. One set in a later script of the same frame does. With `SetText` called directly in `typeText`, the whole new text showed for one frame in 7 of 8 recorded starts from an `onComplete` or an `OnUpdate` script, and 0 of 4 from a timer. With the timer above, 0 of 12, called from all three.

**Color fade.** Three values, one writer: `r`, `g` and `b` move on their own tracks, so a retarget mid-fade turns smoothly toward the new color, and the texture gets one `SetVertexColor` per update.

```lua
local Poly = LibStub("Polymorph-1.0")

-- Returns tint(r, g, b, opts), which fades from the color the texture shows now.
local function ColorFade(tex)
  local r, g, b = tex:GetVertexColor()
  local m = Poly(tex):define({ r = r, g = g, b = b }, function(t, c)
    t:SetVertexColor(c.r, c.g, c.b)
  end)
  return function(red, green, blue, opts)
    m:to({ r = red, g = green, b = blue }, opts)
  end
end

-- local tint = ColorFade(icon)
-- tint(1, 0.2, 0.2, { duration = 0.3, ease = "outSine" })
```

For a font string, read `GetTextColor` and write `SetTextColor`. Polymorph has no built-in color property. A texture, a font string and a status bar each take color through a different call, and this example fits any of them by swapping the two calls.

## `m:show(away, opts)` and `m:hide(away, opts)`

```lua
m:show("pop")
m:hide("below", { duration = 0.3, ease = "inQuad" })
m:show({ alpha = 0, x = 120 }, { spring = "gentle" })
```

`away` is a preset name or a table of property values. It describes where the frame is while it's hidden. `show()` comes from there and `hide()` goes there. The default is `"fade"`. `opts` are the same as for `to()`.

| Preset | Values |
| --- | --- |
| `fade` | `alpha = 0` |
| `pop` | `alpha = 0, scale = 0.92` |
| `below` | `alpha = 0, y = -16` |
| `above` | `alpha = 0, y = 16` |
| `left` | `alpha = 0, x = -16` |
| `right` | `alpha = 0, x = 16` |

**show().**
- If the frame is hidden, `show()` sets the `away` values, calls `Show()`, and animates each of those properties to its rest value.
- If the frame is already shown, it animates the `away` properties to rest from wherever they are.
- It cancels a running `hide()`, so that `Hide()` is never called. It also returns every property that hide was moving, so `hide("pop")` interrupted by `show("fade")` brings back scale as well as alpha.
- In combat, the most recent `show()` or `hide()` wins. A `hide()` cancels a `show()` that was waiting for combat to end, and the reverse.

**hide().** It animates to `away`. Then it calls `Hide()`, resets properties to rest while the frame is hidden, and calls `opts.onComplete`. The reset covers every property that `show()` or `hide()` still owns. Ownership works per property:
- A property becomes theirs when `show()` or `hide()` animates it.
- It stops being theirs when its animation arrives back at rest, or when you take it over with `to()`, `set()` or `stop()`.

Taking over a property doesn't cancel the hide. The hide stops waiting for that property, and it finishes once the properties it still owns have arrived. Only a later `show()`, `hide()` or `stop()` with no name cancels it.

So a `hide()` that interrupts another hide, or a `show()` that is still restoring, still ends with the frame at rest. Properties you have taken over are left as they are.

**Rest values.** Poly records them when it first touches the frame: its alpha, scale, width and height, with `x = 0` and `y = 0`. A frame first touched at alpha 0 rests at alpha 1. Override them with `m:restAt({ alpha = 0.8 })`.

Add your own presets to `Poly.presets`.

## Easings and springs

`Poly.easings`:
- `linear`
- `inSine`, `outSine`, `inOutSine`. These match the game's own curves, so tweens with them can run natively (see [Native tweens](#native-tweens)).
- `inQuad`, `outQuad`, `inOutQuad`
- `outCubic`, `inOutCubic`
- `ease`, `easeOut`, `easeInOut`. These three are the CSS curves.

Each is a function from progress to eased progress. Add your own to the table.

`Poly.bezier(x1, y1, x2, y2)` returns an easing function for a CSS-style cubic-bezier. Values of `y` outside 0..1 overshoot.

`Poly.springs`, with react-spring's values:

| Preset | Stiffness | Damping |
| --- | --- | --- |
| `default` | 170 | 26 |
| `gentle` | 120 | 14 |
| `wobbly` | 180 | 12 |
| `stiff` | 210 | 20 |
| `slow` | 280 | 60 |
| `molasses` | 280 | 120 |

Springs integrate in fixed steps of 1/120 s. Frame time is clamped to 0.1 s, so a long hitch doesn't make the spring jump.

Unknown easing, spring and preset names raise an error at the line that made the call.

## Textures and font strings

`Poly(texture)` and `Poly(fontString)` work like `Poly(frame)`, with the same properties. Textures and font strings have every method Polymorph calls, and native `alpha`, `x` and `y` tweens run on them as on frames.

A texture or font string counts as locked in combat by its own `IsProtected()`, the same rule as a frame. On a `SecureActionButtonTemplate` button, the button's `IsProtected()` is true, and its texture's and font string's are false, before and during combat. In a real fight, `SetPoint`, `SetSize`, `SetWidth`, `SetHeight`, `SetScale`, `Show` and `Hide`, each called once on a texture of such a button, raised no blocked actions. The same layout and visibility calls on a font string haven't been measured in combat yet.

## Combat

During combat lockdown, the game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames, on their parents, and on frames anchored to them. Polymorph treats `SetScale` the same way. A frame, texture or font string counts as locked when `InCombatLockdown()` and its own `IsProtected()` are both true. Polymorph checks this every frame, so combat can start or end in the middle of an animation.

| While locked | Behavior |
| --- | --- |
| `alpha` | Animates normally. |
| `x`, `y` | Animates through a paused native Translation animation. Polymorph moves it with `SetOffset`, which the game allows in combat. When combat ends, the frame is anchored where it shows, and the native animation stops. The handover lands on the same pixel. |
| `scale` | Animates through a paused native Scale animation in the same group, steered with `SetScaleTo`. It grows around the frame's anchor point, and the Translation adds the shift that `SetScale` would give the anchor offset. When combat ends, Polymorph calls `SetScale` and `SetPoint` with what the frame shows. |
| `width`, `height` | Paused. The property animates once combat ends. The game has no native animation for size. |
| `set()` | `alpha`, `x`, `y` and `scale` apply now. `width` and `height` apply when combat ends. |
| `hide()` | Animates the properties it can (`alpha`, `x`, `y`, `scale`). It calls `Hide()` when combat ends. The faded frame still receives clicks until then. |
| `show()` on a hidden frame | Waits for combat to end, then shows. |

`GetPoint()`, `GetLeft()` and `GetScale()` don't include native animations. While locked, read with `m:get("x")` or `m:get("scale")`.

Every row except `set()` was tested on `SecureActionButtonTemplate` buttons in real combat, with no blocked actions. For `scale`, the test covered combat starting and ending in the middle of an `x` and `scale` tween, and a `scale` spring followed by `hide("pop")` in combat.

You can start animations on protected frames in a `PLAYER_REGEN_DISABLED` handler. In two real fights, `InCombatLockdown()` was still false inside that handler and true one frame later. So a native `x` or `y` tween queued there found the frame locked when it started. Polymorph then ran it through the combat animation, with no jump and no blocked actions.

## Using Polymorph with other code

Layouts, frame pools, frame movers and faders write to frames too. When a property is still, Polymorph starts from the frame's current value. Anchors get one more rule, because a stale anchor doesn't heal by itself: Polymorph never overwrites anchors that other code set.

### Anchors

Polymorph compares the frame's anchors with the ones it last wrote:
- at every call that takes or returns `x` or `y`: `to`, `set`, `stop`, `get`, `show` and `hide`,
- in every frame, before it writes them for an `x` or `y` animation running in Lua,
- after the last write of an `x` or `y` animation running in Lua, so a hook on `SetPoint` that re-anchors the frame then takes the slide over,
- when a native `x` or `y` tween ends,
- and when combat ends, for every frame it moved in combat.

If other code changed them, that code wins:
- its anchors become the frame's home, and `x` and `y` are 0 there,
- a running `x` or `y` animation stops where that code put the frame. For its `onComplete`, this counts as a takeover (see [Callbacks and takeovers](#mtotargets-opts)).

So anything can move the frame: a drag, LibWindow-1.1's `RestorePosition`, Edit Mode, an AceGUI or ScrollBox layout, or a secure group header sorting its children in combat. A slide in progress stops where that code put the frame. The next `show("below")` slides from there.

A native `x` or `y` tween writes the anchors once, when it starts. While the game draws it, Polymorph doesn't check them. If other code moves the frame then, Polymorph doesn't undo it. The tween draws its remaining offset from the new anchors, and when it ends, it counts as taken over.

An `x` or `y` animation that arrives in combat, through the combat animation, finishes before the anchors are checked. If a secure header moved the frame during that fight, the animation's `onComplete` has already run, and the frame moves to the header's anchor when combat ends.

`x` and `y` move every anchor, so a ScrollBox row, anchored `TOPLEFT` and `TOPRIGHT`, slides whole. In the client, a 300-wide row anchored that way kept its width while it slid. AceGUI's List and Flow layouts anchor each widget to the one before it, so moving one widget also moves the ones after it.

### Hooks

Code that hooks a frame's setters, such as `hooksecurefunc(frame, "SetPoint", fn)`, can call Polymorph while Polymorph writes to that frame. A call on a frame that arrives while Polymorph is working on that same frame runs right after that work finishes, so the call made last wins.

- The work is a call to `to`, `set`, `stop`, `show`, `hide` or `restAt`, an update that moves the frame, a native tween's start or end, the hand-over when combat ends, or a restart after an error. A call from an `ease` function waits the same way.
- Waiting calls run in the order they were made, and a call made while one of them runs waits behind them.
- Work that already reached its targets still completes. If a hook calls `set()` during a slide's last update, the slide's `onComplete` still runs, after the `set()`.
- `get()` and `isMoving()` answer at once. During the work, they return the work's own values. `define()` also takes effect at once.
- A waiting call checks its arguments at once, so an unknown name raises at the hook's line.
- Calls on other frames run at once.
- A waiting call that throws starts the frame over (see [Errors](#mtotargets-opts)), and the calls waiting behind it are dropped. If more than 100 calls wait for one frame in a row, for example from a hook that calls Polymorph on every write, Polymorph reports an error and starts the frame over.

### Pools

Blizzard's `CreateFramePool` hands out the same frames again. Its default resetter hides the frame and clears its anchors, and leaves alpha, scale and size as they are. AceGUI-3.0's `Release` does the same, and also parents the frame to `UIParent`. The frame keeps its Polymorph handle. Two ways to reuse it cleanly:

- Let the frame leave with `hide()`, and release it in `onComplete`. It's then hidden and at rest.
- Call `Poly(frame):stop()` before you release it, or in the pool's resetter. Without it, a `hide()` still running would call `Hide()` on the frame after its next owner shows it.

```lua
local pool = CreateFramePool("Frame", parent, "MyRowTemplate", function(_, row)
  Poly(row):stop()
  row:Hide()
  row:ClearAllPoints()
end)
```

A frame stopped mid-fade keeps that alpha, and `show()` on it later still returns to its rest values. Rest values stay the ones recorded when Polymorph first touched the frame. The new owner's anchors become the frame's home at the next call.

### Alpha, scale and size from other code

Faders write alpha on the frames they manage:
- `UIFrameFadeIn` and `UIFrameFadeOut`, every frame while they fade,
- oUF's range element, on range events, and every 0.5 s for units such as `targettarget`,
- LibDBIcon-1.0, on its minimap buttons.

While Polymorph animates `alpha` in Lua, it writes alpha every frame too, and a native alpha tween replaces the frame's alpha while it plays. Two writers on one frame overwrite each other, and Polymorph doesn't mix them. Animate a different frame from the fader's. For example, put the content in a child frame and animate that. The child draws at its own alpha times its parent's. In the client, a child at 0.5 under a parent at 0.5 drew at 0.251.

If a fader holds the frame at another alpha when Polymorph first touches it, that alpha becomes the rest value. Change it with `m:restAt({ alpha = 1 })`.

The same goes for scale and size. `LibWindow.Embed(frame)` replaces the frame's `SetScale` with one that saves and re-anchors the frame. A `scale` animation would call it every frame, so animate a child of that frame instead. Edit Mode also replaces `SetPoint`, `SetScale` and `ClearAllPoints` on Blizzard's own frames. Animate your own frames, not Blizzard's.

## Performance and limits

- **One driver.** A single shared `OnUpdate` frame steps every animation. It turns itself off when nothing moves.
- **Few game calls.** Stepping the animations makes one `InCombatLockdown()` call per update. Each frame then gets one `SetPoint` per anchor for `x` and `y` together, and one `SetSize` for `width` and `height` together, or `SetWidth` or `SetHeight` when only one moves. Finishing work, such as a `hide()` resetting the frame, makes its own calls. Before that `SetPoint`, it reads the frame's anchors with `GetNumPoints()` and one `GetPoint()` per anchor (see [Anchors](#anchors)). A frame with more than one anchor reads them all again after each `SetPoint` but the last, since a hook can re-anchor it in between, so two anchors cost two `GetNumPoints()` and four `GetPoint()` per update. The update where `x` or `y` arrives reads them once more. A call that takes or returns `x` or `y` reads them the same way.
- **No timers.** Polymorph makes no per-animation timers. One shared timer starts native tweens, and at most one is pending at a time. The game caps each addon at 500 timers and 2000 animation groups. Animation groups are made once per frame and reused: one for a frame animated in combat, and one per property for native tweens. Polymorph stops making native groups after 1000, and later tweens run in Lua.
- **Allocation.** While animations only run, the driver allocates nothing per frame. Allocation happens when work starts or ends:
  - Each `to()` call allocates one small closure, plus a track table for each property that wasn't already moving. `show()` and `hide()` also build small tables of targets.
  - A call that waits for its frame (see [Hooks](#hooks)) allocates one small table.
  - A `hide()` builds one more table when it finishes, to reset the frame.
  - The list of pending `onComplete` callbacks grows to the most animations that finish in a single frame, and is then reused.
  - A protected frame's first move during combat lockdown creates its native animation, once.

### Native tweens

A tween of `alpha`, `x` or `y` runs as one of the game's own animations when all of these hold:
- its ease is `linear`, `inSine`, `outSine` or `inOutSine`, by name or as the function from `Poly.easings`,
- it has a `duration` above 0,
- the frame isn't locked when the tween starts. A `delay` is fine. The tween starts natively once the delay is over.

The tween holds its start value until the next frame, when one shared timer starts every native tween queued since. Started from an `OnUpdate` script, a native `x` or `y` tween sometimes drew its first frame or two against the old anchor, far outside its path. Started from a timer, it never did in the recordings. Timers run before `OnUpdate` scripts, so a native tween called from a timer draws one frame later than the same tween in Lua would. Called from an `onComplete` callback, they draw the same.

The game then draws the whole tween, and Polymorph runs no Lua for it until it ends. Polymorph writes the final value when the tween starts, and the native animation draws the way there. So `GetPoint()` already returns the final anchor while it plays. `GetAlpha()` depends on where you read it: from an `OnUpdate` script it returned the final value, and from a `C_Timer` callback the drawn one. Use `m:get()` for the value it draws. Retargeting, `stop()`, `set()` and combat starting midway all work as they do in Lua. Polymorph computes the drawn value from the time since the tween started and continues from there.

Springs, the other easings, `scale`, `width` and `height` always run in Lua. So does an `alpha` tween that starts or ends outside 0..1, so that it follows exactly the curve it would in Lua. When combat lockdown makes Polymorph draw a frame's position through its combat animation, a native `x` or `y` tween on that frame continues in Lua from where it draws.

Measured in the client:
- the four curves and reverse playback,
- that `GetPoint()` ignores native animations, and so do `GetAlpha()`, `GetScale()` and `GetWidth()` read from `OnUpdate`,
- that a native Alpha replaces the frame's own alpha instead of multiplying it,
- that Translations in separate groups add up,
- that a Lua tween and the game's own Translation, started together, draw on the same pixel,
- that a Translation started from a timer draws its first frames in place: 0 of 32 recorded starts misdrew, against 3 of 8 started from `OnUpdate`,
- that the start timer runs in the next frame, before `OnUpdate` scripts, and that Polymorph's native `x` tweens drew in place in 96 recorded starts at 120 fps, called from a timer, another frame's `OnUpdate`, after a `delay` and from `onComplete`.

With 300 frames tweening `x` at once, Polymorph used 0.65 to 0.71 ms of Lua per frame when the tweens ran in Lua. Native, it spent 2.1 ms once, in the start timer, to start all 300, and no Lua after that. Two runs each, at 60 fps.

`Poly.stats()` returns:
- `frames`: driver updates counted,
- `ms`: total Lua time in the driver and the start timer,
- `peakTracks`: the most properties on the frames the driver visited in one update. A frame whose tweens are all native leaves the driver, so its properties don't count.
- `active`: frames currently moving, including frames whose tweens only the game draws.

`Poly.resetStats()` clears the counters.

## Loading

- **LibStub.** Polymorph registers as `Polymorph-1.0` and needs LibStub.
- **Upgrades.** If several addons embed different versions, the newest one wins. It takes over the driver frame. Animations running in an older copy stop where they are.
- **Loading the file directly.** If the file is loaded with a namespace table that has `dev = true`, it skips LibStub and puts a private copy in `ns.Polymorph`. The offline tests use this.
