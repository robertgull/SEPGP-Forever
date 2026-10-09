-- Run from the repository root: lua tests/dfb.lua
local output = print
print = function() end
local me, master, grouped = "Master-Realm", "Master-Realm", true
local roster = { "Master-Realm", "Alice-Realm", "Bob-Realm" }
local frames, hooks, sent = {}, {}, {}
local announcements = {}
SendChatMessage = function(message, channel)
    announcements[#announcements + 1] = { message = message, channel = channel }
end
UIParent = {}
SlashCmdList = {}
GetNormalizedRealmName = function() return "Realm" end
GetUnitName = function(unit)
    if unit == "player" then return me end
    return roster[tonumber(unit:match("raid(%d+)"))]
end
UnitClass = function(unit)
    local name = GetUnitName(unit)
    if name == "Alice-Realm" then return "Mage", "MAGE" end
    if name == "Bob-Realm" then return "Warrior", "WARRIOR" end
end
RAID_CLASS_COLORS = {
    MAGE = { r = 0.25, g = 0.75, b = 1 },
    WARRIOR = { r = 0.75, g = 0.5, b = 0.25 },
}
IsInGroup = function() return grouped end
IsInRaid = function() return grouped end
GetNumGroupMembers = function() return #roster end
GetLootMethod = function()
    for i, name in ipairs(roster) do
        if name == master then return "master", nil, i end
    end
    return "group"
end
time = function() return 1 end
C_GuildInfo = { IsGuildOfficer = function() return true end }
C_ChatInfo = { SendAddonMessage = function() return 0 end }
C_Timer = { After = function() end }
IsShiftKeyDown = function() return true end
ContainerFrameItemButton_OnModifiedClick = function() end
HandleModifiedItemClick = function() end
hooksecurefunc = function(name, fn) hooks[name] = fn end
local function frame()
    local f = { scripts = {}, shown = false }
    local noop = function() end
    setmetatable(f, { __index = function() return noop end })
    f.SetScript = function(self, name, fn) self.scripts[name] = fn end
    f.IsShown = function(self) return self.shown end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self)
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    f.SetText = function(self, value) self.text = value end
    f.SetSize = function(self, width, height) self.width, self.height = width, height end
    f.SetWidth = function(self, width) self.width = width end
    f.SetResizeBounds = function(self, minWidth, minHeight, maxWidth, maxHeight)
        self.resizeBounds = { minWidth, minHeight, maxWidth, maxHeight }
    end
    f.StartSizing = function(self)
        local bounds = self.resizeBounds
        self.width = math.min(bounds[3], math.max(bounds[1], self.width))
        self.height = math.min(bounds[4], math.max(bounds[2], self.height))
        self.sizing = true
    end
    f.StopMovingOrSizing = function(self) self.sizing = false end
    f.CreateFontString = frame
    f.CreateTexture = frame
    frames[#frames + 1] = f
    return f
end
CreateFrame = frame
dofile("SEPGP-Forever/libs/LibStub/LibStub.lua")
dofile("SEPGP-Forever/libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local comm = LibStub:NewLibrary("AceComm-3.0", 999)
comm.Embed = function(_, target)
    target.RegisterComm = function() end
    target.SendCommMessage = function(_, prefix, message, channel, targetName)
        sent[#sent + 1] = { prefix, message, channel, targetName }
    end
end
dofile("SEPGP-Forever/EPGP.lua")
LibStub("AceSerializer-3.0"):Embed(SEPGP)
dofile("SEPGP-Forever/UI.lua") -- Matches the active core overrides in the TOC.
dofile("SEPGP-Forever/PlayerNames.lua")
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/Standings.lua")
dofile("SEPGP-Forever/raidep.lua")
local link = "|cffa335ee|Hitem:123:0:0:0|h[Test item]|h|r"
SEPGP.GP = { GetItemGP = function() return 101 end }
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/BidSettings.lua")
C_Container = { GetContainerItemLink = function() return link end }
dofile("SEPGP-Forever/ItemEligibility.lua")
dofile("SEPGP-Forever/dfb.lua")
local events = frames[#frames]
local DFB = SEPGP.DFB
local function receive(payload, channel, sender)
    payload.version = 1
    DFB:OnCommReceived("SEPGPF_DFB", SEPGP:Serialize(payload), channel, sender)
end
SEPGP_DB.players = {
    alice = { EP = 100, GP = 100 },
    bob = { EP = 1000, GP = 100 },
}
-- /sep show still reaches the standings UI through the DFB slash wrapper.
SlashCmdList.SEPGP("show")
local standingsFrame = SEPGP.UI.standingsFrame
assert(standingsFrame:IsShown())
assert(SEPGP.UI.rows[1].name.text == "bob")
assert(SEPGP.UI.rows[1].pr.text == "10.00")
assert(SEPGP.UI.count.text == "2 players")
SlashCmdList.SEPGP("show")
assert(not standingsFrame:IsShown())
SlashCmdList.SEPGP("show")
assert(SEPGP.UI.standingsFrame == standingsFrame and standingsFrame:IsShown())
-- Decayed zero-GP standings must display a finite ratio, and refresh must
-- hide old rows when the database becomes empty.
SEPGP_DB.players.bob.GP = 0
SEPGP.RefreshStandingsWindow()
assert(SEPGP.UI.rows[1].name.text == "alice")
assert(SEPGP.UI.rows[2].pr.text == "0.00")
SEPGP_DB.players.bob.GP = 100
local players = SEPGP_DB.players
SEPGP_DB.players = {}
SEPGP.RefreshStandingsWindow()
assert(SEPGP.UI.count.text == "0 players" and not SEPGP.UI.rows[1]:IsShown())
SEPGP_DB.players = players
SlashCmdList.SEPGP("show")
-- Unauthorized users cannot open the master window.
me = "Alice-Realm"
SlashCmdList.SEPGP("dfb")
assert(not DFB.masterFrame)
me = master
SlashCmdList.SEPGP(" DfB ")
assert(DFB.masterFrame:IsShown())
-- Beginning a resize must preserve the compact size and enforce a bounded range.
DFB.masterFrame.resizeHandle.scripts.OnMouseDown(nil, "LeftButton")
assert(DFB.masterFrame.width == 330 and DFB.masterFrame.height == 340)
DFB.masterFrame.resizeHandle.scripts.OnMouseUp()
assert(not DFB.masterFrame.sizing)
DFB.masterFrame:SetSize(2000, 2000)
DFB.masterFrame.resizeHandle.scripts.OnMouseDown(nil, "LeftButton")
assert(DFB.masterFrame.width == 900 and DFB.masterFrame.height == 800)
DFB.masterFrame.resizeHandle.scripts.OnMouseUp()
DFB.masterFrame:SetSize(200, 200)
DFB.masterFrame.resizeHandle.scripts.OnMouseDown(nil, "LeftButton")
assert(DFB.masterFrame.width == 260 and DFB.masterFrame.height == 260)
DFB.masterFrame.scripts.OnSizeChanged(DFB.masterFrame, 260, 260)
assert(DFB.masterFrame.compactLayout and DFB.masterFrame.bidContent.width == 180)
assert(DFB.masterFrame.award.width == 105 and DFB.masterFrame.cancel.width == 105)
DFB.masterFrame.resizeHandle.scripts.OnMouseUp()
DFB.masterFrame:SetSize(330, 340)
DFB.masterFrame.scripts.OnSizeChanged(DFB.masterFrame, 330, 340)
-- Exercise the bag hook installed on addon load.
events.scripts.OnEvent(nil, "ADDON_LOADED")
hooks.ContainerFrameItemButton_OnModifiedClick({
    GetParent = function() return { GetID = function() return 0 end } end,
    GetID = function() return 1 end,
}, "LeftButton")
local id = DFB.round.id
assert(#announcements == 2 and announcements[1].channel == "RAID")
assert(announcements[1].message:find(link, 1, true))
assert(announcements[1].message:find("101 base GP", 1, true))
assert(announcements[2].channel == "RAID")
assert(announcements[2].message == "SEPGP: Click a button or whisper me: BiS (100% GP), Alternative (80% GP), Upgrade (50% GP), Off Spec (0% GP), Pass.")
assert(#announcements[2].message <= 255)
DFB.Start(link)
assert(#announcements == 2) -- Repeated clicks during bidding do not announce again.
DFB.Respond(5)
assert(DFB.round.responses["master-realm"] == 5)
assert(not DFB.bidFrame:IsShown())
DFB.RecordResponse(id, "Outsider-Realm", 1)
DFB.RecordResponse("stale", "Alice", 1)
DFB.RecordResponse(id, "Alice", 1.5)
assert(not DFB.round.responses["alice-realm"])
-- Chat whispers use the same bids, eligibility checks and ranking as buttons.
for _, bid in ipairs({
    { "BIS", 1 }, { "  Alternative  ", 2 }, { "uPgRaDe", 3 },
    { "Off   Spec", 4 }, { "offspec", 4 }, { "PASS", 5 },
}) do
    events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", bid[1], "Alice")
    assert(DFB.round.responses["alice-realm"] == bid[2])
end
events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", "is this BIS?", "Alice")
assert(DFB.round.responses["alice-realm"] == 5) -- Conversation is not a bid.
events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", "BIS", "Outsider-Realm")
assert(not DFB.round.responses["outsider-realm"])
me = "Bob-Realm"
events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", "BIS", "Alice")
assert(DFB.round.responses["alice-realm"] == 5) -- Only the master records bids.
me = master
events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", "BIS", "Alice")
assert(DFB.GetRankedBids()[1].name == "Alice-Realm")
DFB.round.responses["alice-realm"] = nil
receive({ kind = "BID", id = id, choice = 2 }, "RAID", "Alice")
assert(not DFB.round.responses["alice-realm"])
receive({ kind = "BID", id = id, choice = 2 }, "WHISPER", "Alice")
DFB.RecordResponse(id, "Bob", 3)
assert(DFB.masterFrame.bids.text:find("|cff40bfffAlice|r", 1, true))
assert(DFB.masterFrame.bids.text:find("|cffbf8040Bob|r", 1, true))
assert(DFB.GetRankedBids()[1].name == "Alice-Realm") -- Category beats ratio.
DFB.RecordResponse(id, "Bob", 2)
assert(DFB.GetRankedBids()[1].name == "Bob-Realm") -- Ratio within category.
DFB.RecordResponse(id, "Bob", 5)
assert(DFB.masterFrame.bids.text:find("|cffbf8040Bob|r - Pass", 1, true))
local beforeAwardAnnouncements = #announcements
DFB.Award()
assert(SEPGP_DB.players.alice.GP == 181) -- 80%, rounded to integer GP.
local recordedLoot
for _, action in pairs(SEPGP_DB.actions) do
    if action.type == "GP" and action.amount == 81 and action.player == "alice" then recordedLoot = action end
end
assert(recordedLoot and recordedLoot.reason == link)
assert(not DFB.round)
assert(#announcements == beforeAwardAnnouncements + 1)
assert(announcements[#announcements].channel == "RAID")
assert(announcements[#announcements].message:find("awarded to Alice-Realm (Alternative, 81 GP)", 1, true))
local revision = SEPGP_DB.revision
DFB.Award()
assert(SEPGP_DB.revision == revision)
assert(#announcements == beforeAwardAnnouncements + 1)
for choice, expected in ipairs({101, 81, 51, 0}) do
    DFB.Start(link)
    DFB.RecordResponse(DFB.round.id, "Alice", choice)
    local before = SEPGP_DB.players.alice.GP
    DFB.Award()
    assert(SEPGP_DB.players.alice.GP == before + expected)
end
-- Exact ties resolve deterministically; departing players are excluded.
SEPGP_DB.players.alice = { EP = 100, GP = 100 }
SEPGP_DB.players.bob = { EP = 100, GP = 100 }
DFB.Start(link)
DFB.RecordResponse(DFB.round.id, "Alice", 1)
DFB.RecordResponse(DFB.round.id, "Bob", 1)
assert(DFB.GetRankedBids()[1].name == "Alice-Realm")
roster[2] = "Other-Realm"
assert(DFB.GetRankedBids()[1].name == "Bob-Realm")
roster[2] = "Alice-Realm"
revision = SEPGP_DB.revision
DFB.CloseRound()
assert(SEPGP_DB.revision == revision)
-- A modern ItemLocation hook ignores equipment/bank items, and free awards
-- leave GP below the base unchanged (possible after decay).
hooks.HandleModifiedItemClick(link, { IsBagAndSlot = function() return false end })
assert(not DFB.round)
hooks.HandleModifiedItemClick(link, {
    IsBagAndSlot = function() return true end,
    GetBagAndSlot = function() return -1, 1 end,
})
assert(not DFB.round)
hooks.HandleModifiedItemClick(link, {
    IsBagAndSlot = function() return true end,
    GetBagAndSlot = function() return 0, 1 end,
})
assert(DFB.round)
SEPGP_DB.players.alice.GP = 50
local freeRevision = SEPGP_DB.revision
DFB.RecordResponse(DFB.round.id, "Alice", 4)
DFB.Award()
assert(SEPGP_DB.players.alice.GP == 50)
assert(SEPGP_DB.revision == freeRevision + 1)
local freeLoot
for _, action in pairs(SEPGP_DB.actions) do
    if action.type == "GP" and action.amount == 0 and action.before.GP == 50 then freeLoot = action end
end
assert(freeLoot and freeLoot.reason == link and freeLoot.after.GP == 50)
-- Modified loot clicks come through the shared click handler without an
-- ItemLocation. Use the actual loot slot, not the visible row number.
LootFrame = { GetParent = function() return UIParent end }
local focus = { slot = 7, GetParent = function() return LootFrame end }
GetMouseFocus = function() return focus end
GetLootSlotLink = function(slot) if slot == 7 then return link end end
DFB.lootOpen, DFB.lootSession = true, 1
local assignments = {}
GetMasterLootCandidate = function(slot, index)
    if slot == 7 and index == 2 then return "Alice" end
end
GiveMasterLoot = function(slot, index) assignments[#assignments + 1] = { slot, index } end
hooks.HandleModifiedItemClick(link, nil)
assert(DFB.round and DFB.round.link == link and DFB.round.lootSlot == 7)
DFB.CloseRound()
focus.slot = 8
hooks.HandleModifiedItemClick(link, nil)
assert(not DFB.round)
focus = { slot = 7, GetParent = function() return UIParent end }
hooks.HandleModifiedItemClick(link, nil)
assert(not DFB.round) -- Matching item outside the loot frame is ignored.
local lootRow = { GetSlotIndex = function() return 7 end,
    GetParent = function() return LootFrame end }
focus = { GetParent = function() return lootRow end }
GetMouseFoci = function() return { focus } end
-- A gray item with no equipment slot uses the real GP calculator and can
-- enter bidding from the loot window.
dofile("SEPGP-Forever/GP.lua")
C_Item = {
    GetItemInfo = function() return "Gray item", link, 0, 104, nil, nil, nil, nil, "" end,
    GetDetailedItemLevelInfo = function() return 104 end,
}
hooks.HandleModifiedItemClick(link, nil)
assert(DFB.round and DFB.round.gp == 4)
SEPGP_DB.players.alice.GP = 100
DFB.RecordResponse(DFB.round.id, "Alice", 1)
DFB.Award()
assert(assignments[#assignments][1] == 7 and assignments[#assignments][2] == 2)
assert(SEPGP_DB.players.alice.GP == 100) -- Wait for server confirmation.
events.scripts.OnEvent(nil, "LOOT_SLOT_CLEARED", 7)
assert(SEPGP_DB.players.alice.GP == 104)
-- Non-masters accept offers only from the actual master; duplicate START
-- and stale CLOSE packets cannot reopen or dismiss the current popup.
me = "Alice-Realm"
receive({ kind = "START", id = "remote", link = link, gp = 101 }, "RAID", "Bob")
assert(not DFB.offer)
receive({ kind = "START", id = "remote", link = link, gp = 101 }, "RAID", master)
assert(DFB.offer.id == "remote")
receive({ kind = "BID_ACK", id = "remote", choice = 1 }, "WHISPER", "Bob")
assert(DFB.bidFrame:IsShown())
receive({ kind = "BID_ACK", id = "stale", choice = 1 }, "WHISPER", master)
assert(DFB.bidFrame:IsShown())
local sentBeforeAck = #sent
receive({ kind = "BID_ACK", id = "remote", choice = 1 }, "WHISPER", master)
assert(not DFB.bidFrame:IsShown() and DFB.offer.responded)
assert(#sent == sentBeforeAck) -- Closing after acknowledgment does not send Pass.
DFB.Respond(3)
assert(sent[#sent][3] == "WHISPER" and sent[#sent][4] == master)
receive({ kind = "START", id = "remote", link = link, gp = 101 }, "RAID", master)
assert(not DFB.bidFrame:IsShown())
receive({ kind = "CLOSE", id = "older" }, "RAID", master)
assert(DFB.offer.id == "remote")
receive({ kind = "CLOSE", id = "remote" }, "RAID", master)
assert(not DFB.offer)
receive({ kind = "START", id = "pass", link = link, gp = 101 }, "RAID", master)
DFB.bidFrame:Hide()
local ok, pass = SEPGP:Deserialize(sent[#sent][2])
assert(ok and pass.choice == 5)
master = "Bob-Realm"
events.scripts.OnEvent(nil, "PARTY_LOOT_METHOD_CHANGED")
assert(not DFB.offer)
-- Opening qualifying loot automatically opens only the master's DFB window,
-- at or above the configured threshold, without starting a bid round.
master, me = "Master-Realm", "Master-Realm"
local threshold, loot = 3, {}
GetLootThreshold = function() return threshold end
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(slot) return loot[slot].link end
GetLootSlotInfo = function(slot)
    local item = loot[slot]
    if item.legacy then return "texture", "Item", 1, item.quality, false end
    return "texture", "Item", 1, item.currencyID, item.quality, false
end
DFB.masterFrame:Hide()
loot = { { link = link, quality = 2 } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(not DFB.masterFrame:IsShown())
loot[1].quality = 3
events.scripts.OnEvent(nil, "LOOT_SLOT_CHANGED")
assert(DFB.masterFrame:IsShown() and not DFB.round)
DFB.masterFrame:Hide()
events.scripts.OnEvent(nil, "LOOT_SLOT_CHANGED")
assert(not DFB.masterFrame:IsShown()) -- Respect manual dismissal this loot session.
events.scripts.OnEvent(nil, "LOOT_CLOSED")
events.scripts.OnEvent(nil, "LOOT_SLOT_CHANGED")
assert(not DFB.masterFrame:IsShown())
loot = { { link = link, quality = 4, legacy = true } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(DFB.masterFrame:IsShown()) -- Older quality return layout, above threshold.
DFB.masterFrame:Hide()
me = "Alice-Realm"
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(not DFB.masterFrame:IsShown())
me = master
loot = { { quality = 5 }, { link = "|Hcurrency:123|h[Currency]|h", quality = 5 } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(not DFB.masterFrame:IsShown())
threshold = 0
loot = { { link = link, quality = 0 } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(DFB.masterFrame:IsShown()) -- Gray loot qualifies when threshold permits it.
DFB.masterFrame:Hide()
threshold = 4
loot = { { link = link, quality = 3 } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(not DFB.masterFrame:IsShown()) -- Threshold is read afresh each session.
-- Party distributions use party chat; rejected starts never announce.
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end
GetLootMethod = function() return "master", 0 end
DFB.Open()
local announcementCount = #announcements
DFB.Start(link)
assert(#announcements == announcementCount + 2)
assert(announcements[#announcements].channel == "PARTY")
events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", "Upgrade", me)
assert(DFB.round.responses["master-realm"] == 3)
DFB.CloseRound()
events.scripts.OnEvent(nil, "CHAT_MSG_WHISPER", "BIS", me)
assert(not DFB.round)
SEPGP.GP.GetItemGP = function() return nil, "Item information not available" end
DFB.Start(link)
assert(#announcements == announcementCount + 2)
DFB.masterFrame:Hide()
DFB.Start(link)
assert(#announcements == announcementCount + 2)
-- Bag recipient notes follow the exact item instance, including identical
-- copies, bag moves, reloads, and cancelled/completed trades.
IsInRaid = function() return true end
GetLootMethod = function() return "master", nil, 1 end
local inventory = { ["0:1"] = "Item-A", ["0:2"] = "Item-B", ["0:3"] = "Item-C" }
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsBagAndSlot = function() return true end,
            GetBagAndSlot = function() return bag, slot end }
    end,
}
C_Item.GetItemGUID = function(location)
    return inventory[location.bag .. ":" .. location.slot]
end
C_Item.GetItemLocation = function(guid)
    for position, value in pairs(inventory) do
        if value == guid then
            local bag, slot = position:match("^(-?%d+):(%d+)$")
            return ItemLocation:CreateFromBagAndSlot(tonumber(bag), tonumber(slot))
        end
    end
end
SEPGP.GP.GetItemGP = function()
    return 101, { itemLevel = 104, rarity = 4, equipLoc = "INVTYPE_HEAD", slotModifier = 1 }
end
DFB.Open()
hooks.ContainerFrameItemButton_OnModifiedClick({
    GetParent = function() return { GetID = function() return 0 end } end,
    GetID = function() return 1 end,
}, "LeftButton")
assert(DFB.round.bagGUID == "Item-A")
DFB.RecordResponse(DFB.round.id, "Alice", 4)
DFB.Award()
assert(DFB.GetAwardRecipient("Item-A") == "Alice-Realm")
assert(not DFB.GetAwardRecipient("Item-B"))
DFB.Start(link, 0, 2)
DFB.RecordResponse(DFB.round.id, "Bob", 4)
DFB.Award()
assert(DFB.GetAwardRecipient("Item-B") == "Bob-Realm")
DFB.Start(link, 0, 3)
DFB.CloseRound()
assert(not DFB.GetAwardRecipient("Item-C")) -- Cancelled bidding adds no note.
DFB.Start(link)
DFB.RecordResponse(DFB.round.id, "Bob", 4)
DFB.Award()
assert(not DFB.GetAwardRecipient("Item-C")) -- Loot-window awards add no bag note.
inventory["0:1"], inventory["2:6"] = nil, "Item-A"
events.scripts.OnEvent(nil, "BAG_UPDATE_DELAYED")
assert(DFB.GetAwardRecipient("Item-A") == "Alice-Realm")
-- Tooltip callback displays only the relevant recipient, even if GP data is
-- temporarily unavailable. A hyperlink without an instance gets no note.
local tooltipCallback
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(_, callback) tooltipCallback = callback end,
}
dofile("SEPGP-Forever/tooltip.lua")
local function tooltipLines(guid)
    local lines = {}
    local tooltip = { AddLine = function(_, value) lines[#lines + 1] = value end,
        Show = function() end }
    tooltipCallback(tooltip, { guid = guid, hyperlink = link })
    return lines
end
assert(tooltipLines("Item-A")[1] == "SEPGP: Awarded to Alice-Realm")
assert(tooltipLines("Item-B")[1] == "SEPGP: Awarded to Bob-Realm")
assert(tooltipLines("Item-C")[1] == "SEPGP GP: 101")
assert(tooltipLines(nil)[1] == "SEPGP GP: 101")
SEPGP.SetGPTooltipEnabled(false)
assert(#tooltipLines(nil) == 0)
assert(#tooltipLines("Item-C") == 0)
local hiddenGP = tooltipLines("Item-A")
assert(#hiddenGP == 1 and hiddenGP[1] == "SEPGP: Awarded to Alice-Realm")
SEPGP.SetGPTooltipEnabled(true)
assert(tooltipLines(nil)[1] == "SEPGP GP: 101")
SEPGP.GP.GetItemGP = function() return nil end
assert(tooltipLines("Item-A")[1] == "SEPGP: Awarded to Alice-Realm")
me = "Alice-Realm"
assert(not DFB.GetAwardRecipient("Item-A")) -- Shared DB is character scoped.
me = master
dofile("SEPGP-Forever/dfb.lua") -- Module reload preserves saved assignments.
DFB = SEPGP.DFB
events = frames[#frames]
events.scripts.OnEvent(nil, "PLAYER_ENTERING_WORLD")
assert(DFB.GetAwardRecipient("Item-A") == "Alice-Realm")
-- Trade opening fills only the matching recipient's exact awarded instances.
local previousUnitName, previousAfter = GetUnitName, C_Timer.After
local partner, tradeItems, tradePositions, cursor, tradeTimers = "Alice-Realm", {}, {}, nil, {}
local locked, rejected, placements, clears = {}, {}, 0, 0
GetUnitName = function(unit, full)
    if unit == "NPC" then return partner end
    return previousUnitName(unit, full)
end
C_Timer.After = function(_, callback) tradeTimers[#tradeTimers + 1] = callback end
local function drainTradeTimers()
    while #tradeTimers > 0 do local callback = table.remove(tradeTimers, 1); callback() end
end
GetCursorInfo = function() if cursor then return "item", 123, link end end
GetTradePlayerItemLink = function(slot) if tradeItems[slot] then return link end end
C_Container.GetContainerItemInfo = function(bag, slot)
    return { isLocked = locked[inventory[bag .. ":" .. slot]] }
end
C_Container.PickupContainerItem = function(bag, slot)
    local position = bag .. ":" .. slot
    cursor = { guid = inventory[position], position = position }
    inventory[position] = nil
end
ClickTradeButton = function(slot)
    assert(slot >= 1 and slot <= 6 and not tradeItems[slot])
    if rejected[cursor.guid] then return end
    tradeItems[slot] = cursor.guid
    tradePositions[cursor.guid] = cursor.position
    cursor = nil
    placements = placements + 1
end
ClearCursor = function()
    clears = clears + 1
    inventory[cursor.position] = cursor.guid
    cursor = nil
end
local function cancelTrade()
    for _, guid in pairs(tradeItems) do
        if tradePositions[guid] then inventory[tradePositions[guid]] = guid end
    end
    tradeItems, tradePositions = {}, {}
    events.scripts.OnEvent(nil, "TRADE_CLOSED")
    drainTradeTimers()
end
local beforeTradeRevision = SEPGP_DB.revision
tradeItems[1] = "Manual item"
events.scripts.OnEvent(nil, "TRADE_SHOW")
drainTradeTimers()
assert(tradeItems[1] == "Manual item" and tradeItems[2] == "Item-A")
assert(inventory["0:2"] == "Item-B" and inventory["0:3"] == "Item-C")
assert(SEPGP_DB.revision == beforeTradeRevision)
events.scripts.OnEvent(nil, "BAG_UPDATE_DELAYED")
assert(DFB.GetAwardRecipient("Item-A") == "Alice-Realm")
events.scripts.OnEvent(nil, "TRADE_PLAYER_ITEM_CHANGED", 2)
assert(placements == 1)
cancelTrade()
assert(DFB.GetAwardRecipient("Item-A") == "Alice-Realm" and inventory["2:6"] == "Item-A")
partner = "Alice-OtherRealm"
events.scripts.OnEvent(nil, "TRADE_SHOW")
drainTradeTimers()
assert(placements == 1)
cancelTrade()
-- Existing cursor items are untouched; cancelled deferred fills cannot run later.
partner, cursor = "Alice-Realm", { guid = "User cursor item" }
events.scripts.OnEvent(nil, "TRADE_SHOW")
drainTradeTimers()
assert(placements == 1 and clears == 0 and cursor.guid == "User cursor item")
cancelTrade()
cursor = nil
events.scripts.OnEvent(nil, "TRADE_SHOW")
events.scripts.OnEvent(nil, "TRADE_CLOSED")
drainTradeTimers()
assert(placements == 1)
-- Find moved items, skip locks, and return rejected items without consuming a slot.
inventory["2:6"], inventory["3:1"] = nil, "Item-A"
inventory["0:4"], inventory["0:5"] = "Item-0", "Item-D"
DFB.GetBagAwards()["Item-0"] = { winner = partner, link = link }
DFB.GetBagAwards()["Item-D"] = { winner = partner, link = link }
rejected["Item-0"], locked["Item-D"] = true, true
events.scripts.OnEvent(nil, "TRADE_SHOW")
drainTradeTimers()
assert(tradeItems[1] == "Item-A" and inventory["0:4"] == "Item-0" and clears == 1)
locked["Item-D"] = false
events.scripts.OnEvent(nil, "ITEM_LOCK_CHANGED", 0, 5)
assert(tradeItems[2] == "Item-D")
cancelTrade()
-- Only six transferable slots are filled; excess awards stay in the bags.
for index = 1, 7 do
    local guid = "Extra-" .. index
    inventory["4:" .. index] = guid
    DFB.GetBagAwards()[guid] = { winner = partner, link = link }
end
events.scripts.OnEvent(nil, "TRADE_SHOW")
drainTradeTimers()
for slot = 1, 6 do assert(tradeItems[slot] == "Extra-" .. slot) end
assert(not tradeItems[7] and inventory["4:7"] == "Extra-7")
events.scripts.OnEvent(nil, "TRADE_CLOSED") -- Completed trade leaves offered items outside inventory.
drainTradeTimers()
assert(not DFB.GetAwardRecipient("Extra-1") and DFB.GetAwardRecipient("Extra-7") == partner)
tradeItems, tradePositions = {}, {}
inventory["3:1"], inventory["2:6"] = nil, "Item-A"
GetUnitName, C_Timer.After = previousUnitName, previousAfter
GetCursorInfo, GetTradePlayerItemLink, ClickTradeButton, ClearCursor = nil, nil, nil, nil

events.scripts.OnEvent(nil, "BAG_UPDATE_DELAYED") -- Cancelled trade keeps item.
assert(DFB.GetAwardRecipient("Item-A") == "Alice-Realm")
inventory["2:6"] = nil -- Completed trade removes that exact item instance.
events.scripts.OnEvent(nil, "BAG_UPDATE_DELAYED")
assert(not DFB.GetAwardRecipient("Item-A"))
assert(DFB.GetAwardRecipient("Item-B") == "Bob-Realm")
assert(#tooltipLines("Item-A") == 0)
-- Corpse assignment resolves candidate indices, freezes bidding while pending,
-- and never charges or announces a failed/stale assignment.
SEPGP.GP.GetItemGP = function() return 101 end
local corpse = { [7] = link }
GetNumLootItems = function() return 7 end
GetLootSlotLink = function(slot) return corpse[slot] end
GetLootSlotInfo = function() return "texture", "Item", 1, nil, 4, false end
local candidates = { [7] = { [3] = "Alice" } }
GetMasterLootCandidate = function(slot, index) return candidates[slot] and candidates[slot][index] end
events.scripts.OnEvent(nil, "LOOT_OPENED")
DFB.Start(link, nil, nil, 7)
DFB.RecordResponse(DFB.round.id, "Alice", 2)
local gpBefore = SEPGP_DB.players.alice.GP
local chatBefore, callsBefore = #announcements, #assignments
DFB.Award()
assert(#assignments == callsBefore + 1 and assignments[#assignments][2] == 3)
assert(SEPGP_DB.players.alice.GP == gpBefore and #announcements == chatBefore)
DFB.RecordResponse(DFB.round.id, "Bob", 1)
assert(not DFB.round.responses["bob-realm"])
DFB.Award()
assert(#assignments == callsBefore + 1)
events.scripts.OnEvent(nil, "LOOT_SLOT_CLEARED", 6)
assert(SEPGP_DB.players.alice.GP == gpBefore)
corpse[7] = nil
events.scripts.OnEvent(nil, "LOOT_SLOT_CLEARED", 7)
assert(not DFB.round and SEPGP_DB.players.alice.GP == gpBefore + 81)
assert(#announcements == chatBefore + 1)
events.scripts.OnEvent(nil, "LOOT_SLOT_CLEARED", 7)
assert(#announcements == chatBefore + 1)
-- A bidder absent from the per-item candidate list is not awarded or charged.
corpse[7] = link
DFB.Start(link, nil, nil, 7)
DFB.RecordResponse(DFB.round.id, "Bob", 1)
gpBefore, chatBefore, callsBefore = SEPGP_DB.players.bob.GP, #announcements, #assignments
DFB.Award()
assert(not DFB.round.pendingAward and #assignments == callsBefore)
assert(SEPGP_DB.players.bob.GP == gpBefore and #announcements == chatBefore)
DFB.CloseRound()
-- Closing the corpse or replacing its slot never assigns an unrelated item.
DFB.Start(link, nil, nil, 7)
DFB.RecordResponse(DFB.round.id, "Alice", 1)
corpse[7] = "|Hitem:456:0|h[Other item]|h"
DFB.Award()
assert(not DFB.round and #assignments == callsBefore)
corpse[7] = link
DFB.Start(link, nil, nil, 7)
events.scripts.OnEvent(nil, "LOOT_CLOSED")
DFB.Award()
assert(not DFB.round and #assignments == callsBefore)
-- Assignment API errors leave bidding open for correction without charging GP.
events.scripts.OnEvent(nil, "LOOT_OPENED")
DFB.Start(link, nil, nil, 7)
DFB.RecordResponse(DFB.round.id, "Alice", 1)
local giveLoot = GiveMasterLoot
GiveMasterLoot = function() error("Assignment rejected") end
chatBefore = #announcements
DFB.Award()
assert(DFB.round and not DFB.round.pendingAward and #announcements == chatBefore)
GiveMasterLoot = giveLoot
gpBefore = SEPGP_DB.players.alice.GP
DFB.Award()
assert(DFB.round.pendingAward)
events.scripts.OnEvent(nil, "UI_ERROR_MESSAGE", 1, "Unrelated combat error")
assert(DFB.round.pendingAward)
ERR_LOOT_MASTER_INV_FULL = "Recipient inventory is full"
events.scripts.OnEvent(nil, "UI_ERROR_MESSAGE", 2, ERR_LOOT_MASTER_INV_FULL)
assert(not DFB.round.pendingAward and SEPGP_DB.players.alice.GP == gpBefore)
assert(#announcements == chatBefore)
DFB.CloseRound()
-- Party awards use party chat as well as party start announcements.
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end
GetLootMethod = function() return "master", 0 end
DFB.Start(link)
DFB.RecordResponse(DFB.round.id, me, 4)
DFB.Award()
assert(announcements[#announcements].channel == "PARTY")
assert(announcements[#announcements].message:find("awarded to Master-Realm (Off Spec, 0 GP)", 1, true))
-- Custom buttons are snapshotted for the round and shared with bidders.
IsInRaid = function() return true end
GetLootMethod = function() return "master", nil, 1 end
DFB.Open()
local custom = SEPGP.Bids.Copy(SEPGP.Bids.GetSettings())
custom[1].label, custom[1].discount = "Main Spec", 25
custom[2].active = false
custom[5].label, custom[5].active = "Decline", false
assert(SEPGP.Bids.SetSettings(custom))
DFB.Start(link)
local customID = DFB.round.id
assert(DFB.round.choices[1].percent == 75)
assert(DFB.bidFrame.buttons[1].text:find("Main Spec", 1, true))
assert(not DFB.bidFrame.buttons[2]:IsShown() and not DFB.bidFrame.buttons[5]:IsShown())
assert(not announcements[#announcements].message:find("Alternative", 1, true))
local startPayload
for index = #sent, 1, -1 do
    local ok, payload = SEPGP:Deserialize(sent[index][2])
    if ok and payload.kind == "START" and payload.id == customID then startPayload = payload; break end
end
assert(startPayload.choices[1].discount == 25 and not startPayload.choices[2].active)
DFB.RecordResponse(customID, "Alice", 2)
assert(not DFB.round.responses["alice-realm"])
DFB.HandleWhisper("Alternative", "Alice")
assert(not DFB.round.responses["alice-realm"])
DFB.HandleWhisper(" MAIN   SPEC ", "Alice")
assert(DFB.round.responses["alice-realm"] == 1)
SEPGP.Bids.ResetSettings() -- Editing settings cannot change an existing award.
local beforeCustom = SEPGP_DB.players.alice.GP
DFB.Award()
assert(SEPGP_DB.players.alice.GP == beforeCustom + 76)
assert(announcements[#announcements].message:find("Main Spec, 76 GP", 1, true))
-- Remote popup uses the master's settings, even when local settings differ.
me = "Alice-Realm"
receive({ kind = "START", id = "custom-remote", link = link, gp = 101,
    choices = startPayload.choices }, "RAID", master)
assert(DFB.offer.choices[1].label == "Main Spec")
assert(not DFB.bidFrame.buttons[2]:IsShown())
local beforeDisabled = #sent
DFB.Respond(2)
assert(#sent == beforeDisabled and not DFB.offer.responded)
DFB.bidFrame:Hide() -- Automatic Pass still works with the Pass button hidden.
local ok, decline = SEPGP:Deserialize(sent[#sent][2])
assert(ok and decline.choice == 5)
receive({ kind = "CLOSE", id = "custom-remote" }, "RAID", master)
local invalidChoices = SEPGP.Bids.Copy(custom)
invalidChoices[1].discount = -1
receive({ kind = "START", id = "invalid-choices", link = link, gp = 101,
    choices = invalidChoices }, "RAID", master)
assert(not DFB.offer)
-- Old START messages continue to use the original defaults.
receive({ kind = "START", id = "legacy-choices", link = link, gp = 101 }, "RAID", master)
assert(DFB.offer.choices[1].label == "BiS" and DFB.bidFrame.buttons[2]:IsShown())
receive({ kind = "CLOSE", id = "legacy-choices" }, "RAID", master)
-- Class eligibility applies to incoming offers and to bids sent to the master.
local itemClass, itemSubclass, equipLoc, itemCached = 4, 4, "INVTYPE_CHEST", true
local localClass = "MAGE"
local savedUnitClass = UnitClass
UnitClass = function(unit)
    if unit == "player" then return localClass, localClass end
    return savedUnitClass(unit)
end
local requestedItem
C_Item.GetItemInfo = function()
    if not itemCached then return nil end
    return "Equipment", link, 4, 104, nil, nil, nil, nil, equipLoc, nil, nil, itemClass, itemSubclass
end
C_Item.RequestLoadItemDataByID = function(itemID) requestedItem = itemID end
local Eligibility = SEPGP.ItemEligibility
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "SHAMAN", "ROGUE", "DRUID", "MAGE", "PRIEST", "WARLOCK" }) do
    localClass = class
    assert(Eligibility.CanPlayerUse(link) == (class == "WARRIOR" or class == "PALADIN"))
end
localClass = "MAGE"
receive({ kind = "START", id = "plate-mage", link = link, gp = 101 }, "RAID", master)
assert(not DFB.bidFrame:IsShown() and DFB.offer.responded)
local ok, automaticPass = SEPGP:Deserialize(sent[#sent][2])
assert(ok and automaticPass.choice == 5 and automaticPass.id == "plate-mage")
receive({ kind = "CLOSE", id = "plate-mage" }, "RAID", master)
localClass = "WARRIOR"
receive({ kind = "START", id = "plate-warrior", link = link, gp = 101 }, "RAID", master)
assert(DFB.bidFrame:IsShown() and not DFB.bidFrame.compact)
receive({ kind = "CLOSE", id = "plate-warrior" }, "RAID", master)
itemClass, itemSubclass, equipLoc = 2, 7, "INVTYPE_WEAPON"
localClass = "DRUID"
assert(not Eligibility.CanPlayerUse(link))
receive({ kind = "START", id = "sword-druid", link = link, gp = 101 }, "RAID", master)
assert(not DFB.bidFrame:IsShown() and DFB.offer.responded)
receive({ kind = "CLOSE", id = "sword-druid" }, "RAID", master)
itemSubclass = 10 -- Staff is usable by druids.
receive({ kind = "START", id = "staff-druid", link = link, gp = 101 }, "RAID", master)
assert(DFB.bidFrame:IsShown())
receive({ kind = "CLOSE", id = "staff-druid" }, "RAID", master)
-- Current usability (level, trained skills, etc.) must not exclude compatible gear.
C_Item.IsUsableItem = function() return false, false end
assert(Eligibility.CanPlayerUse(link))
C_Item.IsUsableItem = function() return false, true end
assert(Eligibility.CanPlayerUse(link)) -- Lack of mana does not make a class ineligible.
C_Item.IsUsableItem = nil
-- Linen cloth is a trade good, not cloth armor. Everyone receives its popup.
itemClass, itemSubclass, equipLoc = 7, 1, ""
C_Item.IsUsableItem = function() return false, false end
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "SHAMAN", "ROGUE", "DRUID", "MAGE", "PRIEST", "WARLOCK" }) do
    localClass = class
    assert(Eligibility.CanPlayerUse(link))
    local id = "linen-" .. class
    receive({ kind = "START", id = id, link = link, gp = 101 }, "RAID", master)
    assert(DFB.bidFrame:IsShown() and not DFB.offer.responded)
    receive({ kind = "CLOSE", id = id }, "RAID", master)
end
-- Both druids and warriors can bid on one-handed maces even when IsUsableItem is false.
itemClass, itemSubclass, equipLoc = 2, 4, "INVTYPE_WEAPON"
for _, class in ipairs({ "DRUID", "WARRIOR" }) do
    localClass = class
    local id = "mace-" .. class
    receive({ kind = "START", id = id, link = link, gp = 101 }, "RAID", master)
    assert(DFB.bidFrame:IsShown() and not DFB.offer.responded)
    DFB.Respond(1)
    local ok, maceBid = SEPGP:Deserialize(sent[#sent][2])
    assert(ok and maceBid.id == id and maceBid.choice == 1)
    receive({ kind = "CLOSE", id = id }, "RAID", master)
end
C_Item.IsUsableItem = nil
-- Instant type metadata resolves uncached trade goods without auto-passing.
itemCached = false
C_Item.GetItemInfoInstant = function() return 123, "Trade Goods", "Cloth", "", nil, 7, 1 end
assert(Eligibility.CanPlayerUse(link))
C_Item.GetItemInfoInstant = nil
itemClass, itemSubclass, equipLoc, localClass = 2, 10, "INVTYPE_2HWEAPON", "DRUID"
-- Uncached items wait for data; closing a round prevents a late popup.
itemCached = false
receive({ kind = "START", id = "uncached", link = link, gp = 101 }, "RAID", master)
assert(DFB.offer.waitingData and not DFB.bidFrame:IsShown() and requestedItem == 123)
local sentBeforeFailedLoad = #sent
events.scripts.OnEvent(nil, "GET_ITEM_INFO_RECEIVED", 123, false)
assert(#sent == sentBeforeFailedLoad and not DFB.offer.responded and DFB.offer.waitingData)
itemCached = true
events.scripts.OnEvent(nil, "GET_ITEM_INFO_RECEIVED", 123, true)
assert(DFB.bidFrame:IsShown() and not DFB.offer.waitingData)
receive({ kind = "CLOSE", id = "uncached" }, "RAID", master)
itemCached = false
receive({ kind = "START", id = "closed-uncached", link = link, gp = 101 }, "RAID", master)
receive({ kind = "CLOSE", id = "closed-uncached" }, "RAID", master)
itemCached = true
events.scripts.OnEvent(nil, "GET_ITEM_INFO_RECEIVED", 123, true)
assert(not DFB.offer and not DFB.bidFrame:IsShown())
-- A master who cannot equip the item can distribute it, but automatically passes.
me, localClass = master, "MAGE"
itemClass, itemSubclass, equipLoc = 4, 4, "INVTYPE_CHEST"
DFB.Open()
DFB.Start(link)
assert(DFB.round and DFB.round.responses["master-realm"] == 5)
DFB.RecordResponse(DFB.round.id, "Alice", 1) -- Mage cannot bid on plate.
assert(not DFB.round.responses["alice-realm"])
DFB.RecordResponse(DFB.round.id, "Bob", 1)
assert(DFB.GetRankedBids()[1].name == "Bob-Realm")
DFB.CloseRound()
localClass = "WARRIOR"
DFB.Start(link)
assert(DFB.bidFrame:IsShown() and DFB.bidFrame.compact)
DFB.CloseRound()
output("DFB tests passed")
