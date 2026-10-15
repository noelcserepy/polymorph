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
--   7. M.makeCounter(fontString): returns add(amount). Each call adds to a running total, which the
--      font string shows as a whole number that rolls smoothly to each new total, also when a call
--      comes mid-roll. Totals can pass 3 billion.
local libPath, answerPath = assert(arg[1], "Polymorph.lua"), assert(arg[2], "answer.lua")

local combat, now, tick = false, 0, 1 / 60
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
function Region:CreateTexture() return setmetatable({ scripts = {}, parent = self, shown = true, alpha = 1, w = 0, h = 0, s = 1 }, Region) end
function Region:CreateFontString() return setmetatable({ scripts = {}, parent = self, shown = true, alpha = 1, w = 0, h = 0, s = 1 }, Region) end
function Region:GetParent() return self.parent end
-- Frames have a kind from CreateFrame. Textures and font strings don't.
function Region:IsObjectType(kind) return kind == "Frame" and self.kind ~= nil end
function Region:SetText(text) self.text = text end
function Region:GetText() return self.text end
function Region:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
-- The combat puppet: Polymorph steers a paused Translation and Scale. Only
-- their effect on where the frame draws matters here, so they are recorded.
-- Native animation groups, as measured in the client. Progress runs over the
-- duration, backwards when played in reverse, through the smoothing curve. A
-- Translation offset is in the frame's scaled units, a Scale grows the frame
-- around its origin, and an Alpha draws its own value in place of the frame's.
local CURVES = {
  NONE = function(p) return p end,
  IN = function(p) return 1 - math.cos(p * math.pi / 2) end,
  OUT = function(p) return math.sin(p * math.pi / 2) end,
  IN_OUT = function(p) return (1 - math.cos(p * math.pi)) / 2 end,
}
local groups = {}
function Region:CreateAnimationGroup()
  local owner = self
  local ag = setmetatable({ scripts = {}, anims = {}, elapsed = 0 }, Region)
  owner.groups = owner.groups or {}
  table.insert(owner.groups, ag)
  table.insert(groups, ag)
  function ag:CreateAnimation(kind)
    local a = setmetatable({ kind = kind, duration = 1, smoothing = "NONE", ox = 0, oy = 0, k = 1,
                             origin = { "CENTER", 0, 0 }, scripts = {} }, Region)
    function a:SetDuration(d) self.duration = d end
    function a:SetSmoothing(v) self.smoothing = v end
    function a:SetSmoothProgress(v) self.forced = v end
    function a:GetProgress()
      local p = math.min(1, ag.elapsed / self.duration)
      return ag.reverse and 1 - p or p
    end
    function a:GetSmoothProgress() return self.forced or CURVES[self.smoothing](self:GetProgress()) end
    function a:SetOffset(x, y) self.ox, self.oy = x, y end
    function a:SetScaleTo(x) self.k = x end
    function a:SetOrigin(point, x, y) self.origin = { point, x or 0, y or 0 } end
    function a:SetFromAlpha(v) self.from = v end
    function a:SetToAlpha(v) self.to = v end
    table.insert(ag.anims, a)
    return a
  end
  function ag:Play(reverse)
    self.playing, self.paused, self.reverse, self.elapsed = true, false, reverse or false, 0
    for _, a in ipairs(self.anims) do a.forced = nil end
  end
  function ag:Pause() self.paused = true end
  function ag:Stop() self.playing = false end
  function ag:IsPlaying() return self.playing end
  return ag
end
local function advanceAnimations(dt)
  for _, ag in ipairs(groups) do
    if ag.playing and not ag.paused then
      ag.elapsed = ag.elapsed + dt
      local longest = 0
      for _, a in ipairs(ag.anims) do longest = math.max(longest, a.duration) end
      if ag.elapsed >= longest then
        ag.playing = false
        if ag.scripts.OnFinished then ag.scripts.OnFinished(ag) end
      end
    end
  end
end
-- What every playing group on the frame adds: translation, scale and its origin, alpha.
function Region:Native()
  local x, y, k, origin, alpha = 0, 0, 1, { "CENTER", 0, 0 }, nil
  for _, ag in ipairs(self.groups or {}) do
    if ag.playing then
      for _, a in ipairs(ag.anims) do
        local sp = a:GetSmoothProgress()
        if a.kind == "Translation" then x, y = x + a.ox * sp, y + a.oy * sp
        elseif a.kind == "Scale" then k, origin = k * (1 + (a.k - 1) * sp), a.origin
        elseif a.kind == "Alpha" then alpha = a.from + (a.to - a.from) * sp end
      end
    end
  end
  return x, y, k, origin, alpha
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
function Region:EffectiveAlpha()
  local own = select(5, self:Native()) or self.alpha
  return own * (self.parent and self.parent:EffectiveAlpha() or 1)
end
function Region:EffectiveScale() return self.s * (self.parent and self.parent:EffectiveScale() or 1) end
function Region:Rect()
  if self == UIParent then return 0, 0, self.w, self.h end
  local e, p = self:EffectiveScale(), assert(self.point, "frame has no anchor")
  local w, h = self.w * e, self.h * e
  local nx, ny, k, origin = self:Native()
  local rl, rb, rw, rh = (p[2] or UIParent):Rect()
  local ax, ay = pointIn(rl, rb, rw, rh, p[3])
  local ox, oy = pointIn(0, 0, w, h, p[1])
  local l, b = ax + (p[4] + nx) * e - ox, ay + (p[5] + ny) * e - oy
  if k ~= 1 then
    local gx, gy = pointIn(l, b, w, h, origin[1])
    gx, gy = gx + origin[2] * e, gy + origin[3] * e
    l, b, w, h = gx + (l - gx) * k, gy + (b - gy) * k, w * k, h * k
  end
  return l, b, w, h
end
function InCombatLockdown() return combat end
function debugprofilestop() return os.clock() * 1000 end
function GetTime() return now end
function GetTickTime() return tick end
C_Timer = {
  After = function(sec, fn) timers[#timers + 1] = { at = now + sec, fn = fn } end,
  NewTimer = function(sec, fn) local t = { at = now + sec, fn = fn, Cancel = function(self) self.cancelled = true end }; timers[#timers + 1] = t; return t end,
}
-- WoW's string.format errors on %d and %i outside the 32-bit range.
local realFormat = string.format
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
function BreakUpLargeNumbers(n)
  local s = realFormat("%.0f", n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end },
  { __call = function(_, name) return assert(libs[name], "no library " .. name) end })

assert(loadfile(libPath))("Polymorph", {})

local M = assert(loadfile(answerPath))()

-- Runs frames as the client does: scripts, then animations, then drawing.
-- Code between calls runs at the start of the next frame, as an event does.
-- Timers run before the OnUpdates here. Their order in the client is unmeasured.
local function run(seconds, fps)
  local dt = 1 / (fps or 60)
  for _ = 1, math.floor(seconds / dt + 0.5) do
    for i = #timers, 1, -1 do
      local t = timers[i]
      if now >= t.at then table.remove(timers, i); if not t.cancelled then t.fn(t) end end
    end
    -- Every frame's OnUpdate runs, as in the game: Polymorph's driver and the answer's own.
    for _, f in ipairs(frames) do
      local fn = f.scripts.OnUpdate
      if fn and f:IsVisible() then fn(f, tick) end
    end
    advanceAnimations(tick)
    now, tick = now + dt, dt
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
  return { f:IsVisible() and f:EffectiveAlpha() or 0, l, b, w, h, b + h }
end
-- Fields of a look: 1 alpha, 2 left, 3 bottom, 4 width, 5 height, 6 top.
local ALL, SIZE, WIDTH, VERTICAL = { 1, 2, 3, 4, 5 }, { 4, 5 }, { 4 }, { 6 }
local function same(a, b, fields)
  for _, i in ipairs(fields or ALL) do if math.abs(a[i] - b[i]) > 0.01 then return false end end
  return true
end

-- Runs `action`, then samples what the frame draws at 240 fps for `seconds`,
-- keeping the samples the player can see. Counts distinct values in the middle
-- of each field's travel. With `fields`, every listed field must move through
-- its middle on its own, and the count is the smallest of theirs. Without, the
-- count is the largest. Also returns the samples, and the biggest step.
-- Distinct values in the middle of a travel: between 20% and 80% of the way
-- from the first value to the last. A jump never lands there, and a wobble or
-- a few steps near one end stay out of it.
local function middle(values)
  local a, b = values[1], values[#values]
  if not a or math.abs(b - a) < 0.01 then return 0 end
  local seen, n = {}, 0
  for _, v in ipairs(values) do
    local k, key = (v - a) / (b - a), ("%.2f"):format(v)
    if k >= 0.2 and k <= 0.8 and not seen[key] then seen[key] = true; n = n + 1 end
  end
  return n
end

local function transition(f, action, seconds, fields)
  local before = look(f)
  action()
  local samples = {}
  -- Only what the player can see counts: shown, and not fully transparent.
  -- The first sample is right after the call, before the driver runs.
  -- hidden: frames the player could not see, once the frame had been seen
  -- (before the call, or since).
  -- back: whether it came back into view after such a frame.
  local hidden, back = 0, false
  local function sample()
    local l = look(f)
    if l[1] > 0.01 then
      if hidden > 0 then back = true end
      samples[#samples + 1] = l
    elseif samples[1] or before[1] > 0.01 then
      hidden = hidden + 1
    end
  end
  sample()
  for _ = 1, math.floor(seconds * 240) do
    run(1 / 240, 240)
    sample()
  end
  local function count(i)
    local values = {}
    for n, l in ipairs(samples) do values[n] = l[i] end
    return middle(values)
  end
  -- The biggest step between consecutive looks, from the look before the action.
  local jump, last = 0, before
  for _, l in ipairs(samples) do
    for _, i in ipairs(fields or ALL) do jump = math.max(jump, math.abs(l[i] - last[i])) end
    last = l
  end
  -- With no fields named, any one field moving smoothly is enough.
  if not fields then
    local most = 0
    for _, i in ipairs(ALL) do most = math.max(most, count(i)) end
    return most, samples, jump, hidden, back
  end
  local least = math.huge
  for _, i in ipairs(fields) do least = math.min(least, count(i)) end
  return least, samples, jump, hidden, back
end
local ANIMATED = 3 -- distinct in-between looks: real motion, not a hold and a jump
local SMOOTH = 8 -- the most a size may change between two samples 1/240 s apart

check("1 toggle animates open and closed, and survives fast clicks", function()
  local panel, button = newFrame(), newFrame()
  panel:Hide()
  M.setupToggle(panel, button)
  local click = function() button.scripts.OnClick(button, "LeftButton") end
  local n, _, _, hidden = transition(panel, click, 1.5)
  assert(hidden == 0, "disappeared while opening")
  assert(n >= ANIMATED, "did not animate open")
  assert(panel.shown and atRest(panel), "not open at rest after one click")
  local back
  n, _, _, _, back = transition(panel, click, 1.5)
  assert(not back, "came back while closing")
  assert(n >= ANIMATED, "did not animate closed")
  assert(not panel.shown, "still shown after the second click")
  click(); run(0.05); click(); run(0.05); click(); run(1.5)
  assert(panel.shown and atRest(panel), "three fast clicks did not end open at rest")
end)

check("2 toast slides in from above and leaves upward after 3 s", function()
  local toast = newFrame()
  toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
  local _, b0, w0, h0 = toast:Rect()
  local top = b0 + h0
  -- One look per frame from the call to 4.5 s, checked against the toast's
  -- whole timeline. A slide moves the toast without changing its size, which
  -- makes its top edge an honest measure of the slide.
  M.notify(toast)
  local frames, t = {}, {}
  for n = 1, math.floor(4.5 * 240) do
    run(1 / 240, 240)
    frames[n], t[n] = look(toast), n / 240
  end
  local entry, exit = {}, {}
  local shownAt, leftAt, hiddenAt, highest, lowest
  for n, l in ipairs(frames) do
    local seen = l[1] > 0.01
    if seen then
      assert(near(l[4], w0, 0.05) and near(l[5], h0, 0.05), "changed size while shown")
    end
    if t[n] < 3 then
      if seen and not shownAt then
        shownAt = n
        assert(l[6] > top + 0.5, "did not slide in from above")
      end
      assert(not shownAt or seen, "hid before 3 s")
      if t[n] < 1 then
        if seen then
          -- Coming in, the toast only comes down. A spring may overshoot a little.
          lowest = math.min(lowest or l[6], l[6])
          assert(l[6] < lowest + 2, "went back up while coming in")
          entry[#entry + 1] = l[6]
        end
      else
        assert(near(l[1], 1) and near(l[6], top), "moved or hid before 3 s")
      end
    else
      if not leftAt and math.abs(l[6] - top) > 2 then
        leftAt = t[n]
        assert(l[6] > top, "did not slide out upward")
      end
      if hiddenAt then assert(not seen, "came back after leaving") end
      if leftAt and not hiddenAt then
        if seen then
          highest = math.max(highest or l[6], l[6])
          assert(l[6] > highest - 2, "came back down while leaving")
          exit[#exit + 1] = l[6]
        else
          hiddenAt = t[n]
        end
      end
    end
  end
  assert(shownAt and entry[1] and entry[1] > top + 0.5 and middle(entry) >= ANIMATED, "did not slide in from above")
  assert(leftAt and leftAt <= 3.3, "did not start leaving by 3.3 s")
  table.insert(exit, 1, top)
  assert(exit[#exit] > top + 0.5 and middle(exit) >= ANIMATED, "did not slide out upward")
  assert(hiddenAt, "still shown after 4.5 s")
end)

check("3 bar follows events smoothly", function()
  local bar = newFrame()
  bar:SetWidth(200)
  -- Every event animates without a jump, including ones that arrive mid-animation.
  local function event(fraction, seconds, label)
    local n, _, jump, hidden = transition(bar, function() M.updateBar(bar, fraction) end, seconds, WIDTH)
    assert(hidden == 0, "disappeared " .. label)
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
  assert(look(b)[1] > 0.05, "button not visible after creation")
  assert(near(l, pl + 10) and near(bottom + h, pb + ph - 10), "not at the parent's TOPLEFT (10, -10)")
  local cx, cy = l + w / 2, bottom + h / 2
  local before = look(b)
  local function centered(samples)
    for _, l in ipairs(samples) do
      if not (near(l[2] + l[4] / 2, cx, 0.5) and near(l[3] + l[5] / 2, cy, 0.5)) then return false end
    end
    return true
  end
  local n, samples, jump, hidden = transition(b, function() b.scripts.OnEnter(b) end, 1, SIZE)
  assert(hidden == 0, "disappeared while growing")
  assert(n >= ANIMATED, "did not animate growing")
  assert(jump < SMOOTH, ("jumped %.1f while growing"):format(jump))
  assert(centered(samples), "center moved while growing")
  l, bottom, w, h = b:Rect()
  assert(near(w, 46) and near(h, 46), "drawn " .. w .. " wide on hover, want 46")
  assert(near(l + w / 2, cx) and near(bottom + h / 2, cy), "center moved while growing")
  n, samples, jump, hidden = transition(b, function() b.scripts.OnLeave(b) end, 1, SIZE)
  assert(hidden == 0, "disappeared while shrinking")
  assert(n >= ANIMATED, "did not animate shrinking")
  assert(jump < SMOOTH, ("jumped %.1f while shrinking"):format(jump))
  assert(centered(samples), "center moved while shrinking")
  assert(same(look(b), before), "not back to its first size and place after leave")
end)

check("5 secure panel animates out and hides, in and out of combat, with no blocked calls", function()
  local panel = newFrame("SecureHandlerStateTemplate")
  combat = true
  local n, _, _, _, back = transition(panel, function() M.closeSecurePanel(panel) end, 1)
  assert(not back, "came back while closing in combat")
  assert(n >= ANIMATED, "did not animate in combat")
  assert(look(panel)[1] < 0.01, "not faded in combat: alpha " .. look(panel)[1])
  combat = false
  fire("PLAYER_REGEN_ENABLED")
  run(0.1)
  assert(not panel.shown, "not hidden after combat")
  local other = newFrame("SecureHandlerStateTemplate")
  n, _, _, _, back = transition(other, function() M.closeSecurePanel(other) end, 1)
  assert(not back, "came back while closing out of combat")
  assert(n >= ANIMATED, "did not animate out of combat")
  assert(not other.shown, "not hidden out of combat")
end)

check("6 list fades in one after another", function()
  local rows = {}
  for i = 1, 5 do rows[i] = newFrame() end
  M.fadeListIn(rows)
  for i, r in ipairs(rows) do
    assert(r:EffectiveAlpha() < 0.05, "row " .. i .. " did not start invisible: alpha " .. r:EffectiveAlpha())
  end
  -- Every frame for 2.5 s: once a row starts, it never dims below the most it
  -- has shown. Its fade, for the middle-of-travel rule, runs from its start
  -- until it first reaches full alpha.
  local started, peak, alphas = {}, {}, { {}, {}, {}, {}, {} }
  for step = 1, 240 * 2.5 do
    run(1 / 240, 240)
    for i, r in ipairs(rows) do
      local alpha = look(r)[1]
      if not started[i] and alpha > 0.02 then started[i] = step end
      if started[i] then
        local a = alphas[i]
        if not (a[#a] and a[#a] >= 0.99) then a[#a + 1] = alpha end
        peak[i] = math.max(peak[i] or 0, alpha)
        assert(alpha > peak[i] - 0.05, ("row %d dimmed%s"):format(i, a[#a] >= 0.99 and " after fading in" or " while fading in"))
      end
    end
  end
  for i = 1, 5 do
    table.insert(alphas[i], 1, 0) -- each fade starts from invisible
    assert(started[i] and middle(alphas[i]) >= ANIMATED, "row " .. i .. " did not fade in")
  end
  for i = 2, 5 do
    assert(started[i] > started[i - 1], ("row %d started with or before row %d"):format(i, i - 1))
  end
  for i, r in ipairs(rows) do
    assert(near(look(r)[1], 1), "row " .. i .. " not fully visible at the end")
  end
end)

check("7 counter rolls to each total, keeps rolling through a call mid-roll, and passes 3 billion", function()
  local fs = newFrame():CreateFontString()
  local add = M.makeCounter(fs)
  -- What the font string shows, every frame at 240 fps, as numbers.
  local function shown()
    local text = assert(fs.text, "shows no text")
    assert(text:match("^[%d,]+$"), "not a whole number: " .. text)
    return tonumber((text:gsub(",", "")))
  end
  local function roll(seconds)
    local values = { fs.text and shown() or 0 }
    for _ = 1, math.floor(seconds * 240) do
      run(1 / 240, 240)
      values[#values + 1] = shown()
    end
    return values
  end
  local function smooth(values, label)
    local a, b = values[1], values[#values]
    assert(middle(values) >= ANIMATED, "did not roll " .. label)
    for i = 2, #values do
      assert(values[i] >= values[i - 1], ("rolled back from %.0f to %.0f %s"):format(values[i - 1], values[i], label))
      assert(values[i] - values[i - 1] <= 0.15 * (b - a), ("jumped from %.0f to %.0f %s"):format(values[i - 1], values[i], label))
    end
  end
  add(1000)
  local first = roll(1.5)
  smooth(first, "to 1000")
  assert(first[#first] == 1000, ("shows %.0f, want 1000"):format(first[#first]))
  add(500)
  local partway = roll(0.05)
  add(3e9)
  local rest = roll(4)
  for _, v in ipairs(rest) do partway[#partway + 1] = v end
  smooth(partway, "after a call mid-roll")
  assert(partway[#partway] == 3000001500, ("shows %.0f, want 3000001500"):format(partway[#partway]))
end)

local failed = 0
for _, r in ipairs(results) do
  print((r.ok and "ok   " or "FAIL ") .. r.name .. (r.ok and "" or ": " .. tostring(r.err)))
  if not r.ok then failed = failed + 1 end
end
print(("%d of %d passed"):format(#results - failed, #results))
os.exit(failed == 0 and 0 or 1)
