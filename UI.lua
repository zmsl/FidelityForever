-- Fidelity Forever settings pages (Settings > AddOns), built from stock templates.
local _, SG = ...

local ROW_H = 32
local SEVERE, WARN, MUTED = "|cffff7d5f", "|cfff0d873", "|cff9aa3ad"

-- Small helpers ---------------------------------------------------------------

local function Tooltip(owner, lines)
  owner:SetScript("OnEnter", function(self)
    local text = type(lines) == "function" and lines() or lines
    if not text or text == "" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", GameTooltip_Hide)
end

local function Icon(parent, glyph, color)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER")
  fs:SetText(color .. glyph .. "|r")
  b.text = fs
  return b
end

-- The game's own round "i" (Interface\common\help-i), drawn the way Blizzard's guild rewards button does.
local function InfoIcon(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b:SetNormalTexture("Interface\\common\\help-i")
  b:SetHighlightTexture("Interface\\common\\help-i", "ADD")
  b:GetHighlightTexture():SetAlpha(0.2)
  return b
end

local function Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 100, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function Check(parent, label, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(26, 26)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("LEFT", c, "RIGHT", 4, 0)
  fs:SetText(label)
  c:SetScript("OnClick", function(self) set(self:GetChecked()) end)
  c.Refresh = function() c:SetChecked(get()) end
  return c
end

local function Heading(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetText(text)
  return fs
end

local function PageTitle(page, text)
  local fs = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
  fs:SetPoint("TOPLEFT", 10, -15)
  fs:SetText(text)
  return fs
end

-- Dialogs --------------------------------------------------------------------

StaticPopupDialogs.FIDELITYFOREVER_NAME = {
  text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, maxLetters = 32,
  OnAccept = function(dialog, cb) return not cb(dialog:GetEditBox():GetText()) end, -- true keeps it open
  EditBoxOnEnterPressed = function(editBox, cb)
    local text = editBox:GetText()
    if cb(text) then editBox:GetParent():Hide() end
  end,
  OnShow = function(dialog) dialog:GetEditBox():SetFocus() end,
  OnHide = function(dialog) dialog:GetEditBox():SetText("") end,
  timeout = 0, exclusive = 1, hideOnEscape = 1,
}

StaticPopupDialogs.FIDELITYFOREVER_CONFIRM = {
  text = "%s", button1 = ACCEPT, button2 = CANCEL,
  OnAccept = function(_, cb) cb() end,
  timeout = 0, exclusive = 1, hideOnEscape = 1, showAlert = 1,
}

-- Ask for a new setting name; cb(name) runs only for a valid name. Returns true from cb to close.
local function AskName(prompt, cb)
  StaticPopup_Show("FIDELITYFOREVER_NAME", prompt, nil, function(text)
    text = strtrim(text or "")
    if not SG.ValidName(text) then
      SG.Message("That name is empty or already used.")
      return false
    end
    C_Timer.After(0, function() cb(text) end) -- after this popup closes
    return true
  end)
end

local function Confirm(text, onAccept)
  StaticPopup_Show("FIDELITYFOREVER_CONFIRM", text, nil, onAccept)
end

local function ConfirmRisky(list, ok)
  Confirm("These values have caused crashes:\n\n" .. table.concat(list, "\n") ..
    "\n\nYour current settings are saved to disk first, so the game reloads the UI once.", ok)
end

local function Commit()
  SG.CommitStage(function(go) AskName("Name for your new setting:", go) end, ConfirmRisky)
end

-- Pending bar: attached to the Settings panel itself (bottom strip, left of Blizzard's Apply/Close), so it shows on
-- every Options screen, ours or not, until the changes are applied or cancelled.

local bar

local function RefreshBar()
  if not bar then return end
  local n = SG.PendingCount()
  bar:SetShown(n > 0)
  bar.text:SetFormattedText("|cffe0b25aFidelity Forever:|r %d pending change%s", n, n == 1 and "" or "s")
end

local function CreateBar()
  bar = CreateFrame("Frame", nil, SettingsPanel, "InsetFrameTemplate")
  bar:SetHeight(30)
  bar:SetPoint("BOTTOMLEFT", SettingsPanel.CategoryList, "BOTTOMRIGHT", 16, -36)
  bar:SetPoint("RIGHT", SettingsPanel.ApplyButton, "LEFT", -12, 0)
  bar:SetFrameLevel(SettingsPanel:GetFrameLevel() + 20)
  bar:Hide()
  bar.text = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  bar.text:SetPoint("LEFT", 10, 0)
  bar.cancel = Button(bar, CANCEL, 80, function() SG.Cancel() end)
  bar.cancel:SetPoint("RIGHT", -6, 0)
  bar.apply = Button(bar, APPLY, 80, Commit)
  bar.apply:SetPoint("RIGHT", bar.cancel, "LEFT", -4, 0)
  SettingsPanel:HookScript("OnShow", RefreshBar)
end

local function NewPage()
  local page = CreateFrame("Frame")
  page.OnCommit, page.OnDefault, page.OnRefresh = function() end, function() end, function() end
  return page
end

-- Group pages ---------------------------------------------------------------

local function UsesSteps(def)
  return not def.float and (def.max - def.min) <= 5
end

local function Round(def, v)
  if def.float then return math.floor(v * 100 + 0.5) / 100 end
  return math.floor(v + 0.5)
end

local function BuildRow(parent, cvar, y)
  local def = SG.CVARS[cvar]
  local row = CreateFrame("Frame", nil, parent)
  row:SetPoint("TOPLEFT", 0, y)
  row:SetPoint("RIGHT")
  row:SetHeight(ROW_H)
  row.cvar = cvar

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()

  local info = InfoIcon(row)
  info:SetPoint("LEFT", 2, 0)
  Tooltip(info, function() return (def.desc and (def.desc .. "\n\n") or "") .. MUTED .. cvar .. "|r" end)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", info, "RIGHT", 6, 0)
  label:SetWidth(190)
  label:SetJustifyH("LEFT")
  label:SetText(def.label)

  if def.values then
    local dd = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dd:SetWidth(180)
    dd:SetPoint("LEFT", 216, 0)
    dd:SetupMenu(function(_, root)
      for i, v in ipairs(def.values) do
        root:CreateRadio(def.labels[i], function() return SG.Same(SG.StagedValue(cvar), v) end,
          function() SG.StageEdit(cvar, v) end)
      end
    end)
    row.dropdown = dd
  elseif def.min == 0 and def.max == 1 and not def.float then
    local c = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c:SetPoint("LEFT", 216, 0)
    c:SetScript("OnClick", function(self) SG.StageEdit(cvar, self:GetChecked() and 1 or 0) end)
    row.check = c
  elseif UsesSteps(def) then
    row.steps = {}
    for v = def.min, def.max do
      local b = Button(row, tostring(v), 30, function() SG.StageEdit(cvar, v) end)
      b:SetPoint("LEFT", 220 + (v - def.min) * 32, 0)
      if def.risk and def.risk[v] then
        b:GetFontString():SetTextColor(1, 0.49, 0.37)
        Tooltip(b, def.risk[v])
      end
      row.steps[v] = b
    end
  else
    local steps = def.step and math.floor((def.max - def.min) / def.step + 0.5)
      or (def.float and 100 or math.max(1, math.min(def.max - def.min, 500)))
    local s = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    s:SetSize(180, 20)
    s:SetPoint("LEFT", 214, 0)
    s:Init(def.min, def.min, def.max, steps, {})
    s:SetEnabled(true)
    s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
      if not row.refreshing then SG.StageEdit(cvar, Round(def, v)) end
    end, row)
    row.slider = s
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(64, 20)
    box:SetPoint("LEFT", s, "RIGHT", 12, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function(self)
      local v = tonumber(self:GetText())
      if v then SG.StageEdit(cvar, Round(def, math.min(def.max, math.max(def.min, v)))) end
      self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); row:Refresh() end)
    box:SetScript("OnShow", function() if SG.db then row:Refresh() end end)
    row.box = box
  end

  -- Right side: "!!" crash-reported values, "!" heavy or drifted, then Re-apply on drift.
  local ICONS_X = 482 -- after the slider (214..394) and number box (406..470); keeps rows within ~600
  row.warn = Icon(row, "!", WARN)
  row.warn:SetPoint("LEFT", ICONS_X, 0)
  if def.risk then
    local notes = {}
    for _, note in pairs(def.risk) do notes[#notes + 1] = note end
    local sev = Icon(row, "!!", SEVERE)
    sev:SetPoint("LEFT", ICONS_X + 20, 0)
    Tooltip(sev, table.concat(notes, "\n"))
  end
  row.reapply = Button(row, "Re-apply", 78, function() SG.ReapplyOne(cvar) end)
  row.reapply:SetPoint("LEFT", ICONS_X + 42, 0)

  function row:Refresh()
    self.refreshing = true
    local value = SG.StagedValue(cvar)
    local live = SG.Live(cvar)
    local real = SG.RealLive(cvar) -- differs from live only while adaptive performance has lowered it
    local lowered = not SG.Same(real, live)
    local staged = not SG.Same(value, real)
    local applied = SG.db.applied and SG.Resolve(SG.db.applied)
    local drifted = not staged and applied and applied[cvar] ~= nil and not SG.Same(applied[cvar], real)

    if self.dropdown then
      self.dropdown:GenerateMenu()
    elseif self.check then
      self.check:SetChecked(SG.Same(value, 1))
    elseif self.steps then
      for v, b in pairs(self.steps) do
        if SG.Same(v, value) then b:LockHighlight() else b:UnlockHighlight() end
      end
    else
      self.slider:SetValue(tonumber(value) or def.min)
      if not self.box:HasFocus() then
        self.box:SetText(tostring(value or ""))
        self.box:SetCursorPosition(0) -- text set before layout can sit scrolled out of view
      end
    end

    if staged then
      self.bg:SetColorTexture(0.18, 0.29, 0.41, 0.35)
    elseif drifted then
      self.bg:SetColorTexture(0.37, 0.33, 0.14, 0.30)
    else
      self.bg:SetColorTexture(1, 1, 1, 0.03)
    end

    local warnText = {}
    if def.heavy then warnText[#warnText + 1] = "Very demanding" end
    if lowered then warnText[#warnText + 1] = ("Lowered for now by adaptive performance (game: %s, your value: %s)"):format(tostring(live), tostring(real)) end
    if drifted then warnText[#warnText + 1] = ("The game changed this: %s is %s, your setting is %s"):format(SG.db.applied, tostring(real), tostring(applied[cvar])) end
    self.warn:SetShown(#warnText > 0)
    Tooltip(self.warn, table.concat(warnText, "\n"))
    self.reapply:SetShown(drifted and true or false)
    if drifted then Tooltip(self.reapply, ("Set it back to %s"):format(tostring(applied[cvar]))) end
    self.refreshing = false
  end
  return row
end

local function BuildGroupPage(group)
  local page = NewPage()
  PageTitle(page, group.title)
  local scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -50)
  scroll:SetPoint("BOTTOMRIGHT", -30, 10)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(600, 10)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

  -- Rows are built now, like the other pages (SG.Init already ran); building them in the first OnShow
  -- left the page blank until it was shown a second time.
  page.rows = {}
  local y = 0
  for _, cvar in ipairs(group.cvars) do
    if SG.available[cvar] then
      page.rows[#page.rows + 1] = BuildRow(content, cvar, y)
      y = y - (ROW_H + 2)
    end
  end
  content:SetHeight(-y + 4)
  page:SetScript("OnShow", function(self)
    self:Refresh()
  end)
  function page:Refresh()
    for _, row in ipairs(self.rows) do row:Refresh() end
  end
  return page
end

-- General page ---------------------------------------------------------------

local function SelectedName()
  return (SG.stage and SG.stage.name) or SG.db.applied
end

local function SetMenu(root, onPick, isPicked)
  root:CreateTitle("Presets")
  for _, p in ipairs(SG.PRESETS) do
    local r = root:CreateRadio(p.name, function() return isPicked(p.name) end, function() onPick(p.name) end)
    r:SetTooltip(function(tip) GameTooltip_SetTitle(tip, p.hint) end)
  end
  root:CreateDivider()
  root:CreateTitle("Yours")
  for _, name in ipairs(SG.OwnNames()) do
    root:CreateRadio(name, function() return isPicked(name) end, function() onPick(name) end)
  end
end

local function CopyFromMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    SetMenu(root, function(name) SG.StageCopy(name) end, function() return false end)
  end)
end

local function BuildGeneral()
  local page = NewPage()
  PageTitle(page, "Fidelity Forever")
  local x, y = 20, -56
  local function place(region, dx, dy) region:SetPoint("TOPLEFT", x + (dx or 0), y + (dy or 0)) end

  local h = Heading(page, "Graphics settings"); place(h); y = y - 24
  local dd = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
  dd:SetWidth(200); place(dd)
  dd:SetupMenu(function(_, root)
    SetMenu(root, SG.StageSet, function(name) return SelectedName() == name end)
  end)
  local new = Button(page, "New", 70, function()
    AskName("Name for the new setting (starts from your current values):", SG.NewSetting)
  end)
  new:SetPoint("LEFT", dd, "RIGHT", 8, 0)
  local rename = Button(page, "Rename", 80, function()
    local old = SelectedName()
    AskName(("New name for %s:"):format(old), function(name) SG.RenameSetting(old, name) end)
  end)
  rename:SetPoint("LEFT", new, "RIGHT", 4, 0)
  local delete = Button(page, "Delete", 70, function()
    local name = SelectedName()
    Confirm(("Delete %s?"):format(name), function() SG.DeleteSetting(name) end)
  end)
  delete:SetPoint("LEFT", rename, "RIGHT", 4, 0)
  local copy = Button(page, "Copy from", 100, function(self) CopyFromMenu(self) end)
  copy:SetPoint("LEFT", delete, "RIGHT", 16, 0)
  y = y - 36

  -- Options that belong to the selected setting (prebuilt presets show theirs, read-only).
  local function flag(key) return SG.Flags(SelectedName())[key] end
  local function setFlag(key) return function(v) SG.SetFlag(SelectedName(), key, v) end end
  local adaptive = Check(page, "Adaptive performance", function() return flag("adaptive") end, setFlag("adaptive"))
  place(adaptive, -4)
  Tooltip(adaptive, "While your frame rate stays under the target, lowers particles, grass, horizon, shadows and similar settings in five steps, then restores them once it recovers. Your saved values never change.")
  local fpsLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fpsLabel:SetPoint("LEFT", adaptive, "RIGHT", 190, 0)
  fpsLabel:SetText("Target FPS")
  local fps = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
  fps:SetSize(48, 20); fps:SetAutoFocus(false); fps:SetNumeric(true)
  fps:SetPoint("LEFT", fpsLabel, "RIGHT", 10, 0)
  fps:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v and v >= 10 and v <= 500 then SG.db.options.targetFPS = v end
    self:SetText(tostring(SG.db.options.targetFPS)); self:ClearFocus()
  end)
  y = y - 26
  local loginOpt = Check(page, "Faster loading screens", function() return flag("loginOpt") end, setFlag("loginOpt"))
  place(loginOpt, -4)
  Tooltip(loginOpt, "At logout, sets very short view distances so the next loading screen is faster; your values come back right after login.")
  y = y - 40

  h = Heading(page, "At login"); place(h); y = y - 26
  local useLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  useLabel:SetText("Apply at login"); place(useLabel, 0, -4)
  local use = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
  use:SetWidth(200); place(use, 150, 0)
  use:SetupMenu(function(_, root)
    root:CreateRadio("Don't change anything", function() return SG.chardb.use == nil end, function() SG.chardb.use = nil end)
    root:CreateDivider()
    SetMenu(root, function(name) SG.chardb.use = name end, function(name) return SG.chardb.use == name end)
  end)
  local auto = Check(page, "Apply automatically", function() return SG.db.options.autoApply end,
    function(v) SG.db.options.autoApply = v end)
  auto:SetPoint("LEFT", use, "RIGHT", 12, 0)
  y = y - 44

  h = Heading(page, "Safety and messages"); place(h); y = y - 24
  local risky = Check(page, "Confirm before risky values", function() return SG.db.options.confirmRisky end,
    function(v) SG.db.options.confirmRisky = v end)
  place(risky, -4); y = y - 24
  local help = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  help:SetText("Asks first for values marked as crash reports. Saves to disk first, so a crash keeps your rollback (one /reload).")
  place(help, 26); y = y - 22
  local msgs = Check(page, "Show on-screen messages", function() return SG.db.options.messages end,
    function(v) SG.db.options.messages = v end)
  place(msgs, -4); y = y - 40

  h = Heading(page, "Hotkeys"); place(h); y = y - 26
  local keys = {}
  for _, k in ipairs({ { "FIDELITYFOREVER_SCREENSHOT", "Screenshot mode on/off" }, { "FIDELITYFOREVER_BACK", "Back to my setting" } }) do
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    place(fs); y = y - 22
    keys[#keys + 1] = function()
      local key = GetBindingKey(k[1])
      fs:SetText(k[2] .. ":  " .. (key and ("|cffffd100" .. key .. "|r") or (MUTED .. "Not bound|r")))
    end
  end
  local open = Button(page, "Open Key Bindings", 150, function()
    Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
  end)
  place(open, 0, -4)

  function page:Refresh()
    dd:GenerateMenu(); use:GenerateMenu()
    local own = SG.db.settings[SelectedName() or ""] ~= nil
    rename:SetEnabled(own); delete:SetEnabled(own)
    adaptive:SetEnabled(own); loginOpt:SetEnabled(own)
    adaptive.Refresh(); loginOpt.Refresh()
    if not fps:HasFocus() then fps:SetText(tostring(SG.db.options.targetFPS)); fps:SetCursorPosition(0) end
    for _, c in ipairs({ auto, risky, msgs }) do c.Refresh() end
    for _, fn in ipairs(keys) do fn() end
  end
  page:SetScript("OnShow", function(self) self:Refresh() end)
  return page
end

-- Profiles page: a thin view of the per-character "apply at login" pointer ----

local function BuildProfiles()
  local page = NewPage()
  PageTitle(page, "Profiles")
  local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 20, -60)
  label:SetText("Profile")
  local dd = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
  dd:SetWidth(200)
  dd:SetPoint("LEFT", label, "RIGHT", 12, 0)
  dd:SetupMenu(function(_, root)
    SetMenu(root, function(name) SG.chardb.use = name end, function(name) return SG.chardb.use == name end)
  end)
  local copy = Button(page, "Copy From", 110, function(self)
    local use = SG.chardb.use
    if not use then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
      SetMenu(root, function(from) SG.StageSet(use); SG.StageCopy(from) end, function() return false end)
    end)
  end)
  copy:SetPoint("LEFT", dd, "RIGHT", 24, 0)
  function page:Refresh()
    dd:GenerateMenu()
    copy:SetEnabled(SG.chardb.use ~= nil)
  end
  page:SetScript("OnShow", function(self) self:Refresh() end)
  return page
end

-- Troubleshooting page --------------------------------------------------------

local function BuildTroubleshooting()
  local page = NewPage()
  PageTitle(page, "Troubleshooting")
  local actions = {
    { "Safe mode", "Apply Performance", SG.SafeMode },
    { "Undo last apply", "Undo", SG.UndoLast },
    { "Restore original game settings", "Restore", function()
      Confirm("Restore the graphics settings you had before installing Fidelity Forever?", SG.RestoreOriginal)
    end },
  }
  for i, a in ipairs(actions) do
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 20, -60 - (i - 1) * 36)
    fs:SetText(a[1])
    local b = Button(page, a[2], 150, a[3])
    b:SetPoint("LEFT", fs, "LEFT", 300, 0)
  end
  function page:Refresh() end
  return page
end

-- Search -------------------------------------------------------------------------
-- The Settings search box only reads list-style (vertical layout) categories. Like Blizzard's Key Bindings, each page
-- gets a hidden list category whose controls stage changes (never write directly) and which redirects to the page:
-- the category list skips it, the search finds its controls and heads the results with the page's name.

local function RegisterSearch(group, pageCategory)
  local hidden = Settings.RegisterVerticalLayoutCategory(group.title)
  for _, cvar in ipairs(group.cvars) do
    if SG.available[cvar] then
      local def = SG.CVARS[cvar]
      local key = "FIDELITYFOREVER_" .. cvar
      if def.values then
        local numeric = type(def.values[1]) == "number"
        local setting = Settings.RegisterProxySetting(hidden, key,
          numeric and Settings.VarType.Number or Settings.VarType.String, def.label, def.values[1],
          function() local v = SG.StagedValue(cvar); return numeric and tonumber(v) or v end,
          function(v) SG.StageEdit(cvar, v) end)
        Settings.CreateDropdown(hidden, setting, function()
          local c = Settings.CreateControlTextContainer()
          for i, v in ipairs(def.values) do c:Add(v, def.labels[i]) end
          return c:GetData()
        end, def.desc)
      elseif def.min == 0 and def.max == 1 and not def.float then
        local setting = Settings.RegisterProxySetting(hidden, key, Settings.VarType.Boolean, def.label, false,
          function() return SG.Same(SG.StagedValue(cvar), 1) end,
          function(v) SG.StageEdit(cvar, v and 1 or 0) end)
        Settings.CreateCheckbox(hidden, setting, def.desc)
      else
        local setting = Settings.RegisterProxySetting(hidden, key, Settings.VarType.Number, def.label, def.min,
          function() return tonumber(SG.StagedValue(cvar)) or def.min end,
          function(v) SG.StageEdit(cvar, Round(def, v)) end)
        local options = Settings.CreateSliderOptions(def.min, def.max, def.step or (def.float and 0.01 or 1))
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(hidden, setting, options, def.desc)
      end
    end
  end
  hidden.redirectCategory = pageCategory
  Settings.RegisterAddOnCategory(hidden)
end

-- Registration -----------------------------------------------------------------

function SG.BuildUI()
  CreateBar()
  local pages = {}
  local general = BuildGeneral()
  local root = Settings.RegisterCanvasLayoutCategory(general, "Fidelity Forever")
  pages[#pages + 1] = general

  -- Graphics and Audio are folders: selecting one opens its first page instead of an empty page. (The Settings list has no non-selectable entry for addon categories.)
  local folders = {}
  for _, group in ipairs(SG.GROUPS) do
    local folder = folders[group.section]
    if not folder then
      local folderPage = NewPage()
      function folderPage:Refresh() end
      folder = { category = Settings.RegisterCanvasLayoutSubcategory(root, folderPage, group.section), page = folderPage }
      folderPage:SetScript("OnShow", function()
        C_Timer.After(0, function() Settings.OpenToCategory(folder.first:GetID()) end)
      end)
      folders[group.section] = folder
    end
    local page = BuildGroupPage(group)
    local cat = Settings.RegisterCanvasLayoutSubcategory(folder.category, page, group.title)
    folder.first = folder.first or cat
    RegisterSearch(group, cat)
    pages[#pages + 1] = page
  end
  local profiles = BuildProfiles()
  Settings.RegisterCanvasLayoutSubcategory(root, profiles, "Profiles")
  pages[#pages + 1] = profiles
  local trouble = BuildTroubleshooting()
  Settings.RegisterCanvasLayoutSubcategory(root, trouble, "Troubleshooting")
  Settings.RegisterAddOnCategory(root)
  SG.category = root

  SG.listeners[#SG.listeners + 1] = function()
    for _, page in ipairs(pages) do
      if page:IsVisible() then page:Refresh() end
    end
    RefreshBar()
  end
end

function SG.Open()
  Settings.OpenToCategory(SG.category:GetID())
end
