-- Checks Data.lua (hand-edited) and the CVar tables in Adaptive.lua: run from the addon folder (make test).
local SG = {}
assert(loadfile("Data.lua"))("FidelityForever", SG)
assert(loadfile("Adaptive.lua"))("FidelityForever", SG)

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

-- Every setting: a label and a tooltip; a range or an option list with a label per option.
for cvar, def in pairs(SG.CVARS) do
  check(type(def.label) == "string" and def.label ~= "", cvar .. ": label")
  check(type(def.desc) == "string" and def.desc ~= "", cvar .. ": tooltip (desc)")
  if def.values then
    check(type(def.labels) == "table" and #def.labels == #def.values, cvar .. ": one label per option")
  else
    check(type(def.min) == "number" and type(def.max) == "number" and def.min < def.max, cvar .. ": min < max")
  end
end

-- Every CVar is on exactly one page, every page entry is a known CVar (names are case-insensitive in the client).
local seen = {}
for _, g in ipairs(SG.GROUPS) do
  check(g.section == "Graphics" or g.section == "Audio", g.key .. ": section")
  for _, cvar in ipairs(g.cvars) do
    check(SG.CVARS[cvar] ~= nil, g.key .. ": unknown CVar " .. cvar)
    check(not seen[cvar:lower()], "listed twice: " .. cvar)
    seen[cvar:lower()] = true
  end
end
for cvar in pairs(SG.CVARS) do check(seen[cvar:lower()], "not on any page: " .. cvar) end

-- Presets: known CVars, values in range, never a crash value.
local function inRange(def, v)
  if v == "DEF" then return true end
  if def.values then
    for _, ok in ipairs(def.values) do if ok == v then return true end end
    return false
  end
  return type(v) == "number" and v >= def.min and v <= def.max
end
local names = {}
for _, p in ipairs(SG.PRESETS) do
  names[p.name] = p
  check(not p.loginOpt, p.name .. ": no prebuilt preset uses login optimization")
  for cvar, v in pairs(p.values) do
    local def = SG.CVARS[cvar]
    check(def ~= nil, p.name .. ": unknown CVar " .. cvar)
    if def then
      check(inRange(def, v), ("%s: %s = %s is out of range"):format(p.name, cvar, tostring(v)))
      check(not (def.risk and def.risk[v]), ("%s: %s = %s is a crash value"):format(p.name, cvar, tostring(v)))
    end
  end
end
for _, n in ipairs({ "Default", "Performance", "Balanced", "Adaptive", "High", "Beyond Ultra", "Screenshot" }) do
  check(names[n] ~= nil, "preset missing: " .. n)
end
check(names.Adaptive and names.Adaptive.adaptive == true, "Adaptive preset has adaptive performance on")
for _, p in ipairs(SG.PRESETS) do
  if p.name ~= "Adaptive" then check(not p.adaptive, p.name .. ": adaptive only in the Adaptive preset") end
end
for cvar, v in pairs(names.Balanced and names.Balanced.values or {}) do
  check(names.Adaptive.values[cvar] == v, "Adaptive = Balanced values: " .. cvar)
end

-- Adaptive steps and login optimization only touch known CVars, with in-range values.
for _, step in ipairs(SG.ADAPTIVE_STEPS) do
  local def = SG.CVARS[step.cvar]
  check(def ~= nil, "adaptive step: unknown CVar " .. step.cvar)
  if def and step.mode ~= "scale" then
    for _, v in pairs(step.levels) do check(inRange(def, v), "adaptive step out of range: " .. step.cvar) end
  end
end
for cvar, v in pairs(SG.LOGIN_OPT) do
  check(SG.CVARS[cvar] ~= nil and inRange(SG.CVARS[cvar], v), "login optimization: " .. cvar)
end

if failures > 0 then
  io.stderr:write(("data_test: %d failure(s)\n"):format(failures))
  os.exit(1)
end
io.stdout:write("data_test: all checks passed\n")
