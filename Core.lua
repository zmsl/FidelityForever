-- Fidelity Forever core: named settings, apply engine, drift, undo/original, screenshot mode.
-- No UI here, so tests/core_test.lua can run it headless with stubbed game APIs.
local _, SG = ...
FidelityForever = SG -- Bindings.xml calls into this

local PREFIX = "|cffe0b25aFidelity Forever:|r "

SG.available = {}   -- [cvar] = true when the client knows it
SG.listeners = {}   -- UI refresh callbacks
SG.stage = nil      -- { name = "...", isPreset = bool, values = {cvar = value}, edited = bool }

function SG.Notify()
  for _, fn in ipairs(SG.listeners) do fn() end
end

function SG.Message(text)
  if SG.db and SG.db.options.messages then
    print(PREFIX .. text)
  end
end

local function same(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return math.abs(na - nb) < 0.001 end
  return tostring(a) == tostring(b)
end
SG.Same = same

function SG.Live(cvar)
  return C_CVar.GetCVar(cvar)
end

-- The player's value: the live one, except where adaptive performance has lowered it for now.
function SG.RealLive(cvar)
  local a = SG.adaptive
  if a and a.active[cvar] ~= nil and a.baseline[cvar] ~= nil then return a.baseline[cvar] end
  return SG.Live(cvar)
end

-- Every whitelisted CVar the client knows, in display order.
function SG.Known()
  local list = {}
  for _, g in ipairs(SG.GROUPS) do
    for _, cvar in ipairs(g.cvars) do
      if SG.available[cvar] then list[#list + 1] = cvar end
    end
  end
  return list
end

function SG.Capture()
  local values = {}
  for _, cvar in ipairs(SG.Known()) do values[cvar] = SG.RealLive(cvar) end
  return values
end

function SG.Preset(name)
  for _, p in ipairs(SG.PRESETS) do
    if p.name == name then return p end
  end
end

-- Values a named set resolves to ("DEF" becomes the client default). Presets first, then own settings.
function SG.Resolve(name)
  local p = SG.Preset(name)
  local src = p and p.values or SG.db.settings[name]
  if not src then return nil end
  local out = {}
  for cvar, v in pairs(src) do
    if SG.available[cvar] then
      if v == "DEF" then
        local d = C_CVar.GetCVarDefault(cvar)
        if d ~= nil then out[cvar] = d end
      else
        out[cvar] = v
      end
    end
  end
  return out, p ~= nil
end

function SG.RiskyIn(values)
  local hits = {}
  for cvar, v in pairs(values) do
    local def = SG.CVARS[cvar]
    local note = def and def.risk and def.risk[tonumber(v)] and not same(SG.Live(cvar), v) and def.risk[tonumber(v)]
    if note then hits[#hits + 1] = SG.CVARS[cvar].label .. " " .. v .. " (" .. note .. ")" end
  end
  table.sort(hits)
  return hits
end

-- Cvars whose live value differs from the given values.
function SG.Diff(values)
  local diff = {}
  for cvar, v in pairs(values or {}) do
    if SG.available[cvar] and not same(SG.RealLive(cvar), v) then diff[cvar] = true end
  end
  return diff
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end
SG.Count = count

-- Drift: live values that differ from the applied set. Empty while nothing has been applied.
function SG.Drift()
  local applied = SG.db.applied and SG.Resolve(SG.db.applied)
  return applied and SG.Diff(applied) or {} -- Diff uses real values, so adaptive reductions are not drift
end

-- Per-setting options: presets carry their own (read-only), own settings keep theirs in db.flags.
function SG.Flags(name)
  local p = name and SG.Preset(name)
  if p then return { adaptive = p.adaptive or false, loginOpt = p.loginOpt or false }, true end
  return (name and SG.db.flags[name]) or {}, false
end

function SG.SetFlag(name, key, value)
  if not SG.db.settings[name] then return false end
  SG.db.flags[name] = SG.db.flags[name] or {}
  SG.db.flags[name][key] = value and true or false
  if name == SG.db.applied and key == "adaptive" then SG.AdaptiveSync() end
  SG.Notify()
  return true
end

-- Own writes are remembered for a few seconds so the CVAR_UPDATE they cause is not taken for an outside change.
local SELF_WRITE_TTL = 3
SG.selfWrites = {} -- [lowercase cvar] = { { value =, expires = }, ... }

function SG.RecordWrite(cvar, value)
  local key = cvar:lower()
  local list = SG.selfWrites[key] or {}
  list[#list + 1] = { value = value, expires = GetTime() + SELF_WRITE_TTL }
  SG.selfWrites[key] = list
end

-- True (and forgets it) when this CVAR_UPDATE matches one of our recent writes.
function SG.ConsumeSelfWrite(cvar, value)
  local list = SG.selfWrites[tostring(cvar):lower()]
  if not list then return false end
  local now = GetTime()
  for i = #list, 1, -1 do
    local w = list[i]
    if w.expires < now then
      table.remove(list, i)
    elseif same(w.value, value) then
      table.remove(list, i)
      return true
    end
  end
  return false
end

-- Low-level write: set every value, read it back. Returns the cvars the client did not accept.
local function write(values)
  local rejected, soundRestart = {}, false
  for cvar, v in pairs(values) do
    if SG.available[cvar] and not same(SG.Live(cvar), v) then
      SG.RecordWrite(cvar, tostring(v))
      C_CVar.SetCVar(cvar, tostring(v))
      if not same(SG.Live(cvar), v) then rejected[#rejected + 1] = cvar end
      soundRestart = soundRestart or (SG.CVARS[cvar] and SG.CVARS[cvar].soundRestart) or false
    end
  end
  -- Sample rate and DSP buffer only take effect when the sound system restarts (a short audio gap; never in combat,
  -- since applies wait for combat to end).
  if soundRestart and Sound_GameSystem_RestartSoundSystem then
    Sound_GameSystem_RestartSoundSystem()
    SG.Message("Restarted the sound system for the new audio settings.")
  end
  table.sort(rejected)
  for _, cvar in ipairs(rejected) do
    SG.Message(("Not accepted: the game kept %s at %s instead of %s."):format(cvar, tostring(SG.Live(cvar)), tostring(values[cvar])))
  end
  return rejected
end

-- Apply a full set now (or after combat). name = the set it came from, nil for restore points.
-- opts.keepUndo: do not overwrite the undo point (used when finishing a reload-deferred apply).
function SG.ApplyNow(values, name, opts)
  opts = opts or {}
  if InCombatLockdown() then
    SG.queued = { values = values, name = name, opts = opts }
    SG.Message("Applies after combat.")
    return "queued"
  end
  -- A real apply starts from the real values: drop the adaptive overlay first (undo must not hold lowered values).
  if not opts.overlay and SG.AdaptiveRelease then SG.AdaptiveRelease() end
  if not opts.keepUndo then SG.db.undo = SG.Capture() end
  local rejected = write(values)
  if name ~= nil or opts.clearName then SG.db.applied = name end
  if #rejected == 0 and not opts.quiet then SG.Message(name and ("Applied " .. name .. ".") or "Applied.") end
  if not opts.overlay then SG.AdaptiveSync(true) end
  SG.Notify()
  return "applied", rejected
end

function SG.OnCombatEnd()
  local q = SG.queued
  if q then
    SG.queued = nil
    SG.ApplyNow(q.values, q.name, q.opts)
  end
end

-- Risky values with the confirm option on: save the undo point and the request to disk (reload), finish after login.
function SG.ApplyChecked(values, name, confirm, proceed)
  proceed = proceed or function() end
  local risky = SG.RiskyIn(values)
  if #risky > 0 and SG.db.options.confirmRisky then
    confirm(risky, function()
      proceed()
      SG.db.undo = SG.Capture()
      SG.db.pendingApply = { values = values, name = name, at = time() }
      ReloadUI()
    end)
    return "confirming"
  end
  proceed()
  return SG.ApplyNow(values, name)
end

local RELOAD_WINDOW = 60 -- seconds; a reload logs back in well within this, a crash and restart does not

function SG.FinishPendingApply()
  local p = SG.db.pendingApply
  if not p then return end
  SG.db.pendingApply = nil
  if not p.at or time() - p.at > RELOAD_WINDOW then
    SG.Message("The last risky apply did not finish (the game may have crashed). Nothing was re-applied; Troubleshooting > Undo last apply restores your previous values.")
    return
  end
  SG.ApplyNow(p.values, p.name, { keepUndo = true })
end

-- Staging -------------------------------------------------------------------

function SG.StageSet(name)
  local values, isPreset = SG.Resolve(name)
  if not values then return end
  SG.stage = { name = name, isPreset = isPreset, values = values, edited = false }
  SG.Notify()
end

function SG.StageEdit(cvar, value)
  if not SG.stage then
    local base = SG.db.applied and SG.Resolve(SG.db.applied)
    local isPreset = SG.db.applied and SG.Preset(SG.db.applied) ~= nil
    SG.stage = { name = base and SG.db.applied or nil, isPreset = isPreset, values = base or SG.Capture(), edited = false }
  end
  SG.stage.values[cvar] = value
  SG.stage.edited = true
  SG.Notify()
end

-- Copy another set's values into the stage, keeping the stage's name.
function SG.StageCopy(fromName)
  local values = SG.Resolve(fromName)
  if not values then return end
  local name = SG.stage and SG.stage.name or SG.db.applied
  SG.stage = { name = name, isPreset = name and SG.Preset(name) ~= nil, values = values, edited = true }
  SG.Notify()
end

function SG.StagedValue(cvar)
  if SG.stage and SG.stage.values[cvar] ~= nil then return SG.stage.values[cvar] end
  return SG.RealLive(cvar)
end

function SG.PendingCount()
  return SG.stage and count(SG.Diff(SG.stage.values)) or 0
end

function SG.Cancel()
  SG.stage = nil
  SG.Notify()
end

-- Commit the stage. askName(callback) is called when edits on a preset need a new name.
function SG.CommitStage(askName, confirm)
  local st = SG.stage
  if not st then return end
  local function go(name)
    return SG.ApplyChecked(st.values, name, confirm, function()
      if not st.isPreset or st.edited then SG.db.settings[name] = CopyTable(st.values) end
      SG.stage = nil
    end)
  end
  if st.name == nil or (st.isPreset and st.edited) then
    askName(function(newName) return go(newName) end)
    return "naming"
  end
  return go(st.name)
end

-- Named settings ------------------------------------------------------------

function SG.ValidName(name)
  return type(name) == "string" and name:match("%S") ~= nil and not SG.Preset(name) and SG.db.settings[name] == nil
end

function SG.NewSetting(name)
  if not SG.ValidName(name) then return false end
  SG.db.settings[name] = SG.Capture()
  SG.StageSet(name)
  return true
end

function SG.RenameSetting(old, new)
  if not SG.db.settings[old] or not SG.ValidName(new) then return false end
  SG.db.settings[new], SG.db.settings[old] = SG.db.settings[old], nil
  SG.db.flags[new], SG.db.flags[old] = SG.db.flags[old], nil
  if SG.db.applied == old then SG.db.applied = new end
  if SG.chardb.use == old then SG.chardb.use = new end
  if SG.stage and SG.stage.name == old then SG.stage.name = new end
  SG.Notify()
  return true
end

function SG.DeleteSetting(name)
  if not SG.db.settings[name] then return false end
  SG.db.settings[name] = nil
  SG.db.flags[name] = nil
  if SG.db.applied == name then SG.db.applied = nil; SG.AdaptiveSync() end
  if SG.chardb.use == name then SG.chardb.use = nil end
  if SG.stage and SG.stage.name == name then SG.stage = nil end
  SG.Notify()
  return true
end

function SG.OwnNames()
  local names = {}
  for name in pairs(SG.db.settings) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Immediate actions ---------------------------------------------------------

function SG.ReapplyOne(cvar)
  local applied = SG.db.applied and SG.Resolve(SG.db.applied)
  if not applied or applied[cvar] == nil then return end
  if InCombatLockdown() then SG.Message("Applies after combat.") end
  return SG.ApplyNow({ [cvar] = applied[cvar] }, SG.db.applied, { keepUndo = true })
end

function SG.ScreenshotToggle()
  if SG.db.shot then return SG.ScreenshotBack() end
  local values = SG.Resolve("Screenshot")
  SG.db.shot = { returnTo = SG.db.applied, values = SG.Capture() }
  SG.ApplyNow(values, "Screenshot", { keepUndo = true })
  SG.Message("Screenshot mode on. Press it again to go back.")
end

function SG.ScreenshotBack()
  local shot = SG.db.shot
  if not shot then
    local name = SG.chardb.use or SG.db.applied
    local values = name and SG.Resolve(name)
    if values then SG.ApplyNow(values, name) end
    return
  end
  SG.db.shot = nil
  SG.ApplyNow(shot.values, shot.returnTo, { keepUndo = true, clearName = true })
end

function SG.SafeMode()
  return SG.ApplyNow(SG.Resolve("Performance"), "Performance")
end

function SG.UndoLast()
  if not SG.db.undo then SG.Message("Nothing to undo.") return end
  local values = SG.db.undo
  return SG.ApplyNow(values, nil, { clearName = true })
end

function SG.RestoreOriginal()
  return SG.ApplyNow(SG.db.original, nil, { clearName = true })
end

-- Startup -------------------------------------------------------------------

local DEFAULTS = { confirmRisky = true, messages = true, autoApply = false, targetFPS = 60 }

function SG.Init()
  FidelityForeverDB = FidelityForeverDB or {}
  FidelityForeverCharDB = FidelityForeverCharDB or {}
  local db = FidelityForeverDB
  db.settings = db.settings or {}
  db.flags = db.flags or {}
  db.options = db.options or {}
  for k, v in pairs(DEFAULTS) do
    if db.options[k] == nil then db.options[k] = v end
  end
  SG.db, SG.chardb = db, FidelityForeverCharDB

  for cvar in pairs(SG.CVARS) do
    local ok, value = pcall(C_CVar.GetCVarInfo, cvar)
    SG.available[cvar] = ok and value ~= nil
  end
  -- First run: capture before anything is written. Never overwritten afterwards.
  if not db.original then db.original = SG.Capture() end
end

function SG.Login()
  SG.FinishLoginOpt() -- first: put back what logout shortened, so a deferred apply lands on real values
  SG.FinishPendingApply()
  local use = SG.chardb.use
  if use and SG.db.options.autoApply and SG.Resolve(use) then
    SG.ApplyNow(SG.Resolve(use), use)
  end
  SG.AdaptiveSync(true) -- the applied setting may have adaptive performance on
end

function SG.Probe()
  local out = { build = { GetBuildInfo() }, cvars = {} }
  for cvar in pairs(SG.CVARS) do
    local value, default, account, character, locked, secure, readOnly = C_CVar.GetCVarInfo(cvar)
    out.cvars[cvar] = value and { value = value, default = default, account = account, character = character,
      locked = locked, secure = secure, readOnly = readOnly } or false
  end
  SG.db.probe = out
  print(PREFIX .. "probe saved to FidelityForeverDB.probe (written at logout or /reload).")
end
