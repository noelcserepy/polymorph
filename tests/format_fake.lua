-- WoW's string.format stores %d and %i in a 32-bit int and errors outside that
-- range (unmeasured in-game). Reference Lua uses 64 bits, so fake the game's limit.
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
return realFormat
