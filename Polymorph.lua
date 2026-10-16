-- Polymorph: target-state animation for WoW frames.
--
--   local Poly = LibStub("Polymorph-1.0")
--   Poly(frame):to({ alpha = 1, y = 20 })                     -- spring (default)
--   Poly(frame):to({ width = 300 }, { duration = 0.25, ease = "outCubic" })
--   Poly(fs):define({ total = 0 }, function(fs, v) fs:SetText(("%.0f"):format(v.total)) end)
--   Poly(fs):to({ total = 1500 })                             -- your own values
--
-- frame can be a frame, a texture or a font string.
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

local InCombatLockdown, GetTime, GetTickTime = InCombatLockdown, GetTime, GetTickTime
local abs, min, max, next = math.abs, math.min, math.max, next

-- The time every track's value belongs to: this frame once the driver has
-- stepped, otherwise the last drawn frame. Every value Polymorph sets, reads or
-- carries over is paired with this time, so a retarget never moves it. The game
-- counts an animation started during a frame from the last drawn frame, and
-- draws it one frame in already. A Lua track started before the driver steps
-- counts from there too, so both draw the same value in every frame.
local lastStep
local function trackTime()
  local now = GetTime()
  if lastStep == now then return now end
  return now - GetTickTime()
end

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

-- A call's curve: an ease function when opts has a duration, otherwise a
-- spring table. Called from a public method, so error level 3 is the line
-- that called it.
local function curveOf(opts)
  local duration, ease, spring = opts and opts.duration, opts and opts.ease, opts and opts.spring
  if duration then
    if type(ease) == "function" then return ease end
    if type(ease) == "table" then return bezier(ease[1], ease[2], ease[3], ease[4]) end
    return Poly.easings[ease or "outCubic"] or error("Polymorph: unknown ease " .. tostring(ease), 3)
  end
  if type(spring) == "table" then return spring end
  return Poly.springs[spring or "default"] or error("Polymorph: unknown spring " .. tostring(spring), 3)
end

---------------------------------------------------------------------------
-- Properties
---------------------------------------------------------------------------

-- x and y offset every anchor of the frame by the same amount, so a frame with
-- two anchors slides instead of stretching. m.anchors is the frame's anchors
-- as { point, relativeTo, relativePoint, x, y, setX, setY } lists, and is
-- empty when the frame has none. x and y leave out Polymorph's offset, and
-- setX and setY are what the anchor has, recorded by each SetPoint commit()
-- makes. offsetX/Y is where the frame shows. It differs from the anchors'
-- offset only while combat lockdown forces drawing through the puppet. The
-- same goes for scale: drawScale is where it shows and layoutScale is the
-- frame's own scale, both set only while puppeted.
--
-- Other code anchors frames too: layouts, pools, frame movers. Polymorph
-- checks the frame's anchors before every call that takes or returns x or y,
-- and before every write of them once the frame is unlocked. If they aren't
-- the ones it last wrote, the other code wins (adoptAnchors).
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

-- A frame's animation groups are made once, the first time each is needed,
-- and reused for its life. They live outside the motion, which a halt rebuilds.
local puppets = setmetatable({}, { __mode = "k" })  -- motion -> its puppet
local channels = setmetatable({}, { __mode = "k" }) -- motion -> { property -> native channel }
local handNativeToPuppet -- defined with the native tween code below
local anchorsHeld, adoptAnchors -- defined with the motion code below

-- Scale grows around the first anchor. A frame without anchors grows around
-- its center.
local NO_ANCHOR = { "CENTER", nil, "CENTER", 0, 0, 0, 0 }

local function puppetMove(m)
  -- The puppet's offsets assume it owns every displacement, so a native x or y
  -- tween still drawing becomes a Lua track first.
  handNativeToPuppet(m)
  local p = puppets[m]
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
    puppets[m] = p
  end
  local b = m.anchors[1] or NO_ANCHOR
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
  p.tr:SetOffset((b[4] + m.offsetX) * k - b[6], (b[5] + m.offsetY) * k - b[7])
end

local function commit(m)
  if m.drawScale then
    if m.drawScale ~= m.layoutScale then m.frame:SetScale(m.drawScale) end
    m.drawScale = nil
  end
  if anchorsHeld(m) then
    local anchors, x, y = m.anchors, m.offsetX, m.offsetY
    local n = #anchors
    for i = 1, n do
      local a = anchors[i]
      a[6], a[7] = a[4] + x, a[5] + y
      m.frame:SetPoint(a[1], a[2], a[3], a[6], a[7])
      -- A hook on SetPoint can reanchor the frame before the next anchor.
      if i < n and not anchorsHeld(m) then
        adoptAnchors(m)
        break
      end
    end
  else
    adoptAnchors(m)
  end
  if puppeted[m] then
    puppets[m].ag:Stop()
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

-- Built-in properties, then the handle's own values from define(). define()
-- refuses built-in names, so a name means one thing on each handle.
local function propOf(m, name)
  return PROPS[name] or m.props and m.props[name]
end

-- Argument errors point at the line that made the call: each public call
-- checks its arguments before any work on the frame starts, even work that
-- would wait. Called from a public method, so error level 3 is that line.
-- The work then trusts its arguments.
local function checkNames(m, values)
  for name in pairs(values) do
    if not propOf(m, name) then error("Polymorph: unknown property " .. tostring(name), 3) end
  end
end

local LAYOUT_FIELD = { x = "offsetX", y = "offsetY" }

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

-- Frames, textures and font strings alike: the game reports protection on each
-- object. A texture or font string of a protected button reports false, and in
-- a real fight SetPoint, SetSize, SetWidth, SetHeight, SetScale, Show and Hide
-- on such a texture raised no blocked action.
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
  if dt > 0 then t.velocity = (value - last) / dt end
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

local queueNative -- defined with the other native tween code below
local resetMotion -- defined with the motion code below
local halt -- defined below
local takeVisibility -- defined with show and hide below
-- Work the game blocks on protected frames in combat, run as work on the
-- frame once combat ends.
local afterCombat = {} -- motion -> function(m)

-- Errors. Game calls can throw: SetPoint does when an anchor would close a
-- loop. So can an ease, a define() writer or a hook. Any error in work on a
-- frame starts that frame over (halt) before the error goes anywhere, so the
-- error doesn't repeat and whoever hears of it can start fresh work on it. A
-- public call then raises the error to its caller. Everything else is the
-- game calling in: the driver, the start timer, a native OnFinished, the
-- combat-end event, a call that waited. Each reports the error to the game's
-- error handler once, and every other frame keeps moving. Lua 5.1's xpcall
-- passes no arguments, so they go over in upvalues.
local tryFn, tryA, tryB, tryC, tryD
local function callTry()
  local fn, a, b, c, d = tryFn, tryA, tryB, tryC, tryD
  tryFn, tryA, tryB, tryC, tryD = nil, nil, nil, nil, nil
  return fn(a, b, c, d)
end
local function caught(err) return err end
local function report(err) geterrorhandler()(err) end

-- Runs fn(m, a, b, c). If it throws, m starts over and the error is returned.
local function guarded(m, fn, a, b, c)
  tryFn, tryA, tryB, tryC, tryD = fn, m, a, b, c
  local ok, err = xpcall(callTry, caught)
  if ok then return end
  halt(m)
  return err
end

-- Runs a callback, which owns no frame: an error is only reported.
local function try(fn, a, b, c)
  tryFn, tryA, tryB, tryC = fn, a, b, c
  local ok, err = xpcall(callTry, caught)
  if not ok then report(err) end
end

-- Reentrant calls. Polymorph works on a frame during a public call, the
-- frame's update, its native start or finish, its combat-end work and its
-- halt. A hook on a game call it makes there, or an ease, can call Polymorph
-- on the same frame. That call waits while the frame is m.busy or `driving`,
-- and runs once the work is done, in the order the calls came. So the work
-- never sees the motion change under it, and the waiting call lands last.
-- Calls on other frames run at once.
local driving -- the motion the driver is stepping
local queuedAny = false -- a call waited since the driver last looked
-- The motions a halt is starting over. A call on one, from a hook on a game
-- call the halt makes, is dropped: the frame is starting over, and a call that
-- failed there would halt it again, make the same game call, and call the hook
-- again without end. A set, since a hook can halt another frame meanwhile.
local halting = {}
local function runWaiting(m)
  local q, i = m.waiting, 1
  -- A halt clears m.waiting: the frame runs nothing queued before it.
  while m.waiting == q and q[i] do
    if i > 100 then
      halt(m)
      return report("Polymorph: hooks on this frame keep calling Polymorph")
    end
    local c = q[i]
    local err = guarded(m, c[1], c[2], c[3], c[4])
    if err then return report(err) end
    i = i + 1
  end
  if m.waiting == q then m.busy, m.waiting = nil, nil end
end

-- Runs fn(m, a, b, c) as work on m, or queues it while m is busy. Returns the
-- error if the work threw.
local function attempt(m, fn, a, b, c)
  if halting[m] then return end
  if m.busy or m == driving then
    local q = m.waiting
    if not q then q = {}; m.waiting = q end
    q[#q + 1] = { fn, a, b, c }
    queuedAny = true
    return
  end
  m.busy = true
  local err = guarded(m, fn, a, b, c)
  if err then return err end
  if m.waiting then runWaiting(m) else m.busy = nil end
end

-- Work for a public call: an error goes on to the caller.
local function work(m, fn, a, b, c)
  local err = attempt(m, fn, a, b, c)
  if err then error(err, 0) end
  return m
end

-- Work the game calls in for: a timer, an event, an animation's OnFinished.
local function enter(m, fn, a, b, c)
  local err = attempt(m, fn, a, b, c)
  if err then report(err) end
end

-- Stops every group of the frame. A Stop() that throws, from a hook on it,
-- doesn't leave the others drawing: each runs, then the first error is reported.
local function stopGroups(m)
  local err
  for _, ch in pairs(channels[m] or {}) do
    local ok, e = pcall(ch.ag.Stop, ch.ag)
    if not ok then err = err or e end
  end
  local p = puppets[m]
  if p then
    local ok, e = pcall(p.ag.Stop, p.ag)
    if not ok then err = err or e end
  end
  if err then report(err) end
end

-- A frame whose work threw starts over, so the error doesn't repeat and
-- nothing from before it moves, shows or hides the frame later. Its animations
-- stop, its queued work goes, and resetMotion rebuilds its motion state from
-- the frame as it is now. A queued native start needs no clearing: it runs
-- only while its track is the motion's.
function halt(m)
  halting[m] = true
  active[m], puppeted[m], afterCombat[m] = nil, nil, nil
  local frame = m.frame
  for i = 1, callbackCount do
    if callbacks[i][2] == frame then callbacks[i][1] = nil end
  end
  resetMotion(m)
  stopGroups(m)
  halting[m] = nil
end

local inCombat -- InCombatLockdown() for this update
-- The writers one frame staged in this update. Reused, so stepping allocates nothing.
local flushes = {}

-- Steps the Lua tracks of every moving frame to lastStep, from `stepping` on,
-- or from the first when it is nil. The driver pays for one xpcall per update,
-- not one per frame: after an error it halts the frame that threw and calls
-- stepAll again from the frame after it.
local stepping, tracks
local function stepAll()
  local now = lastStep
  local m = stepping or next(active)
  while m do
    stepping = m
    -- Checked every frame: combat can start in the middle of an animation.
    local isLocked = inCombat and m.frame:IsProtected() or false
    m.isLocked = isLocked
    -- Properties that share a writer (x and y, width and height, the values of
    -- one define()) stage their values, and each writer runs once after the loop.
    local flushCount = 0
    local stepped, arrived = false, false
    driving = m
    for name, t in pairs(m.tracks) do
      tracks = tracks + 1
      local prop = t.prop
      -- A native track is drawn by the game, and its OnFinished arrives it. A
      -- queued track holds still until the start timer runs.
      if not (t.native or t.queued) then
        stepped = true
        local step = now - t.time
        if step > 0.1 then step = 0.1 end -- a long hitch doesn't make a spring jump
        t.time = now
        if t.delay > 0 then
          t.delay = t.delay - step
          if t.delay <= 0 then queueNative(m, name, t, isLocked) end
        elseif not (isLocked and waitsWhileLocked(prop)) then
          local rest
          if t.spring then rest = stepSpring(t, step) else rest = stepTween(t, step) end
          if rest then
            t.value, t.arrived = t.target, true
            arrived = true
          end
          local staged = prop.staged
          if staged then
            local into = prop.values or m
            into[staged] = t.value
            local flush, i = prop.flush, 1
            while i <= flushCount and flushes[i] ~= flush do i = i + 1 end
            if i > flushCount then flushCount = i; flushes[i] = flush end
          else
            prop.write(m, t.value)
          end
        end
      end
    end
    local layoutWritten = false
    for i = 1, flushCount do
      local flush = flushes[i]
      flushes[i] = nil
      flush(m)
      if flush == writeLayout then layoutWritten = true end
    end
    -- A track arrives once every write of this update has landed: a write that
    -- finds other code's anchors takes the x and y tracks over instead. So
    -- does a hook that reanchors the frame on its last SetPoint.
    if arrived then
      if layoutWritten and not isLocked and not anchorsHeld(m) then
        adoptAnchors(m)
      end
      for name, t in pairs(m.tracks) do
        if t.arrived then arrive(m, name, t) end
      end
    end
    driving = nil
    if queuedAny then
      queuedAny = false
      if m.waiting then
        m.busy = true
        runWaiting(m)
      end
    end
    -- Native and queued tracks need no driver, so a frame with only those goes
    -- idle. A track can be queued during the loop, and a Lua track can arrive,
    -- so look again.
    if not stepped or next(m.tracks) == nil then
      local idle = true
      for _, t in pairs(m.tracks) do
        if not (t.native or t.queued) then idle = false; break end
      end
      if idle then active[m] = nil end
    end
    m = next(active, m)
  end
end

local function update()
  local started = profile()
  -- Each Lua track moves by the time since it last moved, so a track that
  -- joined or left native drawing this frame moves only by what is left.
  lastStep = GetTime()
  inCombat = InCombatLockdown()
  stepping, tracks = nil, 0
  while true do
    local ok, err = xpcall(stepAll, caught)
    if ok then break end
    -- Find the next frame while the failed one is still a key of active.
    local failed = stepping
    stepping, driving = next(active, failed), nil
    halt(failed)
    report(err)
    if not stepping then break end
  end
  -- A callback can queue more callbacks. They run in this pass too.
  local i = 1
  while i <= callbackCount do
    local c = callbacks[i]
    local fn, frame, name, takenOver = c[1], c[2], c[3], c[4]
    c[1], c[2], c[3], c[4] = nil, nil, nil, nil
    if fn then try(fn, frame, name, takenOver) end
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
--
-- Tweens start from one shared timer, never from an OnUpdate script. Recorded
-- in the client, SetPoint then Play(true) from OnUpdate drew 3 of 8 starts
-- against the old anchor for a frame or two, and from a timer 0 of 32. A
-- queued track holds its value until the timer, the next frame at the latest.
---------------------------------------------------------------------------

-- The game allows each addon 2000 animation groups, and the addon that embeds
-- Polymorph shares them. Past this many, tweens run in Lua.
local MAX_NATIVE_GROUPS = 1000
local nativeGroups = 0

local function nativeFinished(m, name, ch)
  local t = m.tracks[name]
  if t and t.native == ch then
    -- The game drew this slide, so nothing checked the anchors since it
    -- started. Other code may have moved the frame meanwhile.
    if LAYOUT_FIELD[name] and not anchorsHeld(m) then
      adoptAnchors(m)
    else
      t.native = nil
      arrive(m, name, t)
    end
    wake(m) -- runs the callback on the next update
  end
end

local function nativeChannel(m, name)
  local own = channels[m]
  if not own then own = {}; channels[m] = own end
  local ch = own[name]
  if ch or nativeGroups >= MAX_NATIVE_GROUPS then return ch end
  nativeGroups = nativeGroups + 1
  local ag = m.frame:CreateAnimationGroup()
  ch = { ag = ag, anim = ag:CreateAnimation(PROPS[name].tween) }
  ag:SetScript("OnFinished", function() enter(m, nativeFinished, name, ch) end)
  own[name] = ch
  return ch
end

-- The start rule: a tween that hasn't stepped yet, no delay left, the frame
-- unlocked, a curve the game has, and a group left in the budget. A native
-- Alpha interpolates clamped ends, so alpha outside 0..1 stays in Lua.
local function startsNative(m, name, t, isLocked)
  if t.native or t.spring or t.elapsed ~= 0 or t.delay > 0 or isLocked or t.duration <= 0
      or not t.prop.tween or not NATIVE_SMOOTHING[t.ease] then
    return false
  end
  if name == "alpha" and not (t.value >= 0 and t.value <= 1 and t.target >= 0 and t.target <= 1) then
    return false
  end
  return (channels[m] and channels[m][name]) ~= nil or nativeGroups < MAX_NATIVE_GROUPS
end

-- Plays a tween as its native animation. The game counts an animation from the
-- last drawn frame, so the track does too.
local function startNative(m, name, t)
  local ch = nativeChannel(m, name)
  local smoothing, a = NATIVE_SMOOTHING[t.ease], ch.anim
  a:SetDuration(t.duration)
  if name == "alpha" then
    a:SetSmoothing(smoothing.forward)
    a:SetFromAlpha(t.value)
    a:SetToAlpha(t.target)
    PROPS.alpha.write(m, t.target)
    ch.ag:Play()
  else
    a:SetSmoothing(smoothing.reverse)
    local d = t.value - t.target
    if name == "x" then a:SetOffset(d, 0) else a:SetOffset(0, d) end
    m[LAYOUT_FIELD[name]] = t.target
    commit(m)
    if m.tracks[name] ~= t then return end -- other code had moved the frame
    ch.ag:Play(true)
  end
  t.native, t.startedAt = ch, GetTime() - GetTickTime()
end

-- Queued starts as flat (motion, name, track) triples, and whether the timer
-- that starts them is pending. There is at most one such timer. The timer
-- drains one list while new starts go to the other.
local queue, spare, queued = {}, {}, 0
local timerPending = false

-- Work on m for one queued start: a track that is still queued starts
-- natively if the rule still allows, and otherwise goes on in Lua.
local function startTrack(m, name, t)
  if not t.queued or m.tracks[name] ~= t then return end
  t.queued = nil
  if startsNative(m, name, t, locked(m)) then startNative(m, name, t) else wake(m) end
end

-- The timer: starts every queued track, each as work on its frame.
local function startQueued()
  local started = profile()
  timerPending = false
  -- Starting a tween calls SetPoint or SetAlpha, and a hook on either can queue
  -- more starts. Those go to the other list and wait for the next timer.
  local list, n = queue, queued
  queue, queued = spare, 0
  for i = 1, n, 3 do
    local m, name, t = list[i], list[i + 1], list[i + 2]
    list[i], list[i + 1], list[i + 2] = nil, nil, nil
    enter(m, startTrack, name, t)
  end
  spare = list
  stats.ms = stats.ms + (profile() - started)
end

-- Queues a native start when the rule allows, and otherwise leaves the track
-- to the driver. Every call decides afresh, so a retarget can unqueue a track.
function queueNative(m, name, t, isLocked)
  if not startsNative(m, name, t, isLocked) then
    t.queued = nil
    return
  end
  if t.queued then return end
  t.queued = true
  queue[queued + 1], queue[queued + 2], queue[queued + 3] = m, name, t
  queued = queued + 3
  if not timerPending then
    timerPending = true
    C_Timer.After(0, startQueued)
  end
end

-- Progress, value and velocity of a native track at trackTime(), from its
-- start and the track's own ease.
local function nativeState(t)
  local p = min(1, max(0, (trackTime() - t.startedAt) / t.duration))
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
  t.time = trackTime()
  t.native.ag:Stop()
  t.native = nil
end

-- Stops a native track where it draws, and leaves it as a Lua track there.
local function freezeNative(m, name, t)
  nativeToLua(t)
  m.isLocked = locked(m)
  t.prop.write(m, t.value)
end

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

local function readAnchors(frame)
  local anchors = {}
  for i = 1, frame:GetNumPoints() do
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
    anchors[i] = { point, relativeTo, relativePoint, x, y, x, y }
  end
  return anchors
end

-- What a handle keeps for its life: its frame, its rest values, and the
-- values define() made with their writers. Everything else is motion state.
local HANDLE = { frame = true, rest = true, props = true, values = true }

-- Every field of a motion's state, read from the frame as it is now: no
-- tracks, its anchors as they are, x and y 0 there. Poly(frame) builds a
-- motion with it, and halt rebuilds one, so a halted motion keeps only what
-- HANDLE names. The same table stays, so handles the caller holds stay valid.
-- A halt must finish, so a getter that throws doesn't stop the reset: the
-- motion then holds no anchors, and the next write reads them again as work.
function resetMotion(m)
  for k in pairs(m) do
    if not HANDLE[k] then m[k] = nil end
  end
  m.tracks, m.anchors = {}, {}
  m.offsetX, m.offsetY, m.visibilityToken = 0, 0, 0
  local ok, anchors = pcall(readAnchors, m.frame)
  if ok then m.anchors = anchors end
  return m
end

local function motionFor(frame)
  local m = motions[frame]
  if m then return m end
  local alpha = frame:GetAlpha()
  -- What show() returns to. A frame first touched at alpha 0 rests at 1.
  local rest = { alpha = alpha > 0 and alpha or 1, scale = frame:GetScale(), width = frame:GetWidth(),
                 height = frame:GetHeight(), x = 0, y = 0 }
  m = resetMotion(setmetatable({ frame = frame, rest = rest }, Motion))
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

-- Whether the frame's anchors are still the ones Polymorph last wrote or read:
-- each of m.anchors at its setX and setY. Points match by name, and offsets
-- within 0.01, so a getter that rounds doesn't count as a move.
function anchorsHeld(m)
  local frame, anchors = m.frame, m.anchors
  local n = frame:GetNumPoints()
  if n ~= #anchors then return false end
  for i = 1, n do
    local point, rel, relPoint, x, y = frame:GetPoint(i)
    local a = anchors[i]
    if a[1] ~= point then
      a = nil
      for j = 1, n do
        if anchors[j][1] == point then a = anchors[j] break end
      end
    end
    if not a or a[2] ~= rel or a[3] ~= relPoint
        or abs(a[6] - x) > 0.01 or abs(a[7] - y) > 0.01 then
      return false
    end
  end
  return true
end

-- Other code anchored the frame since Polymorph last did, and it wins: its
-- anchors become the frame's home, x and y are 0 there, and Polymorph's x and
-- y animations stop without writing.
function adoptAnchors(m)
  m.anchors = readAnchors(m.frame)
  m.offsetX, m.offsetY = 0, 0
  for name in pairs(LAYOUT_FIELD) do
    local t = m.tracks[name]
    if t then
      takeOver(m, name)
      if t.native then t.native.ag:Stop() end
      m.tracks[name] = nil
    end
    release(m, name)
  end
end

-- Runs before every call that takes or returns x or y. While the puppet draws,
-- its offsets come from the old anchors, so it draws again from the new ones.
local function syncAnchors(m)
  if anchorsHeld(m) then return end
  adoptAnchors(m)
  if puppeted[m] then
    puppets[m].sc:SetOrigin((m.anchors[1] or NO_ANCHOR)[1], 0, 0)
    puppetMove(m)
  end
end

local function touchesLayout(values)
  return values.x ~= nil or values.y ~= nil
end

-- owner: nil for to(), "show" or "hide".
-- curve: curveOf(opts), resolved when the call was made.
local function animate(m, targets, opts, curve, owner)
  opts = opts or {}
  if touchesLayout(targets) then syncAnchors(m) end
  local spring, ease
  if opts.duration then ease = curve else spring = curve end
  local pending, lost = 0, false
  -- A hide() finishes once every property it still owns has arrived. Any other
  -- call skips its onComplete once one of its properties is taken over.
  local function settled(_, _, takenOver)
    pending = pending - 1
    if takenOver and owner ~= "hide" then lost = true end
    if pending == 0 and not lost and opts.onComplete then opts.onComplete(m.frame) end
  end
  for name, target in pairs(targets) do
    local prop = propOf(m, name)
    local t = m.tracks[name]
    if t then
      takeOver(m, name)
      if t.native then freezeNative(m, name, t) end
    else
      t = { prop = prop, value = prop.read(m), velocity = 0, time = trackTime() }
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
    if owner then
      m.awayKeys = m.awayKeys or {}
      m.awayKeys[name] = true
    else
      release(m, name)
    end
    pending = pending + 1
    t.onDone = settled
    queueNative(m, name, t, locked(m))
  end
  if pending > 0 then wake(m) end
end

-- Animates each property in `targets` toward its value.
-- opts: spring = preset name or { stiffness, damping, mass }
--       duration (seconds) and ease = name, { x1, y1, x2, y2 } or function
--       delay (seconds), onComplete(frame) when every property in this call has arrived
function Motion:to(targets, opts)
  checkNames(self, targets)
  return work(self, animate, targets, opts, curveOf(opts))
end

local function set(m, values)
  if touchesLayout(values) then syncAnchors(m) end
  m.isLocked = locked(m)
  for name, value in pairs(values) do
    local prop = propOf(m, name)
    takeOver(m, name)
    local t = m.tracks[name]
    if t and t.native then t.native.ag:Stop() end
    m.tracks[name] = nil
    release(m, name)
    if m.isLocked and waitsWhileLocked(prop) then
      animate(m, { [name] = value }, { duration = 0 }, linear) -- applied when combat ends
    else
      prop.write(m, value)
    end
  end
end

-- Jumps to values immediately and stops those properties.
function Motion:set(values)
  checkNames(self, values)
  return work(self, set, values)
end

local function stop(m, name)
  if not name or LAYOUT_FIELD[name] then syncAnchors(m) end
  if not name then
    takeVisibility(m)
    m.awayKeys = nil
  end
  -- Native tweens stop where they draw.
  for n in pairs(name and { [name] = true } or m.tracks) do
    local t = m.tracks[n]
    takeOver(m, n)
    if t and t.native then freezeNative(m, n, t) end
    m.tracks[n] = nil
    release(m, n)
  end
end

-- Stops one property where it is. With no name, stops every property and
-- cancels a running show() or hide(), so Hide() is never called.
function Motion:stop(name)
  return work(self, stop, name)
end

-- get() and isMoving() answer at once. While Polymorph works on the frame,
-- they answer from that work's state, and get() leaves the anchors unchecked.
function Motion:get(name)
  if LAYOUT_FIELD[name] and not self.busy then work(self, syncAnchors) end
  local t = self.tracks[name]
  if t and t.native then
    local value, velocity = nativeState(t)
    return value, velocity, t.target
  end
  if t then return t.value, t.velocity, t.target end
  return propOf(self, name).read(self), 0, nil
end

-- Makes each name in `values` a property of this handle, starting at its
-- value there. The handle keeps every defined value in one table, and in every
-- update where any of a writer's names moved, Polymorph calls write(frame,
-- values) once. Defining a name again replaces its writer and keeps its value,
-- and every writer reads the values from the one table, so none goes stale.
-- opts.precision: how close a value must come to its target to arrive.
-- define() changes what names mean on the handle, not the frame, so it runs
-- at once, even during work: a call made right after it can use its names.
function Motion:define(values, write, opts)
  local precision = opts and opts.precision or 0.001
  local current, frame = self.values or {}, self.frame
  self.values = current
  local function flush() write(frame, current) end
  self.props = self.props or {}
  for name, value in pairs(values) do
    if PROPS[name] then error("Polymorph: " .. name .. " is a built-in property", 2) end
    if type(value) ~= "number" then error("Polymorph: " .. tostring(name) .. " must start at a number", 2) end
    if current[name] == nil then current[name] = value end
    local prop = {
      precision = precision, staged = name, values = current, flush = flush,
      read = function() return current[name] end,
      write = function(_, v) current[name] = v; flush() end,
    }
    self.props[name] = prop
    local t = self.tracks[name]
    if t then t.prop, t.precision = prop, precision end
    if self.rest[name] == nil then self.rest[name] = value end
  end
  return self
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

local combatWatch = Poly._combatWatch or CreateFrame("Frame")
Poly._combatWatch = combatWatch
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function()
  for m in pairs(puppeted) do
    m.isLocked = false
    -- commit checks the anchors: a secure header may have moved the frame in combat.
    enter(m, commit)
  end
  for m, fn in pairs(afterCombat) do
    afterCombat[m] = nil
    enter(m, fn)
  end
end)

local function restAt(m, values)
  for name, value in pairs(values) do m.rest[name] = value end
end

function Motion:restAt(values)
  return work(self, restAt, values)
end

-- Every show() and hide() replaces the previous one: it takes a new token,
-- which cancels a running hide's Hide(), and it clears any action deferred to
-- combat end. Tokens are never reused, so a hide's finish from before a halt
-- can't match the token the rebuilt motion starts with.
local lastToken = 0
function takeVisibility(m)
  lastToken = lastToken + 1
  m.visibilityToken = lastToken
  afterCombat[m] = nil
  return lastToken
end

-- Rest values for the `away` properties and every property show()/hide() own.
local function restingTargets(m, away)
  local targets = {}
  for name in pairs(away) do targets[name] = m.rest[name] end
  for name in pairs(m.awayKeys or {}) do targets[name] = m.rest[name] end
  return targets
end

local function show(m, away, opts, curve)
  takeVisibility(m)
  local frame = m.frame
  if not frame:IsShown() then
    if locked(m) then
      afterCombat[m] = function() show(m, away, opts, curve) end
      return
    end
    set(m, away)
    frame:Show()
  end
  animate(m, restingTargets(m, away), opts, curve, "show")
end

-- Shows the frame from `away` (preset name or values) and animates to rest.
-- While a hide is running, show() cancels it and turns the frame around,
-- returning every property that hide was moving.
function Motion:show(away, opts)
  away = resolveAway(away)
  checkNames(self, away)
  return work(self, show, away, opts, curveOf(opts))
end

local function hide(m, away, opts, curve)
  opts = opts or {}
  local token = takeVisibility(m)
  local userDone = opts.onComplete
  local function hideNow()
    if m.visibilityToken ~= token then return end
    if locked(m) then
      afterCombat[m] = hideNow
      return
    end
    m.frame:Hide()
    -- Only what show()/hide() still own. set() releases each one it resets.
    set(m, restingTargets(m, {}))
    if userDone then try(userDone, m.frame) end
  end
  local copy = {}
  for k, v in pairs(opts) do copy[k] = v end
  copy.onComplete = function() enter(m, hideNow) end
  -- Locked: animate only what the game allows (alpha, and x/y/scale via the puppet).
  -- The rest would wait for combat to end, and a fading frame does not need it.
  local targets = away
  if locked(m) then
    targets = {}
    for name, value in pairs(away) do
      if not waitsWhileLocked(propOf(m, name)) then targets[name] = value end
    end
    if next(targets) == nil then return hideNow() end
  end
  animate(m, targets, copy, curve, "hide")
end

-- Animates to `away`, then hides the frame and resets it to rest while hidden.
-- On a protected frame in combat the fade still plays, and Hide() waits for
-- combat to end. The frame takes clicks until then.
function Motion:hide(away, opts)
  away = resolveAway(away)
  checkNames(self, away)
  return work(self, hide, away, opts, curveOf(opts))
end

setmetatable(Poly, { __call = function(_, frame) return motionFor(frame) end })

function Poly.stats()
  -- Frames the driver steps, and frames whose tweens only the game draws.
  local moving = 0
  for _, m in pairs(motions) do
    if next(m.tracks) then moving = moving + 1 end
  end
  return { frames = stats.frames, ms = stats.ms, peakTracks = stats.peakTracks, active = moving }
end

function Poly.resetStats()
  stats.frames, stats.ms, stats.peakTracks = 0, 0, 0
end
