-- Checks code an agent wrote from skills/polymorph/SKILL.md alone.
-- Usage: lua tools/skill_check.lua Polymorph.lua answer.lua
--
-- The brief given to the agent, with no other documentation:
--   Write answer.lua, a chunk returning a table M with
--   1. M.setupToggle(panel, button): button's OnClick opens the hidden panel, or closes it, animated.
--   2. M.notify(toast): an anchored toast slides in from above and leaves the same way after 3 s.
--   3. M.updateBar(bar, fraction): called on every health event, width follows 200 * fraction smoothly.
--   4. M.makeHoverButton(parent): a 40x40 button at the parent's TOPLEFT (10, -10) that grows to
--      1.15x around its center on enter, and back on leave.
--   5. M.closeSecurePanel(panel): animates a protected panel out and hides it, in or out of combat.
--   6. M.fadeListIn(rows): fades in anchored rows from invisible, one slightly after another.
local libPath, answerPath = assert(arg[1], "Polymorph.lua"), assert(arg[2], "answer.lua")

local combat, now = false, 0
local events, timers = {}, {}
local violations = {}
unpack = unpack or table.unpack

local function noop() end
-- Any method we do not model is a no-op, so idiomatic extras do not crash.
local Region = {}
Region.__index = function(_, k)
  local v = Region[k]
  if v == nil and type(k) == "string" and k:match("^%u") then return noop end
  return v
end

local function locked(f) return combat and f.protected end
local function guard(f, what)
  if locked(f) then violations[#violations + 1] = what .. " on a protected frame in combat" end
end

function Region:SetSize(w, h) guard(self, "SetSize"); self.w, self.h = w, h end
function Region:SetWidth(w) guard(self, "SetWidth"); self.w = w end
function Region:SetHeight(h) guard(self, "SetHeight"); self.h = h end
function Region:GetWidth() return self.w end
function Region:GetHeight() return self.h end
function Region:GetSize() return self.w, self.h end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha end
function Region:SetScale(s) guard(self, "SetScale"); self.s = s end
function Region:GetScale() return self.s end
function Region:ClearAllPoints() guard(self, "ClearAllPoints"); self.point = nil end
function Region:SetPoint(point, a, b, c, d)
  guard(self, "SetPoint")
  local rel, relPoint, x, y
  if type(a) == "number" then x, y = a, b
  elseif type(b) == "number" then rel, x, y = a, b, c
  else rel, relPoint, x, y = a, b, c, d end
  self.point = { point, rel or self.parent, relPoint or point, x or 0, y or 0 }
end
function Region:SetAllPoints(rel) self:SetPoint("TOPLEFT", rel or self.parent, "TOPLEFT", 0, 0) end
function Region:GetPoint() if self.point then return unpack(self.point, 1, 5) end end
function Region:Show() guard(self, "Show"); self.shown = true end
function Region:Hide() guard(self, "Hide"); self.shown = false end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Region:IsProtected() return self.protected end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
  local old = self.scripts[name]
  self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Region:RegisterEvent(e) events[e] = events[e] or {}; table.insert(events[e], self) end
function Region:CreateTexture() return setmetatable({ scripts = {} }, Region) end
function Region:CreateFontString() return setmetatable({ scripts = {} }, Region) end
function Region:GetParent() return self.parent end
-- The combat puppet: Polymorph steers a paused Translation and Scale. Only
-- their effect on where the frame draws matters here, so they are recorded.
function Region:CreateAnimationGroup()
  local ag = setmetatable({ scripts = {} }, Region)
  function ag:CreateAnimation() return setmetatable({ scripts = {} }, Region) end
  return ag
end

local frames = {}
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, alpha = 1, w = 0, h = 0, s = 1,
                           protected = type(template) == "string" and template:find("Secure") ~= nil }, Region)
  frames[#frames + 1] = f
  return f
end
UIParent = CreateFrame("Frame")
function InCombatLockdown() return combat end
function debugprofilestop() return os.clock() * 1000 end
function GetTime() return now end
C_Timer = {
  After = function(sec, fn) timers[#timers + 1] = { at = now + sec, fn = fn } end,
  NewTimer = function(sec, fn) local t = { at = now + sec, fn = fn, Cancel = function(self) self.cancelled = true end }; timers[#timers + 1] = t; return t end,
}
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end },
  { __call = function(_, name) return assert(libs[name], "no library " .. name) end })

assert(loadfile(libPath))("Polymorph", {})

local M = assert(loadfile(answerPath))()

local function run(seconds)
  local dt = 1 / 60
  for _ = 1, math.floor(seconds / dt + 0.5) do
    now = now + dt
    for i = #timers, 1, -1 do
      local t = timers[i]
      if now >= t.at then table.remove(timers, i); if not t.cancelled then t.fn(t) end end
    end
    -- Every frame's OnUpdate runs, as in the game: Polymorph's driver and the answer's own.
    for _, f in ipairs(frames) do
      local fn = f.scripts.OnUpdate
      if fn and f:IsVisible() then fn(f, dt) end
    end
  end
end
local function fire(e) for _, f in ipairs(events[e] or {}) do local fn = f.scripts.OnEvent; if fn then fn(f, e) end end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end

local results = {}
local function check(name, fn)
  violations = {}
  combat = false
  local ok, err = pcall(fn)
  if ok and #violations > 0 then ok, err = false, violations[1] end
  results[#results + 1] = { name = name, ok = ok, err = err }
end
local function newFrame(template)
  local f = CreateFrame("Frame", nil, UIParent, template)
  f:SetSize(200, 100)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  return f
end
local function atRest(f) return near(f.alpha, 1) and near(f.s, 1) end

check("1 toggle opens, closes, and survives fast clicks", function()
  local panel, button = newFrame(), newFrame()
  panel:Hide()
  M.setupToggle(panel, button)
  local click = function() button.scripts.OnClick(button, "LeftButton") end
  click(); run(1.5)
  assert(panel.shown and atRest(panel), "not open at rest after one click")
  click(); run(1.5)
  assert(not panel.shown, "still shown after the second click")
  click(); run(0.05); click(); run(0.05); click(); run(1.5)
  assert(panel.shown and atRest(panel), "three fast clicks did not end open at rest")
end)

check("2 toast slides in from above and leaves after 3 s", function()
  local toast = newFrame()
  toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
  M.notify(toast)
  run(0.05)
  local _, _, _, _, y = toast:GetPoint()
  assert(toast.shown and y > -120, "did not start above its anchor: y " .. tostring(y))
  run(1)
  _, _, _, _, y = toast:GetPoint()
  assert(toast.shown and near(toast.alpha, 1) and near(y, -120), "not in place after 1 s")
  run(3)
  assert(not toast.shown, "still shown after 4 s")
end)

check("3 bar follows events smoothly", function()
  local bar = newFrame()
  bar:SetWidth(200)
  M.updateBar(bar, 0.5); run(0.1)
  local before = bar.w
  M.updateBar(bar, 0.8)
  assert(bar.w == before, "jumped on a new event")
  run(2)
  assert(near(bar.w, 160, 0.1), "width " .. bar.w .. ", want 160")
end)

check("4 hover button grows around its center", function()
  local parent = newFrame()
  local b = M.makeHoverButton(parent)
  local point, _, _, x, y = b:GetPoint()
  local onTopLeft = point == "TOPLEFT" and near(x, 10) and near(y, -10)
  local centered = point == "CENTER" and near(x, 0) and near(y, 0)
  if centered then
    local holder = b.point[2]
    local hp, hrel, hrp, hx, hy = holder:GetPoint()
    assert(hrel == parent and hp == "TOPLEFT" and hrp == "TOPLEFT" and near(hx, 10) and near(hy, -10), "holder not at the parent's TOPLEFT (10, -10)")
  else
    assert(not onTopLeft, "anchored by TOPLEFT, so scale grows toward the bottom right")
    error("button anchored at " .. tostring(point) .. " " .. tostring(x) .. "," .. tostring(y))
  end
  b.scripts.OnEnter(b); run(1)
  assert(near(b.s, 1.15), "scale " .. b.s .. " on hover")
  b.scripts.OnLeave(b); run(1)
  assert(near(b.s, 1), "scale " .. b.s .. " after leave")
end)

check("5 secure panel closes in combat without blocked calls", function()
  local panel = newFrame("SecureHandlerStateTemplate")
  combat = true
  M.closeSecurePanel(panel)
  run(1)
  assert(near(panel.alpha, 0), "not faded in combat: alpha " .. panel.alpha)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.1)
  assert(not panel.shown, "not hidden after combat")
  local other = newFrame("SecureHandlerStateTemplate")
  M.closeSecurePanel(other)
  run(1)
  assert(not other.shown, "not hidden out of combat")
end)

check("6 list fades in one after another", function()
  local rows = {}
  for i = 1, 5 do rows[i] = newFrame() end
  M.fadeListIn(rows)
  run(1 / 60)
  assert(rows[1].alpha < 0.5 and rows[5].alpha < 0.5, "rows did not start invisible")
  run(0.1)
  assert(rows[1].alpha > rows[5].alpha, "not staggered: " .. rows[1].alpha .. " vs " .. rows[5].alpha)
  run(2)
  for i, r in ipairs(rows) do assert(near(r.alpha, 1), "row " .. i .. " alpha " .. r.alpha) end
end)

local failed = 0
for _, r in ipairs(results) do
  print((r.ok and "ok   " or "FAIL ") .. r.name .. (r.ok and "" or ": " .. tostring(r.err)))
  if not r.ok then failed = failed + 1 end
end
print(("%d of %d passed"):format(#results - failed, #results))
os.exit(failed == 0 and 0 or 1)
