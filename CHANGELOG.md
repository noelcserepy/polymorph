# Changelog

## Unreleased

First version.

- `Poly(frame):to(targets, opts)` animates `alpha`, `x`, `y`, `width`, `height` and `scale`, with springs (react-spring presets or custom stiffness, damping and mass) or tweens (named easings or any cubic-bezier).
- Retargeting continues from the current value. Springs keep their velocity.
- `delay` and `onComplete` on every call.
- `set`, `stop`, `get`, `isMoving`.
- `show(away, opts)` and `hide(away, opts)` with the presets `fade`, `pop`, `below`, `above`, `left` and `right`.
- Combat lockdown: alpha animates, `x` and `y` draw through a native animation, and other blocked properties wait for combat to end. Polymorph never calls a blocked function.
- One shared driver, with no per-animation timers.
