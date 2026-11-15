-- Lint for Fidelity Forever (WoW Forever, Lua 5.1).
std = "lua51"
max_line_length = false
codes = true

exclude_files = { ".lua/", ".release/", ".luacheckrc" }

ignore = {
    "11./SLASH_.*",   -- slash command globals
    "11./BINDING_.*", -- key binding header/name globals
    "212",            -- unused arguments (event and script handler signatures)
}

-- The addon's own globals (written and read).
globals = {
    "FidelityForever", "FidelityForeverDB", "FidelityForeverCharDB",
    "StaticPopupDialogs", "SlashCmdList",
}

-- Game API, FrameXML and client Lua extensions the addon reads.
read_globals = {
    "C_CVar", "C_Timer", "CreateFrame", "InCombatLockdown", "ReloadUI", "GetTime", "GetFramerate", "GetBuildInfo",
    "GetBindingKey", "Sound_GameSystem_RestartSoundSystem", "time", "strtrim", "CopyTable",
    "UIParent", "GameTooltip", "GameTooltip_Hide", "GameTooltip_SetTitle", "StaticPopup_Show", "MenuUtil",
    "Settings", "SettingsPanel", "MinimalSliderWithSteppersMixin", "ACCEPT", "CANCEL", "APPLY",
}

-- The headless test stubs the game API it needs.
files["tests/"] = { globals = {
    "C_CVar", "InCombatLockdown", "ReloadUI", "GetBuildInfo", "CopyTable", "print", "time", "GetTime",
    "Sound_GameSystem_RestartSoundSystem",
} }
