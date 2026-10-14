# Polymorph API

```lua
local Poly = LibStub("Polymorph-1.0")
local m = Poly(frame)   -- the frame's motion handle, created on first use
```

`Poly(frame)` always returns the same handle for the same frame. Every method below returns the handle, so calls chain:

```lua
Poly(f):set({ alpha = 0 }):to({ alpha = 1 })
```

## Properties

| Name | Reads | Writes | Precision |
| --- | --- | --- | --- |
| `alpha` | `GetAlpha` | `SetAlpha`, clamped to 0..1 | 0.001 |
| `x`, `y` | Polymorph's own offset | `SetPoint` on the frame's first anchor | 0.05 |
| `width`, `height` | `GetWidth`, `GetHeight` | `SetWidth`, `SetHeight`, or one `SetSize` when both move | 0.05 |
| `scale` | `GetScale` | `SetScale` | 0.0005 |

`x` and `y` are offsets from the frame's first anchor, as it was when Polymorph first touched the frame. Polymorph only rewrites that one anchor point. Set your anchors before the first `Poly(frame)` call.

`scale` also scales the frame's anchor offsets. To grow a frame around its center, anchor it at offset 0 inside a holder frame and position the holder.

A property is finished when it's within its precision of the target. For springs, its speed must also be below 10x the precision per second. It then snaps exactly to the target.

Unknown property names raise an error.

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

## `m:set(values)`

Jumps to the values immediately and stops those properties. During combat lockdown, on protected frames, restricted values are applied when combat ends (see [Combat](#combat)).

## `m:stop(name)`

Stops one property where it is, or every property when `name` is nil. `onComplete` callbacks don't run for stopped properties.

## `m:get(name)`

Returns `value, velocity, target`. `target` is nil when the property isn't moving.

## `m:isMoving(name)`

True while the property is animating, or with no `name`, while any property is.

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

Taking over a property doesn't cancel the hide. The hide stops waiting for that property, and it finishes once the properties it still owns have arrived. Only a later `show()` or `hide()` cancels it.

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

Unknown easing, spring and preset names raise an error.

## Combat

During combat lockdown, the game blocks `SetPoint`, `SetSize`, `Show` and `Hide` on protected frames, on their parents, and on frames anchored to them. Polymorph treats `SetScale` the same way. A frame counts as locked when `InCombatLockdown()` and `frame:IsProtected()` are both true. Polymorph checks this every frame, so combat can start or end in the middle of an animation.

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

## Performance and limits

- **One driver.** A single shared `OnUpdate` frame steps every animation. It turns itself off when nothing moves.
- **Few game calls.** Stepping the animations makes one `InCombatLockdown()` call per update. Each frame then gets at most one `SetPoint` for `x` and `y` together, and one `SetSize` for `width` and `height` together, or `SetWidth` or `SetHeight` when only one moves. Finishing work, such as a `hide()` resetting the frame, makes its own calls.
- **No timers.** Polymorph makes no per-animation timers. The game caps each addon at 500 timers and 2000 animation groups. Animation groups are made once per frame and reused: one for a frame animated in combat, and one per property for native tweens. Polymorph stops making native groups after 1000, and later tweens run in Lua.
- **Allocation.** While animations only run, the driver allocates nothing per frame. Allocation happens when work starts or ends:
  - Each `to()` call allocates one small closure, plus a track table for each property that wasn't already moving. `show()` and `hide()` also build small tables of targets.
  - A `hide()` builds one more table when it finishes, to reset the frame.
  - The list of pending `onComplete` callbacks grows to the most animations that finish in a single frame, and is then reused.
  - A protected frame's first move during combat lockdown creates its native animation, once.

### Native tweens

A tween of `alpha`, `x` or `y` runs as one of the game's own animations when all of these hold:
- its ease is `linear`, `inSine`, `outSine` or `inOutSine`, by name or as the function from `Poly.easings`,
- it has a `duration` above 0,
- the frame isn't locked when the tween starts. A `delay` is fine. The tween starts natively once the delay is over.

The game then draws the whole tween, and Polymorph runs no Lua for it until it ends. Polymorph writes the final value first, and the native animation draws the way there. So `GetAlpha()` and `GetPoint()` already return the final values while it plays. Use `m:get()` for the value it draws. Retargeting, `stop()`, `set()` and combat starting midway all work as they do in Lua. Polymorph computes the drawn value from the time since the tween started and continues from there.

Springs, the other easings, `scale`, `width` and `height` always run in Lua. So does an `alpha` tween that starts or ends outside 0..1, so that it follows exactly the curve it would in Lua. When combat lockdown makes Polymorph draw a frame's position through its combat animation, a native `x` or `y` tween on that frame continues in Lua from where it draws.

Measured in the client: the four curves, reverse playback, and that getters ignore native animations. Not measured yet: whether a native Alpha replaces the frame's own alpha or multiplies it, and whether Translations in separate groups add up. Both are assumed here.

`Poly.stats()` returns:
- `frames`: driver updates counted,
- `ms`: total Lua time in the driver,
- `peakTracks`: the most properties moving at once,
- `active`: frames currently moving.

`Poly.resetStats()` clears the counters.

## Loading

- **LibStub.** Polymorph registers as `Polymorph-1.0` and needs LibStub.
- **Upgrades.** If several addons embed different versions, the newest one wins. It takes over the driver frame. Animations running in an older copy stop where they are.
- **Loading the file directly.** If the file is loaded with a namespace table that has `dev = true`, it skips LibStub and puts a private copy in `ns.Polymorph`. The offline tests use this.
