-- Run from the repository root: lua tests/settings.lua
SEPGP, SEPGP_DB = {}, {}
local officer = true
C_GuildInfo = { IsGuildOfficer = function() return officer end }
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/GP.lua")
dofile("SEPGP-Forever/BidSettings.lua")

local frames = {}
local function frame(kind)
    local object = { kind = kind, scripts = {}, text = "" }
    for _, method in ipairs({ "SetPoint", "SetWidth", "SetJustifyH", "SetSize", "SetAutoFocus", "ClearFocus", "SetScrollChild", "SetMaxLetters", "RegisterEvent" }) do
        object[method] = function() end
    end
    function object:SetText(value) self.text = value end
    function object:GetText() return self.text end
    function object:SetChecked(value) self.checked = value end
    function object:GetChecked() return self.checked end
    function object:Enable() self.enabled = true end
    function object:Disable() self.enabled = false end
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:CreateFontString() return frame("FontString") end
    frames[#frames + 1] = object
    return object
end
CreateFrame = function(kind, _, parent)
    local object = frame(kind)
    object.parentFrame = parent
    return object
end

local registered, legacy = nil, {}
local subcategories = {}
local category = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        assert(panel.name == "SEPGP Forever" and name == "SEPGP Forever")
        return category
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, name)
        assert(parent == category and panel.name == name)
        subcategories[name] = panel
    end,
    RegisterAddOnCategory = function(value) registered = value end,
}
InterfaceOptions_AddCategory = function(panel) legacy[#legacy + 1] = panel end
dofile("SEPGP-Forever/Settings.lua")
assert(registered == category and #legacy == 0)
assert(subcategories.Officer == SEPGP.settingsPanel)
assert(subcategories.Member == SEPGP.memberSettingsPanel)
local panel = SEPGP.settingsPanel
panel.scripts.OnShow()
SEPGP.memberSettingsPanel.scripts.OnShow()
local fields, buttons, checks = {}, {}, {}
for _, object in ipairs(frames) do
    if object.kind == "EditBox" then fields[#fields + 1] = object end
    if object.kind == "Button" then buttons[object.text] = object end
    if object.kind == "CheckButton" then checks[#checks + 1] = object end
end
assert(fields[1].text == "8" and fields[2].text == "2" and fields[3].text == "1")
fields[1]:SetText("10")
fields[2]:SetText("3")
fields[3]:SetText("0.5")
buttons.Apply.scripts.OnClick()
assert(SEPGP.GP.Calculate(26, 4, 1) == 15)
assert(fields[4].text == "BiS" and fields[5].text == "0" and checks[1].checked)
fields[4]:SetText("Main Spec")
fields[5]:SetText("25")
checks[2]:SetChecked(false)
buttons.Apply.scripts.OnClick()
assert(SEPGP.Bids.GetSettings()[1].label == "Main Spec")
assert(SEPGP.Bids.GetSettings()[1].discount == 25)
assert(not SEPGP.Bids.GetSettings()[2].active)
fields[5]:SetText("101")
fields[1]:SetText("99")
buttons.Apply.scripts.OnClick()
assert(SEPGP.GP.Calculate(26, 4, 1) == 15) -- Neither section is saved on invalid input.
panel.scripts.OnShow()
fields[6]:SetText("MainSpec")
buttons.Apply.scripts.OnClick()
assert(SEPGP.Bids.GetSettings()[2].label == "Alternative")
panel.scripts.OnShow()
fields[1]:SetText("99")
fields[2]:SetText("oops")
buttons.Apply.scripts.OnClick()
assert(SEPGP.GP.Calculate(26, 4, 1) == 15)
panel.scripts.OnShow()
assert(fields[1].text == "10" and fields[2].text == "3")
buttons["Restore defaults"].scripts.OnClick()
assert(fields[1].text == "8" and SEPGP.GP.Calculate(26, 4, 1) == 16)
assert(fields[4].text == "BiS" and checks[2].checked)
local saved = SEPGP.Bids.Copy(SEPGP.Bids.GetSettings())
saved[3].label, saved[3].discount = "Small Upgrade", 70
assert(SEPGP.Bids.SetSettings(saved))
dofile("SEPGP-Forever/BidSettings.lua")
assert(SEPGP.Bids.GetSettings()[3].label == "Small Upgrade")
assert(SEPGP.Bids.GetChoices()[3].percent == 30)
-- Members can view settings, but neither UI actions nor setters may change them.
officer = false
panel.scripts.OnShow()
assert(fields[1].text == "8" and not fields[1].enabled)
assert(fields[8].text == "Small Upgrade" and not fields[8].enabled)
assert(not checks[1].enabled and not buttons.Apply.enabled)
assert(not buttons["Restore defaults"].enabled)
local personal = checks[6]
assert(personal.parentFrame == SEPGP.memberSettingsPanel)
assert(buttons["Update settings"].parentFrame == SEPGP.memberSettingsPanel)
assert(not buttons["Send settings"].enabled)
assert(personal.checked)
personal:SetChecked(false)
personal.scripts.OnClick(personal)
assert(not SEPGP.GetPersonalSettings().gpTooltip)
fields[1]:SetText("99")
fields[4]:SetText("Edited by member")
buttons.Apply.scripts.OnClick()
buttons["Restore defaults"].scripts.OnClick()
assert(SEPGP.GP.GetFormulaSettings().Base == 8)
assert(SEPGP.Bids.GetSettings()[3].label == "Small Upgrade")
assert(not SEPGP.GP.SetFormulaSettings(99, 3, 2))
assert(not SEPGP.GP.ResetFormulaSettings())
assert(not SEPGP.Bids.SetSettings(saved))
assert(not SEPGP.Bids.ResetSettings())
assert(not SEPGP.GetPersonalSettings().gpTooltip)
dofile("SEPGP-Forever/SettingsData.lua")
assert(not SEPGP.GetPersonalSettings().gpTooltip) -- Preference survives reload.
-- Promotion/demotion changes access without reopening the page.
officer = true
panel.scripts.OnEvent()
assert(fields[1].enabled and checks[1].enabled and buttons.Apply.enabled)
assert(not fields[13].enabled) -- Pass discount is always locked.
officer = false
panel.scripts.OnEvent()
assert(not fields[1].enabled and not buttons.Apply.enabled)
personal:SetChecked(true)
personal.scripts.OnClick(personal)
assert(SEPGP.GetPersonalSettings().gpTooltip)
C_GuildInfo = nil
assert(not SEPGP.CanEditOfficerSettings())
Settings = nil
dofile("SEPGP-Forever/Settings.lua")
assert(#legacy == 3 and legacy[1].name == "SEPGP Forever")
assert(legacy[2] == SEPGP.officerSettingsPanel and legacy[2].parent == legacy[1].name)
assert(legacy[3] == SEPGP.memberSettingsPanel and legacy[3].parent == legacy[1].name)
print("Settings tests passed")
