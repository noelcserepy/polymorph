# Changelog

## Unreleased

First version.

- `Poly(frame):to(targets, opts)` animates `alpha`, `x`, `y`, `width`, `height` and `scale`, with springs (react-spring presets or custom stiffness, damping and mass) or tweens (named easings or any cubic-bezier).
- Retargeting continues from the current value. Springs keep their velocity.
- `delay` and `onComplete` on every call.
- `set`, `stop`, `get`, `isMoving`.
- `show(away, opts)` and `hide(away, opts)` with the presets `fade`, `pop`, `below`, `above`, `left` and `right`. The most recent call wins, also across combat.
- Combat lockdown: alpha animates, `x`, `y` and `scale` draw through native animations, and `width` and `height` wait for combat to end. Polymorph never calls a blocked function.
- One shared driver, with no per-animation timers.
- Native tweens: `alpha`, `x` and `y` tweens with `linear`, `inSine`, `outSine` or `inOutSine` run as the game's own animations, with no Lua per frame. One shared timer starts them on the next frame.
