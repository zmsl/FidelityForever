-- Adaptive performance (an FPS-driven overlay on the applied setting) and login optimization.
-- No UI here; tests/core_test.lua drives both headless.
local _, SG = ...

-- Five levels. Per CVar, the value at each level: "scale" = multiply the setting's own value (never below min),
-- "set"/"cap" = this value (cap only lowers). nil = that level leaves the CVar alone.
local STEPS = {
  { cvar = "particleMTDensity",     mode = "scale", levels = { 0.85, 0.70, 0.55, 0.40, 0.25 }, min = 10 },
  { cvar = "groundEffectDensity",   mode = "scale", levels = { 0.85, 0.70, 0.55, 0.40, 0.25 }, min = 16 },
  { cvar = "horizonStart",          mode = "scale", levels = { 0.85, 0.70, 0.55, 0.40, 0.25 }, min = 400 },
  { cvar = "vrsParticles",          mode = "set",   levels = { "2x2", "2x2", "2x2", "2x2", "2x2" } },
  { cvar = "animFrameSkipLOD",      mode = "set",   levels = { 1, 1, 1, 1, 1 } },
  { cvar = "shadowBlendCascades",   mode = "cap",   levels = { 0, 0, 0, 0, 0 } },
  { cvar = "entityShadowFadeScale", mode = "scale", levels = { nil, 0.85, 0.70, 0.55, 0.40 }, min = 1 },
  { cvar = "maxLightDist",          mode = "scale", levels = { nil, 0.85, 0.70, 0.55, 0.40 }, min = 8 },
  { cvar = "terrainLodDist",        mode = "scale", levels = { nil, 0.85, 0.70, 0.55, 0.40 }, min = 128 },
  { cvar = "shadowSoft",            mode = "cap",   levels = { nil, 0, 0, 0, 0 } },
  { cvar = "shadowTextureSize",     mode = "cap",   levels = { nil, 1024, 1024, 512, 512 } },
  { cvar = "groundEffectDist",      mode = "scale", levels = { nil, nil, 0.85, 0.70, 0.55 }, min = 40 },
  { cvar = "groundEffectFade",      mode = "scale", levels = { nil, nil, 0.85, 0.70, 0.55 }, min = 40 },
  { cvar = "WeatherDensity",        mode = "cap",   levels = { 2, 2, 1, 1, 0 } },
  { cvar = "specular",              mode = "cap",   levels = { nil, nil, 0, 0, 0 } },
  { cvar = "ssaoMagicNormals",      mode = "cap",   levels = { nil, nil, nil, 0, 0 } },
  { cvar = "clusteredShading",      mode = "cap",   levels = { nil, nil, nil, 0, 0 } },
}
SG.ADAPTIVE_STEPS = STEPS

local MAX_LEVEL = 5
local LOW_SAMPLES = 5    -- seconds under target before stepping down
local HIGH_SAMPLES = 60  -- seconds comfortably over target before stepping back up
local SETTLE = 5         -- seconds ignored after a change

SG.adaptive = { level = 0, active = {}, baseline = {}, low = 0, high = 0, settle = 0, on = false }

local function stepValue(def, level, base)
  local v = def.levels[level]
  if v == nil or base == nil then return nil end
  if def.mode == "scale" then
    local n = tonumber(base)
    if not n then return nil end
    return math.max(def.min or 0, math.floor(n * v + 0.5))
  elseif def.mode == "cap" then
    local n = tonumber(base)
    if n and n <= v then return nil end
  end
  return v
end

-- Writes the overlay for a level on top of the baseline; level 0 puts the baseline back.
local function setLevel(level)
  local a = SG.adaptive
  local values = {}
  for _, def in ipairs(STEPS) do
    if SG.available[def.cvar] then
      local base = a.baseline[def.cvar]
      local v = level > 0 and stepValue(def, level, base) or nil
      if v ~= nil then
        values[def.cvar] = v
        a.active[def.cvar] = v
      elseif a.active[def.cvar] ~= nil then
        values[def.cvar] = base
        a.active[def.cvar] = nil
      end
    end
  end
  a.level, a.low, a.high, a.settle = level, 0, 0, SETTLE
  SG.ApplyNow(values, nil, { keepUndo = true, overlay = true, quiet = true })
end

-- Called after every real apply (reset = true) and when the option changes: follows the applied setting's flag.
function SG.AdaptiveSync(reset)
  local a = SG.adaptive
  local want = SG.db and SG.db.applied and SG.Flags(SG.db.applied).adaptive or false
  if a.on and (reset or not want) then
    if not reset and next(a.active) then setLevel(0) end -- turned off: put the real values back
    a.active, a.level = {}, 0
  end
  a.on = want and true or false
  if a.on then
    a.baseline = {}
    for _, def in ipairs(STEPS) do
      if SG.available[def.cvar] then a.baseline[def.cvar] = SG.Live(def.cvar) end
    end
    a.low, a.high, a.settle = 0, 0, SETTLE
  end
  if SG.OnAdaptiveChanged then SG.OnAdaptiveChanged(a.on) end
end

-- One sample per second. In combat nothing changes (writes there are unverified on Forever).
function SG.AdaptiveTick(fps, inCombat)
  local a = SG.adaptive
  if not a.on or inCombat then return end
  if a.settle > 0 then a.settle = a.settle - 1 return end
  local target = SG.db.options.targetFPS or 60
  local bk = tonumber(C_CVar.GetCVar("maxFPSBk"))
  if bk and bk > 0 and fps <= bk + 1 and fps < target then return end -- game in the background, capped
  if fps < target * 0.95 then
    a.low, a.high = a.low + 1, 0
  elseif fps >= target * 1.1 then
    a.high, a.low = a.high + 1, 0
  else
    a.low, a.high = 0, 0
  end
  if a.low >= LOW_SAMPLES and a.level < MAX_LEVEL then
    setLevel(a.level + 1)
  elseif a.high >= HIGH_SAMPLES and a.level > 0 then
    setLevel(a.level - 1)
  end
end

function SG.AdaptiveRelease()
  if next(SG.adaptive.active) then setLevel(0) end
end

-- Login optimization: very short distances while logged out make the next loading screen faster;
-- the real values come back right after login.
local LOGIN_OPT = {
  farclip = 1000, horizonStart = 400, horizonClip = 750, groundEffectDensity = 16, groundEffectDist = 40,
  groundEffectFade = 40, terrainLodDist = 128, TerrainLodDiv = 128, wmoLodDist = 1, entityLodDist = 1,
  doodadLodScale = 1, lodObjectCullSize = 100, lodObjectCullDist = 1, lodObjectMinSize = 1, lodObjectFadeScale = 50,
  entityShadowFadeScale = 1, maxLightDist = 8,
}
SG.LOGIN_OPT = LOGIN_OPT

function SG.Logout()
  SG.AdaptiveRelease()
  if not (SG.db.applied and SG.Flags(SG.db.applied).loginOpt) then return end
  local restore, values = {}, {}
  for cvar, v in pairs(LOGIN_OPT) do
    if SG.available[cvar] then restore[cvar], values[cvar] = SG.Live(cvar), v end
  end
  SG.db.loginOpt = restore
  SG.ApplyNow(values, nil, { keepUndo = true, overlay = true, quiet = true })
end

function SG.FinishLoginOpt()
  local restore = SG.db.loginOpt
  if not restore then return end
  SG.db.loginOpt = nil
  SG.ApplyNow(restore, nil, { keepUndo = true, quiet = true })
end
