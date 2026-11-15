-- Fidelity Forever boot: events, slash command, key binding labels.
local ADDON, SG = ...

BINDING_HEADER_FIDELITYFOREVER = "Fidelity Forever"
BINDING_NAME_FIDELITYFOREVER_SCREENSHOT = "Screenshot mode on/off"
BINDING_NAME_FIDELITYFOREVER_BACK = "Back to my setting"

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CVAR_UPDATE")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    SG.Init()
    SG.BuildUI()
  elseif event == "PLAYER_LOGIN" then
    SG.Login()
  elseif event == "PLAYER_REGEN_ENABLED" then
    SG.OnCombatEnd()
  elseif event == "CVAR_UPDATE" then
    if SG.db and not SG.ConsumeSelfWrite(arg1, arg2) then
      SG.Notify() -- something outside the addon changed a CVar: redraw drift on the open page
    end
  elseif event == "PLAYER_LOGOUT" then
    SG.Logout()
  elseif event == "PLAYER_ENTERING_WORLD" then
    SG.adaptive.settle = 10 -- loading screens and zoning dip the frame rate
  end
end)

C_Timer.NewTicker(1, function()
  if SG.adaptive.on then SG.AdaptiveTick(GetFramerate(), InCombatLockdown()) end
end)

SLASH_FIDELITYFOREVER1 = "/ff"
SLASH_FIDELITYFOREVER2 = "/fidelity"
SlashCmdList.FIDELITYFOREVER = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "probe" then SG.Probe()
  elseif msg == "safe" then SG.SafeMode()
  elseif msg == "undo" then SG.UndoLast()
  else SG.Open() end
end
