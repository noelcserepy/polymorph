-- The fake WoW client that tests/core_test.lua and tools/skill_check.lua run
-- Polymorph against. Runs on Lua 5.1+. From the repository root, before
-- loading the library:
--   local wow = dofile("tests/fake_wow.lua")
-- It installs the game's globals and returns the controls in `wow`:
--   wow.combat         InCombatLockdown()'s answer
--   wow.run(s, fps)    runs frames for s seconds
--   wow.fire(event)    runs the OnEvent handlers registered for event
--   wow.blocked(r, m)  called for a call the client blocks, which is then skipped. Errors by default.
--   wow.lenient        when true, methods the fake doesn't model are no-ops
--   wow.realFormat     string.format without the 32-bit %d limit
--   wow.Region         the methods of every frame, texture and font string
--
-- Every line that models the client cites the in-game job and date that
-- measured it, UNMEASURED when nothing did, or CONTRADICTED with the
-- measurement it disagrees with. The jobs and their notes are the
-- maintainer's private harness, run on WoW Forever beta 1.60.1 (build 70374 on
-- 2026-10-14 and 15, 70425 on 2026-10-16). "Probe session 1" is the first
-- probe, 2026-10-14. A change here keeps its citation with it.
--
-- Not modelled, so the fake errors or ignores it: a non-uniform or SetScaleFrom
-- other than 1 Scale, smoothing names other than the four below, a frame's size
-- from two anchors, a Scale animation on a parent scaling its children, anchor
-- loops, the ADDON_ACTION_BLOCKED event and popup, and the per-addon caps of
-- 2000 animation groups and 500 timers (startup log, 2026-10-14).

local wow = { combat = false, lenient = false }
unpack = unpack or table.unpack

-- Deliberate difference: the client returns normally from a blocked call,
-- skips it, fires ADDON_ACTION_BLOCKED and shows a popup (probe session 1).
-- The fake hands it to wow.blocked, which errors unless a harness replaces it.
function wow.blocked(_, method) error(method .. " while locked", 4) end

local clock, tick, frameNumber = 0, 1 / 60, 0
-- Which callback the game is in, for SetText and SetAlphaGradient.
local callback = 0
local inOnUpdate, inTimer = false, false
local updating, events, timers, allGroups = {}, {}, {}, {}

local function noop() end
-- With wow.lenient, a capitalized method the fake doesn't model is a no-op,
-- so a harness can run code that calls the wider API.
local function lenientIndex(class)
  return function(_, k)
    local v = class and class[k]
    if v == nil and wow.lenient and type(k) == "string" and k:match("^%u") then return noop end
    return v
  end
end
-- Every frame, texture and font string method, for tests that wrap them all.
local Region = {}
wow.Region = Region
local regionMeta = { __index = lenientIndex(Region) }
local lenientMeta = { __index = lenientIndex(nil) }

-- Clock --------------------------------------------------------------------

-- GetTime() is the same in a timer callback and the OnUpdate of one frame: regions_gradient2.lua, 2026-10-15.
-- It grows by OnUpdate's elapsed between frames: UNMEASURED.
_G.GetTime = function() return clock end
-- GetTickTime() equals OnUpdate's elapsed, also in job code and C_Timer callbacks: tick_time.lua, 2026-10-15.
_G.GetTickTime = function() return tick end
_G.debugprofilestop = function() return os.clock() * 1000 end

-- Combat -------------------------------------------------------------------

_G.InCombatLockdown = function() return wow.combat end
-- A region is locked while InCombatLockdown() and its own IsProtected(): probe session 1 for frames.
-- A texture or font string of a SecureActionButtonTemplate button reports IsProtected() false, before
-- and in combat, while the button reports true: regions.lua, 2026-10-15, regions_combat.lua, 2026-10-16.
-- Their SetPoint, SetSize, SetWidth, SetHeight, SetScale, Show and Hide in combat applied with 0 blocked
-- actions: textures, regions_combat.lua, 2026-10-15; textures and font strings, regions_combat.lua, 2026-10-16.
-- A plain frame accepts everything in combat: probe session 1.
-- The parent of a protected frame is protected too (probe session 1): not modelled.
local function allowed(r, method)
  if wow.combat and r.protected then
    wow.blocked(r, method)
    return false
  end
  return true
end

-- Errors -------------------------------------------------------------------

-- geterrorhandler() returns the handler seterrorhandler() installed, and calling it reports the
-- error: errors.lua, 2026-10-15.
local errorHandler = function(err) error(err, 0) end
_G.seterrorhandler = function(fn) errorHandler = fn end
_G.geterrorhandler = function() return errorHandler end

-- Timers -------------------------------------------------------------------

-- C_Timer.After(0, fn) runs fn in the next frame, never the one that scheduled it: start_timing.lua,
-- 2026-10-15 (60 of 60). A timer runs in the first later frame whose GetTime() has reached its
-- due time: UNMEASURED for delays above 0. Timers due in one frame run in the order they were
-- made: UNMEASURED.
local function newTimer(seconds, fn)
  local t = { due = clock + seconds, frame = frameNumber, fn = fn }
  -- C_Timer.NewTimer and Cancel(): UNMEASURED (the library does not call them).
  function t.Cancel(self) self.cancelled = true end
  timers[#timers + 1] = t
  return t
end
_G.C_Timer = {
  After = function(seconds, fn) newTimer(seconds, fn) end,
  NewTimer = newTimer,
}
local function runTimers()
  local due = {}
  for i = #timers, 1, -1 do
    local t = timers[i]
    if t.frame < frameNumber and t.due <= clock then
      table.remove(timers, i)
      table.insert(due, 1, t)
    end
  end
  inTimer = true
  -- Each timer callback is its own callback: UNMEASURED between two timers.
  for _, t in ipairs(due) do
    if not t.cancelled then
      callback = callback + 1
      t.fn(t)
    end
  end
  inTimer = false
end

-- Strings ------------------------------------------------------------------

-- string.format errors on %d and %i outside the 32-bit range: UNMEASURED in this client.
-- Reference Lua uses 64 bits, so the fake adds the limit.
local realFormat = string.format
wow.realFormat = realFormat
string.format = function(fmt, ...)
  local i = 0
  for spec in fmt:gmatch("%%[-+ #0-9.]*([%a%%])") do
    if spec ~= "%" then
      i = i + 1
      local v = select(i, ...)
      if (spec == "d" or spec == "i") and type(v) == "number" and (v >= 2 ^ 31 or v < -2 ^ 31) then
        error("integer overflow attempting to store " .. realFormat("%.0f", v), 2)
      end
    end
  end
  return realFormat(fmt, ...)
end
-- BreakUpLargeNumbers(n) groups whole numbers in threes with commas: UNMEASURED.
_G.BreakUpLargeNumbers = function(n)
  local out = realFormat("%.0f", n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- The frame order ----------------------------------------------------------

-- A Translation group played from OnUpdate draws its first frame against the
-- anchor the frame had before that frame's scripts ran: native_order.lua,
-- 2026-10-15, recorded at 120 fps, 3 of 8 starts from OnUpdate misdrew for 1-2
-- frames. The fake misdraws every such start, for one frame. The same calls
-- from a C_Timer callback: 0 of 32 misdrew, and the fake draws them right.
-- Polymorph's start timer: native_contexts.lua, 2026-10-15 (96 recorded starts
-- at 120 fps from a timer, an OnUpdate, a delay and onComplete, 0 flagged).
-- From event code: UNMEASURED, and the fake draws them right.
local misdrawn = {}
local function clearMisdraws()
  for _, r in ipairs(misdrawn) do r.pointBefore, r.staleAnchor = nil, nil end
  misdrawn = {}
end

-- Native animations advance after the frame's scripts, so a group drawn in the
-- frame it was played already counts that frame: anim_clock.lua, draw_lag.lua,
-- 2026-10-15. A group's elapsed read in OnUpdate is GetTime() minus GetTime() in
-- the frame it was played: anim_clock.lua, 2026-10-15.
local function advanceAnimations(dt)
  for _, ag in ipairs(allGroups) do
    if ag.playing and not ag.paused then
      ag.elapsed = ag.elapsed + dt
      -- A group finishes when its longest animation ends: UNMEASURED.
      local longest = 0
      for _, a in ipairs(ag.anims) do longest = math.max(longest, a.duration) end
      if ag.elapsed >= longest then
        ag.playing = false
        -- OnFinished fires in the animation step of the frame whose elapsed
        -- reaches the duration, before drawing: UNMEASURED. That it fires,
        -- also played in reverse: native_reverse.lua, 2026-10-14.
        if ag.scripts.OnFinished then ag.scripts.OnFinished(ag) end
      end
    end
  end
end

-- Runs frames as the client does: timers, then every OnUpdate, then
-- animations, then drawing. Code between calls runs at the start of the next
-- frame, as an event does, so GetTickTime() is that frame's elapsed time and
-- the Visual and Rect methods give what the last frame drew.
-- Timer callbacks run before OnUpdate scripts: start_timing.lua, 2026-10-15
-- (60 of 60 frames, against one probe OnUpdate). Event code runs before the
-- frame's timers and OnUpdates: UNMEASURED.
function wow.run(seconds, fps)
  local dt = 1 / (fps or 60)
  for _ = 1, math.floor(seconds / dt + 0.5) do
    clearMisdraws()
    runTimers()
    -- OnUpdate runs only on visible frames, in the order the frames were
    -- made: UNMEASURED. Each script is its own callback: measured for a timer
    -- and an OnUpdate in one frame, regions_gradient2.lua, 2026-10-15,
    -- UNMEASURED between two OnUpdates.
    local list = {}
    for f in pairs(updating) do list[#list + 1] = f end
    table.sort(list, function(a, b) return a.id < b.id end)
    inOnUpdate = true
    for _, f in ipairs(list) do
      local fn = f.scripts.OnUpdate
      if fn and f:IsVisible() then
        callback = callback + 1
        fn(f, tick)
      end
    end
    inOnUpdate = false
    advanceAnimations(tick)
    clock, tick = clock + dt, dt
    frameNumber = frameNumber + 1
    callback = callback + 1 -- code after this runs as the next frame's event
  end
end

-- Writers work again when PLAYER_REGEN_ENABLED fires: combat.lua, 2026-10-14
-- (the library commits in that handler, 0 blocked actions).
-- Handlers run in the order their frames registered: UNMEASURED.
-- InCombatLockdown() is false inside PLAYER_REGEN_ENABLED handlers: UNMEASURED; the harness sets wow.combat.
function wow.fire(e, ...)
  for _, f in ipairs(events[e] or {}) do
    local fn = f.scripts.OnEvent
    if fn then fn(f, e, ...) end
  end
end

-- Regions ------------------------------------------------------------------

local nextId = 0
-- A new frame, texture or font string is shown, at alpha 1 and scale 1, 0x0,
-- with no anchors: UNMEASURED. GetPoint(1) on one with no anchors returns nil:
-- anchors_probe.lua, 2026-10-15.
local function newRegion(kind, parent, protected, isFrame)
  nextId = nextId + 1
  return setmetatable({ id = nextId, kind = kind, parent = parent, protected = protected, isFrame = isFrame,
                        scripts = {}, shown = true, alpha = 1, w = 0, h = 0, s = 1, points = {}, groups = {} },
                      regionMeta)
end

-- A frame made from SecureActionButtonTemplate is protected: probe session 1.
-- Any other template whose name contains "Secure": UNMEASURED.
_G.CreateFrame = function(kind, _, parent, template)
  local protected = type(template) == "string" and template:find("Secure") ~= nil
  return newRegion(kind or "Frame", parent, protected, true)
end
-- Textures and font strings have every method the library calls: regions.lua, 2026-10-15.
function Region:CreateTexture() return newRegion("Texture", self, false, false) end
function Region:CreateFontString() return newRegion("FontString", self, false, false) end
-- IsObjectType("Frame") is false for textures and font strings: regions.lua, 2026-10-15.
function Region:IsObjectType(kind) return kind == self.kind or (kind == "Frame" and self.isFrame) end
function Region:GetParent() return self.parent end
function Region:IsProtected() return self.protected end

-- Alpha is stored in steps of 1/255, so SetAlpha(0.5) reads 0.50196: anchors_probe.lua, 2026-10-15.
-- SetAlpha works on a locked frame: probe session 1.
function Region:SetAlpha(v) self.alpha = math.floor(v * 255 + 0.5) / 255 end
-- GetAlpha() read from OnUpdate reports the frame's own alpha under an Alpha
-- animation: native_curves.lua, 2026-10-14. Read from a C_Timer callback it
-- reports the drawn alpha, on frames, textures and font strings:
-- regions_measure.lua, regions_gradient.lua, 2026-10-15. From event code: UNMEASURED, the own alpha.
-- A finished Alpha leaves GetAlpha() at the value set before Play: native_reverse.lua, 2026-10-14.
function Region:GetAlpha()
  if inTimer then return select(5, self:Native()) or self.alpha end
  return self.alpha
end

-- Sizes and scale. GetScale() and GetWidth() read from OnUpdate report the
-- frame's own values under a Scale: native_curves.lua, 2026-10-14. GetHeight()
-- the same: UNMEASURED. Getters return exactly the value set: CONTRADICTED,
-- the client read back 59.9999 for a width of 60 and 30.0000019 for 30
-- (regions_combat.lua, 2026-10-16). The library compares sizes within 0.01.
-- SetSize is blocked on a locked frame: probe session 1. SetWidth, SetHeight
-- and SetScale: UNMEASURED.
function Region:SetSize(w, h) if allowed(self, "SetSize") then self.w, self.h = w, h end end
function Region:SetWidth(w) if allowed(self, "SetWidth") then self.w = w end end
function Region:SetHeight(h) if allowed(self, "SetHeight") then self.h = h end end
function Region:SetScale(s) if allowed(self, "SetScale") then self.s = s end end
function Region:GetWidth() return self.w end
function Region:GetHeight() return self.h end
function Region:GetSize() return self.w, self.h end
function Region:GetScale() return self.s end

-- Anchors. SetPoint is blocked on a locked frame: probe session 1.
-- SetPoint() replaces the point of the same name in its place, or adds one,
-- and keeps the other points in order: anchors_probe.lua, 2026-10-15.
-- An omitted relativeTo is the parent, an explicit nil stays nil for GetPoint(),
-- and an omitted relativePoint is the point: UNMEASURED.
function Region:SetPoint(point, ...)
  if not allowed(self, "SetPoint") then return end
  local a, b, c, d = ...
  local rel, relPoint, x, y
  if select("#", ...) == 0 or type(a) == "number" then rel, x, y = self.parent, a, b
  elseif type(b) == "number" then rel, x, y = a, b, c
  else rel, relPoint, x, y = a, b, c, d end
  if inOnUpdate and not self.pointBefore then
    self.pointBefore = self.points[1]
    misdrawn[#misdrawn + 1] = self
  end
  local i = #self.points + 1
  for j, p in ipairs(self.points) do
    if p[1] == point then i = j end
  end
  self.points[i] = { point, rel, relPoint or point, x or 0, y or 0 }
end
-- Moving both anchors of a two-anchor frame by the same offset keeps its
-- width: anchors_probe.lua, 2026-10-15. The fake keeps width as a field, which agrees.
-- In the client SetAllPoints sets TOPLEFT and BOTTOMRIGHT. Here it sets
-- TOPLEFT only, since sizes from two anchors aren't modelled.
function Region:SetAllPoints(rel) self:SetPoint("TOPLEFT", rel or self.parent, "TOPLEFT", 0, 0) end
-- ClearAllPoints() removes every point: anchors_probe.lua, 2026-10-15. Blocked on a locked frame: UNMEASURED.
function Region:ClearAllPoints() if allowed(self, "ClearAllPoints") then self.points = {} end end
-- GetNumPoints() counts the anchors and GetPoint(i) returns the i-th, nil
-- past the last: anchors_probe.lua, 2026-10-15. GetPoint() ignores animation
-- displacement: native_probe.lua, native_puppet.lua, combat.lua, 2026-10-14.
-- The fake returns offsets exactly: CONTRADICTED, the client returns them
-- within 3e-6 of those set (anchors_probe.lua, 2026-10-15) and a texture's 100
-- as 99.99999 (regions.lua, 2026-10-15). The library allows 0.01.
-- GetPoint() on a locked frame in combat: UNMEASURED.
function Region:GetNumPoints() return #self.points end
function Region:GetPoint(i)
  local p = self.points[i or 1]
  if p then return unpack(p, 1, 5) end
end

-- Visibility. Hide is blocked on a locked frame: probe session 1. Show: UNMEASURED.
-- IsShown() reports the region's own flag, and IsVisible() also needs every parent shown: UNMEASURED.
function Region:Show() if allowed(self, "Show") then self.shown = true end end
function Region:Hide() if allowed(self, "Hide") then self.shown = false end end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end

-- Scripts and events. Not client measurements: the harness's plumbing.
function Region:SetScript(name, fn)
  self.scripts[name] = fn
  if name == "OnUpdate" then updating[self] = fn and true or nil end
end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
  local old = self.scripts[name]
  self:SetScript(name, old and function(...) old(...); fn(...) end or fn)
end
function Region:RegisterEvent(e)
  events[e] = events[e] or {}
  table.insert(events[e], self)
end

-- Text, color and gradients. SetText, SetVertexColor and SetAlphaGradient on
-- regions of protected frames in combat raised 0 blocked actions, and the text
-- and color read back changed: regions_combat.lua, 2026-10-15.
-- SetAlphaGradient(start, length) shows `start` characters and fades the next
-- `length` out, counting on across wrapped lines, a UTF-8 character once, and
-- no |c color codes: regions_measure.lua, regions_gradient.lua, 2026-10-15.
-- ClearAlphaGradient() shows it all: regions.lua, 2026-10-15. The fake keeps
-- the drawn gradient in `gradient` and leaves counting to the test.
-- SetText, even of the same string, clears the drawn gradient, and a gradient
-- set later in the same callback doesn't draw. One set in a later callback,
-- such as an OnUpdate after a timer in the same frame, does:
-- regions_gradient.lua, regions_gradient2.lua, 2026-10-15.
function Region:SetText(text)
  self.text, self.gradient, self.textCallback = text, nil, callback
end
function Region:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
function Region:GetText() return self.text end
function Region:SetAlphaGradient(start, length)
  if self.textCallback ~= callback then self.gradient = { start, length } end
end
function Region:ClearAlphaGradient() self.gradient = nil end
function Region:SetVertexColor(r, g, b) self.color = { r, g, b } end
-- A new texture's vertex color is white: UNMEASURED.
function Region:GetVertexColor() return unpack(self.color or { 1, 1, 1 }) end

-- Native animations --------------------------------------------------------

-- The NONE, IN, OUT and IN_OUT smoothing curves: native_curves.lua, 2026-10-14.
local CURVES = {
  NONE = function(p) return p end,
  IN = function(p) return 1 - math.cos(p * math.pi / 2) end,
  OUT = function(p) return math.sin(p * math.pi / 2) end,
  IN_OUT = function(p) return (1 - math.cos(p * math.pi)) / 2 end,
}

-- CreateAnimationGroup and native Alpha, Translation and Scale groups work on a
-- locked frame: probe session 1. On textures and font strings, Alpha and
-- Translation, drawing at the same x and brightness as a Lua tween on the same
-- curve: regions_measure.lua, 2026-10-15. Scale there: UNMEASURED.
-- Methods are fields of each group and animation, so a test can wrap them all.
function Region:CreateAnimationGroup()
  local owner = self
  local ag = setmetatable({ playing = false, paused = false, reverse = false, elapsed = 0, anims = {}, scripts = {} }, lenientMeta)
  owner.groups[#owner.groups + 1] = ag
  allGroups[#allGroups + 1] = ag
  function ag:CreateAnimation(kind)
    -- A new animation lasts 1 s with NONE smoothing: UNMEASURED (the library sets both).
    local a = setmetatable({ kind = kind, duration = 1, smoothing = "NONE", ox = 0, oy = 0, k = 1,
                             origin = { "CENTER", 0, 0 } }, lenientMeta)
    function a:SetDuration(d) self.duration = d end
    function a:SetSmoothing(v) assert(CURVES[v], "smoothing not modelled: " .. tostring(v)); self.smoothing = v end
    -- SetSmoothProgress() on a paused animation sets its drawn progress: native_puppet.lua, 2026-10-14.
    -- The value holds while its group plays unpaused: UNMEASURED.
    function a:SetSmoothProgress(v) self.forced = v end
    -- GetProgress() is elapsed / duration, capped at 1: UNMEASURED. Played in
    -- reverse it runs from 1 to 0: native_reverse.lua, 2026-10-14.
    function a:GetProgress()
      local p = math.min(1, ag.elapsed / self.duration)
      return ag.reverse and 1 - p or p
    end
    -- GetSmoothProgress() is the curve applied to GetProgress(): native_curves.lua, 2026-10-14.
    function a:GetSmoothProgress() return self.forced or CURVES[self.smoothing](self:GetProgress()) end
    function a:SetScaleFrom(x, y) assert(x == 1 and y == 1, "SetScaleFrom other than 1 not modelled") end
    -- SetScaleTo() and SetOffset() on a paused animation move the drawing live: native_puppet.lua, 2026-10-14.
    function a:SetScaleTo(x, y) assert(x == y, "non-uniform scale not modelled"); self.k = x end
    -- A Scale grows around its origin, CENTER by default, and SetOrigin(point)
    -- keeps that point still: scale_compose.lua, 2026-10-14. SetOrigin()'s x and
    -- y are in the frame's own units: UNMEASURED (the library passes 0, 0).
    function a:SetOrigin(point, x, y) self.origin = { point, x or 0, y or 0 } end
    function a:SetOffset(x, y) self.ox, self.oy = x, y end
    function a:SetFromAlpha(v) self.from = v end
    function a:SetToAlpha(v) self.to = v end
    ag.anims[#ag.anims + 1] = a
    return a
  end
  -- Play() restarts from progress 0 and clears a SetSmoothProgress() value: UNMEASURED.
  function ag:Play(reverse)
    self.playing, self.paused, self.reverse, self.elapsed = true, false, reverse or false, 0
    for _, a in ipairs(self.anims) do
      a.forced = nil
      if inOnUpdate and a.kind == "Translation" then
        owner.staleAnchor = owner.pointBefore or owner.points[1]
        misdrawn[#misdrawn + 1] = owner
      end
    end
  end
  -- Pause() holds the drawn displacement: native_probe.lua, 2026-10-14.
  function ag:Pause() self.paused = true end
  -- Stop() removes the displacement: native_puppet.lua, 2026-10-14. Stopping a
  -- paused Translation and calling SetPoint() at the same offset lands on the
  -- same pixel: native_probe.lua, 2026-10-14. Stop() does not fire OnFinished: UNMEASURED.
  function ag:Stop() self.playing = false end
  -- IsPlaying() is true while paused, and false after Stop() or finishing: UNMEASURED.
  function ag:IsPlaying() return self.playing end
  -- Only OnFinished fires here.
  function ag:SetScript(name, fn) self.scripts[name] = fn end
  return ag
end

-- What every playing group on the region adds: translation, scale and its
-- origin, and alpha. A finished group stops drawing, so the region draws its
-- own values again: native_order.lua, 2026-10-15 (SetPoint in OnFinished, no
-- snap in 32 recorded finishes).
-- Translation groups on one frame add up: native_tweens.lua, 2026-10-15. Two
-- Translations in one group: UNMEASURED (the probe's group had finished).
-- Scale groups multiply, and the last playing Scale's origin wins: UNMEASURED.
-- An Alpha animation's value replaces the region's alpha: native_tweens.lua,
-- 2026-10-15. Of two playing Alpha animations, the last one made draws: UNMEASURED.
function Region:Native()
  local x, y, k, origin, alpha = 0, 0, 1, { "CENTER", 0, 0 }, nil
  for _, ag in ipairs(self.groups) do
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

-- Drawing ------------------------------------------------------------------
-- What the last frame drew. These are the fake's, not the game's, methods.

-- UIParent's size is the harness's choice, not the client's.
local UIParent = CreateFrame("Frame")
UIParent.w, UIParent.h = 1000, 800
_G.UIParent = UIParent

-- A child's scale is its own times its parents': UNMEASURED.
local function effectiveScale(r) return r.s * (r.parent and effectiveScale(r.parent) or 1) end
-- Where a named point sits, relative to the center of a w x h box.
local function pointOffset(point, w, h)
  local x = point:find("LEFT") and -w / 2 or point:find("RIGHT") and w / 2 or 0
  local y = point:find("TOP") and h / 2 or point:find("BOTTOM") and -h / 2 or 0
  return x, y
end

-- Where the region's first anchor point draws, relative to the point it is
-- anchored to, and its drawn width and height, in screen units.
-- Anchor offsets are in the region's own scaled units: scale_units.lua, 2026-10-14.
-- Translation offsets are in its scaled units, and a Scale in the same group
-- does not multiply them: scale_compose.lua, scale_units.lua, 2026-10-14.
function Region:Visual()
  local nx, ny, k, o = self:Native()
  local e = effectiveScale(self)
  local point = assert(self.staleAnchor or self.points[1], "region has no anchor")
  local w, h = self.w * e, self.h * e
  local ax, ay = (point[4] + nx) * e, (point[5] + ny) * e
  local px, py = pointOffset(point[1], w, h)
  local ox, oy = pointOffset(o[1], w, h)
  ox, oy = ox + o[2] * e, oy + o[3] * e
  -- The origin stays put and everything else scales away from it by k.
  local originX, originY = ax + ox - px, ay + oy - py
  return originX + (ax - originX) * k, originY + (ay - originY) * k, w * k, h * k
end
function Region:VisualX() return (self:Visual()) end
function Region:VisualY() return select(2, self:Visual()) end
function Region:VisualScale() return effectiveScale(self) * select(3, self:Native()) end
-- A child's drawn alpha is its own times its parents': anchors_probe.lua, 2026-10-15
-- (0.5 under 0.5 has effective alpha 64/255). The fake doesn't round the product.
function Region:VisualAlpha()
  local own = select(5, self:Native()) or self.alpha
  return own * (self.parent and self.parent:VisualAlpha() or 1)
end
-- The region's drawn rectangle on screen: left, bottom, width, height. An
-- anchor's offset counts from the named point of the region it is anchored to:
-- measured for CENTER on UIParent's CENTER, scale_compose.lua, 2026-10-14.
-- Other points and anchor chains: UNMEASURED.
function Region:Rect()
  if self == UIParent then return 0, 0, self.w, self.h end
  local x, y, w, h = self:Visual()
  local point = self.staleAnchor or self.points[1]
  local rl, rb, rw, rh = (point[2] or UIParent):Rect()
  local rx, ry = pointOffset(point[3], rw, rh)
  local px, py = pointOffset(point[1], w, h)
  return rl + rw / 2 + rx + x - px - w / 2, rb + rh / 2 + ry + y - py - h / 2, w, h
end

return wow
