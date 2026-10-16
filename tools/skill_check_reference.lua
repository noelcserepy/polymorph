-- A correct answer to the brief in tools/skill_check.lua. skill_check_selftest.lua
-- mutates it to prove the checker rejects answers that break the brief.
local Poly = LibStub("Polymorph-1.0")
local M = {}
function M.setupToggle(panel, button)
  local open = false
  button:SetScript("OnClick", function()
    open = not open
    if open then Poly(panel):show("pop") else Poly(panel):hide("pop", { duration = 0.15, ease = "inQuad" }) end
  end)
end
function M.notify(toast)
  if not Poly(toast):isMoving() and toast:IsShown() then toast:Hide() end
  Poly(toast):show("above", { spring = "stiff" })
  C_Timer.After(3, function() Poly(toast):hide("above") end)
end
function M.updateBar(bar, fraction) Poly(bar):to({ width = 200 * fraction }) end
function M.makeHoverButton(parent)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(40, 40)
  holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
  local b = CreateFrame("Button", nil, holder)
  b:SetSize(40, 40)
  b:SetPoint("CENTER", holder, "CENTER", 0, 0)
  b:SetScript("OnEnter", function(self) Poly(self):to({ scale = 1.15 }, { spring = "stiff" }) end)
  b:SetScript("OnLeave", function(self) Poly(self):to({ scale = 1 }, { spring = "stiff" }) end)
  return b
end
function M.closeSecurePanel(panel) Poly(panel):hide("fade", { duration = 0.2 }) end
function M.fadeListIn(rows)
  for i, row in ipairs(rows) do
    Poly(row):set({ alpha = 0 }):to({ alpha = 1 }, { duration = 0.3, delay = (i - 1) * 0.05 })
  end
end
function M.makeCounter(fs)
  local m = Poly(fs):define({ total = 0 }, function(text, v) text:SetText(("%.0f"):format(v.total)) end)
  m:set({ total = 0 })
  local total = 0
  return function(amount)
    total = total + amount
    m:to({ total = total })
  end
end
return M
