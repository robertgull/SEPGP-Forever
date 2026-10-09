-- Run from the repository root: lua tests/standings.lua
local output = print
print = function() end
SEPGP, SEPGP_DB, SlashCmdList = {}, {}, {}
local officer, inRaid = true, true
local guild = {
    { name = "Alice-Realm", class = "MAGE" },
    { name = "Bob-Realm", class = "WARRIOR" },
    { name = "New-Realm", class = "MAGE" },
}
local raid = { "Alice-Realm", "Bob-Realm" }
C_GuildInfo = { IsGuildOfficer = function() return officer end }
GetNormalizedRealmName = function() return "Realm" end
GetNumGuildMembers = function() return #guild end
GetGuildRosterInfo = function(index)
    local member = guild[index]
    return member.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, member.class
end
IsInRaid = function() return inRaid end
GetNumGroupMembers = function() return #raid end
GetUnitName = function(unit)
    if unit == "player" then return "Officer-Realm" end
    return raid[tonumber(unit:match("raid(%d+)"))]
end
UnitClass = function(unit)
    local name = GetUnitName(unit)
    for _, member in ipairs(guild) do
        if name == member.name then return member.class, member.class end
    end
end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.75, b = 1 }, WARRIOR = { r = 0.75, g = 0.5, b = 0.25 } }
time = function() return 1 end
C_Timer = { After = function() end }
local sent = {}
C_ChatInfo = { SendAddonMessage = function(prefix, message, channel)
    sent[#sent + 1] = { prefix, message, channel }
end }
SendChatMessage = function() end
UIParent = {}
local function frame()
    local object = { scripts = {}, shown = false, text = "" }
    setmetatable(object, { __index = function() return function() end end })
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:SetText(value) self.text = value end
    function object:GetText() return self.text end
    function object:SetTextColor(r, g, b) self.color = { r, g, b } end
    function object:SetFrameStrata(value) self.strata = value end
    function object:SetChecked(value) self.checked = value and true or false end
    function object:Show() self.shown = true end
    function object:Hide() self.shown = false end
    function object:IsShown() return self.shown end
    function object:Enable() self.enabled = true end
    function object:Disable() self.enabled = false end
    function object:EnableMouse(value) self.mouse = value end
    object.CreateTexture, object.CreateFontString = frame, frame
    return object
end
CreateFrame = frame
dofile("SEPGP-Forever/EPGP.lua")
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/UI.lua")
dofile("SEPGP-Forever/PlayerNames.lua")
dofile("SEPGP-Forever/Standings.lua")
dofile("SEPGP-Forever/raidep.lua")
SEPGP_DB.players = { alice = { EP = 200, GP = 100 }, bob = { EP = 100, GP = 100 },
    outsider = { EP = 1000, GP = 100 } }
SlashCmdList.SEPGP("show")
local UI = SEPGP.UI
assert(UI.count.text == "3 players") -- Includes new guild members, excludes former members.
assert(UI.rows[1].name.text == "Alice" and UI.rows[1].name.color[3] == 1)
assert(UI.rows[2].name.text == "Bob" and UI.rows[2].name.color[1] == 0.75)
assert(not SEPGP_DB.players["new-realm"]) -- Viewing a roster does not create point records.
assert(UI.raidEP:IsShown() and UI.decay:IsShown() and UI.rows[1].mouse)
UI.classFilter.scripts.OnClick()
assert(UI.classMenu:IsShown() and UI.classMenu.buttons[1].label.text == "All classes")
assert(UI.classMenu.buttons[1].checked and not UI.classMenu.buttons[2].checked)
assert(UI.standingsFrame.strata == "DIALOG" and UI.classMenu.strata == "FULLSCREEN_DIALOG")
assert(UI.classMenu.buttons[2].label.text == "Mage" and UI.classMenu.buttons[3].label.text == "Warrior")
UI.classMenu.buttons[2].scripts.OnClick()
assert(UI.standingsClasses.MAGE and UI.count.text == "2 players")
assert(UI.classMenu.buttons[2].checked and not UI.classMenu.buttons[1].checked)
assert(UI.rows[1].name.text == "Alice" and UI.rows[2].name.text == "New")
assert(not UI.rows[3]:IsShown() and UI.classMenu:IsShown())
-- Multiple classes form a union, and the menu stays open for further selections.
UI.classMenu.buttons[3].scripts.OnClick()
assert(UI.standingsClasses.MAGE and UI.standingsClasses.WARRIOR and UI.count.text == "3 players")
assert(UI.classMenu.buttons[2].checked and UI.classMenu.buttons[3].checked)
assert(UI.classFilter.text == "Mage, Warrior" and UI.classMenu:IsShown())
UI.filter.scripts.OnClick()
assert(UI.count.text == "2 players" and not UI.classMenu:IsShown())
UI.classFilter.scripts.OnClick()
UI.classMenu.buttons[2].scripts.OnClick()
assert(UI.count.text == "1 players" and UI.rows[1].name.text == "Bob")
assert(not UI.classMenu.buttons[2].checked and UI.classMenu.buttons[3].checked)
-- Deselecting the last class restores the full roster.
UI.classMenu.buttons[3].scripts.OnClick()
assert(not UI.standingsClasses and UI.count.text == "2 players")
assert(UI.classMenu.buttons[1].checked and UI.classFilter.text == "All classes")
UI.classMenu.buttons[2].scripts.OnClick()
UI.classFilter.scripts.OnClick() -- Close, then reopen; keep the selection checked.
UI.classFilter.scripts.OnClick()
assert(UI.classMenu.buttons[2].checked)
UI.classMenu.buttons[1].scripts.OnClick()
assert(not UI.standingsClasses and UI.count.text == "2 players")
UI.filter.scripts.OnClick()
UI.filter.scripts.OnClick()
assert(UI.standingsFilter == "raid" and UI.count.text == "2 players")
inRaid = false
UI.standingsFrame.scripts.OnEvent()
assert(UI.count.text == "0 players" and not UI.raidEP.enabled)
UI.raidEP.scripts.OnClick()
assert(not rawget(UI, "awardDialog"))
inRaid = true
UI.filter.scripts.OnClick()
-- Selecting a member awards through the core action history, then updates rankings.
UI.rows[1].scripts.OnClick(UI.rows[1])
local dialog = UI.awardDialog
assert(dialog.player.key == "alice" and dialog.mode == "member")
dialog.amount:SetText("25")
dialog.reason:SetText("Attendance")
dialog.ep.scripts.OnClick()
assert(SEPGP_DB.players.alice.EP == 225 and SEPGP_DB.revision == 1)
UI.rows[1].scripts.OnClick(UI.rows[1])
dialog.amount:SetText("50")
dialog.gp.scripts.OnClick()
assert(SEPGP_DB.players.alice.GP == 150 and SEPGP_DB.revision == 2)
UI.rows[1].scripts.OnClick(UI.rows[1])
dialog.amount:SetText("nan")
assert(not SEPGP.SubmitStandingsAward("EP") and SEPGP_DB.revision == 2)
-- Raid EP uses the current raid; decay always includes every saved player.
UI.raidEP.scripts.OnClick()
dialog.amount:SetText("100")
dialog.reason:SetText("Boss")
dialog.apply.scripts.OnClick()
assert(SEPGP_DB.players.alice.EP == 325 and SEPGP_DB.players.bob.EP == 200)
assert(SEPGP_DB.players.outsider.EP == 1000)
UI.filter.scripts.OnClick()
UI.decay.scripts.OnClick()
dialog.amount:SetText("20")
dialog.apply.scripts.OnClick()
assert(SEPGP_DB.players.alice.EP == 260 and SEPGP_DB.players.alice.GP == 120)
assert(SEPGP_DB.players.outsider.EP == 800 and SEPGP_DB.players.outsider.GP == 80)
-- Member dialog buttons accept deductions and record signed adjustments.
SEPGP.OpenStandingsAward("member", { key = "alice", name = "Alice" })
dialog.amount:SetText("-60")
dialog.reason:SetText("Correction")
dialog.ep.scripts.OnClick()
assert(SEPGP_DB.players.alice.EP == 200 and not dialog:IsShown())
SEPGP.OpenStandingsAward("member", { key = "alice", name = "Alice" })
dialog.amount:SetText("-10")
dialog.gp.scripts.OnClick()
assert(SEPGP_DB.players.alice.GP == 110 and not dialog:IsShown())
local negativeEP, negativeGP = false, false
for _, action in pairs(SEPGP_DB.actions) do
    if action.type == "EP" and action.amount == -60 then
        assert(action.before.EP == 260 and action.after.EP == 200 and action.reason == "Correction")
        negativeEP = true
    elseif action.type == "GP" and action.amount == -10 then
        assert(action.before.GP == 120 and action.after.GP == 110)
        negativeGP = true
    end
end
assert(negativeEP and negativeGP)
SEPGP.OpenStandingsAward("member", { key = "alice", name = "Alice" })
local beforeInvalid = SEPGP_DB.revision
for _, invalid in ipairs({ "", "abc", "0", "-1.5", "1.5", "1e309", "-1e309" }) do
    dialog.amount:SetText(invalid)
    assert(not SEPGP.SubmitStandingsAward("EP") and SEPGP_DB.revision == beforeInvalid)
end
UI.raidEP.scripts.OnClick()
dialog.amount:SetText("-10")
assert(not SEPGP.SubmitStandingsAward() and SEPGP_DB.revision == beforeInvalid)
UI.decay.scripts.OnClick()
dialog.amount:SetText("-10")
assert(not SEPGP.SubmitStandingsAward() and SEPGP_DB.revision == beforeInvalid)
-- Demotion removes officer controls, closes the editor, and rejects stale callbacks.
UI.rows[1].scripts.OnClick(UI.rows[1])
dialog.amount:SetText("100")
local revision = SEPGP_DB.revision
officer = false
UI.standingsFrame.scripts.OnEvent()
assert(not UI.raidEP:IsShown() and not UI.decay:IsShown() and not UI.rows[1].mouse)
assert(not dialog:IsShown())
assert(not SEPGP.SubmitStandingsAward("EP") and SEPGP_DB.revision == revision)
-- Members can request the same guild standings update as /sep update.
local beforeRefresh = #sent
UI.refresh.scripts.OnClick()
assert(#sent == beforeRefresh + 1)
local refreshRequest = sent[#sent]
SlashCmdList.SEPGP("update")
local slashRequest = sent[#sent]
assert(refreshRequest[1] == slashRequest[1] and refreshRequest[2] == "STANDINGS_REQUEST"
    and refreshRequest[2] == slashRequest[2] and refreshRequest[3] == "GUILD")
UI.rows[1].scripts.OnClick(UI.rows[1])
assert(not dialog:IsShown())
UI.decay.scripts.OnClick()
assert(not dialog:IsShown())
-- Guild mode can display and award members beyond the previous 20-row limit.
officer = true
for index = 1, 30 do guild[#guild + 1] = { name = "Member" .. index .. "-Realm", class = "WARRIOR" } end
UI.filter.scripts.OnClick()
assert(UI.count.text == "33 players" and UI.rows[33]:IsShown())
UI.rows[33].scripts.OnClick(UI.rows[33])
local recipient = dialog.player.key
dialog.amount:SetText("10")
dialog.ep.scripts.OnClick()
assert(SEPGP_DB.players[recipient].EP == 10)
-- Display the roster's spelling, with spaces, while retaining the full DB key.
guild = { { name = "Randolf Pal-ClassicBetaPvP", class = "PALADIN" } }
SEPGP_DB.players["randolf pal-classicbetapvp"] = { EP = 500, GP = 100 }
SEPGP.RefreshStandingsWindow()
assert(UI.rows[1].name.text == "Randolf Pal")
local clean = SEPGP.GetStandings()[1]
assert(clean.key == "randolf pal" and clean.EP == 500)
assert(SEPGP.DisplayName("Randolf Pal") == "Randolf Pal")
output("Standings tests passed")
