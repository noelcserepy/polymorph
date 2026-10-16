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
-- GetAlpha() returns the alpha set, stored in steps of 1/255: SetAlpha(0.5) reads 0.50196, anchors_probe.lua, 2026-10-15
-- GetPoint() returns the offsets set within 3e-6: anchors_probe.lua, 2026-10-15. A texture's SetPoint(..., 100) reads 99.99999:
--   regions.lua, 2026-10-15. The fake returns offsets exactly, and the library allows 0.01
-- Other getters return exactly the value last set: unmeasured
-- GetNumPoints() counts the frame's anchors and GetPoint(i) returns the i-th, nil past the last: anchors_probe.lua, 2026-10-15
--
-- Anchors:
-- SetPoint() replaces the point of the same name in its place and keeps the frame's other points in order: anchors_probe.lua, 2026-10-15
-- Moving both anchors of a two-anchor frame by the same offset keeps its width: anchors_probe.lua, 2026-10-15
-- ClearAllPoints() removes every point: anchors_probe.lua, 2026-10-15 (the library does not call it)
-- ClearAllPoints() is blocked on a locked frame: unmeasured (the library does not call it)
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
-- Errors:
-- geterrorhandler() returns the handler that seterrorhandler() installed, and calling it reports the error:
--   errors.lua, 2026-10-15 (both reports Polymorph caught reached the job's handler)
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
-- The game's error handler. Each test fails on an error it didn't take from here.
local reported = {}
_G.geterrorhandler = function()
  return function(err) reported[#reported + 1] = tostring(err) end
end
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
  local f = { alpha = 1, w = 100, h = 50, s = 1, points = { { "CENTER", nil, "CENTER", 10, 20 } }, pointCalls = 0 }
  function f:GetAlpha() return self.alpha end
  -- The client stores alpha in steps of 1/255.
  function f:SetAlpha(v) self.alpha = math.floor(v * 255 + 0.5) / 255 end
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
  -- SetPoint replaces the point of the same name in its place, or adds one.
  function f:GetNumPoints() return #self.points end
  function f:GetPoint(i)
    local p = self.points[i or 1]
    if p then return unpack(p, 1, 5) end
  end
  function f:SetPoint(a, b, c, x, y)
    assert(not (combat and protected), "SetPoint while locked")
    if inOnUpdate and not self.pointBefore then
      self.pointBefore = self.points[1]
      misdrawn[#misdrawn + 1] = self
    end
    local i = #self.points + 1
    for j, p in ipairs(self.points) do
      if p[1] == a then i = j end
    end
    self.points[i] = { a, b, c, x, y }
    self.pointCalls = self.pointCalls + 1
  end
  function f:ClearAllPoints()
    assert(not (combat and protected), "ClearAllPoints while locked")
    self.points = {}
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
          f.staleAnchor = f.pointBefore or f.points[1]
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
    local point = self.staleAnchor or self.points[1]
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
  fn()
  assert(#reported == 0, name .. ": reported " .. tostring(reported[1]))
  passed = passed + 1; print("ok " .. name)
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
  assert(f.points[1][4] == 50 and f.points[1][5] == 10, f.points[1][4] .. "," .. f.points[1][5])
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
  assert(f.points[1][4] == 60 and f:Native() == 0 and f:VisualX() == 60, "commit moved the frame")
  run(0.5)
  assert(f.w == 160, "width not applied after combat")
end)

test("protected frame in combat: scale draws through the puppet and hands over without a jump", function()
  local f = fakeFrame(true)
  f.points = { { "TOPLEFT", nil, "TOPLEFT", 10, 20 } } -- a corner anchor, so the scale origin matters
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
  assert(f.s == 2 and f.points[1][4] == 40)
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
  assert(f.points[1][4] == 110)
end)

test("x and y share one SetPoint per update, width and height one SetSize", function()
  local f = fakeFrame()
  Poly(f):to({ x = 50, y = 20, width = 200, height = 80 }, { duration = 0.5 })
  run(0.1)
  assert(f.pointCalls == 6 and f.sizeCalls == 6, f.pointCalls .. " SetPoint, " .. f.sizeCalls .. " SetSize in 6 updates")
  run(0.5)
  assert(f.points[1][4] == 60 and f.points[1][5] == 40 and f.w == 200 and f.h == 80)
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
  assert(f.alpha == 1 and f.points[1][4] == 110, "final values not written first")
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
  assert(waiting.points[1][4] == 110 and nested.points[1][4] == 50 and nested.points[1][5] == 60, "did not land")
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
  assert(near(f:VisualAlpha(), 0.3, 1 / 510) and not m:isMoving(), "set did not take over the native alpha")
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
  assert(f.points[1][4] == 10 and f:Native() == 0)
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

-- Other code anchors frames too: layouts, pools, frame movers. Polymorph checks
-- the anchors at each call that takes or returns x or y.
test("an anchor set by other code becomes home", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:show("below", { duration = 0.2 })
  run(0.5)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", nil, "TOPLEFT", 300, -400) -- a mover drops the frame here
  assert(m:get("y") == 0, "y is not 0 at the new anchor")
  m:hide("below", { duration = 0.2, ease = "linear" })
  run(0.1)
  local p = f.points[1]
  assert(#f.points == 1 and p[1] == "TOPLEFT" and f:VisualX() == 300, "hide moved the frame off the new anchor")
  assert(f:VisualY() < -400 and f:VisualY() > -416, "hide did not slide from the new anchor: " .. f:VisualY())
  run(0.5)
  p = f.points[1]
  assert(not f.shown and #f.points == 1 and p[4] == 300 and p[5] == -400, "not back at the new anchor: " .. p[5])
end)

test("a call after other code moved a sliding frame starts from where it put it", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:to({ x = 100 })
  run(0.1)
  f:SetPoint("CENTER", nil, "CENTER", 500, 20) -- same point, no ClearAllPoints, as LibDBIcon drags
  m:to({ x = 10 }, { duration = 0.2 })
  assert(m:get("x") == 0, "x did not restart at the new anchor")
  run(0.5)
  assert(f.points[1][4] == 510 and #f.points == 1, "x is not an offset from the new anchor: " .. f.points[1][4])
end)

test("a frame with two anchors slides instead of stretching", function()
  local f = fakeFrame()
  f.points = { { "TOPLEFT", "list", "TOPLEFT", 0, -40 }, { "TOPRIGHT", "list", "TOPRIGHT", 0, -40 } } -- a ScrollBox row
  Poly(f):to({ y = -20 }, { duration = 0.2 })
  run(0.5)
  local a, b = f.points[1], f.points[2]
  assert(a[1] == "TOPLEFT" and a[4] == 0 and a[5] == -60, "first anchor " .. a[4] .. "," .. a[5])
  assert(b[1] == "TOPRIGHT" and b[4] == 0 and b[5] == -60, "second anchor " .. b[4] .. "," .. b[5])
end)

test("a layout that re-anchors a sliding row wins", function()
  local f = fakeFrame()
  f.points = { { "TOPLEFT", "list", "TOPLEFT", 0, -40 }, { "TOPRIGHT", "list", "TOPRIGHT", 0, -40 } }
  f.shown = false
  local m = Poly(f)
  m:show("left")
  run(0.1)
  -- The ScrollBox lays its rows out again after a data change.
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", "list", "TOPLEFT", 0, -60)
  f:SetPoint("TOPRIGHT", "list", "TOPRIGHT", 0, -60)
  run(1)
  local a, b = f.points[1], f.points[2]
  assert(#f.points == 2 and a[4] == 0 and a[5] == -60 and b[4] == 0 and b[5] == -60, "the row left the layout's anchors")
  assert(m:get("x") == 0 and not m:isMoving("x") and f.alpha == 1, "x still moving, or alpha stopped too")
end)

test("a layout that re-anchors a slide just before its last update wins", function()
  local f = fakeFrame()
  local m = Poly(f)
  local completed = 0
  m:to({ x = 100 }, { duration = 0.11, onComplete = function() completed = completed + 1 end })
  run(0.1)
  assert(m:isMoving("x"))
  f:SetPoint("CENTER", nil, "CENTER", 500, 20)
  run(1 / 60)
  assert(f.points[1][4] == 500 and m:get("x") == 0, "the slide wrote over the layout's anchor")
  assert(completed == 0, "an interrupted slide called onComplete")
end)

test("a layout that re-anchors a native slide wins when the slide ends", function()
  local f = fakeFrame()
  local m = Poly(f)
  local completed = 0
  m:to({ y = 40 }, { duration = 0.2, ease = "linear", onComplete = function() completed = completed + 1 end })
  run(0.1)
  assert(select(2, f:Native()) ~= 0, "not drawn natively")
  f:SetPoint("CENTER", nil, "CENTER", 10, -100)
  run(0.3)
  assert(f.points[1][5] == -100 and m:get("y") == 0 and not m:isMoving(), "the slide did not stop at the new anchor")
  assert(completed == 0, "an interrupted slide called onComplete")
end)

test("a layout that re-anchors a frame before its native slide starts wins at once", function()
  local f = fakeFrame()
  local m = Poly(f)
  local completed = 0
  m:to({ y = 40 }, { duration = 0.2, ease = "linear", onComplete = function() completed = completed + 1 end })
  f:SetPoint("CENTER", nil, "CENTER", 10, -100)
  run(0.1)
  assert(f.points[1][5] == -100 and f:VisualY() == -100 and m:get("y") == 0 and not m:isMoving(), "the slide drew from the new anchor")
  run(0.3)
  assert(completed == 0, "an interrupted slide called onComplete")
end)

test("a pooled frame released mid-hide comes back clean", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("below", { duration = 0.4 })
  run(0.1)
  -- One refresh: the pool's resetter (Blizzard's default, with a stop() first),
  -- then the same frame acquired again and laid out in a new place.
  m:stop()
  f:Hide()
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, -80)
  f:Show()
  run(0.5)
  local p = f.points[1]
  assert(f.shown and f.hideCalls == 1, "the old hide() hid the reused frame")
  assert(#f.points == 1 and p[1] == "TOPLEFT" and p[5] == -80, "Polymorph wrote the released frame's old anchor")
  m:show("fade", { duration = 0.2 })
  run(0.5)
  assert(f.alpha == 1 and #f.points == 1 and f.points[1][5] == -80, "reused frame not at rest in its new place")
end)

test("protected frame: an anchor set by secure code in combat wins when combat ends", function()
  local f = fakeFrame(true)
  local m = Poly(f)
  combat = true
  m:to({ x = 50 }, { duration = 0.2 })
  run(0.5)
  f.points = { { "TOPLEFT", "header", "TOPLEFT", 0, -36 } } -- a secure group header sorts its children
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  local p = f.points[1]
  assert(#f.points == 1 and p[1] == "TOPLEFT" and p[4] == 0 and p[5] == -36, "commit overwrote the header's anchor")
  assert(f:Native() == 0 and m:get("x") == 0, "puppet still displaced")
end)

test("protected frame: a call in combat after secure code moved the frame draws from the new anchor", function()
  local f = fakeFrame(true)
  local m = Poly(f)
  combat = true
  m:to({ x = 50 }, { duration = 0.2 })
  run(0.5)
  f.points = { { "CENTER", nil, "CENTER", 200, 20 } } -- a secure header moves it
  assert(m:get("x") == 0 and f:VisualX() == 200, "still drawn off the new anchor: " .. f:VisualX())
  m:to({ x = 30 }, { duration = 0.2 })
  run(0.5)
  assert(f.pointCalls == 0 and f:VisualX() == 230, "drew at " .. f:VisualX())
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(f.points[1][4] == 230 and f:Native() == 0, "not committed at the new anchor")
end)

-- One frame's error: SetPoint throws when an anchor would close a loop. It
-- goes to the error handler once, and every other frame keeps animating.
test("an error on one frame stops that frame only, and is reported once", function()
  local bad, badNative, good = fakeFrame(), fakeFrame(), fakeFrame()
  function bad:SetPoint() error("anchor family connection") end
  badNative.SetPoint = bad.SetPoint
  local completed = 0
  local function count() completed = completed + 1 end
  Poly(bad):to({ x = 50, alpha = 0 }, { onComplete = count })
  Poly(badNative):to({ x = 50 }, { duration = 0.2, ease = "linear", onComplete = count }) -- starts from the timer
  Poly(good):to({ x = 50 }, { onComplete = function() error("onComplete failed") end })
  Poly(good):to({ alpha = 0 }, { duration = 0.5, ease = "linear" })
  run(1 / 60)
  local badAlpha = bad.alpha
  assert(not Poly(bad):isMoving() and badAlpha > 0, "the failing frame kept its tracks")
  run(2)
  assert(bad.alpha == badAlpha, "the failing frame kept drawing")
  assert(#reported == 3, "reported " .. #reported .. " times")
  table.sort(reported)
  assert(reported[1]:find("anchor family") and reported[2]:find("anchor family") and reported[3]:find("onComplete failed"))
  reported = {}
  assert(not Poly(bad):isMoving() and not Poly(badNative):isMoving() and completed == 0, "a failing frame kept animating")
  assert(good.points[1][4] == 60 and good.alpha == 0 and not Poly(good):isMoving(), "the other frame stalled")
  Poly(good):to({ alpha = 1 }, { onComplete = function() completed = completed + 1 end })
  run(1)
  assert(completed == 1 and good.alpha == 1, "callbacks stalled after an onComplete error")
end)

-- A halted frame runs nothing that was queued for it before the error, whichever
-- path halted it: a callback, a native start, or a show() or hide() waiting for combat.
local function takeReports(n)
  assert(#reported == n, "reported " .. #reported .. " times, want " .. n)
  reported = {}
end

test("a frame whose update throws runs no callback queued for it", function()
  -- A native finish queued the completion before the error.
  local f = fakeFrame()
  local m, done = Poly(f), 0
  m:to({ alpha = 0 }, { duration = 0.1, ease = "linear", onComplete = function() done = done + 1 end })
  repeat run(1 / 60) until not m:isMoving("alpha")
  function f:SetPoint() error("anchor family connection") end
  m:to({ x = 50 })
  run(1 / 60)
  takeReports(1)
  assert(done == 0, "halted frame ran its completion")
  -- A takeover queued a hide's finish before the error.
  local g = fakeFrame()
  local n = Poly(g)
  n:hide("fade")
  run(1 / 60)
  function g:SetAlpha() error("alpha failed") end
  n:to({ alpha = 1 })
  run(1 / 60)
  takeReports(1)
  assert(g.shown, "halted frame ran its hide's finish")
end)

test("a frame whose native start throws runs no callback queued for it", function()
  local f = fakeFrame()
  local m, done = Poly(f), 0
  m:to({ alpha = 0 }, { duration = 0.125, ease = "linear", onComplete = function() done = done + 1 end })
  run(8 / 60)
  function f:SetPoint() error("anchor family connection") end
  m:to({ x = 50 }, { duration = 0.2, ease = "linear" })
  run(2 / 60)
  takeReports(1)
  assert(done == 0 and not m:isMoving(), "halted frame ran its completion")
end)

test("a frame whose combat-end commit throws runs no deferred hide or show", function()
  local f = fakeFrame(true)
  local m = Poly(f)
  combat = true
  m:hide("below", { duration = 0.1 })
  run(0.3)
  function f:SetPoint() error("anchor family connection") end
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  takeReports(1)
  assert(f.shown, "halted frame still ran its deferred hide")
  -- The puppet stopped, so the frame draws at its anchor, and y says so.
  assert(m:get("y") == 0 and f:VisualY() == 20, "y reads " .. m:get("y") .. " where the frame draws at its anchor")

  local g = fakeFrame(true)
  g.shown = false
  local n = Poly(g)
  combat = true
  n:to({ x = 50 }, { duration = 0.1 })
  n:show("fade", { duration = 1 })
  run(0.3)
  function g:SetPoint() error("anchor family connection") end
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  takeReports(1)
  assert(not g.shown and not n:isMoving(), "deferred show restarted the halted frame")
end)

test("a frame whose update throws in combat runs no deferred show when combat ends", function()
  local f = fakeFrame(true)
  f.shown = false
  local m = Poly(f)
  combat = true
  m:show("fade")
  local setAlpha = f.SetAlpha
  function f:SetAlpha() error("alpha failed") end
  m:to({ alpha = 0.5 })
  run(1 / 60)
  takeReports(1)
  f.SetAlpha = setAlpha
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.1)
  assert(not f.shown and not m:isMoving(), "deferred show restarted the halted frame")
end)

-- A halted frame starts over: its motion is what Poly(frame) would build for
-- the frame as it is now. Nothing an animation staged before the error reaches
-- the frame through a later call.
local function breakSetPoint(f)
  local original = f.SetPoint
  function f:SetPoint() error("anchor family connection") end
  return function() f.SetPoint = original end
end

test("a halted slide's staged offset isn't written by a later set() of the other axis", function()
  for _, axis in ipairs({ "x", "y" }) do
    local other, i = axis == "x" and "y" or "x", axis == "x" and 4 or 5
    local f = fakeFrame()
    local m = Poly(f)
    local restore = breakSetPoint(f)
    m:to({ [axis] = 100 }, { duration = 0.2 })
    run(2 / 60)
    takeReports(1)
    restore()
    assert(m:get(axis) == 0, axis .. " reads " .. m:get(axis) .. " where the frame stayed")
    m:set({ [other] = 5 })
    assert(f.points[1][i] == (i == 4 and 10 or 20), "halted " .. axis .. " moved on a " .. other .. "-only set")
  end
end)

test("a failed native start's target isn't written by a later set() of the other axis", function()
  for _, axis in ipairs({ "x", "y" }) do
    local other, i = axis == "x" and "y" or "x", axis == "x" and 4 or 5
    local f = fakeFrame()
    local m = Poly(f)
    local restore = breakSetPoint(f)
    m:to({ [axis] = 100 }, { duration = 0.2, ease = "linear" })
    run(2 / 60)
    takeReports(1)
    restore()
    m:set({ [other] = 5 })
    assert(f.points[1][i] == (i == 4 and 10 or 20), "failed native " .. axis .. " target was applied")
  end
end)

test("a halted resize's staged size isn't written by a later set() of the other side", function()
  -- Whether the position or the size flush runs first depends on table order,
  -- so every pair runs. A size is staged and left only when the position throws first.
  for _, pair in ipairs({ { "x", "width", "height" }, { "y", "width", "height" }, { "x", "height", "width" }, { "y", "height", "width" } }) do
    local axis, side, other = pair[1], pair[2], pair[3]
    local f = fakeFrame()
    local m = Poly(f)
    local restore = breakSetPoint(f)
    m:to({ [axis] = 100, [side] = 200 }, { duration = 0.2 })
    run(1 / 60)
    takeReports(1)
    restore()
    local before = m:get(side)
    m:set({ [other] = 80 })
    assert(m:get(side) == before, other .. "-only set applied the halted " .. side .. ": " .. before .. " -> " .. m:get(side))
  end
end)

-- Recovery is observable through the same handle: no motion, no drawing left
-- over, no delayed writes, and subsequent calls work with the caller's rest.
local function assertStartedOver(m, f, path)
  assert(not m:isMoving(), path .. ": animation survived halt")
  assert(m:get("x") == 0 and m:get("y") == 0, path .. ": offsets survived halt")
  for name, expected in pairs({ alpha = f:GetAlpha(), scale = f:GetScale(), width = f:GetWidth(), height = f:GetHeight() }) do
    local value, velocity, target = m:get(name)
    assert(value == expected and velocity == 0 and target == nil, path .. ": stale " .. name)
  end
  local nx, ny, k, _, drawnAlpha = f:Native()
  assert(nx == 0 and ny == 0 and k == 1 and drawnAlpha == nil, path .. ": an animation still draws")
  local x, y, alpha, w, h, scale, shown = f.points[1][4], f.points[1][5], f.alpha, f.w, f.h, f.s, f.shown
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.5)
  assert(f.points[1][4] == x and f.points[1][5] == y and f.alpha == alpha and f.w == w and f.h == h and f.s == scale and f.shown == shown,
    path .. ": the halted frame changed afterwards")
  m:set({ y = 5, height = 80 })
  assert(f.points[1][4] == x and f.points[1][5] == y + 5 and f.w == w and f.h == 80, path .. ": later set applied halted values")
  m:show("fade", { duration = 0.05 })
  run(0.2)
  assert(f.shown and f.alpha == 1 and f.s == scale, path .. ": show retained halted hide ownership")
  m:show("pop", { duration = 0.05 })
  run(0.2)
  assert(f.shown and f.alpha == 1 and f.s == 1 and not m:isMoving(), path .. ": rest values were lost")
end

test("a halted frame recovers through its public handle on every halt path", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:hide("pop", { duration = 0.5 })
  m:to({ x = 40, y = 30, width = 150, height = 70 })
  run(2 / 60)
  local restore = breakSetPoint(f)
  run(1 / 60)
  takeReports(1)
  restore()
  assertStartedOver(m, f, "driver")

  f = fakeFrame()
  m = Poly(f)
  m:to({ alpha = 0 }, { duration = 0.5, ease = "linear" })
  run(2 / 60)
  restore = breakSetPoint(f)
  m:to({ x = 40 }, { duration = 0.2, ease = "linear" })
  run(2 / 60)
  takeReports(1)
  restore()
  assertStartedOver(m, f, "native start")

  f = fakeFrame(true)
  m = Poly(f)
  combat = true
  m:to({ x = 40, scale = 1.2, width = 150 })
  run(0.1)
  restore = breakSetPoint(f)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  takeReports(1)
  restore()
  assertStartedOver(m, f, "combat end")

  f = fakeFrame(true)
  f.shown = false
  m = Poly(f)
  combat = true
  m:show("below")
  m:to({ x = 40, scale = 1.2 })
  run(0.1)
  local setAlpha = f.SetAlpha
  function f:SetAlpha() error("alpha failed") end
  m:to({ alpha = 0.5 })
  run(1 / 60)
  takeReports(1)
  f.SetAlpha = setAlpha
  assertStartedOver(m, f, "driver in combat")
end)

test("a halted frame keeps the values define() made, where they stopped", function()
  local f = fakeFrame()
  local m, drawn = Poly(f), nil
  m:define({ n = 0 }, function(_, v) drawn = v.n end)
  m:to({ n = 10 }, { duration = 1, ease = "linear" })
  run(0.5)
  local restore = breakSetPoint(f)
  m:to({ x = 40 })
  run(1 / 60)
  takeReports(1)
  restore()
  local stopped = m:get("n")
  assert(not m:isMoving() and stopped > 0 and stopped < 10, "n did not stop where it was: " .. stopped)
  m:to({ n = 20 }, { duration = 0.2, ease = "linear" })
  run(0.5)
  assert(drawn == 20 and m:get("n") == 20, "the defined value did not animate after the halt")
end)

test("a resize retargeted inside its final writer reaches the replacement", function()
  for _, writer in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
    local f = fakeFrame()
    local m, done, once = Poly(f), 0, false
    local replacement = writer == "SetWidth" and { width = 300 } or writer == "SetHeight" and { height = 120 } or { width = 300, height = 120 }
    local expectedWidth, expectedHeight = replacement.width or 100, replacement.height or 50
    local original = f[writer]
    f[writer] = function(self, ...)
      original(self, ...)
      if not once then
        once = true
        m:to(replacement, { duration = 0.1, onComplete = function()
          assert(f.w == expectedWidth and f.h == expectedHeight, "replacement completed before arrival")
          done = done + 1
        end })
      end
    end
    local targets = writer == "SetWidth" and { width = 150 } or writer == "SetHeight" and { height = 80 } or { width = 150, height = 80 }
    m:to(targets, { duration = 0.01 })
    run(1 / 60)
    assert(m:isMoving(writer == "SetHeight" and "height" or "width") and done == 0, writer .. ": replacement completed in old update")
    run(0.3)
    assert(once and f.w == expectedWidth and f.h == expectedHeight and done == 1 and not m:isMoving(), writer .. ": replacement lost")
  end
end)

test("SetPoint hooks can read both offsets through every commit producer", function()
  for _, path in ipairs({ "driver", "native", "set", "combat end" }) do
    for _, axis in ipairs({ "x", "y" }) do
      local f = fakeFrame(true)
      f.points = { { "TOPLEFT", nil, "TOPLEFT", 10, 20 }, { "TOPRIGHT", nil, "TOPRIGHT", -10, 20 } }
      local m, done, reads = Poly(f), 0, 0
      local original = f.SetPoint
      function f:SetPoint(...)
        original(self, ...)
        local x, y = m:get("x"), m:get("y")
        if path == "set" then assert(x == (axis == "x" and 100 or 0) and y == (axis == "y" and 100 or 0), "hook read stale offset") end
        reads = reads + 1
      end
      if path == "set" then
        m:set({ [axis] = 100 })
      else
        combat = path == "combat end"
        m:to({ [axis] = 100 }, { duration = 0.2, ease = path == "native" and "linear" or "outCubic", onComplete = function() done = done + 1 end })
        run(0.05)
        combat = false
        if path == "combat end" then fire("PLAYER_REGEN_ENABLED") end
        run(0.4)
        assert(done == 1, path .. ": reading interrupted completion")
      end
      assert(reads > 0 and not m:isMoving(), path .. ": hook was not exercised")
      for i, home in ipairs({ 10, -10 }) do
        assert(f.points[i][4] == home + (axis == "x" and 100 or 0) and f.points[i][5] == 20 + (axis == "y" and 100 or 0), path .. ": slide stopped early")
      end
    end
  end
end)

-- Discover every frame writer from the fake, rather than maintaining a second
-- list that silently misses a new property. Each path installs all the hooks;
-- the first invocation of the selected writer makes a nested public call.
test("reentrant hooks on every frame writer preserve the last public call", function()
  local paths = { "driver", "width", "height", "set", "native start", "native retarget", "stop one", "stop all", "show", "hide", "deferred show", "deferred hide", "combat end" }
  local writers, exercised = {}, {}
  for name in pairs(fakeFrame()) do
    if name:match("^Set") or name == "Show" or name == "Hide" or name == "ClearAllPoints" then writers[#writers + 1] = name end
  end
  table.sort(writers)
  local target = { alpha = 0.6, scale = 1.3, width = 310, height = 140, x = 70, y = 45 }
  for _, path in ipairs(paths) do
    for _, writer in ipairs(writers) do
      for _, action in ipairs({ "read", "set", "to", "show", "hide", "another frame" }) do
        combat = false
        local f = fakeFrame(true)
        local m, nested, done, originalDone = Poly(f), false, 0, 0
        local other, otherDone = fakeFrame(), 0
        local expected = (path:find("show") or path:find("hide")) and { alpha = 1, scale = 1, width = 100, height = 50, x = 0, y = 0 }
          or path == "width" and { width = 150 } or path == "height" and { height = 80 }
          or path == "native start" and { x = 100, y = 60, alpha = 0.2 }
          or { alpha = 0.2, scale = 0.8, width = 150, height = 80, x = 100, y = 60 }
        -- The nested call runs after the original's work, so the original may
        -- complete after it. It completes only if the frame showed every target first.
        local reached = false
        local function arrived()
          originalDone = originalDone + 1
          assert(originalDone == 1, path .. ": repeated original completion")
          assert(reached, path .. ": original completed before real arrival")
        end
        if path == "native retarget" or path == "stop one" or path == "stop all" then
          m:to({ x = 100, y = 60, alpha = 0.2 }, { duration = 1, ease = "linear" })
          run(0.1)
        end
        if path == "show" or path == "deferred show" then f.shown = false end
        local function onWrite(name)
          -- Reads reenter every writer, including writes made by the nested call.
          m:get("x"); m:get("y"); m:get("scale"); m:isMoving()
          local shown = { alpha = f.alpha, scale = f.s, width = f.w, height = f.h, x = f.points[1][4] - 10, y = f.points[1][5] - 20 }
          local all = true
          for key, value in pairs(expected) do all = all and near(shown[key], value, key == "alpha" and 1 / 510 or 1e-6) end
          reached = reached or all
          if nested or name ~= writer then return end
          nested = true
          exercised[name] = true
          if action == "read" then return end
          if action == "another frame" then
            Poly(other):to({ width = 310 }, { duration = 0.1, onComplete = function()
              assert(other.w == 310, "other frame completed before arrival")
              otherDone = otherDone + 1
            end })
            return
          end
          m:stop()
          if action == "set" then m:set(target)
          elseif action == "to" then
            m:to(target, { duration = 0.1, onComplete = function()
              for key, value in pairs(target) do assert(near(m:get(key), value, key == "alpha" and 1 / 510 or 1e-6), key .. ": completed before real arrival") end
              done = done + 1
              assert(done == 1, "replacement completed twice")
            end })
          else
            local function visibilityDone()
              assert(f.shown == (action == "show") and f.alpha == 1 and f.s == 1, "visibility completed before arrival")
              done = done + 1
              assert(done == 1, "visibility completed twice")
            end
            if action == "show" then m:show("pop", { duration = 0.1, onComplete = visibilityDone })
            else m:hide("pop", { duration = 0.1, onComplete = visibilityDone }) end
          end
        end
        for _, name in ipairs(writers) do
          local original = f[name]
          f[name] = function(self, ...)
            original(self, ...)
            onWrite(name)
          end
        end
        local values = { alpha = 0.2, scale = 0.8, width = 150, height = 80, x = 100, y = 60 }
        if path == "width" then m:to({ width = 150 }, { duration = 0.01, onComplete = arrived })
        elseif path == "height" then m:to({ height = 80 }, { duration = 0.01, onComplete = arrived })
        elseif path == "driver" then m:to(values, { duration = 0.01, onComplete = arrived })
        elseif path == "set" then m:set(values)
        elseif path == "native start" then m:to({ x = 100, y = 60, alpha = 0.2 }, { duration = 0.1, ease = "linear", onComplete = arrived })
        elseif path == "native retarget" then m:to(values, { duration = 0.1, onComplete = arrived })
        elseif path == "stop one" then m:stop("x")
        elseif path == "stop all" then m:stop()
        elseif path == "show" then m:show(values, { duration = 0.01, onComplete = arrived })
        elseif path == "hide" then m:hide(values, { duration = 0.01, onComplete = arrived })
        elseif path == "deferred show" then
          combat = true; m:show(values, { duration = 0.01, onComplete = arrived })
          combat = false; fire("PLAYER_REGEN_ENABLED")
        elseif path == "deferred hide" then
          combat = true; m:hide(values, { duration = 0.01, onComplete = arrived }); run(0.1)
          combat = false; fire("PLAYER_REGEN_ENABLED")
        else
          combat = true; m:to(values, { duration = 0.2, onComplete = arrived }); run(0.05)
          combat = false; fire("PLAYER_REGEN_ENABLED")
        end
        run(1.5)
        local label = path .. "/" .. writer .. "/" .. action
        if nested and (action == "set" or action == "to") then
          for key, value in pairs(target) do assert(near(m:get(key), value, key == "alpha" and 1 / 510 or 1e-6), label .. ": lost " .. key .. " = " .. m:get(key)) end
          assert(f.w == 310 and f.h == 140 and f.s == 1.3 and near(f:VisualX(), 80 * 1.3) and near(f:VisualY(), 65 * 1.3), label .. ": frame missed final target")
          assert(done == (action == "to" and 1 or 0), label .. ": completion lost")
        elseif nested and action == "show" then
          assert(f.shown and f.alpha == 1 and f.s == 1 and done == 1, label .. ": last show lost")
        elseif nested and action == "hide" then
          assert(not f.shown and f.alpha == 1 and f.s == 1 and done == 1, label .. ": last hide lost")
        end
        if nested and action == "another frame" then assert(other.w == 310 and otherDone == 1 and not Poly(other):isMoving(), label .. ": other frame lost") end
        assert(not m:isMoving(), label .. ": still moving")
        assert(#reported == 0, label .. ": " .. tostring(reported[1]))
      end
    end
  end
  -- Polymorph never clears anchors. Exercise the external writer through a
  -- caller's layout change, then the next public call must adopt it.
  local f = fakeFrame()
  local m = Poly(f)
  local original = f.ClearAllPoints
  function f:ClearAllPoints()
    original(self)
    m:set({ x = 30 })
    exercised.ClearAllPoints = true
  end
  f:ClearAllPoints()
  assert(f:GetNumPoints() == 0 and m:get("x") == 30, "clear hook invented an anchor")
  for _, writer in ipairs(writers) do assert(exercised[writer], "unexercised writer " .. writer) end
end)

-- A call from an ease runs once the update that called the ease is done. The
-- old tween completes only when that update was its last.
test("a call from a custom ease runs after the update that called it", function()
  for _, duration in ipairs({ 0.1, 0.01 }) do
    local f = fakeFrame()
    local m, once, done, oldDone, widths = Poly(f), false, 0, 0, {}
    local setWidth = f.SetWidth
    function f:SetWidth(v) setWidth(self, v); widths[#widths + 1] = v end
    m:to({ width = 150 }, { duration = duration, ease = function(p)
      if not once then
        once = true
        m:set({ width = 250, height = 90 })
        assert(f.w == 100 and m:get("height") == 50, "ease call ran inside the update")
        m:to({ height = 120 }, { duration = 0.1, onComplete = function()
          assert(f.h == 120, "ease replacement completed before arrival")
          done = done + 1
        end })
      end
      return p
    end, onComplete = function() oldDone = oldDone + 1 end })
    run(0.5)
    local final = duration < 1 / 60
    assert((final and widths[1] == 150 or widths[1] > 100 and widths[1] < 150) and widths[2] == 250, "the update's write didn't land before the call")
    assert(f.w == 250 and f.h == 120 and done == 1 and oldDone == (final and 1 or 0) and not m:isMoving(), "ease callback lost its replacement")
  end
end)

test("a writer hook that reanchors a two-point frame wins before the next anchor", function()
  local f = fakeFrame()
  f.points = { { "TOPLEFT", nil, "TOPLEFT", 10, 20 }, { "TOPRIGHT", nil, "TOPRIGHT", -10, 20 } }
  local m, once, done = Poly(f), false, 0
  local original = f.SetPoint
  function f:SetPoint(...)
    original(self, ...)
    if not once then
      once = true
      original(self, "TOPLEFT", nil, "TOPLEFT", 200, 90)
      original(self, "TOPRIGHT", nil, "TOPRIGHT", 400, 90)
      m:get("x") -- a read during the commit leaves the anchors to the commit
    end
  end
  m:to({ x = 100 }, { duration = 0.01, onComplete = function() done = done + 1 end })
  run(0.2)
  assert(f.points[1][4] == 200 and f.points[2][4] == 400 and done == 0 and m:get("x") == 0 and not m:isMoving(), "old commit overwrote the hook's anchors")
end)

-- The newest review's reproductions at 0ca05c3. A call from a hook runs once
-- Polymorph's work on that frame is done, so it lands on every anchor.
test("a set() from a SetPoint hook moves both anchors of a two-point frame, on every commit path", function()
  for _, path in ipairs({ "set", "driver", "native", "combat end" }) do
    local f = fakeFrame(true)
    f.points = { { "TOPLEFT", nil, "TOPLEFT", 10, 20 }, { "TOPRIGHT", nil, "TOPRIGHT", -10, 20 } }
    local m, once = Poly(f), false
    local original = f.SetPoint
    function f:SetPoint(...)
      original(self, ...)
      if not once then
        once = true
        m:set({ x = 70, y = 45 })
      end
    end
    if path == "set" then m:set({ x = 100 })
    elseif path == "combat end" then
      combat = true; m:to({ x = 100 }); run(0.05)
      combat = false; fire("PLAYER_REGEN_ENABLED")
    else
      m:to({ x = 100 }, path == "native" and { duration = 0.2, ease = "linear" } or nil)
    end
    run(0.5)
    assert(once and f.points[1][4] == 80 and f.points[1][5] == 65 and f.points[2][4] == 60 and f.points[2][5] == 65,
      path .. ": anchors at (" .. f.points[1][4] .. ", " .. f.points[1][5] .. ") and (" .. f.points[2][4] .. ", " .. f.points[2][5] .. ")")
    assert(m:get("x") == 70 and m:get("y") == 45 and not m:isMoving() and f:Native() == 0, path .. ": the hook's set() didn't win")
  end
end)

test("a hook that reanchors the frame on a slide's last SetPoint takes the slide over", function()
  for _, axis in ipairs({ "x", "y" }) do
    local f = fakeFrame()
    local m, done, once = Poly(f), 0, false
    local original = f.SetPoint
    function f:SetPoint(...)
      original(self, ...)
      if not once then
        once = true
        original(self, "CENTER", nil, "CENTER", 500, 90)
      end
    end
    m:to({ [axis] = 100 }, { duration = 0.01, onComplete = function() done = done + 1 end })
    run(0.2)
    assert(done == 0 and f.points[1][4] == 500 and f.points[1][5] == 90 and m:get(axis) == 0, axis .. ": external takeover called onComplete")
  end
end)

test("a puppet whose setup threw once draws the next slide", function()
  for _, method in ipairs({ "CreateAnimation", "SetDuration", "SetScaleTo" }) do
    local f = fakeFrame(true)
    local m, once = Poly(f), false
    local create = f.CreateAnimationGroup
    function f:CreateAnimationGroup()
      local ag = create(self)
      local createAnimation = ag.CreateAnimation
      local function fail()
        if not once then
          once = true
          error("test: setup hook")
        end
      end
      function ag:CreateAnimation(kind)
        if method == "CreateAnimation" then fail() end
        local a = createAnimation(self, kind)
        local setter = a[method]
        if setter then a[method] = function(...) fail(); return setter(...) end end
        return a
      end
      return ag
    end
    combat = true
    m:to({ x = 100 }, { duration = 0.1 })
    run(0.2)
    takeReports(1)
    m:to({ x = 70 }, { duration = 0.1 })
    run(0.3)
    assert(f:VisualX() == 80 and m:get("x") == 70 and not m:isMoving(), method .. ": recovered slide drew at " .. f:VisualX())
    combat = false
    fire("PLAYER_REGEN_ENABLED")
    assert(f.points[1][4] == 80 and f:VisualX() == 80, method .. ": combat end lost the slide")
  end
end)

-- A hook on a game call the halt makes (a group's Stop(), an anchor getter)
-- calls Polymorph on the frame. That call fails the same way, so if it ran, it
-- would halt the frame again, and the hook would call again without end.
local function hookHaltCalls(f, source, hook)
  if source == "Stop" then
    local create = f.CreateAnimationGroup
    function f:CreateAnimationGroup()
      local ag = create(self)
      local stop = ag.Stop
      function ag:Stop() stop(self); hook() end
      return ag
    end
  else
    local original = f[source]
    f[source] = function(self, ...) hook(); return original(self, ...) end
  end
end

test("error(false) and error(nil) fail like any error", function()
  for _, value in ipairs({ false, "nil" }) do
    if value == "nil" then value = nil end
    local function fail() error(value) end
    -- A public call raises it.
    local m = Poly(fakeFrame())
    m:define({ n = 0 }, fail)
    assert(not pcall(m.set, m, { n = 1 }), tostring(value) .. ": the public call succeeded")
    -- A game entry reports it: here the start timer's SetAlpha.
    local f = fakeFrame()
    Poly(f):to({ alpha = 0.2 }, { duration = 0.2, ease = "linear" })
    f.SetAlpha = fail
    run(2 / 60)
    takeReports(1)
    -- A call that waited reports it.
    local g = fakeFrame()
    local w = Poly(g)
    w:define({ n = 0 }, fail)
    local setAlpha = g.SetAlpha
    function g:SetAlpha(a) setAlpha(self, a); w:set({ n = 1 }) end
    w:set({ alpha = 0.5 })
    takeReports(1)
    assert(not Poly(f):isMoving() and not w:isMoving(), tostring(value) .. ": a failed frame kept moving")
  end
end)

test("a call from a lock-check hook in the driver waits for the update", function()
  local f = fakeFrame(true)
  local m, order = Poly(f), {}
  m:to({ x = 50 })
  run(1 / 60)
  combat = true
  local isProtected, setPoint = f.IsProtected, f.SetPoint
  local armed = true
  function f:IsProtected()
    if armed then armed = false; m:set({ alpha = 0.5 }); order[#order + 1] = "check" end
    return isProtected(self)
  end
  function f:SetAlpha(a) order[#order + 1] = "alpha"; self.alpha = a end
  run(1 / 60)
  combat = false
  f.IsProtected, f.SetPoint = isProtected, setPoint
  assert(order[1] == "check" and order[2] == "alpha", "the hook's call ran inside the lock check")
end)

test("a lock check that throws at a native start halts that frame only", function()
  local f, g = fakeFrame(true), fakeFrame(true)
  Poly(f):to({ alpha = 0.2 }, { duration = 0.2, ease = "linear" })
  Poly(g):to({ alpha = 0.2 }, { duration = 0.2, ease = "linear" })
  run(1 / 60) -- the start timer runs at the start of the next frame
  combat = true -- and checks the lock again
  local isProtected = f.IsProtected
  function f:IsProtected() error("test: IsProtected hook") end
  run(1 / 60)
  takeReports(1)
  f.IsProtected = isProtected
  combat = false
  assert(not Poly(f):isMoving(), "the failing frame kept its track")
  run(0.5)
  assert(g:VisualAlpha() == 0.2 and not Poly(g):isMoving(), "the other frame's start was lost")
end)

test("a call from a hook during a halt is dropped, so the halt can't restart", function()
  for _, source in ipairs({ "Stop", "GetPoint", "GetNumPoints" }) do
    local f = fakeFrame()
    local m, armed, calls = Poly(f), false, 0
    hookHaltCalls(f, source, function()
      if armed and calls < 10 then
        calls = calls + 1
        m:set({ x = 70 })
      end
    end)
    m:to({ alpha = 0.5 }, { duration = 1, ease = "linear" })
    run(0.1)
    local setPoint = f.SetPoint
    function f:SetPoint() error("test: anchor family connection") end
    armed = true
    m:to({ x = 100 })
    run(1 / 60)
    takeReports(1)
    armed, f.SetPoint = false, setPoint
    assert(calls < 10, source .. ": the halt restarted itself")
    local alpha = f:VisualAlpha()
    run(1)
    assert(f:VisualAlpha() == alpha and not m:isMoving(), source .. ": the halted frame kept drawing")
    assert(m:get("x") == 0, source .. ": the hook's set() ran after the halt")
    m:set({ x = 20 })
    assert(m:get("x") == 20, source .. ": a later set() didn't land")
  end
end)

test("a halt of another frame from a hook keeps this frame's calls dropped", function()
  local f, g = fakeFrame(), fakeFrame()
  local m, n = Poly(f), Poly(g)
  local armed, calls = false, 0
  hookHaltCalls(f, "Stop", function()
    if armed and calls < 10 then
      calls = calls + 1
      pcall(n.set, n, { x = 1 })
      m:set({ x = 70 })
    end
  end)
  m:to({ alpha = 0.5 }, { duration = 1, ease = "linear" })
  run(0.1)
  function f:SetPoint() error("test: f anchor") end
  function g:SetPoint() error("test: g anchor") end
  armed = true
  assert(not pcall(m.set, m, { x = 100 }))
  armed = false
  assert(calls < 10, "the halt restarted itself")
  assert(m:get("x") == 0 and not m:isMoving(), "the hook's set() ran after the halt")
  reported = {}
end)

test("a halt finishes when the frame's anchor getter keeps throwing", function()
  for _, getter in ipairs({ "GetPoint", "GetNumPoints" }) do
    local f = fakeFrame()
    local m = Poly(f)
    m:to({ x = 100 }, { duration = 0.1 })
    local original = f[getter]
    f[getter] = function() error("test: getter") end
    run(0.2)
    takeReports(1)
    f[getter] = original
    assert(not m:isMoving(), getter .. ": the halted frame kept its track")
    m:to({ x = 20 }, { duration = 0.1 })
    run(0.5)
    assert(m:get("x") == 20 and not m:isMoving(), getter .. ": the frame didn't animate again")
  end
end)

test("a slide started from a Stop hook during an anchor takeover keeps going", function()
  for _, path in ipairs({ "get", "native finish" }) do
    local f = fakeFrame()
    local m, armed, done = Poly(f), false, 0
    local create = f.CreateAnimationGroup
    function f:CreateAnimationGroup()
      local ag = create(self)
      local stop = ag.Stop
      function ag:Stop()
        stop(self)
        if armed then
          armed = false
          m:to({ x = 50 }, { duration = 0.1, onComplete = function() done = done + 1 end })
        end
      end
      return ag
    end
    m:to({ x = 100 }, { duration = 0.2, ease = "linear" })
    run(0.05)
    f:SetPoint("CENTER", nil, "CENTER", 200, 90)
    armed = true
    if path == "get" then m:get("x") end
    run(0.5)
    assert(not armed and done == 1 and f.points[1][4] == 250 and m:get("x") == 50 and not m:isMoving(), path .. ": the hook's slide was lost")
  end
end)

test("a call that waited for a frame follows the error rules", function()
  -- A waiting call that throws halts the frame, and the calls queued after it go.
  local f = fakeFrame()
  local m, once = Poly(f), false
  local setAlpha = f.SetAlpha
  function f:SetAlpha(v)
    setAlpha(self, v)
    if not once then
      once = true
      m:set({ x = 5 })
      m:to({ width = 300 })
    end
  end
  local restore = breakSetPoint(f)
  m:to({ alpha = 0.5 })
  run(0.5)
  takeReports(1)
  restore()
  assert(f.w == 100 and f.points[1][4] == 10 and not m:isMoving(), "a call queued before the halt ran")
  -- A hook that calls the frame on every write is reported once, not run forever.
  local g = fakeFrame()
  local n = Poly(g)
  local setPoint = g.SetPoint
  function g:SetPoint(...)
    setPoint(self, ...)
    n:set({ x = 5 })
  end
  n:set({ x = 5 })
  takeReports(1)
  -- A call that throws leaves the frame taking calls.
  assert(not pcall(n.set, n, { colour = 1 }), "an unknown property didn't raise")
  n:set({ alpha = 0.5 })
  assert(near(g.alpha, 0.5, 1 / 510), "the frame stopped taking calls after an error")
end)

test("an argument error names the caller's line, also from a hook while the frame is busy", function()
  local f = fakeFrame()
  local m = Poly(f)
  local function raisesHere(call, message)
    local ok, err = pcall(call)
    assert(not ok and tostring(err):find("core_test%.lua:%d+: Polymorph: " .. message), "error points elsewhere: " .. tostring(err))
  end
  raisesHere(function() m:to({ colour = 1 }) end, "unknown property colour")
  raisesHere(function() m:to({ alpha = 1 }, { duration = 1, ease = "bounce" }) end, "unknown ease bounce")
  raisesHere(function() m:to({ alpha = 1 }, { spring = "boing" }) end, "unknown spring boing")
  raisesHere(function() m:set({ colour = 1 }) end, "unknown property colour")
  raisesHere(function() m:show("spin") end, "unknown preset spin")
  raisesHere(function() m:hide({ colour = 0 }) end, "unknown property colour")
  local setAlpha, checked = f.SetAlpha, false
  function f:SetAlpha(v)
    setAlpha(self, v)
    if not checked then
      checked = true
      raisesHere(function() m:to({ colour = 1 }) end, "unknown property colour")
    end
  end
  m:set({ alpha = 0.5 })
  assert(checked and not m:isMoving(), "the hook's call did not raise at once")
end)

-- Polymorph's own animation groups with a hook on Stop() that throws.
local function throwOnStop(f, armed)
  local create = f.CreateAnimationGroup
  function f:CreateAnimationGroup()
    local ag = create(self)
    local stop = ag.Stop
    function ag:Stop()
      stop(self)
      if armed() then error("Stop hook failure") end
    end
    return ag
  end
end

test("an error in a native finish or a public call starts the frame over", function()
  for _, path in ipairs({ "native finish", "get" }) do
    local f = fakeFrame()
    local m = Poly(f)
    throwOnStop(f, function() return true end)
    m:to({ x = 100 }, { duration = 0.1, ease = "linear" })
    run(0.05)
    f:SetPoint("CENTER", nil, "CENTER", 500, 90) -- a layout takes the slide over
    if path == "get" then
      assert(not pcall(m.get, m, "x"), "get: the error didn't reach the caller")
      takeReports(1) -- the halt's own Stop()
    else
      run(0.2)
      takeReports(2)
    end
    run(1)
    assert(not m:isMoving() and m:get("x") == 0 and f:VisualX() == 500, path .. ": the slide survived the takeover")
  end
end)

test("an error in hide()'s onComplete stops nothing", function()
  local f = fakeFrame()
  local m = Poly(f)
  m:to({ x = 50 }, { duration = 1, ease = "linear" })
  m:hide("fade", { duration = 0.1, onComplete = function() error("onComplete failed") end })
  run(0.3)
  takeReports(1)
  assert(not f.shown and m:isMoving("x"), "the error stopped the slide")
  run(1)
  assert(f.points[1][4] == 60 and not m:isMoving(), "the slide did not finish")
end)

test("a halt stops every group even when a Stop() hook throws", function()
  local f = fakeFrame(true)
  local m, armed = Poly(f), false
  throwOnStop(f, function() return armed end)
  m:to({ x = 100, y = 60, alpha = 0.5 }, { duration = 2, ease = "linear" })
  run(0.05)
  combat, armed = true, true
  m:to({ scale = 1.2 }) -- the puppet takes x and y over, and stopping their groups throws
  run(1 / 60)
  takeReports(2)
  armed = false
  local nx, ny, k, _, drawnAlpha = f:Native()
  assert(nx == 0 and ny == 0 and k == 1 and drawnAlpha == nil and not m:isMoving(), "halt left a group drawing")
  combat = false
end)

test("reentrant hooks on animation writers keep the last call", function()
  local exercised, writers = {}, {}
  local probe = fakeFrame():CreateAnimationGroup()
  for name in pairs(probe) do
    if name:match("^Set") or name == "Play" or name == "Pause" or name == "Stop" then writers[#writers + 1] = "group." .. name end
  end
  for name in pairs(probe:CreateAnimation("Translation")) do
    if name:match("^Set") then writers[#writers + 1] = "animation." .. name end
  end
  table.sort(writers)
  for _, path in ipairs({ "native", "puppet", "commit", "halt", "retarget native", "set native", "stop native", "adopt native", "handoff native" }) do
    for _, writer in ipairs(writers) do
      local f = fakeFrame(true)
      local m, nested, done = Poly(f), false, 0
      local function hook(name)
        m:get("x"); m:get("y"); m:get("scale")
        if nested or name ~= writer then return end
        nested = true
        exercised[name] = true
        m:stop()
        m:set({ x = 70, y = 45, scale = 1.3 })
        m:to({ alpha = 0.6, width = 310, height = 140 }, { duration = 0.1, onComplete = function()
          assert(f.w == 310 and f.h == 140, "animation hook completed before arrival")
          done = done + 1
        end })
      end
      local function wrap(object, prefix)
        for name, original in pairs(object) do
          if type(original) == "function" and (name:match("^Set") or name == "Play" or name == "Pause" or name == "Stop") then
            object[name] = function(self, ...)
              original(self, ...)
              hook(prefix .. name)
            end
          end
        end
      end
      local createGroup = f.CreateAnimationGroup
      function f:CreateAnimationGroup()
        local ag = createGroup(self)
        wrap(ag, "group.")
        local createAnimation = ag.CreateAnimation
        function ag:CreateAnimation(kind)
          local anim = createAnimation(self, kind)
          wrap(anim, "animation.")
          return anim
        end
        return ag
      end
      local hasNative = path:find("native", 1, true)
      combat = path ~= "native" and not hasNative
      -- For commit and halt, install the mutating hook only after the puppet
      -- exists. Reads still run during every setup call.
      local enabled = path == "native" or path == "puppet"
      local mutate = hook
      hook = function(name)
        if enabled and (path ~= "halt" or name == "group.Stop") then mutate(name) else m:get("x"); m:get("scale") end
      end
      m:to({ x = 100, y = 60, alpha = 0.2, scale = 0.8 }, { duration = 0.2, ease = "linear" })
      run(0.05)
      enabled = true
      if path == "retarget native" then m:to({ x = 80, y = 40, alpha = 0.5 }, { duration = 0.1 })
      elseif path == "set native" then m:set({ x = 80, y = 40, alpha = 0.5 })
      elseif path == "stop native" then m:stop()
      elseif path == "adopt native" then
        f:SetPoint("CENTER", nil, "CENTER", 200, 90)
        m:get("x")
      elseif path == "handoff native" then
        combat = true; m:to({ scale = 1.1 }); run(1 / 60)
      elseif path == "commit" then combat = false; fire("PLAYER_REGEN_ENABLED")
      elseif path == "halt" then
        local original = f.SetAlpha
        function f:SetAlpha() error("test: animation hook halt") end
        run(1 / 60)
        takeReports(1)
        f.SetAlpha = original
      end
      combat = false
      fire("PLAYER_REGEN_ENABLED")
      run(0.5)
      if nested and path == "halt" then
        assert(done == 0 and not m:isMoving() and m:get("x") == 0 and m:get("y") == 0,
          path .. "/" .. writer .. ": a call from a Stop hook during a halt ran")
      elseif nested then
        local label = path .. "/" .. writer
        local homeX, homeY = path == "adopt native" and 200 or 10, path == "adopt native" and 90 or 20
        assert(near(f:VisualX(), (homeX + 70) * 1.3) and near(f:VisualY(), (homeY + 45) * 1.3) and f.s == 1.3, label .. ": last layout call lost " .. f:VisualX() .. ", " .. f:VisualY() .. ", " .. f.s .. ", get " .. m:get("x") .. ", " .. m:get("y"))
        assert(f.w == 310 and f.h == 140 and done == 1 and not m:isMoving(), label .. ": last animation lost")
      end
      assert(#reported == 0, path .. "/" .. writer .. ": " .. tostring(reported[1]))
    end
  end
  for _, writer in ipairs(writers) do assert(exercised[writer], "unexercised animation writer " .. writer) end
end)

test("an error handler can start fresh work after every halt path", function()
  for _, path in ipairs({ "driver", "native start", "combat end", "driver in combat" }) do
    local f = fakeFrame(true)
    local m, done, reports = Poly(f), 0, 0
    local getHandler = geterrorhandler
    local setPoint, setAlpha = f.SetPoint, f.SetAlpha
    _G.geterrorhandler = function()
      return function()
        reports = reports + 1
        f.SetPoint, f.SetAlpha = setPoint, setAlpha
        assert(not m:isMoving() and m:get("x") == 0 and m:get("y") == 0, "error handler saw a motion before reset")
        m:to({ x = 70, width = 310 }, { duration = 0.1, onComplete = function()
          assert(f.w == 310 and m:get("x") == 70, "handler replacement completed before arrival")
          done = done + 1
        end })
      end
    end
    combat = path == "combat end" or path == "driver in combat"
    m:to({ x = 100, scale = 1.2 }, { duration = 0.2, ease = path == "native start" and "linear" or "outCubic" })
    if combat then run(0.05) end
    if path == "driver in combat" then
      function f:SetAlpha() error("test: alpha hook") end
      m:to({ alpha = 0.5 })
      run(1 / 60)
    else
      function f:SetPoint() error("test: anchor hook") end
      if path == "combat end" then combat = false; fire("PLAYER_REGEN_ENABLED") else run(2 / 60) end
    end
    _G.geterrorhandler = getHandler
    combat = false
    fire("PLAYER_REGEN_ENABLED")
    run(0.5)
    assert(reports == 1 and done == 1 and f.w == 310 and not m:isMoving(), path .. ": handler's fresh work was halted")
  end
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
  assert(f.shown and f.alpha == 0 and f.points[1][5] == 4, "show did not start from below")
  run(0.1)
  assert(f.alpha > 0 and f.alpha < 1 and f.points[1][5] > 4 and f.points[1][5] < 20, "show did not animate from below")
  run(0.4)
  assert(f.alpha == 1 and f.points[1][5] == 20, f.alpha .. " " .. f.points[1][5])
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
  assert(not f.shown and near(f.alpha, 0.4, 1 / 510), "deferred hide reset a taken-over alpha: " .. f.alpha)
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
  assert(not f.shown and near(f.alpha, 0.4, 1 / 510), "deferred hide reset a taken-over alpha: " .. f.alpha)
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
-- to(), set() or stop() hand a property to the caller. stop() with no name also
-- cancels show() and hide(), so the frame keeps its shown state. Once everything settles,
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
        -- stop() with no name cancels a running show() or hide(): the frame stays as shown as it is.
        if not name then lastVis, deferredShow = f.shown and "show" or "hide", nil end
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
  assert(near(tex.alpha, 0.5, 0.002) and tex.points[1][4] == 40 and tex.w == 160, "waited for combat to end")
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
