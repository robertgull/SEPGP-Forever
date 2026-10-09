local output = print
print = function() end
local frames, loot, master, failStart = {}, {}, true, false
local function Frame()
    local f = { scripts = {}, shown = false, width = 250, height = 100, scroll = 0 }
    setmetatable(f, { __index = function() return function() end end })
    function f:SetScript(name, callback) self.scripts[name] = callback end
    function f:HookScript(name, callback)
        local previous = self.scripts[name]
        self.scripts[name] = function(...) if previous then previous(...) end; callback(...) end
    end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetText(text) self.text = text end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function f:IsShown() return self.shown end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:SetMovable(value) self.movable = value end
    function f:SetResizable(value) self.resizable = value end
    function f:SetResizeBounds(...) self.bounds = { ... } end
    function f:StartMoving() self.moving = true end
    function f:StartSizing() self.sizing = true end
    function f:StopMovingOrSizing() self.moving, self.sizing = false, false end
    function f:SetPoint(...) self.point = { ... } end
    function f:GetVerticalScroll() return self.scroll end
    function f:SetVerticalScroll(value) self.scroll = value end
    f.CreateFontString = Frame
    frames[#frames + 1] = f
    return f
end
CreateFrame, UIParent = Frame, {}
GameTooltip = { IsOwned = function() return false end }
SEPGP = { DFB = {}, ItemEligibility = {} }
local DFB = SEPGP.DFB
DFB.IsMaster = function() return master end
DFB.Refresh = function() end
DFB.Open = function()
    if not master then return end
    DFB.masterFrame = DFB.masterFrame or Frame()
    DFB.masterFrame:Show()
end
local starts = {}
DFB.Start = function(link, bag, bagSlot, slot)
    if failStart then return end
    assert(not bag and not bagSlot and GetLootSlotLink(slot) == link)
    starts[#starts + 1] = slot
    DFB.round = { link = link, lootSlot = slot }
    DFB.Refresh()
end
local threshold = 2
GetLootThreshold = function() return threshold end
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(slot) return loot[slot] and not loot[slot].cleared and loot[slot].link end
GetLootSlotInfo = function(slot)
    local item = loot[slot]
    if item.legacy then return nil, nil, nil, item.quality, false end
    return nil, nil, nil, nil, item.quality, false
end
local metadata = {}
SEPGP.ItemEligibility.GetInfo = function(link) return metadata[link] end
local sword, armor, potion, low, late = "|Hitem:1:|h[Sword]|h", "|Hitem:2:|h[Armor]|h",
    "|Hitem:3:|h[Potion]|h", "|Hitem:4:|h[Low]|h", "|Hitem:5:|h[Late]|h"
metadata[sword], metadata[armor] = { classID = 2, equipLoc = "INVTYPE_WEAPON" }, { classID = 4, equipLoc = "INVTYPE_CHEST" }
metadata[potion], metadata[low] = { classID = 0 }, metadata[sword]
loot = { { link = sword, quality = 2, legacy = true }, { link = potion, quality = 4 },
    { link = armor, quality = 4 }, { link = sword, quality = 3 },
    { link = low, quality = 1 }, { link = "|Hcurrency:1|h[Money]|h" }, { link = late, quality = 4 } }
dofile("SEPGP-Forever/LootQueue.lua")
local Queue, events = SEPGP.LootQueue, frames[#frames]
DFB.lootOpen, DFB.lootSession = true, 1
DFB.Open()
assert(#Queue.items == 3 and Queue.items[1].slot == 1 and Queue.items[3].slot == 4)
assert(Queue.frame.point[2] == DFB.masterFrame and Queue.frame.bid.enabled)
assert(Queue.frame.movable and Queue.frame.resizable)
Queue.frame.scripts.OnDragStart(Queue.frame)
assert(Queue.frame.moving)
Queue.frame.scripts.OnDragStop(Queue.frame)
assert(not Queue.frame.moving)
Queue.frame.resizeHandle.scripts.OnMouseDown(nil, "LeftButton")
assert(Queue.frame.sizing)
Queue.frame.resizeHandle.scripts.OnMouseUp()
assert(not Queue.frame.sizing)
Queue.frame.scripts.OnSizeChanged(Queue.frame, 400)
assert(Queue.frame.bid.width == 180 and Queue.frame.content.width == 340)
Queue.Scan(); assert(#Queue.items == 3) -- No duplicates on repeated events.
threshold = 4
Queue.Scan(); assert(#Queue.items == 1 and Queue.items[1].slot == 3)
threshold = 2
Queue.Scan(); assert(#Queue.items == 3)
failStart = true
Queue.frame.bid.scripts.OnClick()
assert(#Queue.items == 3 and not DFB.round) -- Failed bidding retains the head.
failStart = false
Queue.frame.bid.scripts.OnClick()
assert(starts[1] == 1 and #Queue.items == 2 and not Queue.frame.bid.enabled)
Queue.Skip(); Queue.BidNext()
assert(#Queue.items == 2 and #starts == 1) -- Never interrupt an active round.
DFB.round = nil
Queue.frame.skip.scripts.OnClick()
assert(#Queue.items == 1 and Queue.items[1].slot == 4)
Queue.Scan(); assert(#Queue.items == 1) -- Skipped items do not reappear.
metadata[late] = metadata[armor]
events.scripts.OnEvent(nil, "GET_ITEM_INFO_RECEIVED", 5, true)
assert(#Queue.items == 2 and Queue.items[2].slot == 7)
loot[4].cleared = true
events.scripts.OnEvent(nil, "LOOT_SLOT_CLEARED", 4)
assert(#Queue.items == 1 and Queue.items[1].slot == 7)
SEPGP.LootCollect = { queue = {} }
Queue.BidNext(); assert(#starts == 1 and not Queue.frame.bid.enabled)
SEPGP.LootCollect.queue = nil
Queue.BidNext(); assert(starts[2] == 7 and #Queue.items == 0)
DFB.round, DFB.lootOpen = nil, false
events.scripts.OnEvent(nil, "LOOT_CLOSED")
assert(#Queue.items == 0)
DFB.lootOpen, DFB.lootSession = true, 2
loot[4].cleared = false
Queue.Scan(); assert(#Queue.items == 4) -- A new corpse can contain identical links.
master = false
events.scripts.OnEvent(nil, "PARTY_LOOT_METHOD_CHANGED")
assert(#Queue.items == 0 and not Queue.frame.shown)
Queue.BidNext(); assert(#starts == 2)
master = true
DFB.Open()
DFB.masterFrame:Hide()
assert(not Queue.frame.shown)
output("Loot queue tests passed")
