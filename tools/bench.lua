-- Offline benchmark of the driver. Runs on Lua 5.1+.
-- Usage: lua tools/bench.lua Polymorph.lua [fps]   (default 120)
-- Frames are minimal fakes whose methods only store a value. "Lua µs" is
-- Polymorph's own Lua on this machine, so compare runs on one machine only.
-- "calls" counts game API calls per track per update. "est. game µs" prices
-- those calls with costs measured in the client (WoW Forever 1.60.1, 2026-10-14)
-- and adds the Lua time, so it is an estimate, not a measurement.
local COST = { SetPoint = 0.95, SetAlpha = 0.33, SetScale = 0.33, SetWidth = 0.31, SetHeight = 0.31, SetSize = 0.31,
               InCombatLockdown = 0.18, IsProtected = 0.28 }
local calls = {}
local path = assert(arg[1], "path to Polymorph.lua")
local driverScript
local counting = true
_G.InCombatLockdown = function()
  if counting then calls.InCombatLockdown = (calls.InCombatLockdown or 0) + 1 end
  return false
end
_G.debugprofilestop = function() return os.clock() * 1000 end
_G.CreateFrame = function()
  return { SetScript = function(_, name, fn) if name == "OnUpdate" then driverScript = fn end end,
           RegisterEvent = function() end }
end
local plain = {
  GetAlpha = function(self) return self.a end, SetAlpha = function(self, v) self.a = v end,
  GetWidth = function(self) return self.w end, SetWidth = function(self, v) self.w = v end,
  GetHeight = function(self) return self.h end, SetHeight = function(self, v) self.h = v end,
  SetSize = function(self, w, h) self.w, self.h = w, h end,
  GetScale = function(self) return self.s end, SetScale = function(self, v) self.s = v end,
  GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end, SetPoint = function() end,
  IsProtected = function() return false end,
}
local counted = {}
for name, fn in pairs(plain) do
  counted[name] = COST[name] and function(...) calls[name] = (calls[name] or 0) + 1; return fn(...) end or fn
end
local function frame()
  return setmetatable({ a = 1, w = 100, h = 50, s = 1 }, { __index = plain })
end
-- Swaps every frame between plain and counted methods.
local function instrument(frames, on)
  for _, f in ipairs(frames) do getmetatable(f).__index = on and counted or plain end
end
local ns = { dev = true }
assert(loadfile(path))("Polymorph", ns)
local Poly = ns.Polymorph

local FPS = tonumber(arg[2]) or 120
local DT = 1 / FPS
-- Steps the driver `n` times. Returns Lua µs per track per update, timed with
-- uncounted calls, then game calls and their priced µs per track per update.
local function measure(n, tracks)
  counting = false
  local start = os.clock()
  for _ = 1, n do if driverScript then driverScript(nil, DT) end end
  return (os.clock() - start) * 1e6 / (n * tracks)
end
local function countCalls(n, tracks)
  for k in pairs(calls) do calls[k] = nil end
  counting = true
  for _ = 1, n do if driverScript then driverScript(nil, DT) end end
  local total, priced = 0, 0
  for k, c in pairs(calls) do total = total + c; priced = priced + c * assert(COST[k], k) end
  return total / (n * tracks), priced / (n * tracks)
end

local N = 200
local scenarios = {
  { "spring: alpha, x, width (gentle)", { alpha = 0.3, x = 120, width = 24 }, { alpha = 1, x = 0, width = 12 }, { spring = "gentle" } },
  { "tween: alpha, x, width (outCubic)", { alpha = 0.3, x = 120, width = 24 }, { alpha = 1, x = 0, width = 12 }, { duration = 10 } },
  { "spring: alpha only (stiff)", { alpha = 0.3 }, { alpha = 1 }, { spring = "stiff" } },
  { "spring: x, y slide (default)", { x = 40, y = -30 }, { x = 0, y = 0 }, {} },
  { "spring: width, height (default)", { width = 140, height = 90 }, { width = 100, height = 50 }, {} },
}
local ROUNDS = 15
print(("%-36s %9s %7s %13s"):format(("scenario (%s frames, %s fps)"):format(N, FPS), "Lua µs", "calls", "est. game µs"))
for _, sc in ipairs(scenarios) do
  local frames = {}
  for i = 1, N do frames[i] = frame() end
  local count = 0
  for _ in pairs(sc[2]) do count = count + 1 end
  local samples = {}
  for r = 1, ROUNDS do
    -- Retarget every round so springs never settle: every track moves every update.
    local targets = r % 2 == 1 and sc[2] or sc[3]
    for _, f in ipairs(frames) do Poly(f):to(targets, sc[4]) end
    instrument(frames, false)
    samples[r] = measure(20, N * count)
  end
  instrument(frames, true)
  table.sort(samples)
  local lua = samples[math.ceil(ROUNDS / 2)]
  for _, f in ipairs(frames) do Poly(f):to(sc[2], sc[4]) end
  local perTrack, priced = countCalls(20, N * count)
  print(("%-36s %9.3f %7.2f %13.2f"):format(sc[1], lua, perTrack, lua + priced))
  for _, f in ipairs(frames) do Poly(f):stop() end
  for _ = 1, 3 do if driverScript then driverScript(nil, DT) end end
end
