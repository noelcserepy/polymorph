-- Offline tests for Polymorph.lua against a fake frame API. Runs on Lua 5.1+.
-- Usage: lua tests/core_test.lua Polymorph.lua
--        TEST="native slide" lua tests/core_test.lua Polymorph.lua

-- What the fake assumes about the game
--
-- Each behavior the fakes below copy from the client, with the in-game job that
-- measured it, or "unmeasured". The jobs and their notes are the maintainer's
-- private harness. A change to a fake updates its line here. The unmeasured
-- lines are the checklist for the next in-game session.
--
-- Clock and frame order:
-- GetTickTime() equals OnUpdate's elapsed, also in job code and C_Timer callbacks: tick_time.lua, 2026-10-15
-- GetTime() holds still within a frame and grows by OnUpdate's elapsed between frames: unmeasured
-- A group's elapsed read in OnUpdate is GetTime() minus GetTime() in the frame it was played: anim_clock.lua, 2026-10-15
-- Animations advance after scripts, so a group drawn in the frame it was played already counts it: anim_clock.lua, draw_lag.lua, 2026-10-15
-- Timer callbacks run before the frame's OnUpdate scripts: start_timing.lua, 2026-10-15 (60 of 60)
-- Event code runs before the frame's OnUpdate: unmeasured
-- A timer callback and an OnUpdate script in the same frame are separate callbacks: regions_gradient2.lua, 2026-10-15
-- C_Timer.After(0, fn) runs fn in the next frame: start_timing.lua, 2026-10-15 (60 of 60)
-- OnFinished fires in the animation step of the frame whose elapsed reaches the duration, before drawing: unmeasured
--
-- Combat:
-- A frame is locked when InCombatLockdown() and frame:IsProtected(), and a plain frame accepts everything: probe session 1, 2026-10-14
-- SetPoint, SetSize and Hide are blocked on a locked frame: probe session 1, 2026-10-14
-- SetWidth, SetHeight, SetScale and Show are blocked on a locked frame: unmeasured
-- SetAlpha, CreateAnimationGroup and native Alpha, Translation and Scale groups work on a locked frame: probe session 1, 2026-10-14
-- Writers work again when PLAYER_REGEN_ENABLED fires: combat.lua, 2026-10-14 (the library commits in that handler, 0 blocked actions)
-- InCombatLockdown() is false inside PLAYER_REGEN_ENABLED handlers: unmeasured
-- A texture or font string of a SecureActionButtonTemplate button reports IsProtected() false, before and in
--   combat, while the button reports true: regions.lua, regions_combat.lua, 2026-10-15
-- SetPoint, SetSize, SetWidth, SetHeight, SetScale, Show and Hide, each called once in combat on a texture of
--   such a button, raised 0 blocked actions: regions_combat.lua, 2026-10-15. Show, SetScale, SetWidth,
--   SetHeight and Hide read back applied. SetPoint and SetSize failed an exact comparison, which the same
--   calls fail out of combat too (30.000002 and 59.999905): regions_measure.lua, 2026-10-15
-- The same calls on a font string of a protected frame in combat: unmeasured. fakeRegion treats a region like a
--   frame, locked by its own IsProtected().
-- SetText, SetVertexColor and SetAlphaGradient on regions of protected frames in combat raised 0 blocked actions,
--   and the text and color read back changed: regions_combat.lua, 2026-10-15. SetTextColor in combat: unmeasured
-- Deliberate difference: a blocked call errors here. The game returns normally, skips it, fires ADDON_ACTION_BLOCKED and shows a popup: probe session 1, 2026-10-14
--
-- Getters:
-- GetPoint() ignores animation displacement: native_probe.lua, native_puppet.lua, combat.lua, 2026-10-14
-- GetAlpha(), GetScale() and GetWidth() read from OnUpdate report the frame's own values under native animations:
--   native_curves.lua, 2026-10-14. Read from a C_Timer callback, GetAlpha() reports the drawn alpha, on frames,
--   textures and font strings: regions_measure.lua, regions_gradient.lua, 2026-10-15. The fake always reports
--   the own value. The library reads GetAlpha() only for a property with no track.
-- GetHeight() does the same: unmeasured
-- Getters return exactly the value last set, with no float rounding. Measured otherwise: SetAlpha(0.5) reads
--   0.50196 (1/255 steps), and a texture's SetPoint(..., 100) reads 99.99999: regions.lua, 2026-10-15
-- IsShown() reports the frame's own shown flag: unmeasured
--
-- Native animations:
-- The NONE, IN, OUT and IN_OUT smoothing curves have the formulas in CURVES: native_curves.lua, 2026-10-14
-- GetSmoothProgress() is the curve applied to GetProgress(): native_curves.lua, 2026-10-14
-- Play(true) runs progress from 1 to 0 through the curve and fires OnFinished: native_reverse.lua, 2026-10-14
-- GetProgress() is elapsed / duration, capped at 1: unmeasured
-- Play() restarts from progress 0 and clears a SetSmoothProgress() value: unmeasured
-- Pause() holds the drawn displacement: native_probe.lua, 2026-10-14
-- SetSmoothProgress() on a paused animation sets its drawn progress: native_puppet.lua, 2026-10-14
-- A SetSmoothProgress() value holds while its group plays unpaused: unmeasured
-- SetOffset() and SetScaleTo() on a paused animation move the drawing live: native_puppet.lua, 2026-10-14
-- Stop() removes the displacement: native_puppet.lua, 2026-10-14
-- Stopping a paused Translation and calling SetPoint() at the same offset lands on the same pixel: native_probe.lua, 2026-10-14
-- Stop() does not fire OnFinished: unmeasured
-- SetPoint(final) then Play(true) from the start offset draws the start in the group's first frame from a
--   C_Timer callback: native_order.lua, 2026-10-15 (0 of 32 recorded starts misdrew). From OnUpdate it can
--   draw the offset against the anchor from before the frame's scripts for 1-2 frames (3 of 8 starts).
--   The fake misdraws every such start from OnUpdate, for one frame. Polymorph's start timer: native_contexts.lua,
--   2026-10-15 (96 recorded starts at 120 fps, called from a timer, an OnUpdate, a delay and onComplete, 0 flagged).
-- A finished group stops drawing, so the frame draws its own values again: native_order.lua, 2026-10-15 (SetPoint in OnFinished, no snap in 32 recorded finishes)
-- A group finishes when its longest animation ends: unmeasured
-- IsPlaying() is true while paused, and false after Stop() or finishing: unmeasured (the library does not call it)
-- Anchor offsets are in the frame's own scaled units: scale_units.lua, 2026-10-14
-- Translation offsets are in the frame's scaled units, and a Scale in the same group does not multiply them: scale_compose.lua, scale_units.lua, 2026-10-14
-- A Scale grows around its origin, CENTER by default, and SetOrigin(point) keeps that point still: scale_compose.lua, 2026-10-14
-- SetOrigin()'s x and y are in the frame's own units: unmeasured (the library passes 0, 0)
-- An Alpha animation's value replaces the frame's alpha: native_tweens.lua, 2026-10-15
-- Translation groups on one frame add up: native_tweens.lua, 2026-10-15
-- Two Translations in one group add up: unmeasured (the probe's group had finished)
-- Scale groups on one frame multiply, and the last playing Scale's origin wins: unmeasured
-- Of two playing Alpha animations on one frame, the last one created draws: unmeasured
-- A new animation lasts 1 s with NONE smoothing: unmeasured (the library sets both)
-- Textures and font strings have every method the library calls: regions.lua, 2026-10-15
-- Polymorph's native Alpha and Translation tweens start and play on textures and font strings, and draw at the
--   same x and brightness as a Lua tween on the same curve: regions_measure.lua, 2026-10-15
-- Scale animations on textures and font strings: unmeasured
--
-- Region methods:
-- FontString:SetAlphaGradient(start, length) shows `start` characters and fades the next `length` out. It counts
--   on across wrapped lines, a UTF-8 character counts once, and |c color codes don't count:
--   regions_measure.lua, regions_gradient.lua, 2026-10-15. ClearAlphaGradient() shows it all: regions.lua, 2026-10-15
-- SetText, even of the same string, clears the drawn gradient, and a gradient set later in the same callback
--   doesn't draw. One set in a later callback, such as an OnUpdate after a timer in the same frame, does:
--   regions_gradient.lua, regions_gradient2.lua, 2026-10-15. The fake models callbacks as test code, each
--   timer, and the driver's OnUpdate.
--
-- Strings:
-- string.format errors on %d and %i outside the 32-bit range: unmeasured
--
-- The fake's asserts on SetScaleFrom(1, 1), uniform SetScaleTo() and known smoothing names check the
-- library's own calls, and claim nothing about the game. It does not model the per-addon caps of 2000
-- animation groups and 500 timers, measured in the startup log on 2026-10-14.

local path = assert(arg[1], "path to Polymorph.lua")

local combat = false
local driverScript
local eventHandlers = {}
_G.InCombatLockdown = function() return combat end
_G.debugprofilestop = function() return os.clock() * 1000 end
local clock, tick = 0, 1 / 60
_G.GetTime = function() return clock end
_G.GetTickTime = function() return tick end
_G.CreateFrame = function()
  local f = {}
  function f:SetScript(name, fn)
    if name == "OnUpdate" then driverScript = fn else self.onEvent = fn end
  end
  function f:RegisterEvent(e)
    eventHandlers[e] = eventHandlers[e] or {}
    table.insert(eventHandlers[e], self)
  end
  return f
end
local function fire(e)
  for _, f in ipairs(eventHandlers[e] or {}) do f.onEvent(f, e) end
end
local frameNumber, timers = 0, {}
-- Which callback the game is in. SetText clears the gradient for the rest of it.
local callback = 0
_G.C_Timer = {
  After = function(seconds, fn)
    timers[#timers + 1] = { due = clock + seconds, frame = frameNumber, fn = fn }
  end,
}
-- Runs the timers due this frame, never one made in this frame.
local function runTimers()
  local due = {}
  for i = #timers, 1, -1 do
    local t = timers[i]
    if t.frame < frameNumber and t.due <= clock then
      table.remove(timers, i)
      table.insert(due, 1, t)
    end
  end
  for _, t in ipairs(due) do
    callback = callback + 1
    t.fn()
  end
end
-- The recorded misdraw: a Translation group played from OnUpdate draws its first
-- frame against the anchor the frame had before that frame's scripts ran.
local inOnUpdate, misdrawn = false, {}
local function clearMisdraws()
  for _, f in ipairs(misdrawn) do f.pointBefore, f.staleAnchor = nil, nil end
  misdrawn = {}
end

-- The game's smoothing curves, measured in native_curves.lua.
local CURVES = {
  NONE = function(p) return p end,
  IN = function(p) return 1 - math.cos(p * math.pi / 2) end,
  OUT = function(p) return math.sin(p * math.pi / 2) end,
  IN_OUT = function(p) return (1 - math.cos(p * math.pi)) / 2 end,
}
local allGroups = {}
-- Native animations advance after the frame's scripts, as anim_clock.lua measured.
-- When in the frame OnFinished fires is unmeasured.
local function advanceAnimations(dt)
  for _, ag in ipairs(allGroups) do
    if ag.playing and not ag.paused then
      ag.elapsed = ag.elapsed + dt
      local longest = 0
      for _, a in ipairs(ag.anims) do longest = math.max(longest, a.duration) end
      if ag.elapsed >= longest then
        ag.playing = false
        if ag.onFinished then ag.onFinished(ag) end
      end
    end
  end
end

local function fakeFrame(protected)
  local f = { alpha = 1, w = 100, h = 50, s = 1, point = { "CENTER", nil, "CENTER", 10, 20 }, pointCalls = 0 }
  function f:GetAlpha() return self.alpha end
  function f:SetAlpha(v) self.alpha = v end
  function f:GetWidth() return self.w end
  function f:SetWidth(v) assert(not (combat and protected), "SetWidth while locked"); self.w = v end
  function f:GetHeight() return self.h end
  function f:SetHeight(v) assert(not (combat and protected), "SetHeight while locked"); self.h = v end
  f.sizeCalls = 0
  function f:SetSize(w, h)
    assert(not (combat and protected), "SetSize while locked")
    self.w, self.h = w, h
    self.sizeCalls = self.sizeCalls + 1
  end
  function f:GetScale() return self.s end
  function f:SetScale(v) assert(not (combat and protected), "SetScale while locked"); self.s = v end
  function f:GetPoint() return unpack(self.point, 1, 5) end
  function f:SetPoint(a, b, c, x, y)
    assert(not (combat and protected), "SetPoint while locked")
    if inOnUpdate and not self.pointBefore then
      self.pointBefore = self.point
      misdrawn[#misdrawn + 1] = self
    end
    self.point = { a, b, c, x, y }
    self.pointCalls = self.pointCalls + 1
  end
  function f:IsProtected() return protected end
  function f:IsObjectType(kind) return kind == "Frame" end
  function f:GetParent() return nil end
  -- Native animation groups. Progress runs over the duration, backwards when
  -- played in reverse, through the smoothing curve. A Translation offset is in
  -- the frame's scaled units and ignores any Scale. A Scale grows the frame
  -- around its origin, CENTER by default. An Alpha draws its own value in place
  -- of the frame's. Translation groups on one frame add up. How Scale and Alpha
  -- groups combine is unmeasured. The list at the top says which parts are measured.
  local groups = {}
  function f:CreateAnimationGroup()
    local ag = { playing = false, paused = false, reverse = false, elapsed = 0, anims = {} }
    groups[#groups + 1] = ag
    allGroups[#allGroups + 1] = ag
    function ag:CreateAnimation(kind)
      local a = { kind = kind, duration = 1, smoothing = "NONE", ox = 0, oy = 0, k = 1, origin = { "CENTER", 0, 0 } }
      function a:SetDuration(d) self.duration = d end
      function a:SetSmoothing(v) assert(CURVES[v], v); self.smoothing = v end
      function a:SetSmoothProgress(v) self.forced = v end
      function a:GetProgress()
        local p = math.min(1, ag.elapsed / self.duration)
        return ag.reverse and 1 - p or p
      end
      function a:GetSmoothProgress() return self.forced or CURVES[self.smoothing](self:GetProgress()) end
      function a:SetScaleFrom(x, y) assert(x == 1 and y == 1) end
      function a:SetScaleTo(x, y) assert(x == y); self.k = x end
      function a:SetOrigin(point, x, y) self.origin = { point, x or 0, y or 0 } end
      function a:SetOffset(x, y) self.ox, self.oy = x, y end
      function a:SetFromAlpha(v) self.from = v end
      function a:SetToAlpha(v) self.to = v end
      ag.anims[#ag.anims + 1] = a
      return a
    end
    function ag:Play(reverse)
      self.playing, self.paused, self.reverse, self.elapsed = true, false, reverse or false, 0
      for _, a in ipairs(self.anims) do
        a.forced = nil
        if inOnUpdate and a.kind == "Translation" then
          f.staleAnchor = f.pointBefore or f.point
          misdrawn[#misdrawn + 1] = f
        end
      end
    end
    function ag:Pause() self.paused = true end
    function ag:Stop() self.playing = false end
    function ag:IsPlaying() return self.playing end
    function ag:SetScript(name, fn) assert(name == "OnFinished"); self.onFinished = fn end
    return ag
  end
  -- What every playing group adds: translation, scale and its origin, alpha.
  function f:Native()
    local x, y, k, origin, alpha = 0, 0, 1, { "CENTER", 0, 0 }, nil
    for _, ag in ipairs(groups) do
      if ag.playing then
        for _, a in ipairs(ag.anims) do
          local sp = a:GetSmoothProgress()
          if a.kind == "Translation" then
            x, y = x + a.ox * sp, y + a.oy * sp
          elseif a.kind == "Scale" then
            k, origin = k * (1 + (a.k - 1) * sp), a.origin
          elseif a.kind == "Alpha" then
            alpha = a.from + (a.to - a.from) * sp
          end
        end
      end
    end
    return x, y, k, origin, alpha
  end
  -- Where a named point of the frame sits, relative to its center, in its own units.
  local function pointOffset(point, w, h)
    local x = point:find("LEFT") and -w / 2 or point:find("RIGHT") and w / 2 or 0
    local y = point:find("TOP") and h / 2 or point:find("BOTTOM") and -h / 2 or 0
    return x, y
  end
  -- Where the anchor point draws, in parent units, and the drawn scale and alpha.
  function f:Visual()
    local nx, ny, k, o = self:Native()
    local s = self.s
    local point = self.staleAnchor or self.point
    local ax, ay = (point[4] + nx) * s, (point[5] + ny) * s
    local px, py = pointOffset(point[1], self.w, self.h)
    local ox, oy = pointOffset(o[1], self.w, self.h)
    ox, oy = ox + o[2], oy + o[3]
    -- The origin stays put and everything else scales away from it by k.
    local originX, originY = ax + (ox - px) * s, ay + (oy - py) * s
    return originX + (ax - originX) * k, originY + (ay - originY) * k
  end
  function f:VisualX() return (self:Visual()) end
  function f:VisualY() return select(2, self:Visual()) end
  function f:VisualScale() return self.s * select(3, self:Native()) end
  function f:VisualAlpha() return select(5, self:Native()) or self.alpha end
  f.shown = true
  f.hideCalls = 0
  function f:IsShown() return self.shown end
  function f:Show() assert(not (combat and protected), "Show while locked"); self.shown = true end
  function f:Hide()
    assert(not (combat and protected), "Hide while locked")
    self.shown = false
    self.hideCalls = self.hideCalls + 1
  end
  return f
end
unpack = unpack or table.unpack

-- A texture or font string of `parent`. Like a frame, it is locked by its own
-- IsProtected(), which is false on a protected button as measured. `gradient`
-- is what draws: SetText clears it, and a gradient set later in the same
-- callback doesn't draw.
local function fakeRegion(parent, protected)
  local r = fakeFrame(protected)
  function r:IsObjectType(kind) return kind == "Region" end
  function r:GetParent() return parent end
  function r:SetText(text)
    self.text, self.gradient, self.textCallback = text, nil, callback
  end
  function r:GetText() return self.text end
  function r:SetAlphaGradient(start, length)
    if self.textCallback ~= callback then self.gradient = { start, length } end
  end
  function r:ClearAlphaGradient() self.gradient = nil end
  r.color = { 1, 1, 1 }
  function r:SetVertexColor(red, green, blue) self.color = { red, green, blue } end
  function r:GetVertexColor() return unpack(self.color) end
  return r
end

dofile("tests/format_fake.lua")
assert(not pcall(string.format, "%d", 2 ^ 31) and pcall(string.format, "%d", 2 ^ 31 - 1), "%d fake")

local ns = { dev = true }
assert(loadfile(path))("Polymorph", ns)
local Poly = ns.Polymorph

-- Runs frames as the client does: timers, then OnUpdate, then animations, then
-- drawing. Test code between calls runs at the start of the next frame, as an
-- event does, so GetTickTime() is that frame's elapsed time and Visual() what
-- the last frame drew. That events and timers run before OnUpdate is unmeasured.
local function run(seconds, fps)
  local dt = 1 / (fps or 60)
  for _ = 1, math.floor(seconds / dt + 0.5) do
    clearMisdraws()
    runTimers()
    if driverScript then
      callback = callback + 1
      inOnUpdate = true
      driverScript(nil, tick)
      inOnUpdate = false
    end
    advanceAnimations(tick)
    clock, tick = clock + dt, dt
    frameNumber = frameNumber + 1
    callback = callback + 1 -- test code after this runs as the next frame's event
  end
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local passed = 0
-- TEST=text runs only the tests whose names contain text.
local only = os.getenv("TEST")
local function test(name, fn)
  if only and not name:find(only, 1, true) then return end
  fn(); passed = passed + 1; print("ok " .. name)
end

test("bezier matches CSS ease at 0.5", function()
  assert(near(Poly.easings.ease(0.5), 0.8024, 1e-3), Poly.easings.ease(0.5))
  assert(near(Poly.easings.easeInOut(0.5), 0.5, 1e-6))
end)

test("spring settles exactly and the driver stops", function()
  local f = fakeFrame()
  f.alpha = 0
  Poly(f):to({ alpha = 1 })
  run(2)
  assert(f.alpha == 1, f.alpha)
  assert(driverScript == nil, "driver still running")
  assert(Poly.stats().active == 0)
end)

test("tween follows its curve and calls onComplete once", function()
  local f = fakeFrame()
  local calls = 0
  Poly(f):to({ width = 300 }, { duration = 0.25, ease = "outCubic", onComplete = function() calls = calls + 1 end })
  run(0.125, 120)
  -- The first frame ran at the previous 60 fps.
  assert(near(f.w, 100 + 200 * Poly.easings.outCubic((1 / 60 + 14 / 120) / 0.25), 1e-6), f.w)
  run(0.5)
  assert(f.w == 300 and calls == 1, f.w .. " " .. calls)
end)

test("x and y are offsets from the original anchor", function()
  local f = fakeFrame()
  Poly(f):to({ x = 40, y = -10 }, { duration = 0.1 })
  run(0.5)
  assert(f.point[4] == 50 and f.point[5] == 10, f.point[4] .. "," .. f.point[5])
end)

test("retarget keeps value and velocity continuous", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:to({ x = 200 })
  run(0.15)
  local before, velocity = m:get("x")
  assert(velocity > 0)
  m:to({ x = 0 })
  local after, velocityAfter = m:get("x")
  assert(before == after and velocity == velocityAfter, "jump on retarget")
  run(3)
  assert(m:get("x") == 0 and not m:isMoving())
end)

test("protected frame in combat: x moves through the puppet, width waits", function()
  local f = fakeFrame(true)
  combat = true
  Poly(f):to({ alpha = 0, x = 50, width = 160 }, { duration = 0.2 })
  run(0.5)
  assert(f.alpha == 0, "alpha did not animate in combat")
  assert(f.pointCalls == 0 and f.w == 100, "layout written while locked")
  assert(f:VisualX() == 60, "puppet did not show x: " .. f:VisualX())
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(f.point[4] == 60 and f:Native() == 0 and f:VisualX() == 60, "commit moved the frame")
  run(0.5)
  assert(f.w == 160, "width not applied after combat")
end)

test("protected frame in combat: scale draws through the puppet and hands over without a jump", function()
  local f = fakeFrame(true)
  f.point = { "TOPLEFT", nil, "TOPLEFT", 10, 20 } -- a corner anchor, so the scale origin matters
  local m = Poly(f)
  combat = true
  m:to({ scale = 2, x = 30 }, { duration = 1, ease = "linear" })
  run(0.5)
  local s, x = m:get("scale"), m:get("x")
  assert(f.s == 1 and f.pointCalls == 0, "layout written while locked")
  assert(near(f:VisualScale(), s), "puppet scale " .. f:VisualScale() .. " vs " .. s)
  -- Where SetScale(s) with the anchor at 10 + x would draw it.
  assert(near(f:VisualX(), (10 + x) * s) and near(f:VisualY(), 20 * s), "anchor point " .. f:VisualX() .. "," .. f:VisualY())
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(f.s == s and select(3, f:Native()) == 1 and f:Native() == 0, "not committed")
  assert(near(f:VisualX(), (10 + x) * s) and near(f:VisualY(), 20 * s), "jump at handover")
  run(1)
  assert(f.s == 2 and f.point[4] == 40)
end)

test("combat ending mid-animation hands over without a jump", function()
  local f = fakeFrame(true)
  combat = true
  Poly(f):to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.5)
  local mid = f:VisualX()
  assert(f.pointCalls == 0 and mid > 40 and mid < 70, "puppet not tracking: " .. mid)
  combat = false
  run(1 / 60)
  assert(f:Native() == 0 and math.abs(f:VisualX() - mid) < 2, "jump at handover")
  run(1)
  assert(f.point[4] == 110)
end)

test("x and y share one SetPoint per update, width and height one SetSize", function()
  local f = fakeFrame()
  Poly(f):to({ x = 50, y = 20, width = 200, height = 80 }, { duration = 0.5 })
  run(0.1)
  assert(f.pointCalls == 6 and f.sizeCalls == 6, f.pointCalls .. " SetPoint, " .. f.sizeCalls .. " SetSize in 6 updates")
  run(0.5)
  assert(f.point[4] == 60 and f.point[5] == 40 and f.w == 200 and f.h == 80)
end)

test("native tween: drawn by the game on the measured curve, no Lua per frame", function()
  local f = fakeFrame()
  f.alpha = 0
  local m = Poly(f)
  local done = 0
  m:to({ alpha = 1, x = 100 }, { duration = 1, ease = "outSine", onComplete = function() done = done + 1 end })
  -- It holds for this frame, and the timer starts it in the next.
  run(1 / 60)
  assert(f:VisualAlpha() == 0 and f:VisualX() == 10, "moved before the start timer")
  assert(driverScript == nil, "driver still running for native tweens")
  assert(Poly.stats().active == 1, "stats() does not count a natively moving frame")
  run(1 / 60)
  assert(f.alpha == 1 and f.point[4] == 110, "final values not written first")
  run(0.5 - 2 / 60)
  local want = math.sin(math.pi / 2 * (0.5 - 1 / 60))
  assert(near(f:VisualAlpha(), want, 1e-3) and near(f:VisualX(), 10 + 100 * want, 0.1), f:VisualAlpha() .. " " .. f:VisualX())
  assert(near(m:get("alpha"), f:VisualAlpha(), 1e-3) and near(m:get("x") + 10, f:VisualX(), 0.1), "get() differs from drawing")
  run(0.6)
  assert(done == 1 and not m:isMoving(), "not finished once")
  assert(f:VisualAlpha() == 1 and f:VisualX() == 110 and f.pointCalls == 1, "did not land on the target")
end)

test("a native tween draws like a Lua tween started at the next frame's start", function()
  -- Measured in draw_lag.lua: a linear Lua tween drew on the same pixel as the
  -- game's own animation started with it. Polymorph starts native tweens from
  -- the next frame's timer, so a native tween started by an event draws one
  -- frame behind a Lua one, and one started after the driver draws with it.
  local function compare(native, lua)
    for _ = 1, 30 do
      run(1 / 60)
      assert(near(native:VisualX(), lua:VisualX(), 1e-6), native:VisualX() .. " vs " .. lua:VisualX())
    end
    run(1)
  end
  local native, lua = fakeFrame(), fakeFrame()
  Poly(native):to({ x = 100 }, { duration = 1, ease = "linear" })
  run(1 / 60)
  Poly(lua):to({ x = 100 }, { duration = 1, ease = function(p) return p end })
  compare(native, lua)

  native, lua = fakeFrame(), fakeFrame()
  Poly(fakeFrame()):to({ alpha = 0.5 }, { duration = 0, onComplete = function()
    Poly(native):to({ x = 100 }, { duration = 1, ease = "linear" })
    Poly(lua):to({ x = 100 }, { duration = 1, ease = function(p) return p end })
  end })
  compare(native, lua)
end)

test("a native slide draws inside its path from the first frame, wherever it starts", function()
  -- Recorded in native_order.lua: a Translation started from OnUpdate drew a
  -- frame or two against the old anchor, far outside the slide.
  local function check(f, label)
    for frame = 1, 8 do
      run(1 / 60)
      local x = f:VisualX()
      assert(x >= 10 and x <= 110, label .. ": frame " .. frame .. " drew at " .. x)
    end
    run(1)
    assert(f:VisualX() == 110, label .. " did not land")
  end
  local f = fakeFrame()
  Poly(f):to({ x = 100 }, { duration = 0.5, ease = "outSine" })
  check(f, "from an event")

  f = fakeFrame()
  Poly(f):to({ x = 100 }, { duration = 0.5, ease = "outSine", delay = 0.05 })
  check(f, "after a delay")

  f = fakeFrame()
  Poly(f):to({ alpha = 0.5 }, { duration = 0, onComplete = function()
    Poly(f):to({ x = 100 }, { duration = 0.5, ease = "outSine" })
  end })
  check(f, "from a callback")
end)

test("a tween queued while the start timer runs starts on the next timer", function()
  -- pr-reviewer's case: a SetPoint hook queued two starts mid-drain, which
  -- overwrote a waiting start, so that tween never moved.
  local first, waiting, nested = fakeFrame(), fakeFrame(), fakeFrame()
  local setPoint, once = first.SetPoint, false
  function first:SetPoint(...)
    setPoint(self, ...)
    if not once then
      once = true
      Poly(nested):to({ x = 40, y = 40 }, { duration = 0.5, ease = "linear" })
    end
  end
  Poly(first):to({ x = 100 }, { duration = 0.5, ease = "linear" })
  Poly(waiting):to({ x = 100 }, { duration = 0.5, ease = "linear" })
  run(1)
  for _, f in ipairs({ first, waiting, nested }) do
    assert(not Poly(f):isMoving(), "a tween never finished")
  end
  assert(waiting.point[4] == 110 and nested.point[4] == 50 and nested.point[5] == 60, "did not land")
end)

test("a retarget keeps the value, however often and wherever in the frame it runs", function()
  -- pr-reviewer's case: each of ten native retargets in one frame moved x.
  local f = fakeFrame()
  local m = Poly(f)
  m:to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.5)
  local x, drawn = m:get("x"), f:VisualX()
  assert(near(x + 10, drawn), "get " .. x .. " vs drawn " .. drawn)
  for _ = 1, 10 do m:to({ x = 1000 }, { duration = 1, ease = "linear" }) end
  assert(near(m:get("x"), x) and near(f:VisualX(), drawn), "retargets moved x to " .. m:get("x"))
  run(0.25)
  -- The retarget holds one frame for the start timer.
  assert(near(m:get("x"), x + (1000 - x) * (0.25 - 1 / 60)) and near(m:get("x") + 10, f:VisualX()), "x " .. m:get("x"))
  run(1)

  -- A retarget after the driver has moved the frame this time, from a callback.
  local g = fakeFrame()
  local n = Poly(g)
  n:to({ x = 100 }, { duration = 1, ease = function(p) return p end })
  local h = fakeFrame()
  n:to({ alpha = 0.5 }, { duration = 0.25, ease = function(p) return p end, onComplete = function()
    x = n:get("x")
    n:to({ x = 0 }, { duration = 1, ease = "linear" })
    assert(near(n:get("x"), x), "callback retarget moved x from " .. x .. " to " .. n:get("x"))
    -- pr-reviewer's case: a track made here, retargeted at once, then stopped.
    Poly(h):to({ x = 100 }, { duration = 1, ease = function(p) return p end })
    Poly(h):to({ x = 1000 }, { duration = 1, ease = "linear" }):stop("x")
    assert(Poly(h):get("x") == 0 and h:VisualX() == 10, "new track moved to " .. Poly(h):get("x"))
  end })
  run(0.5)
  assert(near(n:get("x") + 10, g:VisualX()), "get " .. n:get("x") .. " vs drawn " .. g:VisualX())
  run(1)
end)

test("native tween: retarget, stop and set continue from where it draws", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.5)
  local drawn = f:VisualX()
  m:to({ x = 0 })
  local x, velocity = m:get("x")
  assert(near(f:VisualX(), drawn) and near(x + 10, drawn) and near(velocity, 100, 1), "retarget jumped: " .. f:VisualX() .. " v " .. velocity)
  run(3)
  assert(f:VisualX() == 10 and not m:isMoving())

  m:to({ x = 100, alpha = 0 }, { duration = 1, ease = "inOutSine" })
  run(0.3)
  drawn = f:VisualX()
  m:stop("x")
  assert(near(f:VisualX(), drawn) and f:Native() == 0 and not m:isMoving("x"), "stop moved the frame")
  m:set({ alpha = 0.3 })
  assert(f:VisualAlpha() == 0.3 and not m:isMoving(), "set did not take over the native alpha")
end)

test("native tween on a protected frame: combat midway blocks nothing, retarget goes to the puppet", function()
  local f = fakeFrame(true)
  local m = Poly(f)
  m:to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.3)
  combat = true
  run(0.2)
  local drawn = f:VisualX()
  assert(near(drawn, 10 + 100 * (0.5 - 1 / 60), 1e-6), "native move stopped in combat: " .. drawn)
  m:to({ x = 0 }, { duration = 0.5 })
  assert(near(f:VisualX(), drawn), "jump when the puppet took over")
  run(1)
  assert(f:VisualX() == 10, f:VisualX())
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(f.point[4] == 10 and f:Native() == 0)
end)

test("native tween on a protected frame: scale in combat composes with the drawn position", function()
  for _, change in ipairs({ "set", "to" }) do
    local f = fakeFrame(true)
    local m = Poly(f)
    m:to({ x = 100, y = 100 }, { duration = 1, ease = "linear" })
    run(0.5)
    combat = true
    if change == "set" then m:set({ scale = 2 }) else m:to({ scale = 2 }, { duration = 0.5, ease = "linear" }) end
    run(0.25)
    local s = m:get("scale")
    assert(near(f:VisualX(), (10 + m:get("x")) * s, 1e-6) and near(f:VisualY(), (20 + m:get("y")) * s, 1e-6),
      change .. ": drawn " .. f:VisualX() .. "," .. f:VisualY() .. " want " .. (10 + m:get("x")) * s .. "," .. (20 + m:get("y")) * s)
    run(2)
    combat = false
    fire("PLAYER_REGEN_ENABLED")
    assert(near(f:VisualX(), 220) and near(f:VisualY(), 240) and f.s == 2, change .. ": did not land")
  end
end)

test("native tween handed to Lua in combat keeps its timeline", function()
  -- Scale in combat hands x to the puppet: it continues, and ends on time.
  local f = fakeFrame(true)
  local m = Poly(f)
  local done = 0
  m:to({ x = 100, y = 100 }, { duration = 1, ease = "linear", onComplete = function() done = done + 1 end })
  run(0.5)
  combat = true
  m:set({ scale = 2 })
  local before = m:get("x")
  run(1 / 60)
  assert(m:get("x") > before and near(f:VisualX(), (10 + m:get("x")) * 2, 1e-6), "restarted: " .. before .. " -> " .. m:get("x"))
  run(0.5 + 1 / 60) -- it started a frame after the call, and one more frame absorbs clock rounding
  assert(not m:isMoving() and done == 1 and near(f:VisualX(), 220), "did not end on time")
  combat = false
  fire("PLAYER_REGEN_ENABLED")

  -- Combat ending right after the handover: get() still matches the drawing.
  f = fakeFrame(true)
  m = Poly(f)
  m:to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.5)
  combat = true
  m:set({ scale = 2 })
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(1 / 60)
  assert(near(f:VisualX(), (10 + m:get("x")) * m:get("scale"), 1e-6), "get " .. m:get("x") .. " vs drawn " .. f:VisualX())

  -- A scale change that finishes at once must not strand the handed-over tracks.
  f = fakeFrame(true)
  m = Poly(f)
  done = 0
  m:to({ x = 100, y = 100 }, { duration = 1, ease = "linear", onComplete = function() done = done + 1 end })
  run(0.5)
  combat = true
  m:to({ scale = 2 }, { duration = 0 })
  run(2)
  assert(not m:isMoving() and done == 1 and m:get("x") == 100 and m:get("y") == 100, "stranded at " .. m:get("x"))
  combat = false
  fire("PLAYER_REGEN_ENABLED")
end)

test("native tween handed to the puppet mid-update moves one frame's worth, not two", function()
  for _, other in ipairs({ { y = 2 }, { scale = 2 } }) do
    run(0.1, 10) -- every frame from the start lasts 0.1 s
    local f = fakeFrame(true)
    local m = Poly(f)
    m:to({ x = 100 }, { duration = 1, ease = "linear" })
    m:to(other, { duration = 2, ease = "outCubic" })
    run(0.5, 10)
    combat = true
    run(0.1, 10)
    -- x held for the first frame, so it is one frame behind the clock.
    assert(near(m:get("x"), 50, 1e-6), "x " .. m:get("x") .. " at t = 0.6")
    run(0.3, 10)
    assert(near(m:get("x"), 80, 1e-6), "x " .. m:get("x") .. " at t = 0.9")
    combat = false
    fire("PLAYER_REGEN_ENABLED")
    run(2)
  end
end)

test("native tween handed to Lua: a delay waits and velocity carries over", function()
  -- A delayed retarget starts moving only once its delay is over.
  local f = fakeFrame()
  local m = Poly(f)
  m:to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.5)
  local frozen = m:get("x")
  m:to({ x = 0 }, { duration = 1, ease = "outCubic", delay = 0.5 })
  run(0.5)
  assert(near(m:get("x"), frozen, 1e-6), "moved during its delay: " .. m:get("x"))
  run(0.1)
  -- outCubic 48 -> 0, about 0.08 s in: near 37.
  assert(m:get("x") > 35 and m:get("x") < 45, "x " .. m:get("x") .. " 0.1 s after the delay")

  -- A handover in combat keeps the tween's velocity for a spring retarget.
  f = fakeFrame(true)
  m = Poly(f)
  m:to({ x = 100 }, { duration = 1, ease = "linear" })
  run(0.5)
  combat = true
  m:to({ scale = 2 }, { duration = 0.5 })
  run(1 / 60)
  local _, velocity = m:get("x")
  assert(near(velocity, 100, 1e-6), "velocity " .. velocity .. " after the handover")
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(2)
end)

test("native tween: alpha outside 0..1 stays in Lua, so stopping does not jump", function()
  local f = fakeFrame()
  f.alpha = 0
  local m = Poly(f)
  m:to({ alpha = 1 }, { spring = "wobbly" })
  run(0.3)
  assert(m:get("alpha") > 1, "spring did not overshoot")
  m:to({ alpha = 0 }, { duration = 1, ease = "linear" })
  run(0.1)
  local drawn = f:VisualAlpha()
  m:stop("alpha")
  assert(f:VisualAlpha() == drawn, "stop jumped from " .. drawn .. " to " .. f:VisualAlpha())
end)

test("onComplete can start the next animation", function()
  local f = fakeFrame()
  Poly(f):to({ alpha = 0 }, { duration = 0.1, onComplete = function(frame)
    Poly(frame):to({ alpha = 1 }, { duration = 0.1 })
  end })
  run(0.5)
  assert(f.alpha == 1, f.alpha)
end)

test("delay holds the start", function()
  local f = fakeFrame()
  Poly(f):to({ height = 150 }, { duration = 0.1, delay = 0.2 })
  run(0.15)
  assert(f.h == 50, f.h)
  run(0.5)
  assert(f.h == 150)
end)

test("show comes from the preset and lands at rest", function()
  local f = fakeFrame()
  f.shown = false
  Poly(f):show("below", { duration = 0.2 })
  assert(f.shown and f.alpha == 0 and f.point[5] == 4, "show did not start from below")
  run(0.5)
  assert(f.alpha == 1 and f.point[5] == 20, f.alpha .. " " .. f.point[5])
end)

test("hide animates, hides, and resets while hidden", function()
  local f = fakeFrame()
  local finished = false
  Poly(f):hide("pop", { duration = 0.2, onComplete = function() finished = true end })
  run(0.1)
  assert(f.shown and f.alpha < 1 and f.alpha > 0, "hide not animating")
  run(0.5)
  assert(not f.shown and finished, "frame not hidden")
  assert(f.alpha == 1 and f.s == 1, "not reset to rest after hiding")
end)

test("show during a hide turns around without hiding", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("fade", { duration = 0.4 })
  run(0.2)
  m:show("fade", { duration = 0.2 })
  run(0.6)
  assert(f.shown and f.hideCalls == 0 and f.alpha == 1, "hide was not cancelled")
end)

test("protected frame: hide fades in combat and hides after", function()
  local f = fakeFrame(true)
  combat = true
  Poly(f):hide("below", { duration = 0.2 })
  run(0.5)
  assert(f.alpha == 0 and f.shown and f.pointCalls == 0, "hide broke lockdown rules")
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(not f.shown, "not hidden after combat")
end)

test("protected frame: show while hidden in combat waits for combat end", function()
  local f = fakeFrame(true)
  f.shown = false
  combat = true
  Poly(f):show("fade", { duration = 0.1 })
  run(0.3)
  assert(not f.shown, "shown during lockdown")
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.3)
  assert(f.shown and f.alpha == 1, "not shown after combat")
end)

test("show interrupting a hide returns every property the hide moved", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("pop", { duration = 0.4 })
  run(0.2)
  assert(f.s < 1, "hide did not start shrinking")
  m:show("fade", { duration = 0.2 })
  run(0.6)
  assert(f.shown and f.alpha == 1, "not shown at rest alpha")
  assert(f.s == 1 and not m:isMoving("scale"), "scale left away from rest: " .. f.s)
end)

test("protected frame: a hide after a deferred show wins", function()
  local f = fakeFrame(true)
  f.shown = false
  combat = true
  local m = Poly(f)
  m:show("fade", { duration = 0.1 })
  m:hide("fade", { duration = 1 })
  run(0.2)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(1.5)
  assert(not f.shown, "deferred show ran after a later hide")
end)

test("a hide interrupted by another hide keeps every away property", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("pop", { duration = 1 })
  run(0.2)
  m:hide("fade", { duration = 1 })
  m:show("fade", { duration = 0.2 })
  run(1.5)
  assert(f.shown and f.alpha == 1 and f.s == 1, "show left scale away: " .. f.s)
end)

test("a hidden frame is fully at rest after stacked hides", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("pop", { duration = 1 })
  run(0.2)
  m:hide("fade", { duration = 0.2 })
  run(1.5)
  assert(not f.shown, "not hidden")
  assert(f.alpha == 1 and f.s == 1 and not m:isMoving(), "hidden frame not at rest: scale " .. f.s)
end)

test("a hide during a still-restoring show resets everything still off rest", function()
  local f = fakeFrame()
  local m = Poly(f)
  local reachedRest
  m:hide("pop", { duration = 1, ease = "linear" })
  run(0.2)
  m:show("fade", { duration = 2, ease = "linear" })
  m:hide("fade", { duration = 0.1, onComplete = function()
    reachedRest = f.alpha == 1 and f.s == 1 and not m:isMoving()
  end })
  run(0.5)
  assert(not f.shown, "not hidden")
  assert(reachedRest, "frame not at rest when the hide completed: scale " .. f.s)
end)

test("a completed show leaves nothing for the next hide to reset", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("pop", { duration = 0.2 })
  run(0.1)
  m:show("fade", { duration = 0.2 })
  run(0.5)
  m:to({ scale = 1.5 }, { duration = 0.1 })
  run(0.3)
  m:hide("fade", { duration = 0.1 })
  run(0.3)
  assert(not f.shown and f.s == 1.5, "hide reset a property the show had already restored: " .. f.s)
end)

test("taking over one show property keeps the others' own arrival", function()
  local f = fakeFrame()
  f.shown = false
  local m = Poly(f)
  m:show("pop", { duration = 0.2 })
  m:to({ alpha = 1 }, { duration = 0.1 })
  run(0.5)
  m:to({ scale = 1.5 }, { duration = 0.1 })
  run(0.3)
  m:hide("fade", { duration = 0.1 })
  run(0.3)
  assert(not f.shown and f.s == 1.5, "hide reset a property the user had animated: " .. f.s)
end)

test("protected frame: set() during a deferred hide keeps its value", function()
  local f = fakeFrame(true)
  combat = true
  local m = Poly(f)
  m:hide("fade", { duration = 0.1 })
  run(0.3)
  m:set({ alpha = 0.4 })
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(not f.shown and f.alpha == 0.4, "deferred hide reset a taken-over alpha: " .. f.alpha)
end)

test("protected frame: to() during a deferred hide keeps its value", function()
  local f = fakeFrame(true)
  combat = true
  local m = Poly(f)
  m:hide("fade", { duration = 0.1 })
  run(0.3)
  m:to({ alpha = 0.4 }, { duration = 0.1 })
  run(0.3)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(not f.shown and f.alpha == 0.4, "deferred hide reset a taken-over alpha: " .. f.alpha)
end)

test("stop() releases a property that already arrived away from rest", function()
  local f = fakeFrame(true)
  combat = true
  local m = Poly(f)
  m:hide("below", { duration = 0.1 })
  run(0.3)
  m:stop("y")
  m:hide("fade", { duration = 0.1 })
  run(0.3)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(not f.shown and m:get("y") == -16, "hide reset a stopped y: " .. m:get("y"))
end)

-- Random sequences of show, hide, to, set, stop and combat on one frame. A model
-- tracks who owns each property: show() and hide() own what they animate, and
-- to(), set() or stop() hand a property to the caller. Once everything settles,
-- the frame is shown if the last visibility call was show(), properties show()
-- and hide() own are at rest, and the caller's properties hold the caller's value.
test("random show/hide sequences end where the last calls say", function()
  local REST = { alpha = 1, scale = 1, x = 0, y = 0, width = 100 }
  local RANGE = { alpha = { 0, 1 }, scale = { 0.5, 1.5 }, x = { -30, 30 }, y = { -30, 30 }, width = { 50, 150 } }
  local NAMES = { "alpha", "scale", "x", "y", "width" }
  local PRESETS = { "fade", "pop", "below", "above", "left", "right" }
  local state = 1
  local function rand(n) -- Park-Miller, so 5.1 and 5.4 draw the same sequences
    state = state * 16807 % 2147483647
    return n and state % n + 1 or state / 2147483647
  end
  local function value(name) local r = RANGE[name]; return r[1] + (r[2] - r[1]) * rand() end
  local EASES = { "outCubic", "linear", "outSine", "inOutSine" } -- the last three run natively
  local function opts()
    if rand(2) == 1 then return { duration = 0.05 + 0.4 * rand(), ease = EASES[rand(#EASES)] } end
    return { spring = rand(2) == 1 and "stiff" or "gentle" }
  end

  for seed = 1, 300 do
    state = seed
    local protected = rand(2) == 1
    local f = fakeFrame(protected)
    local m = Poly(f)
    local owner = {} -- name -> "vis", or { value } once the caller owns it
    local lastVis, deferredShow
    local log = {}
    local function locked() return combat and protected end
    local function visTakes(away)
      for name in pairs(away) do owner[name] = "vis" end
    end
    local function show(away)
      -- show() also returns what show()/hide() still own, which the model already has as "vis".
      visTakes(Poly.presets[away])
    end
    for _ = 1, 14 do
      local op = rand(8)
      if op == 1 then
        local away = PRESETS[rand(#PRESETS)]
        log[#log + 1] = "show " .. away
        lastVis = "show"
        deferredShow = (not f.shown and locked()) and away or nil
        if not deferredShow then show(away) end
        m:show(away, opts())
      elseif op == 2 then
        local away = PRESETS[rand(#PRESETS)]
        log[#log + 1] = "hide " .. away
        lastVis, deferredShow = "hide", nil
        local animated = {}
        for name, v in pairs(Poly.presets[away]) do
          if not (locked() and name == "width") then animated[name] = v end
        end
        visTakes(animated)
        m:hide(away, opts())
      elseif op <= 4 then
        local name = NAMES[rand(#NAMES)]
        local v = value(name)
        log[#log + 1] = ("%s %s %.2f"):format(op == 3 and "to" or "set", name, v)
        owner[name] = { v }
        if op == 3 then m:to({ [name] = v }, opts()) else m:set({ [name] = v }) end
      elseif op == 5 then
        local name = rand(3) == 1 and NAMES[rand(#NAMES)] or nil
        log[#log + 1] = "stop " .. tostring(name)
        m:stop(name)
        for _, n in ipairs(NAMES) do
          if n == name or not name then owner[n] = { (m:get(n)) } end
        end
      elseif op == 6 then
        log[#log + 1] = combat and "combat ends" or "combat starts"
        combat = not combat
        if not combat then
          if deferredShow then show(deferredShow); deferredShow = nil end
          fire("PLAYER_REGEN_ENABLED")
        end
      else
        local t = 0.4 * rand()
        log[#log + 1] = ("run %.2f"):format(t)
        run(t)
      end
    end
    if combat then
      combat = false
      if deferredShow then show(deferredShow) end
      fire("PLAYER_REGEN_ENABLED")
    end
    run(6)

    local function fail(what)
      error(("seed %d: %s\n  %s"):format(seed, what, table.concat(log, "\n  ")), 0)
    end
    if f.shown ~= (lastVis ~= "hide") then fail("shown is " .. tostring(f.shown) .. " after a last " .. tostring(lastVis)) end
    if m:isMoving() then fail("still moving") end
    local nx, ny, k, _, nativeAlpha = f:Native()
    if nx ~= 0 or ny ~= 0 or k ~= 1 or nativeAlpha then fail("a native animation is still drawing") end
    for _, name in ipairs(NAMES) do
      local o = owner[name]
      local want = type(o) == "table" and o[1] or REST[name]
      local got = m:get(name)
      if math.abs(got - want) > 0.01 then
        fail(("%s is %.3f, want %.3f (%s)"):format(name, got, want, type(o) == "table" and "caller's" or "rest"))
      end
    end
  end
end)

test("a texture of a protected frame in combat is not locked: its own IsProtected() decides", function()
  local tex = fakeRegion(fakeFrame(true))
  combat = true
  Poly(tex):to({ alpha = 0.5, x = 30, width = 160 }, { duration = 0.2 })
  run(0.5)
  assert(tex.alpha == 0.5 and tex.point[4] == 40 and tex.w == 160, "waited for combat to end")
  Poly(tex):hide("fade", { duration = 0.2 })
  run(0.5)
  combat = false
  assert(not tex.shown, "Hide waited for combat to end")
end)

-- The examples in docs/api.md, run as written: the block that defines `name`.
-- Run from the repository root.
local docs = assert(io.open("docs/api.md")):read("*a")
_G.LibStub = function(name) assert(name == "Polymorph-1.0"); return Poly end
local compile = loadstring or load
local function example(name)
  for code in docs:gmatch("```lua\n(.-)```") do
    if code:find("local function " .. name .. "(", 1, true) then
      return assert(compile(code .. "\nreturn " .. name, name))()
    end
  end
  error("no example " .. name .. " in docs/api.md")
end

test("define: names belong to the handle, built-in names error, a redefine keeps the value", function()
  local a, b = Poly(fakeFrame()), Poly(fakeFrame())
  local seen = {}
  a:define({ n = 0 }, function(_, v) seen.a = v.n end)
  b:define({ n = 5 }, function(_, v) seen.b = v.n end)
  a:set({ n = 3 })
  assert(seen.a == 3 and seen.b == nil and b:get("n") == 5, "handles share a value")
  assert(not pcall(a.define, a, { alpha = 1 }, print), "redefined a built-in")
  local c = Poly(fakeFrame())
  assert(not pcall(c.to, c, { n = 1 }), "a name defined elsewhere animated here")
  a:to({ n = 10 }, { duration = 1, ease = "linear" })
  run(0.5)
  local mid = a:get("n")
  a:define({ n = 0 }, function(_, v) seen.again = v.n end)
  assert(a:get("n") == mid and a:isMoving("n"), "redefine reset the value")
  run(1)
  assert(seen.again == 10 and a:get("n") == 10, "the new writer did not finish it")
end)

test("define: redefining some of a writer's names leaves its other writer drawing current values", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:define({ r = 1, g = 1 }, function(frame, v) frame.r, frame.g = v.r, v.g end)
  m:define({ r = 1 }, function(frame, v) frame.r = v.r end)
  m:set({ r = 0.2 })
  m:set({ g = 0.5 })
  assert(f.r == 0.2 and m:get("r") == 0.2, "the first writer drew a stale r: " .. f.r)
  m:to({ g = 0 }, { duration = 0.1 })
  run(0.2)
  assert(f.r == 0.2 and f.g == 0, "the driver drew a stale r: " .. f.r)
end)

test("define: a value with precision 0.5 arrives in the frame its digits settle", function()
  local m = Poly(fakeFrame())
  local text
  m:define({ n = 0 }, function(_, v) text = ("%.0f"):format(v.n) end, { precision = 0.5 })
  m:to({ n = 1500000 })
  local frame, changed, last = 0, 0, nil
  repeat
    run(1 / 60)
    frame = frame + 1
    if text ~= last then changed, last = frame, text end
  until not m:isMoving() or frame > 600
  assert(text == "1500000" and frame == changed, "arrived " .. (frame - changed) .. " frames after the digits settled")
end)

test("example number counter: rolls to each total, retargets mid-roll, prints past 2^31", function()
  local fs = fakeRegion(fakeFrame())
  local calls, setText = 0, fs.SetText
  function fs:SetText(text) calls = calls + 1; setText(self, text) end
  local add = example("NumberCounter")(fs)
  assert(fs.text == "0", "not set to 0")
  add(1000)
  local last = 0
  local function rolls(frames)
    for _ = 1, frames do
      run(1 / 60)
      local n = tonumber(fs.text)
      assert(n >= last, "rolled back from " .. last .. " to " .. n)
      last = n
    end
  end
  rolls(6)
  assert(calls == 7 and last > 0 and last < 1000, calls .. " SetText calls, showing " .. last)
  local m = Poly(fs)
  local before, velocity = m:get("total")
  add(2 ^ 31 + 5000)
  local after, velocityAfter = m:get("total")
  assert(before == after and velocity == velocityAfter, "jump on retarget")
  rolls(300)
  assert(fs.text == "2147489648" and not m:isMoving(), fs.text)
end)

test("example typewriter: types at its speed and never draws untyped text, called from an event or onComplete", function()
  local fs = fakeRegion(fakeFrame())
  local typeText = example("Typewriter")(fs, 40)
  -- Runs frames until `text` has typed out. Until then, each frame draws a gradient, never the whole text.
  local function typesOut(text, frames)
    for _ = 1, frames or 120 do
      run(1 / 60)
      if not fs.gradient then
        assert(fs.text == text and not Poly(fs):isMoving(), "drew all of " .. tostring(fs.text) .. " while typing")
        return
      end
    end
    if not frames then error(text .. " never finished") end
  end
  typeText("Hello, w\195\182rld") -- 12 characters in 13 bytes
  typesOut(nil, 10)
  assert(fs.text == "Hello, w\195\182rld" and near(fs.gradient[1], 6, 0.7), "shown " .. fs.gradient[1] .. " after 10 frames at 40 per second")
  typesOut("Hello, w\195\182rld")
  -- From an onComplete, which runs inside the driver's update, after the frame's SetText would draw.
  local started = false
  Poly(fakeFrame()):to({ width = 0 }, { duration = 0.05, ease = "inQuad", onComplete = function()
    typeText("Again, |cffff4040red|r")
    started = true
  end })
  repeat run(1 / 60) until started
  assert(fs.gradient, "drew all of " .. fs.text .. " in the frame typeText was called")
  typesOut(nil, 2)
  assert(select(3, Poly(fs):get("shown")) == 10, "color codes counted as characters")
  typesOut("Again, |cffff4040red|r")
end)

test("example color fade: one SetVertexColor per update, retargets smoothly, runs in combat", function()
  local tex = fakeRegion(fakeFrame(true))
  local calls, setColor = 0, tex.SetVertexColor
  function tex:SetVertexColor(...) calls = calls + 1; setColor(self, ...) end
  local tint = example("ColorFade")(tex)
  combat = true -- the writer is allowed in combat, so the fade runs there
  tint(1, 0.2, 0.2, { duration = 0.3, ease = "outSine" })
  run(0.1)
  local r, g, b = unpack(tex.color)
  assert(calls == 6, calls .. " SetVertexColor calls in 6 updates")
  assert(r == 1 and g < 1 and g > 0.2 and b == g, "not between white and red: " .. g)
  tint(0, 0, 1, { duration = 0.3 })
  assert(Poly(tex):get("g") == g, "jump on retarget")
  run(0.5)
  combat = false
  r, g, b = unpack(tex.color)
  assert(r == 0 and g == 0 and b == 1, "did not land on blue")
end)

print(("CORE OK: %d tests"):format(passed))
