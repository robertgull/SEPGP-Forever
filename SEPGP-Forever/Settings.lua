-- Options > AddOns > SEPGP Forever.
local panel = CreateFrame("Frame")
panel:Hide()
panel.name = "Officer"
panel.parent = "SEPGP Forever"
SEPGP.settingsPanel = panel
SEPGP.officerSettingsPanel = panel
local memberPanel = CreateFrame("Frame")
memberPanel:Hide()
memberPanel.name, memberPanel.parent = "Member", "SEPGP Forever"
SEPGP.memberSettingsPanel = memberPanel

local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", -32, 16)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(560, 620)
scroll:SetScrollChild(content)

local function Text(text, font, x, y, width)
    local label = content:CreateFontString(nil, "ARTWORK", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width or 520)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

Text(panel.name, "GameFontNormalLarge", 16, -16)
Text("GP formula:", "GameFontNormalSmall", 16, -58, 70)
Text("floor(", "GameFontHighlightSmall", 87, -58, 30)
Text("*", "GameFontHighlightSmall", 175, -58, 14)
Text("^ ((ilvl/26)+(rarity-4)) * slot *", "GameFontHighlightSmall", 249, -58, 200)
Text(")", "GameFontHighlightSmall", 513, -58, 12)
Text("Apply saves locally. Send settings shares the saved formula and bid buttons with the guild.",
    "GameFontHighlightSmall", 16, -90)
local permissions = Text("", "GameFontHighlightSmall", 16, -110)

local fields = {}
local definitions = {
    { "Base", "Base", "Default: 8. Starting factor for item GP.", 119 },
    { "Multiplier", "Multiplier", "Default: 2. Exponential scaling for item level and rarity.", 193 },
    { "Mod", "Mod", "Default: 1. Overall item GP scaling factor.", 455 },
}
for _, definition in ipairs(definitions) do
    local field = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    field:SetSize(48, 24)
    field:SetPoint("TOPLEFT", definition[4], -52)
    field:SetAutoFocus(false)
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    field:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(definition[2])
        GameTooltip:AddLine(definition[3], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    field:SetScript("OnLeave", function() GameTooltip:Hide() end)
    fields[definition[1]] = field
end

Text("Bid buttons", "GameFontNormal", 16, -130)
Text("Discount is percent off item GP (20% discount = 80% GP). Priority follows row order.\nThe master looter's settings apply to new rounds. Closing the popup always declines.",
    "GameFontHighlightSmall", 16, -158)
Text("Name", "GameFontNormal", 52, -206, 200)
Text("Discount %", "GameFontNormal", 290, -206, 100)
Text("Active", "GameFontNormal", 430, -206, 80)
local bidFields = {}
for index = 1, 5 do
    local y = -234 - (index - 1) * 44
    Text(tostring(index), "GameFontHighlight", 16, y, 24)
    local name = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    name:SetSize(210, 24)
    name:SetPoint("TOPLEFT", 52, y + 5)
    name:SetAutoFocus(false)
    name:SetMaxLetters(24)
    name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local discount = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    discount:SetSize(100, 24)
    discount:SetPoint("TOPLEFT", 290, y + 5)
    discount:SetAutoFocus(false)
    discount:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if index == 5 then discount:Disable() end
    local active = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    active:SetSize(26, 26)
    active:SetPoint("TOPLEFT", 430, y + 6)
    bidFields[index] = { name = name, discount = discount, active = active }
end
Text("Row 5 is always a decline and has no GP cost.", "GameFontHighlightSmall", 16, -466)
local status = Text("", "GameFontHighlightSmall", 16, -540)
local memberTitle = memberPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
memberTitle:SetPoint("TOPLEFT", 16, -16)
memberTitle:SetText("Member")
local tooltipToggle = CreateFrame("CheckButton", nil, memberPanel, "UICheckButtonTemplate")
tooltipToggle:SetSize(26, 26)
tooltipToggle:SetPoint("TOPLEFT", 16, -52)
local function MemberText(text, x, y)
    local label = memberPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(520)
    label:SetJustifyH("LEFT")
    label:SetText(text)
end
MemberText("Toggle GP tooltip values", 48, -58)
tooltipToggle:SetScript("OnClick", function(self)
    SEPGP.SetGPTooltipEnabled(self:GetChecked())
end)
MemberText("Show GP and formula details on item tooltips. Saves immediately for this character.", 16, -90)
MemberText("Request shared settings from an online guild officer. Members also request them on login.", 16, -158)
local update = CreateFrame("Button", nil, memberPanel, "UIPanelButtonTemplate")
update:SetSize(160, 26)
update:SetPoint("TOPLEFT", 16, -120)
update:SetText("Update settings")
update:SetScript("OnClick", function() SEPGP.RequestSettings() end)
memberPanel:SetScript("OnShow", function()
    tooltipToggle:SetChecked(SEPGP.GetPersonalSettings().gpTooltip)
end)

local apply, reset, send
local refreshing = false
local function HasChanges()
    local settings = SEPGP.GP.GetFormulaSettings()
    for key, field in pairs(fields) do
        if tonumber(field:GetText()) ~= settings[key] then return true end
    end
    for index, value in ipairs(SEPGP.Bids.GetSettings()) do
        local row = bidFields[index]
        if row.name:GetText() ~= value.label
            or tonumber(row.discount:GetText()) ~= value.discount
            or (row.active:GetChecked() and true or false) ~= value.active then
            return true
        end
    end
    return false
end
local function UpdateApply()
    if not refreshing then
        apply:SetEnabled(SEPGP.CanEditOfficerSettings() and HasChanges())
    end
end
local function SetEditable(control, editable)
    if editable then
        control:Enable()
    else
        control:Disable()
        if control.ClearFocus then control:ClearFocus() end
    end
end
local function UpdatePermissions()
    local editable = SEPGP.CanEditOfficerSettings()
    for _, field in pairs(fields) do SetEditable(field, editable) end
    for index, row in ipairs(bidFields) do
        SetEditable(row.name, editable)
        SetEditable(row.discount, editable and index ~= 5)
        SetEditable(row.active, editable)
    end
    UpdateApply()
    SetEditable(reset, editable)
    SetEditable(send, editable)
    permissions:SetText(editable and "Guild officers can edit the formula and bid buttons."
        or "Formula and bid buttons are read-only. Only guild officers can edit them.")
end
local function Refresh()
    refreshing = true
    local settings = SEPGP.GP.GetFormulaSettings()
    for key, field in pairs(fields) do
        field:SetText(tostring(settings[key]))
        field:ClearFocus()
    end
    for index, value in ipairs(SEPGP.Bids.GetSettings()) do
        local row = bidFields[index]
        row.name:SetText(value.label)
        row.discount:SetText(tostring(value.discount))
        row.active:SetChecked(value.active)
        row.name:ClearFocus()
        row.discount:ClearFocus()
    end
    tooltipToggle:SetChecked(SEPGP.GetPersonalSettings().gpTooltip)
    refreshing = false
    UpdatePermissions()
    status:SetText("")
end

apply = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
apply:SetSize(120, 26)
apply:SetPoint("TOPLEFT", 16, -498)
apply:SetText("Apply")
apply:SetScript("OnClick", function()
    if not SEPGP.CanEditOfficerSettings() then
        Refresh()
        status:SetText("Only guild officers can change these settings.")
        return
    end
    local bids = {}
    for index, row in ipairs(bidFields) do
        bids[index] = { label = row.name:GetText(), discount = tonumber(row.discount:GetText()),
            active = row.active:GetChecked() and true or false }
    end
    local valid, validationError = SEPGP.Bids.Validate(bids)
    if not valid then status:SetText(validationError); return end
    local ok, err = SEPGP.GP.SetFormulaSettings(
        tonumber(fields.Base:GetText()),
        tonumber(fields.Multiplier:GetText()),
        tonumber(fields.Mod:GetText()))
    if ok then
        SEPGP.Bids.SetSettings(bids)
        Refresh()
        status:SetText("Settings saved.")
    else
        status:SetText(err)
    end
end)

reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
reset:SetSize(160, 26)
reset:SetPoint("LEFT", apply, "RIGHT", 12, 0)
reset:SetText("Restore defaults")
reset:SetScript("OnClick", function()
    if not SEPGP.CanEditOfficerSettings() then
        Refresh()
        status:SetText("Only guild officers can restore these settings.")
        return
    end
    SEPGP.GP.ResetFormulaSettings()
    SEPGP.Bids.ResetSettings()
    Refresh()
    status:SetText("Default settings restored.")
end)
panel:SetScript("OnShow", Refresh)
SEPGP.RefreshSettings = Refresh
panel:RegisterEvent("GUILD_ROSTER_UPDATE")
panel:RegisterEvent("PLAYER_GUILD_UPDATE")
panel:RegisterEvent("ADDON_LOADED")
panel:RegisterEvent("PLAYER_LOGIN")
panel:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and addon == "SEPGP-Forever") then
        Refresh()
    elseif event ~= "ADDON_LOADED" then
        UpdatePermissions()
    end
end)
send = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
send:SetSize(160, 26)
send:SetPoint("TOPLEFT", 16, -574)
send:SetText("Send settings")
send:SetScript("OnClick", function() SEPGP.SendSettings() end)
apply:Disable()
for _, field in pairs(fields) do field:SetScript("OnTextChanged", UpdateApply) end
for _, row in ipairs(bidFields) do
    row.name:SetScript("OnTextChanged", UpdateApply)
    row.discount:SetScript("OnTextChanged", UpdateApply)
    row.active:SetScript("OnClick", UpdateApply)
end

-- Support both the modern Settings UI and the legacy Interface Options UI.
local root = CreateFrame("Frame")
root.name = "SEPGP Forever"
local rootTitle = root:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
rootTitle:SetPoint("TOPLEFT", 16, -16)
rootTitle:SetText("SEPGP Forever - select Officer or Member settings.")
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutSubcategory then
    local category = Settings.RegisterCanvasLayoutCategory(root, root.name)
    Settings.RegisterCanvasLayoutSubcategory(category, panel, panel.name)
    Settings.RegisterCanvasLayoutSubcategory(category, memberPanel, memberPanel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(root)
    InterfaceOptions_AddCategory(panel)
    InterfaceOptions_AddCategory(memberPanel)
end
