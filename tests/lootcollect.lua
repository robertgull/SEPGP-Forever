-- Run from the repository root: lua tests/lootcollect.lua
local output = print
print = function() end
local master, owner = true, "Master-Realm"
local frames = {}
CreateFrame = function(_, _, parent)
    local frame = { scripts = {}, parent = parent }
    setmetatable(frame, { __index = function() return function() end end })
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:SetText(text) self.text = text end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:Enable() self.enabled = true end
    function frame:Disable() self.enabled = false end
    frames[#frames + 1] = frame
    return frame
end
LootFrame = {}
GetNormalizedRealmName = function() return "Realm" end
GetUnitName = function() return owner end
local closedRounds = 0
SEPGP = { DFB = { IsMaster = function() return master end } }
SEPGP.DFB.CloseRound = function() closedRounds = closedRounds + 1; SEPGP.DFB.round = nil end
local loot = {}
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(slot) return loot[slot] and not loot[slot].cleared and loot[slot].link or nil end
GetLootSlotType = function(slot) return loot[slot] and not loot[slot].cleared and loot[slot].kind or 0 end
GetLootSlotInfo = function(slot)
    local item = loot[slot]
    if item.legacy then return "icon", "Loot", 1, item.quality, item.locked end
    return "icon", "Loot", 1, item.currency, item.quality, item.locked
end
GetLootThreshold = function() return 2 end
GetMasterLootCandidate = function(slot, index)
    if loot[slot].candidate and index == loot[slot].candidate then return "Master" end
end
local assignments, pickups, binds = {}, {}, {}
GiveMasterLoot = function(slot, index) assignments[#assignments + 1] = { slot, index } end
LootSlot = function(slot) pickups[#pickups + 1] = slot end
ConfirmLootSlot = function(slot) binds[#binds + 1] = slot end
SEPGP_DB = { revision = 5, players = { master = { EP = 100, GP = 100 } } }
dofile("SEPGP-Forever/LootCollect.lua")
local Collect, events = SEPGP.LootCollect, frames[#frames]
events.scripts.OnEvent(nil, "PLAYER_LOGIN")
assert(Collect.button.parent == LootFrame and not Collect.button.shown)
local link = "|Hitem:123:0|h[Item]|h"
loot = {
    { kind = 3, link = "|Hcurrency:1|h[Currency]|h", currency = 1 },
    { kind = 1, link = link, quality = 0, legacy = true },
    { kind = 2 },
    { kind = 1, link = link, quality = 4, candidate = 3 },
    { kind = 1, link = link, quality = 4 },
    { kind = 1, link = link, quality = 0, locked = true },
}
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(Collect.button.shown and Collect.button.enabled)
SEPGP.DFB.round = { lootSlot = 4 }
Collect.button.scripts.OnClick()
assert(closedRounds == 1 and not Collect.button.enabled)
assert(#assignments == 1 and assignments[1][1] == 4 and assignments[1][2] == 3)
assert(#pickups == 0 and Collect.queue.pending.slot == 4)
Collect.button.scripts.OnClick()
assert(#assignments == 1) -- Repeated clicks never duplicate assignment.
local function clear(slot)
    loot[slot].cleared = true
    events.scripts.OnEvent(nil, "LOOT_SLOT_CLEARED", slot)
end
clear(6)
assert(#pickups == 0) -- Only the pending item's confirmation advances collection.
clear(4)
assert(pickups[1] == 3)
clear(3)
assert(pickups[2] == 2)
events.scripts.OnEvent(nil, "LOOT_BIND_CONFIRM", 1)
assert(#binds == 0)
events.scripts.OnEvent(nil, "LOOT_BIND_CONFIRM", 2)
assert(binds[1] == 2)
clear(2)
assert(pickups[3] == 1)
clear(1)
assert(not Collect.queue and Collect.button.enabled)
assert(not loot[5].cleared and SEPGP_DB.revision == 5 and SEPGP_DB.players.master.GP == 100)
-- Members and unknown player identities cannot collect on the master's behalf.
master = false
events.scripts.OnEvent(nil, "PARTY_LOOT_METHOD_CHANGED")
assert(not Collect.button.shown)
Collect.TakeEverything()
assert(not Collect.queue)
master, owner = true, nil
Collect.TakeEverything()
assert(not Collect.queue)
owner = "Master-Realm"
-- Pending awards are not interrupted, and full bags stop the collection queue.
loot = { { kind = 1, link = link, quality = 0 }, { kind = 1, link = link, quality = 0 } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
SEPGP.DFB.round = { lootSlot = 1, pendingAward = {} }
Collect.UpdateButton()
assert(not Collect.button.enabled)
Collect.TakeEverything()
assert(not Collect.queue)
SEPGP.DFB.round = nil
Collect.TakeEverything()
local beforeError = #pickups
ERR_INV_FULL = "Inventory is full"
events.scripts.OnEvent(nil, "UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
assert(not Collect.queue and Collect.button.enabled)
clear(2)
assert(#pickups == beforeError)
-- Closing/replacing a corpse cancels queued actions; loss of master status stops too.
Collect.TakeEverything()
events.scripts.OnEvent(nil, "LOOT_CLOSED")
local beforeClose = #pickups
clear(1)
assert(not Collect.queue and not Collect.button.shown and #pickups == beforeClose)
loot = { { kind = 1, link = link, quality = 0 } }
events.scripts.OnEvent(nil, "LOOT_OPENED")
Collect.TakeEverything()
events.scripts.OnEvent(nil, "LOOT_OPENED")
assert(not Collect.queue)
Collect.TakeEverything()
master = false
events.scripts.OnEvent(nil, "PARTY_LOOT_METHOD_CHANGED")
assert(not Collect.queue and not Collect.button.shown)
output("Loot collection tests passed")
