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
UIParent.w, UIParent.h = 1000, 800

-- Where frames draw, in screen units: the anchor chain, sizes and scales.
local function pointIn(left, bottom, w, h, point)
  local x = point:find("LEFT") and left or point:find("RIGHT") and left + w or left + w / 2
  local y = point:find("TOP") and bottom + h or point:find("BOTTOM") and bottom or bottom + h / 2
  return x, y
end
function Region:EffectiveScale() return self.s * (self.parent and self.parent:EffectiveScale() or 1) end
function Region:Rect()
  if self == UIParent then return 0, 0, self.w, self.h end
  local e, p = self:EffectiveScale(), assert(self.point, "frame has no anchor")
  local w, h = self.w * e, self.h * e
  local rl, rb, rw, rh = (p[2] or UIParent):Rect()
  local ax, ay = pointIn(rl, rb, rw, rh, p[3])
  local ox, oy = pointIn(0, 0, w, h, p[1])
  return ax + p[4] * e - ox, ay + p[5] * e - oy, w, h
end
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

local function run(seconds, fps)
  local dt = 1 / (fps or 60)
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

local function between(v, a, b) return v > math.min(a, b) + 0.01 and v < math.max(a, b) - 0.01 end
-- True while a show or hide is visibly under way: alpha or scale off rest.
local function animating(f) return between(f.alpha, 0, 1) or between(f.s, 0.5, 1) or between(f.s, 1, 1.5) end

check("1 toggle animates open and closed, and survives fast clicks", function()
  local panel, button = newFrame(), newFrame()
  panel:Hide()
  M.setupToggle(panel, button)
  local click = function() button.scripts.OnClick(button, "LeftButton") end
  click(); run(0.05)
  assert(panel.shown and animating(panel), "did not animate open")
  run(1.5)
  assert(panel.shown and atRest(panel), "not open at rest after one click")
  click(); run(0.05)
  assert(panel.shown and animating(panel), "did not animate closed")
  run(1.5)
  assert(not panel.shown, "still shown after the second click")
  click(); run(0.05); click(); run(0.05); click(); run(1.5)
  assert(panel.shown and atRest(panel), "three fast clicks did not end open at rest")
end)

check("2 toast slides in from above and leaves upward after 3 s", function()
  local toast = newFrame()
  toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
  M.notify(toast)
  run(0.05)
  local _, _, _, _, y = toast:GetPoint()
  assert(toast.shown and y > -120 and toast.alpha < 1, "did not come in from above: y " .. tostring(y))
  run(1)
  _, _, _, _, y = toast:GetPoint()
  assert(toast.shown and near(toast.alpha, 1) and near(y, -120), "not in place after 1 s")
  run(1.8)
  local leftUp, wentDown = false, false
  for _ = 1, 120 do
    run(1 / 60)
    _, _, _, _, y = toast:GetPoint()
    if toast.shown and y > -119.5 and toast.alpha < 1 then leftUp = true end
    if toast.shown and y < -120.5 then wentDown = true end
  end
  assert(leftUp and not wentDown, "did not leave upward")
  assert(not toast.shown, "still shown after 5 s")
end)

check("3 bar follows events smoothly", function()
  local bar = newFrame()
  bar:SetWidth(200)
  M.updateBar(bar, 0.5); run(0.05)
  assert(between(bar.w, 200, 100), "did not animate: width " .. bar.w)
  local before = bar.w
  M.updateBar(bar, 0.8)
  assert(bar.w == before, "jumped on a new event")
  run(0.05)
  assert(between(bar.w, before, 160) or between(bar.w, 160, 200), "did not move toward 160: " .. bar.w)
  run(2)
  assert(near(bar.w, 160, 0.1), "width " .. bar.w .. ", want 160")
end)

check("4 hover button sits at TOPLEFT (10, -10) and grows around its center", function()
  local parent = newFrame()
  local b = M.makeHoverButton(parent)
  local pl, pb, _, ph = parent:Rect()
  local l, bottom, w, h = b:Rect()
  assert(near(w, 40) and near(h, 40), "size " .. w .. "x" .. h)
  assert(near(l, pl + 10) and near(bottom + h, pb + ph - 10), "not at the parent's TOPLEFT (10, -10)")
  local cx, cy = l + w / 2, bottom + h / 2
  b.scripts.OnEnter(b); run(1)
  l, bottom, w, h = b:Rect()
  assert(near(w, 46) and near(h, 46), "drawn " .. w .. " wide on hover, want 46")
  assert(near(l + w / 2, cx) and near(bottom + h / 2, cy), "center moved while growing")
  b.scripts.OnLeave(b); run(1)
  l, bottom, w = b:Rect()
  assert(near(w, 40) and near(l + w / 2, cx), "did not shrink back")
end)

check("5 secure panel animates out and hides, in and out of combat, with no blocked calls", function()
  local panel = newFrame("SecureHandlerStateTemplate")
  combat = true
  M.closeSecurePanel(panel)
  run(0.05)
  assert(between(panel.alpha, 0, 1), "did not animate in combat: alpha " .. panel.alpha)
  run(1)
  assert(near(panel.alpha, 0), "not faded in combat: alpha " .. panel.alpha)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.1)
  assert(not panel.shown, "not hidden after combat")
  local other = newFrame("SecureHandlerStateTemplate")
  M.closeSecurePanel(other)
  run(0.05)
  assert(other.shown and animating(other), "did not animate out of combat")
  run(1)
  assert(not other.shown, "not hidden out of combat")
end)

check("6 list fades in one after another", function()
  local rows = {}
  for i = 1, 5 do rows[i] = newFrame() end
  M.fadeListIn(rows)
  local started = {}
  for step = 1, 240 * 2 do
    run(1 / 240, 240)
    for i, r in ipairs(rows) do
      if not started[i] and r.alpha > 0.02 then started[i] = step end
    end
  end
  for i = 1, 5 do assert(started[i], "row " .. i .. " never faded in") end
  for i = 2, 5 do
    assert(started[i] > started[i - 1], ("row %d started with or before row %d"):format(i, i - 1))
  end
  for i, r in ipairs(rows) do assert(near(r.alpha, 1), "row " .. i .. " alpha " .. r.alpha) end
end)

local failed = 0
for _, r in ipairs(results) do
  print((r.ok and "ok   " or "FAIL ") .. r.name .. (r.ok and "" or ": " .. tostring(r.err)))
  if not r.ok then failed = failed + 1 end
end
print(("%d of %d passed"):format(#results - failed, #results))
os.exit(failed == 0 and 0 or 1)
