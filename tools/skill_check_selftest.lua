-- Proves tools/skill_check.lua tells good answers from bad ones.
-- Usage: lua tools/skill_check_selftest.lua Polymorph.lua
-- Each case edits the reference answer and states whether the checker should pass it.
local lib = assert(arg[1], "Polymorph.lua")
local lua = arg[-1] or "lua"
local reference = assert(io.open("tools/skill_check_reference.lua")):read("*a")

local cases = {
  { "reference", true, {} },
  { "toggle without animation", false, { 'if open then Poly(panel):show("pop") else Poly(panel):hide("pop", { duration = 0.15, ease = "inQuad" }) end', 'if open then panel:Show() else panel:Hide() end' } },
  { "toggle that slides", true, { 'if open then Poly(panel):show("pop") else Poly(panel):hide("pop", { duration = 0.15, ease = "inQuad" }) end', 'if open then Poly(panel):show({ y = 16 }) else Poly(panel):hide({ y = 16 }, { duration = 0.15, ease = "inQuad" }) end' } },
  { "toast never hidden first", false, { 'if not Poly(toast):isMoving() and toast:IsShown() then toast:Hide() end', '' } },
  { "toast in from below", false, { 'Poly(toast):show("above", { spring = "stiff" })', 'Poly(toast):show("below", { spring = "stiff" })' } },
  { "toast out downward", false, { 'Poly(toast):hide("above")', 'Poly(toast):hide("below")' } },
  { "toast that slides without fading", true, { 'Poly(toast):show("above", { spring = "stiff" })', 'Poly(toast):show({ y = 16 }, { spring = "stiff" })', 'Poly(toast):hide("above")', 'Poly(toast):hide({ y = 16 })' } },
  { "bar without animation", false, { 'Poly(bar):to({ width = 200 * fraction })', 'Poly(bar):to({ width = 200 * fraction }, { duration = 0 })' } },
  { "button without a size", false, { '  b:SetSize(40, 40)\n', '' } },
  { "hover grows at once", false, { 'Poly(self):to({ scale = 1.15 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1.15 }, { duration = 0 })' } },
  { "hover shrinks at once", false, { 'Poly(self):to({ scale = 1 }, { spring = "stiff" })', 'Poly(self):to({ scale = 1 }, { duration = 0 })' } },
  { "hover leave collapses the button", false, { 'b:SetScript("OnLeave", function(self) Poly(self)', 'b:SetScript("OnLeave", function(self) self:SetHeight(0); Poly(self)' } },
  { "secure panel vanishes in combat", false, { 'Poly(panel):hide("fade", { duration = 0.2 })', 'Poly(panel):hide("fade", InCombatLockdown() and { duration = 0 } or nil)' } },
  { "secure panel vanishes always", false, { 'Poly(panel):hide("fade", { duration = 0.2 })', 'Poly(panel):hide("fade", { duration = 0 })' } },
  { "secure panel slides out of combat", true, { 'Poly(panel):hide("fade", { duration = 0.2 })', 'Poly(panel):hide(InCombatLockdown() and "fade" or { y = 16 })' } },
  { "rows 1 to 4 together", false, { 'delay = (i - 1) * 0.05', 'delay = i == 5 and 0.12 or 0' } },
  { "rows appear at once", false, { 'duration = 0.3, delay', 'duration = 0, delay' } },
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
  local ok = os.execute(("%s tools/skill_check.lua %s %s > /dev/null 2>&1"):format(lua, lib, tmp))
  local passed = ok == 0 or ok == true
  local right = passed == shouldPass
  if not right then wrong = wrong + 1 end
  print(("%s %-36s checker %s, want %s"):format(right and "ok  " or "WRONG", name, passed and "passed" or "failed", shouldPass and "pass" or "fail"))
end
os.remove(tmp)
print(("%d of %d cases right"):format(#cases - wrong, #cases))
os.exit(wrong == 0 and 0 or 1)
