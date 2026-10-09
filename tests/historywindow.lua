local output = print
local messages = {}
print = function(message) messages[#messages + 1] = message end
SEPGP, SEPGP_DB, SlashCmdList, UIParent = {}, {}, {}, {}
local officer = true
C_GuildInfo = { IsGuildOfficer = function() return officer end }
GetUnitName = function() return "Officer" end
CreateFrame = nil
local function Frame()
    local object = { scripts = {}, shown = false, text = "", offset = 0, height = 418 }
    setmetatable(object, { __index = function(_, key)
        if key:match("^[A-Z]") then return function() end end
    end })
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:HookScript(event, callback) self.scripts[event] = callback end
    function object:SetText(value)
        self.text = value
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function object:GetText() return self.text end
    function object:Clear() self.text = "" end
    function object:AddMessage(value) self.text = value end
    function object:SetTextColor(r, g, b) self.color = { r, g, b } end
    function object:SetHeight(value) self.height = value end
    function object:GetHeight() return self.height end
    function object:GetVerticalScroll() return self.offset end
    function object:SetVerticalScroll(value)
        self.offset = value
        if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, value) end
    end
    function object:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function object:Hide() self.shown = false end
    function object:IsShown() return self.shown end
    object.CreateFontString, object.CreateTexture = Frame, Frame
    return object
end
CreateFrame = Frame
time = function() return 200 end
date = function(_, value) return "Time " .. value end
C_Timer = { After = function() end }
C_ChatInfo = { SendAddonMessage = function() return 0 end }
dofile("SEPGP-Forever/EPGP.lua")
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/UI.lua")
dofile("SEPGP-Forever/PlayerNames.lua")
SEPGP.GetSyncCheckpoint = function() return SEPGP_DB.syncCheckpoint and SEPGP_DB.syncCheckpoint.timestamp end
dofile("SEPGP-Forever/HistoryWindow.lua")
dofile("SEPGP-Forever/Commands.lua")
for index = 1, 100 do
    local id = string.format("%03d", index)
    SEPGP_DB.actions[id] = { id = id, timestamp = index, type = "EP", amount = 10,
        player = "Ducky Dru-Realm", actor = "Randolf Pal-Realm", reason = "Raid attendance" }
end
local itemLink = "|cffa335ee|Hitem:123:0:0:0|h[Gutgore Ripper]|h|r"
SEPGP_DB.actions["100"].reason = itemLink
SEPGP_DB.syncCheckpoint = { timestamp = 95 }
SlashCmdList.SEPGP("show history")
local frame = SEPGP.UI.historyFrame
assert(frame:IsShown() and frame.count.text == "100 actions")
assert(frame.checkpointText.text:find("Current checkpoint: Time 95", 1, true))
assert(frame.rows[1].action.timestamp == 100 and frame.rows[1].player.text == "Ducky Dru")
assert(frame.rows[1].actor.text == "Randolf Pal")
assert(frame.rows[1].detail.text == "Reason: " .. itemLink)
local clicked
SetItemRef = function(link, text, button) clicked = { link, text, button } end
frame.rows[1].detail.scripts.OnHyperlinkClick(frame.rows[1].detail, "item:123:0:0:0", itemLink, "LeftButton")
assert(clicked[1] == "item:123:0:0:0" and clicked[2] == itemLink)
clicked = nil
frame.rows[1].detail.scripts.OnHyperlinkClick(frame.rows[1].detail, "not-an-item", "text", "LeftButton")
assert(not clicked)
assert(frame.rows[6].checkpoint and frame.rows[6].detail.text:find("Checkpoint", 1, true))
assert(frame.rows[6].time.color[2] == 0.82 and frame.rows[1].time.color[2] == 1)
assert(#frame.rows < 15) -- Virtualized rows, even though all 100 actions are available.
frame.scroll:SetVerticalScroll(90 * 46)
assert(frame.rows[1].action.timestamp == 10)
assert(not frame.rows[1].checkpoint and frame.rows[1].time.color[2] == 1)
assert(#frame.rows < 15)
-- Search the entire ledger immediately, including rows outside the viewport.
frame.search:SetText("DUCKY dru")
assert(#frame.actions == 100 and frame.scroll:GetVerticalScroll() == 0)
frame.search:SetText("gutgore")
assert(#frame.actions == 1 and frame.rows[1].action.timestamp == 100)
assert(frame.rows[1].detail.text == "Reason: " .. itemLink)
frame.search:SetText("ducky gutgore randolf GP")
assert(#frame.actions == 0 and frame.empty.text == "No matching history.")
frame.search:SetText("ducky gutgore randolf EP")
assert(#frame.actions == 1 and frame.count.text == "1 of 100 actions")
frame.search:SetText("attendance Time 1")
assert(#frame.actions > 0 and #frame.actions < 100)
frame.search:SetText("[gutgore") -- Pattern characters are literal.
assert(#frame.actions == 1)
frame.search:SetText("   ")
assert(#frame.actions == 100 and frame.count.text == "100 actions")
frame.search:SetText("101")
assert(#frame.actions == 0)
SEPGP_DB.actions["101"] = { id = "101", timestamp = 101, type = "GP", amount = 25,
    player = "Other", actor = "Officer", reason = "Loot", before = { EP = 12345, GP = 100 },
    after = { EP = 12345, GP = 125 } }
SEPGP.RefreshHistoryWindow()
assert(#frame.actions == 1 and frame.search:GetText() == "101")
frame.search:SetText("12345")
assert(#frame.actions == 1)
SEPGP_DB.actions["101"] = nil
frame.search:SetText("")
SEPGP.RefreshHistoryWindow()
SlashCmdList.SEPGP("history")
local chat = table.concat(messages, "\n")
assert(chat:find("Reason: " .. itemLink, 1, true))
assert(chat:find("Reason: Raid attendance", 1, true))
-- Every action in the checkpoint's second receives the marker.
SEPGP_DB.actions.same = { id = "same", timestamp = 95, type = "GP", amount = 25,
    player = "Ducky Dru", actor = "Officer", reason = "Loot" }
SEPGP_DB.revision = SEPGP_DB.revision + 1
frame.scroll:SetVerticalScroll(0)
frame.scripts.OnUpdate(frame, 1)
assert(frame.count.text == "101 actions" and frame.rows[6].checkpoint and frame.rows[7].checkpoint)
-- Removing a checkpoint and clearing history refreshes the already-open window.
SEPGP_DB.syncCheckpoint = nil
frame.scripts.OnUpdate(frame, 1)
assert(frame.checkpointText.text == "No current checkpoint confirmed.")
for _, row in ipairs(frame.rows) do assert(not row.checkpoint) end
SEPGP_DB = { revision = 0, players = {}, actions = {} }
frame.scroll:SetVerticalScroll(500)
frame.scripts.OnUpdate(frame, 1)
assert(frame.count.text == "0 actions" and frame.scroll:GetVerticalScroll() == 0)
assert(frame.empty.text:find("No history saved", 1, true))
for _, row in ipairs(frame.rows) do assert(not row:IsShown()) end
officer = false
frame.scripts.OnEvent()
assert(not frame:IsShown())
SlashCmdList.SEPGP("show history")
assert(not frame:IsShown())
output("History window tests passed")
