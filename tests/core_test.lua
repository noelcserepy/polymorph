-- Offline tests for Polymorph.lua against a fake frame API. Runs on Lua 5.1+.
-- Usage: lua tests/core_test.lua Polymorph.lua
local path = assert(arg[1], "path to Polymorph.lua")

local combat = false
local driverScript
local eventHandlers = {}
_G.InCombatLockdown = function() return combat end
_G.debugprofilestop = function() return os.clock() * 1000 end
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

local function fakeFrame(protected)
  local f = { alpha = 1, w = 100, h = 50, s = 1, point = { "CENTER", nil, "CENTER", 10, 20 }, pointCalls = 0 }
  function f:GetAlpha() return self.alpha end
  function f:SetAlpha(v) self.alpha = v end
  function f:GetWidth() return self.w end
  function f:SetWidth(v) assert(not (combat and protected), "SetWidth while locked"); self.w = v end
  function f:GetHeight() return self.h end
  function f:SetHeight(v) self.h = v end
  function f:GetScale() return self.s end
  function f:SetScale(v) self.s = v end
  function f:GetPoint() return unpack(self.point) end
  function f:SetPoint(a, b, c, x, y)
    assert(not (combat and protected), "SetPoint while locked")
    self.point = { a, b, c, x, y }
    self.pointCalls = self.pointCalls + 1
  end
  function f:IsProtected() return protected end
  -- Native animation groups: a paused Translation adds its offset to where the
  -- frame shows, like the real client (dev/jobs/core/native_puppet.lua).
  f.nativeX, f.nativeY = 0, 0
  function f:CreateAnimationGroup()
    local ag = { playing = false }
    function ag:CreateAnimation()
      local a = { ox = 0, oy = 0 }
      function a:SetDuration() end
      function a:SetSmoothing() end
      function a:SetSmoothProgress() end
      function a:SetOffset(x, y) self.ox, self.oy = x, y; if ag.playing then f.nativeX, f.nativeY = x, y end end
      ag.anim = a
      return a
    end
    function ag:Play() self.playing = true; f.nativeX, f.nativeY = self.anim.ox, self.anim.oy end
    function ag:Pause() end
    function ag:Stop() self.playing = false; f.nativeX, f.nativeY = 0, 0 end
    return ag
  end
  function f:VisualX() return self.point[4] + self.nativeX end
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

local ns = { dev = true }
assert(loadfile(path))("Polymorph", ns)
local Poly = ns.Polymorph

local function run(seconds, fps)
  local dt = 1 / (fps or 60)
  for _ = 1, math.floor(seconds / dt + 0.5) do
    if driverScript then driverScript(nil, dt) end
  end
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("ok " .. name) end

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
  assert(near(f.w, 100 + 200 * 0.875, 1), f.w)
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
  assert(f.point[4] == 60 and f.nativeX == 0 and f:VisualX() == 60, "commit moved the frame")
  run(0.5)
  assert(f.w == 160, "width not applied after combat")
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
  assert(f.nativeX == 0 and math.abs(f:VisualX() - mid) < 2, "jump at handover")
  run(1)
  assert(f.point[4] == 110)
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

print(("CORE OK: %d tests"):format(passed))
