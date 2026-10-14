-- Polymorph: target-state animation for WoW frames.
--
--   local Poly = LibStub("Polymorph-1.0")
--   Poly(frame):to({ alpha = 1, y = 20 })                     -- spring (default)
--   Poly(frame):to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
--
-- Calling :to() again while a property is moving retargets it from its current
-- value. A spring keeps its velocity across the retarget.
--
-- Combat: on a protected frame (or the parent or anchor of one) in combat, the
-- game blocks SetPoint, SetSize, Show and Hide, and Polymorph treats SetScale the
-- same way. It never calls them there.
-- Alpha keeps animating, x and y keep animating through a native
-- animation, and the other blocked properties wait for combat to end.
-- docs/api.md has the details.
local _, ns = ...

local MAJOR, MINOR = "Polymorph-1.0", 1
local Poly
if type(ns) == "table" and ns.dev then
  -- Tests and dev tools load a fresh, private copy into ns.Polymorph.
  Poly = {}
  ns.Polymorph = Poly
else
  assert(LibStub, "Polymorph-1.0 requires LibStub")
  Poly = LibStub:NewLibrary(MAJOR, MINOR)
  if not Poly then return end -- an equal or newer copy is already loaded
end

local InCombatLockdown = InCombatLockdown
local abs, min, max = math.abs, math.min, math.max

---------------------------------------------------------------------------
-- Easing
---------------------------------------------------------------------------

-- Cubic bezier through (0,0), (x1,y1), (x2,y2), (1,1), solved for x the way
-- CSS does it: Newton steps, then bisection when the slope is too flat.
local function bezier(x1, y1, x2, y2)
  local cx, bx = 3 * x1, 3 * (x2 - x1) - 3 * x1
  local ax = 1 - cx - bx
  local cy, by = 3 * y1, 3 * (y2 - y1) - 3 * y1
  local ay = 1 - cy - by
  local function sampleX(t) return ((ax * t + bx) * t + cx) * t end
  local function sampleY(t) return ((ay * t + by) * t + cy) * t end
  local function slopeX(t) return (3 * ax * t + 2 * bx) * t + cx end
  return function(x)
    local t = x
    for _ = 1, 8 do
      local err = sampleX(t) - x
      if abs(err) < 1e-6 then return sampleY(t) end
      local d = slopeX(t)
      if abs(d) < 1e-6 then break end
      t = t - err / d
    end
    local lo, hi = 0, 1
    t = x
    for _ = 1, 30 do
      local v = sampleX(t)
      if abs(v - x) < 1e-6 then break end
      if v < x then lo = t else hi = t end
      t = (lo + hi) / 2
    end
    return sampleY(t)
  end
end

Poly.easings = {
  linear = function(p) return p end,
  inQuad = function(p) return p * p end,
  outQuad = function(p) return 1 - (1 - p) * (1 - p) end,
  inOutQuad = function(p) return p < 0.5 and 2 * p * p or 1 - (-2 * p + 2) ^ 2 / 2 end,
  outCubic = function(p) return 1 - (1 - p) ^ 3 end,
  inOutCubic = function(p) return p < 0.5 and 4 * p * p * p or 1 - (-2 * p + 2) ^ 3 / 2 end,
  ease = bezier(0.25, 0.1, 0.25, 1),
  easeOut = bezier(0, 0, 0.58, 1),
  easeInOut = bezier(0.42, 0, 0.58, 1),
}
Poly.bezier = bezier

-- Spring presets use react-spring's names and values (tension, friction, mass 1).
Poly.springs = {
  default = { stiffness = 170, damping = 26 },
  gentle = { stiffness = 120, damping = 14 },
  wobbly = { stiffness = 180, damping = 12 },
  stiff = { stiffness = 210, damping = 20 },
  slow = { stiffness = 280, damping = 60 },
  molasses = { stiffness = 280, damping = 120 },
}

local function resolveEase(ease)
  if type(ease) == "function" then return ease end
  if type(ease) == "table" then return bezier(ease[1], ease[2], ease[3], ease[4]) end
  return Poly.easings[ease or "outCubic"] or error("Polymorph: unknown ease " .. tostring(ease), 3)
end

local function resolveSpring(spring)
  if type(spring) == "table" then return spring end
  return Poly.springs[spring or "default"] or error("Polymorph: unknown spring " .. tostring(spring), 3)
end

---------------------------------------------------------------------------
-- Properties
---------------------------------------------------------------------------

-- x and y are offsets from the frame's first anchor as it was when Polymorph
-- first touched the frame. offsetX/Y is where the frame shows; layoutX/Y is
-- where its anchor actually is. They differ only while combat lockdown forces
-- drawing through the puppet.
--
-- Puppet: a native Translation animation, played and paused at full progress.
-- SetOffset on a paused animation moves the frame live, and the game allows
-- that on protected frames in combat, where SetPoint is blocked. When combat
-- ends, commit() anchors the frame where it shows and stops the puppet, which
-- lands on the same pixel. Measured in dev/jobs/core/native_puppet.lua.
local puppeted = {} -- motion -> true while its puppet is displaced

local function puppetMove(m)
  local p = m.puppet
  if not p then
    local ag = m.frame:CreateAnimationGroup()
    local tr = ag:CreateAnimation("Translation")
    tr:SetDuration(1)
    tr:SetSmoothing("NONE")
    p = { ag = ag, tr = tr }
    m.puppet = p
  end
  if not puppeted[m] then
    p.ag:Play()
    p.ag:Pause()
    p.tr:SetSmoothProgress(1)
    puppeted[m] = true
  end
  p.tr:SetOffset(m.offsetX - m.layoutX, m.offsetY - m.layoutY)
end

local function commit(m)
  local b = m.base
  m.frame:SetPoint(b[1], b[2], b[3], b[4] + m.offsetX, b[5] + m.offsetY)
  m.layoutX, m.layoutY = m.offsetX, m.offsetY
  if puppeted[m] then
    m.puppet.ag:Stop()
    puppeted[m] = nil
  end
end

local function writePoint(m)
  if m.isLocked then puppetMove(m) else commit(m) end
end

local PROPS = {
  alpha = {
    precision = 0.001,
    read = function(m) return m.frame:GetAlpha() end,
    write = function(m, v) m.frame:SetAlpha(min(1, max(0, v))) end,
  },
  scale = {
    restricted = true, precision = 0.0005,
    read = function(m) return m.frame:GetScale() end,
    write = function(m, v) m.frame:SetScale(max(0.0001, v)) end,
  },
  width = {
    restricted = true, precision = 0.05,
    read = function(m) return m.frame:GetWidth() end,
    write = function(m, v) m.frame:SetWidth(max(0, v)) end,
  },
  height = {
    restricted = true, precision = 0.05,
    read = function(m) return m.frame:GetHeight() end,
    write = function(m, v) m.frame:SetHeight(max(0, v)) end,
  },
  x = {
    restricted = true, native = true, precision = 0.05,
    read = function(m) return m.offsetX end,
    write = function(m, v) m.offsetX = v; writePoint(m) end,
  },
  y = {
    restricted = true, native = true, precision = 0.05,
    read = function(m) return m.offsetY end,
    write = function(m, v) m.offsetY = v; writePoint(m) end,
  },
}
Poly.properties = PROPS

-- Restricted properties without a native path wait for combat to end.
local function waitsWhileLocked(prop)
  return prop.restricted and not prop.native
end

---------------------------------------------------------------------------
-- Driver: one OnUpdate for every moving track, off while nothing moves.
---------------------------------------------------------------------------

local motions = setmetatable({}, { __mode = "k" }) -- frame -> motion
local active = {}                                    -- motion -> true while it moves
local stats = { frames = 0, ms = 0, peakTracks = 0 }
-- Frames survive a LibStub upgrade. A newer copy takes them over and replaces
-- their scripts. Animations running in the older copy stop where they are.
local driver = Poly._driver or CreateFrame("Frame")
Poly._driver = driver
driver:SetScript("OnUpdate", nil)
local profile = debugprofilestop
local STEP = 1 / 120

local function locked(m)
  return InCombatLockdown() and m.frame:IsProtected()
end

local function stepSpring(t, dt)
  local s = t.spring
  local mass = s.mass or 1
  while dt > 0 do
    local h = min(dt, STEP)
    local accel = (-s.stiffness * (t.value - t.target) - s.damping * t.velocity) / mass
    t.velocity = t.velocity + accel * h
    t.value = t.value + t.velocity * h
    dt = dt - h
  end
  return abs(t.velocity) < t.precision * 10 and abs(t.value - t.target) < t.precision
end

local function stepTween(t, dt)
  t.elapsed = t.elapsed + dt
  local p = t.duration > 0 and min(1, t.elapsed / t.duration) or 1
  local last = t.value
  t.value = t.from + (t.target - t.from) * t.ease(p)
  t.velocity = dt > 0 and (t.value - last) / dt or 0
  return p >= 1
end

-- Callbacks run after the loop, so a callback that starts a new animation never
-- adds tracks to a table the loop is traversing.
local callbacks, callbackCount = {}, 0

local function queueCallback(fn, frame, name)
  callbackCount = callbackCount + 1
  local c = callbacks[callbackCount]
  if not c then c = {}; callbacks[callbackCount] = c end
  c[1], c[2], c[3] = fn, frame, name
end

local function update(_, elapsed)
  local started = profile()
  local dt = min(elapsed, 0.1)
  local tracks = 0
  for m in pairs(active) do
    -- Checked every frame: combat can start in the middle of an animation.
    local isLocked = locked(m)
    m.isLocked = isLocked
    for name, t in pairs(m.tracks) do
      tracks = tracks + 1
      local prop = PROPS[name]
      if t.delay > 0 then
        t.delay = t.delay - dt
      elseif not (isLocked and waitsWhileLocked(prop)) then
        local rest
        if t.spring then rest = stepSpring(t, dt) else rest = stepTween(t, dt) end
        if rest then t.value = t.target end
        prop.write(m, t.value)
        if rest then
          m.tracks[name] = nil
          if t.onDone then queueCallback(t.onDone, m.frame, name) end
        end
      end
    end
    if next(m.tracks) == nil then
      active[m] = nil
    end
  end
  for i = 1, callbackCount do
    local c = callbacks[i]
    local fn, frame, name = c[1], c[2], c[3]
    c[1], c[2], c[3] = nil, nil, nil
    fn(frame, name)
  end
  callbackCount = 0
  if next(active) == nil then driver:SetScript("OnUpdate", nil) end
  stats.frames = stats.frames + 1
  stats.ms = stats.ms + (profile() - started)
  if tracks > stats.peakTracks then stats.peakTracks = tracks end
end

local function wake(m)
  if not active[m] then
    local wasIdle = next(active) == nil
    active[m] = true
    if wasIdle then driver:SetScript("OnUpdate", update) end
  end
end

---------------------------------------------------------------------------
-- Motion: the handle Poly(frame) returns.
---------------------------------------------------------------------------

local Motion = {}
Motion.__index = Motion

local function motionFor(frame)
  local m = motions[frame]
  if m then return m end
  local point, rel, relPoint, x, y = frame:GetPoint(1)
  local alpha = frame:GetAlpha()
  m = setmetatable({
    frame = frame, tracks = {},
    base = { point or "CENTER", rel, relPoint or point or "CENTER", x or 0, y or 0 },
    offsetX = 0, offsetY = 0, layoutX = 0, layoutY = 0, visibilityToken = 0,
    -- What show() returns to. A frame first touched at alpha 0 rests at 1.
    rest = { alpha = alpha > 0 and alpha or 1, scale = frame:GetScale(), width = frame:GetWidth(),
             height = frame:GetHeight(), x = 0, y = 0 },
  }, Motion)
  motions[frame] = m
  return m
end

-- Animates each property in `targets` toward its value.
-- opts: spring = preset name or { stiffness, damping, mass }
--       duration (seconds) and ease = name, { x1, y1, x2, y2 } or function
--       delay (seconds), onComplete(frame) when every property in this call has arrived
function Motion:to(targets, opts)
  opts = opts or {}
  local spring = not opts.duration and resolveSpring(opts.spring) or nil
  local ease = opts.duration and resolveEase(opts.ease) or nil
  local pending = 0
  local function arrived()
    pending = pending - 1
    if pending == 0 and opts.onComplete then opts.onComplete(self.frame) end
  end
  for name, target in pairs(targets) do
    local prop = PROPS[name] or error("Polymorph: unknown property " .. tostring(name), 2)
    local t = self.tracks[name]
    if not t then
      t = { value = prop.read(self), velocity = 0 }
      self.tracks[name] = t
    end
    t.target = target
    t.precision = prop.precision
    t.delay = opts.delay or 0
    t.spring = spring
    if ease then
      t.ease, t.duration, t.elapsed, t.from = ease, opts.duration, 0, t.value
    end
    pending = pending + 1
    t.onDone = arrived
  end
  if pending > 0 then wake(self) end
  return self
end

-- Jumps to values immediately and stops those properties.
function Motion:set(values)
  self.isLocked = locked(self)
  for name, value in pairs(values) do
    local prop = PROPS[name] or error("Polymorph: unknown property " .. tostring(name), 2)
    local t = self.tracks[name]
    self.tracks[name] = nil
    if self.isLocked and waitsWhileLocked(prop) then
      self:to({ [name] = value }, { duration = 0 }) -- applied when combat ends
    else
      prop.write(self, value)
    end
  end
  return self
end

-- Stops one property, or all of them, where they are.
function Motion:stop(name)
  for n in pairs(self.tracks) do
    if name == nil or n == name then self.tracks[n] = nil end
  end
  return self
end

function Motion:get(name)
  local t = self.tracks[name]
  if t then return t.value, t.velocity, t.target end
  return PROPS[name].read(self), 0, nil
end

function Motion:isMoving(name)
  if name then return self.tracks[name] ~= nil end
  return next(self.tracks) ~= nil
end

---------------------------------------------------------------------------
-- Show and hide
---------------------------------------------------------------------------

-- Presets name where the frame is while it is away: show() comes from there,
-- hide() goes there.
Poly.presets = {
  fade = { alpha = 0 },
  pop = { alpha = 0, scale = 0.92 },
  below = { alpha = 0, y = -16 },
  above = { alpha = 0, y = 16 },
  left = { alpha = 0, x = -16 },
  right = { alpha = 0, x = 16 },
}

local function resolveAway(away)
  if type(away) == "table" then return away end
  return Poly.presets[away or "fade"] or error("Polymorph: unknown preset " .. tostring(away), 3)
end

-- Work the game blocks on protected frames in combat, run once combat ends.
local afterCombat = {}
local combatWatch = Poly._combatWatch or CreateFrame("Frame")
Poly._combatWatch = combatWatch
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function()
  for m in pairs(puppeted) do
    m.isLocked = false
    commit(m)
  end
  for m, fn in pairs(afterCombat) do
    afterCombat[m] = nil
    fn()
  end
end)

function Motion:restAt(values)
  for name, value in pairs(values) do self.rest[name] = value end
  return self
end

-- Every show() and hide() replaces the previous one: it bumps the token, which
-- cancels a running hide's Hide(), and it clears any action deferred to combat end.
local function takeVisibility(m)
  m.visibilityToken = m.visibilityToken + 1
  afterCombat[m] = nil
  return m.visibilityToken
end

-- awayKeys holds every property that show() or hide() moved off rest and that
-- has not arrived back yet. show() and hide() add to it. It empties only when a
-- show() arrives at rest or a hide() finishes and resets the frame, so a hide
-- that interrupts anything still resets every property that is off rest.
local function markAway(m, targets)
  m.awayKeys = m.awayKeys or {}
  for name in pairs(targets) do m.awayKeys[name] = true end
end

-- Rest values for the `away` properties and everything still in awayKeys.
local function restingTargets(m, away)
  local targets = {}
  for name in pairs(away) do targets[name] = m.rest[name] end
  for name in pairs(m.awayKeys or {}) do targets[name] = m.rest[name] end
  return targets
end

-- Shows the frame from `away` (preset name or values) and animates to rest.
-- While a hide is running, show() cancels it and turns the frame around,
-- returning every property that hide was moving.
function Motion:show(away, opts)
  away = resolveAway(away)
  opts = opts or {}
  local token = takeVisibility(self)
  local frame = self.frame
  if not frame:IsShown() then
    if locked(self) then
      afterCombat[self] = function() self:show(away, opts) end
      return self
    end
    self:set(away)
    frame:Show()
  end
  local targets = restingTargets(self, away)
  markAway(self, targets)
  local userDone = opts.onComplete
  local copy = {}
  for k, v in pairs(opts) do copy[k] = v end
  -- Runs only if every property arrived. A later call that takes over one of
  -- them leaves it in awayKeys for that call to finish.
  copy.onComplete = function(frame)
    if self.visibilityToken == token then self.awayKeys = nil end
    if userDone then userDone(frame) end
  end
  return self:to(targets, copy)
end

-- Animates to `away`, then hides the frame and resets it to rest while hidden.
-- On a protected frame in combat the fade still plays, and Hide() waits for
-- combat to end. The frame takes clicks until then.
function Motion:hide(away, opts)
  away = resolveAway(away)
  opts = opts or {}
  local token = takeVisibility(self)
  local userDone = opts.onComplete
  local function finish()
    if self.visibilityToken ~= token then return end
    if locked(self) then
      afterCombat[self] = finish
      return
    end
    self.frame:Hide()
    self:set(restingTargets(self, away))
    self.awayKeys = nil
    if userDone then userDone(self.frame) end
  end
  local copy = {}
  for k, v in pairs(opts) do copy[k] = v end
  copy.onComplete = finish
  -- Locked: animate only what the game allows (alpha, and x/y via the puppet).
  -- The rest would wait for combat to end, and a fading frame does not need it.
  local targets = away
  if locked(self) then
    targets = {}
    for name, value in pairs(away) do
      if not waitsWhileLocked(PROPS[name]) then targets[name] = value end
    end
    if next(targets) == nil then finish() return self end
  end
  markAway(self, targets)
  return self:to(targets, copy)
end

setmetatable(Poly, { __call = function(_, frame) return motionFor(frame) end })

function Poly.stats()
  local moving = 0
  for _ in pairs(active) do moving = moving + 1 end
  return { frames = stats.frames, ms = stats.ms, peakTracks = stats.peakTracks, active = moving }
end

function Poly.resetStats()
  stats.frames, stats.ms, stats.peakTracks = 0, 0, 0
end
