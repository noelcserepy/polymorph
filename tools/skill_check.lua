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
function Region:EffectiveAlpha() return self.alpha * (self.parent and self.parent:EffectiveAlpha() or 1) end
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
local function atRest(f) return near(f:EffectiveAlpha(), 1) and near(f.s, 1) end

local function between(v, a, b) return v > math.min(a, b) + 0.01 and v < math.max(a, b) - 0.01 end
-- What a frame draws: alpha as the player sees it (0 when hidden) and its
-- rectangle on screen.
local function look(f)
  local l, b, w, h = f:Rect()
  return { f:IsVisible() and f:EffectiveAlpha() or 0, l, b, w, h }
end
-- Fields of a look: 1 alpha, 2 left, 3 bottom, 4 width, 5 height.
local ALL, SIZE, WIDTH, VERTICAL = { 1, 2, 3, 4, 5 }, { 4, 5 }, { 4 }, { 3 }
local function same(a, b, fields)
  for _, i in ipairs(fields or ALL) do if math.abs(a[i] - b[i]) > 0.01 then return false end end
  return true
end

-- Runs `action`, then samples what the frame draws at 240 fps for `seconds`.
-- Counts distinct in-between looks: shown, and matching neither the look
-- before the action nor the look at the end. With `fields` (default: any change), every
-- listed field must pass through in-between values on its own, and the count
-- is the smallest of theirs. Also returns the samples, for direction checks.
local function transition(f, action, seconds, fields)
  local before = look(f)
  action()
  local samples = {}
  -- Only what the player can see counts: shown, and not fully transparent.
  -- The first sample is right after the call, before the driver runs.
  local function sample() local l = look(f); if l[1] > 0.01 then samples[#samples + 1] = l end end
  sample()
  for _ = 1, math.floor(seconds * 240) do
    run(1 / 240, 240)
    sample()
  end
  local after = look(f)
  -- Distinct in-between looks: a frame that holds still, then jumps, gives one.
  local function count(only)
    local seen, n = {}, 0
    for _, l in ipairs(samples) do
      if not same(l, before, only) and not same(l, after, only) then
        local key = {}
        for _, i in ipairs(only) do key[#key + 1] = ("%.2f"):format(l[i]) end
        key = table.concat(key, " ")
        if not seen[key] then seen[key] = true; n = n + 1 end
      end
    end
    return n
  end
  -- The biggest step between consecutive looks, from the look before the action.
  local jump, last = 0, before
  for _, l in ipairs(samples) do
    for _, i in ipairs(fields or ALL) do jump = math.max(jump, math.abs(l[i] - last[i])) end
    last = l
  end
  if not fields then return count(ALL), samples, jump end
  local least = math.huge
  for _, i in ipairs(fields) do least = math.min(least, count({ i })) end
  return least, samples, jump
end
local ANIMATED = 3 -- distinct in-between looks: real motion, not a hold and a jump
local SMOOTH = 8 -- the most a size may change between two samples 1/240 s apart

check("1 toggle animates open and closed, and survives fast clicks", function()
  local panel, button = newFrame(), newFrame()
  panel:Hide()
  M.setupToggle(panel, button)
  local click = function() button.scripts.OnClick(button, "LeftButton") end
  assert(transition(panel, click, 1.5) >= ANIMATED, "did not animate open")
  assert(panel.shown and atRest(panel), "not open at rest after one click")
  assert(transition(panel, click, 1.5) >= ANIMATED, "did not animate closed")
  assert(not panel.shown, "still shown after the second click")
  click(); run(0.05); click(); run(0.05); click(); run(1.5)
  assert(panel.shown and atRest(panel), "three fast clicks did not end open at rest")
end)

check("2 toast slides in from above and leaves upward after 3 s", function()
  local toast = newFrame()
  toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
  local _, b0, _, h0 = toast:Rect()
  local top = b0 + h0
  -- Direction is where the motion starts (coming in) or ends (leaving). A
  -- spring may overshoot past the anchor on the way.
  local function above(l) return l[3] + l[5] > top + 0.5 end
  local n, samples = transition(toast, function() M.notify(toast) end, 1, VERTICAL)
  assert(n >= ANIMATED and above(samples[1]), "did not slide in from above")
  local _, b, _, h = toast:Rect()
  assert(toast.shown and near(b + h, top), "not in place after 1 s")
  run(1.85)
  _, b, _, h = toast:Rect()
  assert(near(look(toast)[1], 1) and near(b + h, top), "started leaving before 3 s")
  local still = look(toast)
  n, samples = transition(toast, function() end, 1.5, VERTICAL)
  -- Leaving starts by 3.3 s: within 0.45 s of these samples, at 240 per second.
  local moved
  for i, l in ipairs(samples) do
    if not same(l, still) then moved = i; break end
  end
  assert(moved and moved <= 0.45 * 240, "did not start leaving by 3.3 s")
  assert(n >= ANIMATED and above(samples[#samples]), "did not slide out upward")
  assert(not toast.shown, "still shown after 4.5 s")
end)

check("3 bar follows events smoothly", function()
  local bar = newFrame()
  bar:SetWidth(200)
  -- Every event animates without a jump, including ones that arrive mid-animation.
  local function event(fraction, seconds, label)
    local n, _, jump = transition(bar, function() M.updateBar(bar, fraction) end, seconds, WIDTH)
    assert(n >= ANIMATED, "did not animate " .. label .. ": width " .. bar.w)
    assert(jump < SMOOTH, ("jumped %.1f %s"):format(jump, label))
  end
  event(0.5, 2, "to 100")
  assert(near(bar.w, 100, 0.1), "width " .. bar.w .. ", want 100")
  event(0.4, 0.05, "toward 80")
  assert(between(bar.w, 100, 80), "not moving toward 80: width " .. bar.w)
  event(0.8, 2, "to 160 after an interruption")
  assert(near(bar.w, 160, 0.1), "width " .. bar.w .. ", want 160")
end)

check("4 hover button sits at TOPLEFT (10, -10) and grows around its center", function()
  local parent = newFrame()
  local b = M.makeHoverButton(parent)
  local pl, pb, _, ph = parent:Rect()
  local l, bottom, w, h = b:Rect()
  assert(near(w, 40) and near(h, 40), "size " .. w .. "x" .. h)
  assert(near(look(b)[1], 1), "button not visible after creation")
  assert(near(l, pl + 10) and near(bottom + h, pb + ph - 10), "not at the parent's TOPLEFT (10, -10)")
  local cx, cy = l + w / 2, bottom + h / 2
  local before = look(b)
  local function centered(samples)
    for _, l in ipairs(samples) do
      if not (near(l[2] + l[4] / 2, cx, 0.5) and near(l[3] + l[5] / 2, cy, 0.5)) then return false end
    end
    return true
  end
  local n, samples, jump = transition(b, function() b.scripts.OnEnter(b) end, 1, SIZE)
  assert(n >= ANIMATED, "did not animate growing")
  assert(jump < SMOOTH, ("jumped %.1f while growing"):format(jump))
  assert(centered(samples), "center moved while growing")
  l, bottom, w, h = b:Rect()
  assert(near(w, 46) and near(h, 46), "drawn " .. w .. " wide on hover, want 46")
  assert(near(look(b)[1], 1), "button not visible after growing")
  assert(near(l + w / 2, cx) and near(bottom + h / 2, cy), "center moved while growing")
  n, samples, jump = transition(b, function() b.scripts.OnLeave(b) end, 1, SIZE)
  assert(n >= ANIMATED, "did not animate shrinking")
  assert(jump < SMOOTH, ("jumped %.1f while shrinking"):format(jump))
  assert(centered(samples), "center moved while shrinking")
  assert(near(look(b)[1], 1), "button not visible after shrinking")
  assert(same(look(b), before), "not back to its first size and place after leave")
end)

check("5 secure panel animates out and hides, in and out of combat, with no blocked calls", function()
  local panel = newFrame("SecureHandlerStateTemplate")
  combat = true
  assert(transition(panel, function() M.closeSecurePanel(panel) end, 1) >= ANIMATED, "did not animate in combat")
  assert(near(panel.alpha, 0), "not faded in combat: alpha " .. panel.alpha)
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.1)
  assert(not panel.shown, "not hidden after combat")
  local other = newFrame("SecureHandlerStateTemplate")
  assert(transition(other, function() M.closeSecurePanel(other) end, 1) >= ANIMATED, "did not animate out of combat")
  assert(not other.shown, "not hidden out of combat")
end)

check("6 list fades in one after another", function()
  local rows = {}
  for i = 1, 5 do rows[i] = newFrame() end
  M.fadeListIn(rows)
  for i, r in ipairs(rows) do
    assert(r:EffectiveAlpha() < 0.05, "row " .. i .. " did not start invisible: alpha " .. r:EffectiveAlpha())
  end
  local started, faded = {}, {}
  for step = 1, 240 * 2 do
    run(1 / 240, 240)
    for i, r in ipairs(rows) do
      local alpha = r:IsVisible() and r:EffectiveAlpha() or 0
      if not started[i] and alpha > 0.02 then started[i] = step end
      if alpha > 0.05 and alpha < 0.95 then
        faded[i] = faded[i] or {}
        faded[i][("%.2f"):format(alpha)] = true
      end
    end
  end
  local function distinct(set) local n = 0; for _ in pairs(set or {}) do n = n + 1 end; return n end
  for i = 1, 5 do assert(started[i] and distinct(faded[i]) >= ANIMATED, "row " .. i .. " did not fade in") end
  for i = 2, 5 do
    assert(started[i] > started[i - 1], ("row %d started with or before row %d"):format(i, i - 1))
  end
  run(0.5)
  for i, r in ipairs(rows) do
    assert(r:IsVisible() and near(r:EffectiveAlpha(), 1), "row " .. i .. " not fully visible at the end")
  end
end)

local failed = 0
for _, r in ipairs(results) do
  print((r.ok and "ok   " or "FAIL ") .. r.name .. (r.ok and "" or ": " .. tostring(r.err)))
  if not r.ok then failed = failed + 1 end
end
print(("%d of %d passed"):format(#results - failed, #results))
os.exit(failed == 0 and 0 or 1)
