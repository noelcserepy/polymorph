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
-- Alpha keeps animating, x, y and scale keep animating through native
-- animations, and width and height wait for combat to end.
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

local InCombatLockdown, GetTime = InCombatLockdown, GetTime
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

local HALF_PI = math.pi / 2
local function linear(p) return p end
local function inSine(p) return 1 - math.cos(p * HALF_PI) end
local function outSine(p) return math.sin(p * HALF_PI) end
local function inOutSine(p) return (1 - math.cos(p * math.pi)) / 2 end

Poly.easings = {
  linear = linear,
  inSine = inSine,
  outSine = outSine,
  inOutSine = inOutSine,
  inQuad = function(p) return p * p end,
  outQuad = function(p) return 1 - (1 - p) * (1 - p) end,
  inOutQuad = function(p)
    if p < 0.5 then return 2 * p * p end
    local q = 2 - 2 * p
    return 1 - q * q / 2
  end,
  outCubic = function(p) local q = 1 - p; return 1 - q * q * q end,
  inOutCubic = function(p)
    if p < 0.5 then return 4 * p * p * p end
    local q = 2 - 2 * p
    return 1 - q * q * q / 2
  end,
  ease = bezier(0.25, 0.1, 0.25, 1),
  easeOut = bezier(0, 0, 0.58, 1),
  easeInOut = bezier(0.42, 0, 0.58, 1),
}
Poly.bezier = bezier

-- The game's own smoothing curves, measured in the client: NONE is linear, IN
-- is 1 - cos(p·π/2), OUT is sin(p·π/2), IN_OUT is (1 - cos(p·π)) / 2. A tween
-- with one of these eases can run as a native animation. Played in reverse, a
-- curve runs mirrored, so a reversed IN draws outSine.
local NATIVE_SMOOTHING = {
  [linear] = { forward = "NONE", reverse = "NONE" },
  [inSine] = { forward = "IN", reverse = "OUT" },
  [outSine] = { forward = "OUT", reverse = "IN" },
  [inOutSine] = { forward = "IN_OUT", reverse = "IN_OUT" },
}

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
-- drawing through the puppet. The same goes for scale: drawScale is where it
-- shows and layoutScale is the frame's own scale, both set only while puppeted.
--
-- Puppet: a native Translation and Scale, played and paused at full progress.
-- SetOffset and SetScaleTo on a paused animation change the drawing live, and
-- the game allows that on protected frames in combat, where SetPoint and
-- SetScale are blocked. When combat ends, commit() sets the frame to what it
-- shows and stops the puppet, which lands on the same pixel.
--
-- SetScale also scales the anchor offset, while the Scale animation grows
-- around the frame's anchor point. Translation offsets are in the frame's own
-- scaled units and ignore the Scale animation, so the puppet moves the anchor
-- point to where SetScale would put it: offset * k - layout, with
-- k = drawScale / layoutScale. Both facts were measured in the client.
local puppeted = {} -- motion -> true while its puppet is displaced
local handNativeToPuppet -- defined with the native tween code below

local function puppetMove(m)
  -- The puppet's offsets assume it owns every displacement, so a native x or y
  -- tween still drawing becomes a Lua track first.
  handNativeToPuppet(m)
  local p = m.puppet
  if not p then
    local ag = m.frame:CreateAnimationGroup()
    local tr = ag:CreateAnimation("Translation")
    tr:SetDuration(1)
    tr:SetSmoothing("NONE")
    local sc = ag:CreateAnimation("Scale")
    sc:SetDuration(1)
    sc:SetSmoothing("NONE")
    sc:SetScaleFrom(1, 1)
    sc:SetScaleTo(1, 1)
    p = { ag = ag, tr = tr, sc = sc, k = 1 }
    m.puppet = p
  end
  local b = m.base
  if not puppeted[m] then
    m.layoutScale = m.frame:GetScale()
    m.drawScale = m.drawScale or m.layoutScale
    p.sc:SetOrigin(b[1], 0, 0)
    p.ag:Play()
    p.ag:Pause()
    p.tr:SetSmoothProgress(1)
    p.sc:SetSmoothProgress(1)
    puppeted[m] = true
  end
  local k = m.drawScale / m.layoutScale
  if k ~= p.k then
    p.sc:SetScaleTo(k, k)
    p.k = k
  end
  p.tr:SetOffset((b[4] + m.offsetX) * k - (b[4] + m.layoutX), (b[5] + m.offsetY) * k - (b[5] + m.layoutY))
end

local function commit(m)
  local b = m.base
  if m.drawScale then
    if m.drawScale ~= m.layoutScale then m.frame:SetScale(m.drawScale) end
    m.drawScale = nil
  end
  m.frame:SetPoint(b[1], b[2], b[3], b[4] + m.offsetX, b[5] + m.offsetY)
  m.layoutX, m.layoutY = m.offsetX, m.offsetY
  if puppeted[m] then
    m.puppet.ag:Stop()
    puppeted[m] = nil
  end
end

local function writeLayout(m)
  if m.isLocked then puppetMove(m) else commit(m) end
end

-- The one writer of width and height: it clamps them and picks the game call.
-- The driver stages both, then writes them in one call per frame. set() stages
-- one and writes at once. x and y stage straight into offsetX and offsetY.
local function writeSize(m)
  local w, h = m.stagedWidth, m.stagedHeight
  m.stagedWidth, m.stagedHeight = nil, nil
  if w and h then
    m.frame:SetSize(max(0, w), max(0, h))
  elseif w then
    m.frame:SetWidth(max(0, w))
  else
    m.frame:SetHeight(max(0, h))
  end
end

local PROPS = {
  alpha = {
    precision = 0.001, tween = "Alpha",
    read = function(m) return m.frame:GetAlpha() end,
    write = function(m, v) m.frame:SetAlpha(min(1, max(0, v))) end,
  },
  scale = {
    restricted = true, native = true, precision = 0.0005,
    read = function(m) return m.drawScale or m.frame:GetScale() end,
    write = function(m, v)
      v = max(0.0001, v)
      if m.isLocked or puppeted[m] then
        m.drawScale = v
        writeLayout(m)
      else
        m.frame:SetScale(v)
      end
    end,
  },
  width = {
    restricted = true, precision = 0.05,
    read = function(m) return m.frame:GetWidth() end,
    write = function(m, v) m.stagedWidth = v; writeSize(m) end,
    staged = "stagedWidth", flush = writeSize,
  },
  height = {
    restricted = true, precision = 0.05,
    read = function(m) return m.frame:GetHeight() end,
    write = function(m, v) m.stagedHeight = v; writeSize(m) end,
    staged = "stagedHeight", flush = writeSize,
  },
  x = {
    restricted = true, native = true, precision = 0.05, tween = "Translation",
    read = function(m) return m.offsetX end,
    write = function(m, v) m.offsetX = v; writeLayout(m) end,
    staged = "offsetX", flush = writeLayout,
  },
  y = {
    restricted = true, native = true, precision = 0.05, tween = "Translation",
    read = function(m) return m.offsetY end,
    write = function(m, v) m.offsetY = v; writeLayout(m) end,
    staged = "offsetY", flush = writeLayout,
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

-- Semi-implicit Euler in steps of at most STEP. t.k and t.c are stiffness and
-- damping per unit of mass.
local function stepSpring(t, dt)
  local k, c, target = t.k, t.c, t.target
  local value, velocity = t.value, t.velocity
  while dt > STEP do
    velocity = velocity + (k * (target - value) - c * velocity) * STEP
    value = value + velocity * STEP
    dt = dt - STEP
  end
  velocity = velocity + (k * (target - value) - c * velocity) * dt
  value = value + velocity * dt
  t.value, t.velocity = value, velocity
  local restV, d, precision = t.precision * 10, value - target, t.precision
  return velocity < restV and velocity > -restV and d < precision and d > -precision
end

local function stepTween(t, dt)
  local elapsed, duration = t.elapsed + dt, t.duration
  t.elapsed = elapsed
  local p = elapsed < duration and elapsed / duration or 1
  local last, from = t.value, t.from
  local value = from + (t.target - from) * t.ease(p)
  t.value = value
  t.velocity = dt > 0 and (value - last) / dt or 0
  return p >= 1
end

-- Callbacks run after the loop, so a callback that starts a new animation never
-- adds tracks to a table the loop is traversing.
local callbacks, callbackCount = {}, 0

local function queueCallback(fn, frame, name, takenOver)
  callbackCount = callbackCount + 1
  local c = callbacks[callbackCount]
  if not c then c = {}; callbacks[callbackCount] = c end
  c[1], c[2], c[3], c[4] = fn, frame, name, takenOver
end

local function arrive(m, name, t)
  t.value = t.target
  m.tracks[name] = nil
  if m.awayKeys and m.awayKeys[name] and t.target == m.rest[name] then m.awayKeys[name] = nil end
  if t.onDone then queueCallback(t.onDone, m.frame, name) end
end

local tryNative -- defined with the other native tween code below

local function update(_, elapsed)
  local started = profile()
  local dt = min(elapsed, 0.1)
  local tracks = 0
  local inCombat = InCombatLockdown()
  for m in pairs(active) do
    -- Checked every frame: combat can start in the middle of an animation.
    local isLocked = inCombat and m.frame:IsProtected() or false
    m.isLocked = isLocked
    -- Properties that share a game call (x and y, width and height) stage
    -- their values, and each call runs once after the loop.
    local flush1, flush2
    local stepped = false
    for name, t in pairs(m.tracks) do
      tracks = tracks + 1
      local prop = PROPS[name]
      -- tryNative owns the start rule. Only a tween that hasn't stepped can
      -- start, so this filter skips the call for every running track.
      if t.elapsed == 0 then tryNative(m, name, t, isLocked) end
      if t.native then
        -- Drawn by the game. Its OnFinished arrives it.
      elseif t.delay > 0 then
        t.delay = t.delay - dt
        stepped = true
      elseif not (isLocked and waitsWhileLocked(prop)) then
        -- A track that left native drawing already holds its value as of that
        -- moment, so it moves only by the time since.
        local step = dt
        if t.convertedAt then
          step = GetTime() - t.convertedAt
          t.convertedAt = nil
        end
        local rest
        if t.spring then rest = stepSpring(t, step) else rest = stepTween(t, step) end
        if rest then t.value = t.target end
        local staged = prop.staged
        if staged then
          m[staged] = t.value
          local flush = prop.flush
          if not flush1 or flush1 == flush then flush1 = flush else flush2 = flush end
        else
          prop.write(m, t.value)
        end
        if rest then arrive(m, name, t) else stepped = true end
      else
        stepped = true
      end
    end
    if flush1 then flush1(m) end
    if flush2 then flush2(m) end
    -- Native tracks need no driver, so a frame with only those goes idle. A
    -- native track can turn into a Lua track during the loop, so look again.
    if not stepped then
      local idle = true
      for _, t in pairs(m.tracks) do
        if not t.native then idle = false; break end
      end
      if idle then active[m] = nil end
    end
  end
  -- A callback can queue more callbacks. They run in this pass too.
  local i = 1
  while i <= callbackCount do
    local c = callbacks[i]
    local fn, frame, name, takenOver = c[1], c[2], c[3], c[4]
    c[1], c[2], c[3], c[4] = nil, nil, nil, nil
    fn(frame, name, takenOver)
    i = i + 1
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
-- Native tweens: an alpha, x or y tween whose ease the game has runs as a
-- native animation, with no Lua per frame. Polymorph writes the final value
-- first, and the animation draws the way there: an Alpha from the start value,
-- or a Translation played in reverse from the start offset to 0. Nothing needs
-- writing when it ends, so combat starting midway blocks nothing.
--
-- Each frame gets at most one group per property, created once and reused.
---------------------------------------------------------------------------

-- The game allows each addon 2000 animation groups, and the addon that embeds
-- Polymorph shares them. Past this many, tweens run in Lua.
local MAX_NATIVE_GROUPS = 1000
local nativeGroups = 0

local function nativeChannel(m, name)
  m.native = m.native or {}
  local ch = m.native[name]
  if ch or nativeGroups >= MAX_NATIVE_GROUPS then return ch end
  nativeGroups = nativeGroups + 1
  local ag = m.frame:CreateAnimationGroup()
  ch = { ag = ag, anim = ag:CreateAnimation(PROPS[name].tween) }
  ag:SetScript("OnFinished", function()
    local t = m.tracks[name]
    if t and t.native == ch then
      t.native = nil
      arrive(m, name, t)
      wake(m) -- runs the callback on the next update
    end
  end)
  m.native[name] = ch
  return ch
end

-- Starts a native tween when the rule allows: a tween that hasn't stepped yet,
-- no delay left, the frame unlocked, a curve the game has, and a group left in
-- the budget. A native Alpha interpolates clamped ends, so alpha outside 0..1
-- stays in Lua. Returns whether it started.
function tryNative(m, name, t, isLocked)
  if t.native or t.spring or t.elapsed ~= 0 or t.delay > 0 or isLocked or t.duration <= 0
      or not PROPS[name].tween or not NATIVE_SMOOTHING[t.ease] then
    return false
  end
  if name == "alpha" and not (t.value >= 0 and t.value <= 1 and t.target >= 0 and t.target <= 1) then
    return false
  end
  local ch = nativeChannel(m, name)
  if not ch then return false end
  local smoothing, a = NATIVE_SMOOTHING[t.ease], ch.anim
  a:SetDuration(t.duration)
  ch.reverse = name ~= "alpha"
  if name == "alpha" then
    a:SetSmoothing(smoothing.forward)
    a:SetFromAlpha(t.value)
    a:SetToAlpha(t.target)
    PROPS.alpha.write(m, t.target)
    ch.ag:Play()
  else
    a:SetSmoothing(smoothing.reverse)
    local d = t.value - t.target
    if name == "x" then
      m.offsetX = t.target
      a:SetOffset(d, 0)
    else
      m.offsetY = t.target
      a:SetOffset(0, d)
    end
    commit(m)
    ch.ag:Play(true)
  end
  t.native, t.startedAt, t.convertedAt = ch, GetTime(), nil
  return true
end

-- Progress, value and velocity of a native track, from the time since it
-- started and the track's own ease. GetTime() is the same all frame, so this
-- holds whatever order the game runs events, scripts and animations in.
local function nativeState(t)
  local p = min(1, max(0, (GetTime() - t.startedAt) / t.duration))
  local ease, span = t.ease, t.target - t.from
  local q = max(0, p - 0.001)
  local velocity = p > q and span * (ease(p) - ease(q)) / (p - q) / t.duration or 0
  return t.from + span * ease(p), velocity, p
end

-- The one way a native track becomes a Lua track: stop the animation and carry
-- on the same tween from where it is, with its value, velocity and elapsed time.
-- The caller writes where the frame draws.
local function nativeToLua(t)
  local p
  t.value, t.velocity, p = nativeState(t)
  t.elapsed = p * t.duration
  t.convertedAt = GetTime()
  t.native.ag:Stop()
  t.native = nil
end

-- Stops a native track where it draws, and leaves it as a Lua track there.
local function freezeNative(m, name, t)
  nativeToLua(t)
  m.isLocked = locked(m)
  PROPS[name].write(m, t.value)
end

local LAYOUT_FIELD = { x = "offsetX", y = "offsetY" }

function handNativeToPuppet(m)
  for name, field in pairs(LAYOUT_FIELD) do
    local t = m.tracks[name]
    if t and t.native then
      nativeToLua(t)
      m[field] = t.value
      wake(m)
    end
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

-- awayKeys records ownership: a property is in it while show() or hide() owns
-- it off rest. It joins when show() or hide() animates it. It leaves when its
-- track arrives at rest, or when the caller takes it over with to(), set() or
-- stop(). A finished hide() resets whatever is still in it.
local function release(m, name)
  if m.awayKeys then m.awayKeys[name] = nil end
end

-- A property changes hands: to(), set() or stop() takes it, or a newer call
-- animates it. The call that was moving it hears about it after the next update.
local function takeOver(m, name)
  local t = m.tracks[name]
  if t and t.onDone then
    queueCallback(t.onDone, m.frame, name, true)
    t.onDone = nil
    wake(m)
  end
end

-- owner: "caller" for to(), "show" or "hide".
local function animate(m, targets, opts, owner)
  opts = opts or {}
  local spring = not opts.duration and resolveSpring(opts.spring) or nil
  local ease = opts.duration and resolveEase(opts.ease) or nil
  local pending, lost = 0, false
  -- A hide() finishes once every property it still owns has arrived. Any other
  -- call skips its onComplete once one of its properties is taken over.
  local function settled(_, _, takenOver)
    pending = pending - 1
    if takenOver and owner ~= "hide" then lost = true end
    if pending == 0 and not lost and opts.onComplete then opts.onComplete(m.frame) end
  end
  for name, target in pairs(targets) do
    local prop = PROPS[name] or error("Polymorph: unknown property " .. tostring(name), 3)
    local t = m.tracks[name]
    if t then
      takeOver(m, name)
      if t.native then freezeNative(m, name, t) end
    else
      t = { value = prop.read(m), velocity = 0 }
      m.tracks[name] = t
    end
    t.target = target
    t.precision = prop.precision
    t.delay = opts.delay or 0
    t.spring = spring
    if spring then
      local mass = spring.mass or 1
      t.k, t.c = spring.stiffness / mass, spring.damping / mass
    end
    if ease then
      t.ease, t.duration, t.elapsed, t.from = ease, opts.duration, 0, t.value
    end
    if owner == "caller" then
      release(m, name)
    else
      m.awayKeys = m.awayKeys or {}
      m.awayKeys[name] = true
    end
    pending = pending + 1
    t.onDone = settled
    tryNative(m, name, t, locked(m))
  end
  if pending > 0 then wake(m) end
  return m
end

-- Animates each property in `targets` toward its value.
-- opts: spring = preset name or { stiffness, damping, mass }
--       duration (seconds) and ease = name, { x1, y1, x2, y2 } or function
--       delay (seconds), onComplete(frame) when every property in this call has arrived
function Motion:to(targets, opts)
  return animate(self, targets, opts, "caller")
end

-- Jumps to values immediately and stops those properties.
function Motion:set(values)
  self.isLocked = locked(self)
  for name, value in pairs(values) do
    local prop = PROPS[name] or error("Polymorph: unknown property " .. tostring(name), 2)
    takeOver(self, name)
    local t = self.tracks[name]
    if t and t.native then t.native.ag:Stop() end
    self.tracks[name] = nil
    release(self, name)
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
  if name then
    local t = self.tracks[name]
    takeOver(self, name)
    if t and t.native then freezeNative(self, name, t) end
    self.tracks[name] = nil
    release(self, name)
  else
    for n, t in pairs(self.tracks) do
      takeOver(self, n)
      if t.native then freezeNative(self, n, t) end
      self.tracks[n] = nil
    end
    self.awayKeys = nil
  end
  return self
end

function Motion:get(name)
  local t = self.tracks[name]
  if t and t.native then
    local value, velocity = nativeState(t)
    return value, velocity, t.target
  end
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

-- Rest values for the `away` properties and every property show()/hide() own.
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
  takeVisibility(self)
  local frame = self.frame
  if not frame:IsShown() then
    if locked(self) then
      afterCombat[self] = function() self:show(away, opts) end
      return self
    end
    self:set(away)
    frame:Show()
  end
  return animate(self, restingTargets(self, away), opts, "show")
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
    -- Only what show()/hide() still own. set() releases each one it resets.
    self:set(restingTargets(self, {}))
    if userDone then userDone(self.frame) end
  end
  local copy = {}
  for k, v in pairs(opts) do copy[k] = v end
  copy.onComplete = finish
  -- Locked: animate only what the game allows (alpha, and x/y/scale via the puppet).
  -- The rest would wait for combat to end, and a fading frame does not need it.
  local targets = away
  if locked(self) then
    targets = {}
    for name, value in pairs(away) do
      if not waitsWhileLocked(PROPS[name]) then targets[name] = value end
    end
    if next(targets) == nil then finish() return self end
  end
  return animate(self, targets, copy, "hide")
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
