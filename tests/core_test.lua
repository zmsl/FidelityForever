-- Headless test for Core.lua: luajit tests/core_test.lua (from the addon folder)
local cvars, defaults, combat, reloads, printed = {}, {}, false, 0, {}
local rejectOnce = {}   -- cvar -> value the "client" refuses (keeps old value)

C_CVar = {
  GetCVar = function(n) return cvars[n] end,
  GetCVarDefault = function(n) return defaults[n] end,
  GetCVarInfo = function(n) if cvars[n] ~= nil then return cvars[n], defaults[n], false, false, false, false, false end end,
  SetCVar = function(n, v)
    if rejectOnce[n] == v then return false end
    cvars[n] = v
    return true
  end,
}
InCombatLockdown = function() return combat end
ReloadUI = function() reloads = reloads + 1 end
GetBuildInfo = function() return "1.60.1", "70532", "", 16001 end
local now = 1000
time = function() return now end
local clock = 0
GetTime = function() return clock end
CopyTable = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
print = function(s) printed[#printed + 1] = s end

local SG = {}
assert(loadfile("Data.lua"))("FidelityForever", SG)
assert(loadfile("Core.lua"))("FidelityForever", SG)
assert(loadfile("Adaptive.lua"))("FidelityForever", SG)

-- A client that knows every CVar except two (as Forever may), with plain starting values.
for name in pairs(SG.CVARS) do cvars[name] = "1"; defaults[name] = "1" end
cvars.HDRPeakBrightness, cvars.M2UseThreads = nil, nil

local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end end

-- 1. First run captures the original values before anything is written, and never again.
SG.Init()
check(SG.db.original.farclip == "1", "original captured")
check(SG.db.original.M2UseThreads == nil and not SG.available.M2UseThreads, "unknown CVar skipped")
SG.ApplyNow(SG.Resolve("Balanced"), "Balanced")
check(cvars.farclip == "24000", "Balanced applied farclip")
check(cvars.M2UseThreads == nil, "unknown CVar never written")
SG.Init() -- second load (e.g. /reload) must not overwrite the original
check(SG.db.original.farclip == "1", "original not overwritten on re-init")

-- 2. Undo returns to the values before the last apply; Restore returns to first run.
SG.ApplyNow(SG.Resolve("Performance"), "Performance")
check(cvars.farclip == "2112", "Performance farclip")
SG.UndoLast()
check(cvars.farclip == "24000", "undo back to Balanced")
SG.RestoreOriginal()
check(cvars.farclip == "1" and SG.db.applied == nil, "restore original")

-- 3. Read-back: a value the client keeps is reported, not silently assumed.
rejectOnce.giQuality = "4"
local _, rejected = SG.ApplyNow(SG.Resolve("Balanced"), "Balanced")
check(#rejected == 1 and rejected[1] == "giQuality", "rejected value reported")
rejectOnce.giQuality = nil

-- 4. Drift: a value changed outside the addon shows up, and Re-apply fixes only that row.
SG.ApplyNow(SG.Resolve("Balanced"), "Balanced")
cvars.waterDetail = "0"
check(SG.Drift().waterDetail and SG.Count(SG.Drift()) == 1, "drift detected")
SG.ReapplyOne("waterDetail")
check(cvars.waterDetail == "2" and SG.Count(SG.Drift()) == 0, "re-apply one row")

-- 5. Combat: apply waits for combat end.
combat = true
check(SG.ApplyNow(SG.Resolve("Performance"), "Performance") == "queued", "queued in combat")
check(cvars.farclip == "24000", "nothing written in combat")
combat = false
SG.OnCombatEnd()
check(cvars.farclip == "2112" and SG.db.applied == "Performance", "applied after combat")

-- 6. Staging: picking a preset only stages; edits on a preset ask for a name and save a new setting.
SG.StageSet("High")
check(cvars.horizonStart ~= "6000" and SG.PendingCount() > 0, "stage writes nothing")
SG.StageEdit("farclip", 30000)
local asked
SG.CommitStage(function(cb) asked = true; cb("Mine") end, function() error("no risky values here") end)
check(asked and SG.db.settings.Mine and SG.db.applied == "Mine", "edited preset saved as own setting")
check(cvars.farclip == "30000" and cvars.horizonStart == "6000", "stage applied")
check(SG.stage == nil and SG.PendingCount() == 0, "stage cleared")

-- 7. Risky values with confirm on: undo + pending request saved, reload, finish after login.
SG.StageEdit("waterDetail", 3)
local confirmed
SG.CommitStage(function(cb) cb("x") end, function(list, ok) confirmed = list; ok() end)
check(confirmed and #confirmed == 1 and reloads == 1, "risky confirm then reload")
check(cvars.waterDetail == "2" and SG.db.pendingApply, "nothing written before reload")
local undoFarclip = SG.db.undo.farclip
SG.Init(); SG.Login()
check(cvars.waterDetail == "3" and SG.db.pendingApply == nil, "pending apply finished after login")
check(SG.db.undo.farclip == undoFarclip, "undo point from before the reload kept")

-- 7b. Crash during the deferred apply: the request on disk is older than the reload window and is not replayed.
SG.StageEdit("waterDetail", 0) -- back to a safe value first
SG.CommitStage(function(cb) cb("y") end, function() error("0 is not risky") end)
SG.StageEdit("reflectionMode", 4)
SG.CommitStage(function(cb) cb("z") end, function(_, ok) ok() end)
check(SG.db.pendingApply and reloads == 2, "second risky apply deferred")
now = now + 600 -- crash, restart minutes later
SG.Init(); SG.Login()
check(cvars.reflectionMode ~= "4" and SG.db.pendingApply == nil, "crashed risky apply not replayed")

-- 7c. Cancel on the risky confirm keeps the stage and saves nothing.
SG.StageSet("Balanced")
SG.StageEdit("giQuality", 5)
SG.CommitStage(function(cb) cb("Risky") end, function() end) -- confirm shown, never accepted
check(SG.db.settings.Risky == nil and SG.stage and SG.stage.values.giQuality == 5, "cancelled confirm saves nothing")
SG.Cancel()

-- 7d. A risky value already live does not ask again.
cvars.waterDetail = "3"
check(#SG.RiskyIn({ waterDetail = 3 }) == 0 and #SG.RiskyIn({ reflectionMode = 4 }) == 1, "only changing values are risky")
cvars.waterDetail = "2"

-- 7e. A "DEF" value with no client default is skipped, never written literally.
defaults.farclip = nil
check(SG.Resolve("Default").farclip == nil, "missing default skipped")
defaults.farclip = "1"

-- 8. Screenshot mode and back.
SG.ApplyNow(SG.Resolve("Balanced"), "Balanced")
SG.ScreenshotToggle()
check(cvars.horizonStart == "24000" and SG.db.shot, "screenshot on")
SG.ScreenshotToggle()
check(cvars.horizonStart == "1900" and SG.db.applied == "Balanced" and not SG.db.shot, "screenshot back")

-- 9. Names: presets and duplicates are refused; rename and delete follow pointers.
check(not SG.NewSetting("Balanced") and not SG.NewSetting("Mine") and not SG.NewSetting("  "), "bad names refused")
SG.chardb.use = "Mine"
check(SG.RenameSetting("Mine", "Main") and SG.chardb.use == "Main", "rename follows login pointer")
check(SG.DeleteSetting("Main") and SG.chardb.use == nil, "delete clears pointer")

-- 10. Own writes are recognised in CVAR_UPDATE; outside changes and stale records are not.
SG.ApplyNow({ farclip = 5000 }, nil)
check(SG.ConsumeSelfWrite("FARCLIP", "5000"), "own write recognised (case-insensitive)")
check(not SG.ConsumeSelfWrite("farclip", "5000"), "each record used once")
SG.ApplyNow({ farclip = 6000 }, nil)
clock = clock + 10
check(not SG.ConsumeSelfWrite("farclip", "6000"), "stale record ignored")

-- 11. Adaptive: the Adaptive preset lowers detail while fps is under target, never saved, invisible to drift.
SG.ApplyNow(SG.Resolve("Adaptive"), "Adaptive")
check(SG.adaptive.on, "adaptive on with the Adaptive preset")
local horizon = tonumber(cvars.horizonStart)
for _ = 1, 12 do SG.AdaptiveTick(30, false) end
check(SG.adaptive.level == 1 and tonumber(cvars.horizonStart) < horizon, "stepped down at low fps")
check(SG.Count(SG.Drift()) == 0, "overlay is not drift")
for _ = 1, 30 do SG.AdaptiveTick(30, true) end
check(SG.adaptive.level == 1, "no change in combat")
for _ = 1, 70 do SG.AdaptiveTick(120, false) end
check(SG.adaptive.level == 0 and tonumber(cvars.horizonStart) == horizon, "stepped back up when fps recovered")
for _ = 1, 12 do SG.AdaptiveTick(30, false) end
local lowered = cvars.vrsParticles
SG.ApplyNow(SG.Resolve("Balanced"), "Balanced") -- Balanced leaves vrsParticles alone
check(not SG.adaptive.on and cvars.vrsParticles ~= "2x2" and lowered == "2x2", "real apply removes the overlay first")
check(SG.db.undo.vrsParticles ~= "2x2", "undo point holds real values")

-- 12. Options on own settings: adaptive and login optimization; presets are read-only.
check(not SG.SetFlag("Balanced", "adaptive", true), "preset flags read-only")
SG.NewSetting("Mine2"); SG.CommitStage(function() end, function() end)
check(SG.db.applied == "Mine2", "own setting applied")
SG.SetFlag("Mine2", "loginOpt", true)
local far = cvars.farclip
SG.Logout()
check(cvars.farclip == "1000" and SG.db.loginOpt, "logout shortens distances")
SG.Init(); SG.Login()
check(cvars.farclip == far and SG.db.loginOpt == nil, "login restores them")
check(SG.Count(SG.Drift()) == 0, "no drift after login restore")

-- 12b. While adaptive has lowered values: no drift, and an edit elsewhere counts as one pending change.
SG.ApplyNow(SG.Resolve("Adaptive"), "Adaptive")
for _ = 1, 12 do SG.AdaptiveTick(30, false) end
check(SG.adaptive.level >= 1 and SG.Count(SG.Drift()) == 0, "lowered values are not drift")
check(SG.RealLive("groundEffectDensity") == "256" and cvars.groundEffectDensity ~= "256", "real value kept apart from the lowered one")
SG.StageEdit("HDROutput", 0) -- stub starts every CVar at "1"
check(SG.PendingCount() == 1, "only the hand edit is pending")
SG.Cancel()
SG.ApplyNow(SG.Resolve("Balanced"), "Balanced")

-- 13. Sample rate changes restart the sound system once; channel changes do not.
local restarts = 0
Sound_GameSystem_RestartSoundSystem = function() restarts = restarts + 1 end
SG.ApplyNow({ Sound_NumChannels = 40 }, nil)
check(restarts == 0, "channels need no sound restart")
SG.ApplyNow({ Sound_OutputSampleRate = 48000, Sound_DSPBufferSize = 67108864 }, nil)
check(restarts == 1, "one sound restart for sample rate + buffer")
SG.ApplyNow({ Sound_OutputSampleRate = 48000 }, nil)
check(restarts == 1, "no restart when nothing changed")

io.stdout:write("core_test: all checks passed\n")
