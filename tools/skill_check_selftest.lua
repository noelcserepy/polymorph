-- Proves tools/skill_check.lua tells good answers from bad ones.
-- Usage: lua tools/skill_check_selftest.lua Polymorph.lua
-- Each case edits the reference answer and states what the checker must say:
-- true to pass it, or the failure message of the one check it breaks. Naming
-- the message makes each case prove its own check, not some other one.
local lib = assert(arg[1], "Polymorph.lua")
local lua = arg[-1] or "lua"
local reference = assert(io.open("tools/skill_check_reference.lua")):read("*a")

local cases = {
  { "reference", true, {} },
  { "toggle without animation", "did not animate open", { 'if open then Poly(panel):show("pop") else Poly(panel):hide("pop", { duration = 0.15, ease = "inQuad" }) end', 'if open then panel:Show() else panel:Hide() end' } },
  { "toggle that slides", true, { 'if open then Poly(panel):show("pop") else Poly(panel):hide("pop", { duration = 0.15, ease = "inQuad" }) end', 'if open then Poly(panel):show({ y = 16 }) else Poly(panel):hide({ y = 16 }, { duration = 0.15, ease = "inQuad" }) end' } },
  { "toast never hidden first", "did not slide in from above", { 'if not Poly(toast):isMoving() and toast:IsShown() then toast:Hide() end', '' } },
  { "toast in from below", "did not slide in from above", { 'Poly(toast):show("above", { spring = "stiff" })', 'Poly(toast):show("below", { spring = "stiff" })' } },
  { "toast out downward", "did not slide out upward", { 'Poly(toast):hide("above")', 'Poly(toast):hide("below")' } },
  { "toast that slides without fading", true, { 'Poly(toast):show("above", { spring = "stiff" })', 'Poly(toast):show({ y = 16 }, { spring = "stiff" })', 'Poly(toast):hide("above")', 'Poly(toast):hide({ y = 16 })' } },
  { "bar without animation", "did not animate to 100", { 'Poly(bar):to({ width = 200 * fraction })', 'Poly(bar):to({ width = 200 * fraction }, { duration = 0 })' } },
  { "button without a size", "size 0x0", { '  b:SetSize(40, 40)\n', '' } },
  { "hover grows at once", "did not animate growing", { 'Poly(self):to({ scale = 1.15 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1.15 }, { duration = 0 })' } },
  { "hover shrinks at once", "did not animate shrinking", { 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1 }, { duration = 0 })' } },
  { "hover leave collapses the button", "did not animate shrinking", { 'b:SetScript("OnLeave", function(self) Poly(self)', 'b:SetScript("OnLeave", function(self) self:SetHeight(0); Poly(self)' } },
  { "secure panel vanishes in combat", "did not animate in combat", { 'Poly(panel):hide("fade", { duration = 0.2 })', 'Poly(panel):hide("fade", InCombatLockdown() and { duration = 0 } or nil)' } },
  { "secure panel vanishes always", "did not animate in combat", { 'Poly(panel):hide("fade", { duration = 0.2 })', 'Poly(panel):hide("fade", { duration = 0 })' } },
  { "secure panel slides out of combat", true, { 'Poly(panel):hide("fade", { duration = 0.2 })', 'Poly(panel):hide(InCombatLockdown() and "fade" or { y = 16 })' } },
  { "rows 1 to 4 together", "row 2 started with or before row 1", { 'delay = (i - 1) * 0.05', 'delay = i == 5 and 0.12 or 0' } },
  { "rows appear at once", "row 1 did not fade in", { 'duration = 0.3, delay', 'duration = 0, delay' } },
  { "bar first heads the wrong way", "width 300, want 100", { 'Poly(bar):to({ width = 200 * fraction })', 'Poly(bar):to({ width = fraction == 0.5 and 300 or 200 * fraction })' } },
  { "hover grows at once behind a fade", "did not animate growing", { 'Poly(self):to({ scale = 1.15 }, { spring = "stiff" })', 'Poly(self):set({ scale = 1.15, alpha = 0 }):to({ alpha = 1 }, { duration = 0.2 })' } },
  { "hover shrinks at once behind a fade", "did not animate shrinking", { 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):set({ scale = 1, alpha = 0 }):to({ alpha = 1 }, { duration = 0.2 })' } },
  { "round 2 agent answer: rows start fading at once", true, { 'delay = (i - 1) * 0.05', 'delay = (i - 1) * 0.04' , 'duration = 0.3, delay', 'duration = 0.2, delay' } },
  { "toast fades in still, then jumps into place", "did not slide in from above", { 'Poly(toast):show("above", { spring = "stiff" })', 'Poly(toast):show("above", { spring = "stiff" }); Poly(toast):to({ y = 0 }, { duration = 0, delay = 0.1 })' } },
  { "toast fades out still, then jumps up", "did not slide out upward", { 'Poly(toast):hide("above")', 'Poly(toast):hide("above"); Poly(toast):to({ y = 16 }, { duration = 0, delay = 0.1 })' } },
  { "hover width jumps, height animates", "did not animate growing", { 'Poly(self):to({ scale = 1.15 }, { spring = "stiff" })', 'Poly(self):set({ width = 46 }):to({ height = 46 }, { duration = 0.2 })', 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):to({ width = 40, height = 40 }, { duration = 0.2 })' } },
  { "hover leave width jumps", "did not animate shrinking", { 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):set({ width = 40 / 1.15 }):to({ height = 40 / 1.15 }, { duration = 0.2 })' } },
  { "rows hold at half, then jump in", "row 1 did not fade in", { 'duration = 0.3, delay', 'ease = function(p) if p < 0.3 then return 0 elseif p < 0.9 then return 0.5 end return 1 end, duration = 0.3, delay' } },
  { "bar ignores an event mid-animation", "did not animate toward 80", { 'function M.updateBar(bar, fraction) Poly(bar):to({ width = 200 * fraction }) end', 'function M.updateBar(bar, fraction) if fraction == 0.4 then return end Poly(bar):to({ width = 200 * fraction }) end' } },
  { "bar jumps on an event mid-animation", "toward 80", { 'function M.updateBar(bar, fraction) Poly(bar):to({ width = 200 * fraction }) end', 'function M.updateBar(bar, fraction) if fraction == 0.4 then Poly(bar):set({ width = 80 }) return end Poly(bar):to({ width = 200 * fraction }) end' } },
  { "rows fade while hidden", "row 1 did not fade in", { 'for i, row in ipairs(rows) do', 'for i, row in ipairs(rows) do row:Hide()' } },
  { "hover drifts sideways while growing", "center moved while growing", { 'Poly(self):to({ scale = 1.15 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1.15, x = 30 }, { duration = 0.2, onComplete = function() Poly(self):to({ x = 0 }, { duration = 0.2 }) end })' } },
  { "hover drifts sideways while shrinking", "center moved while shrinking", { 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1, x = 30 }, { duration = 0.2, onComplete = function() Poly(self):to({ x = 0 }, { duration = 0.2 }) end })' } },
  { "toast leaves 0.3 s early", "started leaving before 3 s", { 'C_Timer.After(3,', 'C_Timer.After(2.7,' } },
  { "hover button never visible", "button not visible after creation", { '  holder:SetSize(40, 40)\n', '  holder:SetSize(40, 40)\n  holder:Hide()\n' } },
  { "bar jumps partway on the first event", "jumped", { 'function M.updateBar(bar, fraction) Poly(bar):to({ width = 200 * fraction }) end', 'function M.updateBar(bar, fraction) if fraction == 0.5 then Poly(bar):set({ width = 150 }) end Poly(bar):to({ width = 200 * fraction }) end' } },
  { "bar jumps partway mid-animation", "jumped", { 'function M.updateBar(bar, fraction) Poly(bar):to({ width = 200 * fraction }) end', 'function M.updateBar(bar, fraction) if fraction == 0.4 then Poly(bar):set({ width = 90 }) end Poly(bar):to({ width = 200 * fraction }) end' } },
  { "hover button fully transparent", "button not visible after creation", { '  b:SetSize(40, 40)\n', '  b:SetSize(40, 40)\n  b:SetAlpha(0)\n' } },
  { "rows fade under a transparent parent", "row 1 did not fade in", { 'for i, row in ipairs(rows) do', 'for i, row in ipairs(rows) do row:GetParent():SetAlpha(0)' } },
  { "rows vanish after fading in", "row 1 not fully visible at the end", { 'duration = 0.3, delay = (i - 1) * 0.05 })', 'duration = 0.3, delay = (i - 1) * 0.05, onComplete = function(r) r:SetAlpha(0) end })' } },
  { "hover button starts hidden", "button not visible after creation", { '  b:SetSize(40, 40)\n', '  b:SetSize(40, 40)\n  b:Hide()\n', 'b:SetScript("OnEnter", function(self) Poly(self)', 'b:SetScript("OnEnter", function(self) self:Show(); Poly(self)' } },
  { "hover button vanishes after growing", "button not visible after growing", { 'Poly(self):to({ scale = 1.15 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1.15 }, { spring = "stiff", onComplete = function(f) f:Hide() end })', 'b:SetScript("OnLeave", function(self) Poly(self)', 'b:SetScript("OnLeave", function(self) self:Show(); Poly(self)' } },
  { "hover button vanishes after shrinking", "button not visible after shrinking", { 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1 }, { spring = "stiff", onComplete = function(f) f:Hide() end })' } },
  { "toast leaves 0.5 s late", "did not start leaving by 3.3 s", { 'C_Timer.After(3,', 'C_Timer.After(3.5,' } },
  { "bar jumps on the interrupting event", "jumped", { 'function M.updateBar(bar, fraction) Poly(bar):to({ width = 200 * fraction }) end', 'function M.updateBar(bar, fraction) if fraction == 0.8 then bar:SetWidth(130) end Poly(bar):to({ width = 200 * fraction }) end' } },
  { "toast dims at 3 s, slides at 3.5 s", "did not start leaving by 3.3 s", { 'C_Timer.After(3, function() Poly(toast):hide("above") end)', 'C_Timer.After(3, function() toast:SetAlpha(0.9) end) C_Timer.After(3.5, function() Poly(toast):hide("above", { duration = 0.2 }) end)' } },
  { "toast resizes and jumps in", "did not slide in from above", { 'Poly(toast):show("above", { spring = "stiff" })', 'Poly(toast):show("above", { spring = "stiff" }); Poly(toast):to({ y = 0 }, { duration = 0, delay = 0.1 }); Poly(toast):to({ height = 110 }, { duration = 0.2, onComplete = function() Poly(toast):to({ height = 100 }, { duration = 0.2 }) end })' } },
  { "toast shrinks and jumps out", "did not slide out upward", { 'C_Timer.After(3, function() Poly(toast):hide("above") end)', 'C_Timer.After(3, function() Poly(toast):hide("above"); Poly(toast):to({ y = 16 }, { duration = 0, delay = 0.1 }); Poly(toast):to({ height = 90 }, { duration = 0.2 }) end)' } },
  { "translucent hover button", true, { '  b:SetSize(40, 40)\n', '  b:SetSize(40, 40)\n  b:SetAlpha(0.5)\n' } },
  { "first row starts half visible", "row 1 did not start invisible", { 'Poly(row):set({ alpha = 0 })', 'Poly(row):set({ alpha = i == 1 and 0.5 or 0 })' } },
}

local function plain(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local tmp = os.tmpname()
local wrong = 0
for _, c in ipairs(cases) do
  local name, shouldPass, edits = c[1], c[2], c[3]
  local src = reference
  for i = 1, #edits, 2 do
    local count
    src, count = src:gsub(plain(edits[i]), (edits[i + 1]:gsub("%%", "%%%%")))
    assert(count == 1, name .. ": edit did not apply once")
  end
  local f = assert(io.open(tmp, "w")); f:write(src); f:close()
  local pipe = assert(io.popen(("%s tools/skill_check.lua %s %s 2>&1"):format(lua, lib, tmp)))
  local output = pipe:read("*a")
  pipe:close()
  local passed = output:find("6 of 6 passed", 1, true) ~= nil
  local failures = select(2, output:gsub("\nFAIL ", "")) + (output:sub(1, 5) == "FAIL " and 1 or 0)
  local right
  if shouldPass == true then
    right = passed
  else
    right = failures == 1 and output:find(shouldPass, 1, true) ~= nil
  end
  if not right then wrong = wrong + 1 end
  local said = passed and "passed" or (output:match("FAIL [^\n]*") or "failed")
  print(("%s %-36s %s"):format(right and "ok  " or "WRONG", name, right and "" or ("checker: " .. said:sub(1, 120) .. "; want " .. (shouldPass == true and "pass" or shouldPass))))
end
os.remove(tmp)
print(("%d of %d cases right"):format(#cases - wrong, #cases))
os.exit(wrong == 0 and 0 or 1)
