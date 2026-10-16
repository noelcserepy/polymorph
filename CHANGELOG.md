# Changelog

## 0.1.0 (2026-10-16)

First version.

- `Poly(frame):to(targets, opts)` animates `alpha`, `x`, `y`, `width`, `height` and `scale`, with springs (react-spring presets or custom stiffness, damping and mass) or tweens (named easings or any cubic-bezier).
- Retargeting continues from the current value. Springs keep their velocity.
- `delay` and `onComplete` on every call.
- `set`, `stop`, `get`, `isMoving`.
- `show(away, opts)` and `hide(away, opts)` with the presets `fade`, `pop`, `below`, `above`, `left` and `right`. The most recent call wins, also across combat.
- Combat lockdown: alpha animates, `x`, `y` and `scale` draw through native animations, and `width` and `height` wait for combat to end. Polymorph never calls a blocked function.
- One shared driver, with no per-animation timers.
- Textures and font strings animate like frames, locked in combat by their own `IsProtected()`.
- `m:define(values, write, opts)` adds your own values to a handle, such as a color, a number or how much text shows. They retarget, spring, tween, delay and complete like the built-in properties, with one writer call per update. `opts.precision` sets how close a value must come to arrive. `docs/api.md` has a number counter, a typewriter and a color fade.
- Native tweens: `alpha`, `x` and `y` tweens with `linear`, `inSine`, `outSine` or `inOutSine` run as the game's own animations, with no Lua per frame. One shared timer starts them on the next frame.
- `x` and `y` move every anchor of the frame, so a frame with two anchors slides whole. Anchors that other code sets (layouts, pools, frame movers) become the frame's home, and Polymorph never overwrites them. A slide in progress stops there.
- `stop()` with no name also cancels a running `show()` or `hide()`, so a pooled frame can be reused safely.
- A call on a frame that arrives while Polymorph is working on that same frame, such as from a hook on its `SetPoint`, runs right after that work finishes, so the call made last wins.
- An error on one frame, from a game call or an `onComplete`, goes to the game's error handler once, unless it happens during a call such as `to()`, which raises it to its caller instead. Every other frame keeps animating. After an error in Polymorph's work on a frame, from a game call, an ease, a `define()` writer or a hook, Polymorph starts that frame over as if it had just met it, keeping only its rest values and defined values: its animations stop, nothing queued for it runs (no `onComplete`, `show()` or `hide()`), and no later call writes a value from before the error. A call such as `to()` then raises the error to its caller.
