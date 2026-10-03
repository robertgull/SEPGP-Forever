-- Run from the repository root: lua tests/gp.lua
SEPGP = {}
dofile("SEPGP-Forever/GP.lua")
local quality, slot, cached, detailed = 0, "", true, 104
C_Item = {
    GetItemInfo = function()
        if not cached then return nil end
        return "Test item", "item:123", quality, 104, nil, nil, nil, nil, slot
    end,
    GetDetailedItemLevelInfo = function() return detailed end,
}
local GP = SEPGP.GP
local gp, info = GP.GetItemGP("item:123")
assert(gp == 4 and info.rarity == 0 and info.slotModifier == 0.5)
assert(GP.GetSlotModifier(nil) == 0.5)
assert(GP.GetSlotModifier("") == 0.5)
assert(GP.GetSlotModifier("INVTYPE_UNKNOWN") == 0.5)
assert(GP.GetSlotModifier("INVTYPE_RANGEDRIGHT") == 0.5)
assert(GP.GetSlotModifier("INVTYPE_HEAD") == 1)
assert(GP.GetSlotModifier("INVTYPE_2HWEAPON") == 2)
slot = "INVTYPE_UNKNOWN"
assert(GP.GetItemGP("item:123") == 4)
slot = "INVTYPE_HEAD"
assert(GP.GetItemGP("item:123") == 8)
quality = 4
assert(GP.GetItemGP("item:123") == 128)
slot = ""
assert(GP.GetItemGP("item:123") == 64)
detailed = nil
assert(GP.GetItemGP("item:123") == 64) -- Base item-level fallback.
quality = -1
assert(GP.GetItemGP("item:123") == nil)
quality = 6
assert(GP.GetItemGP("item:123") == nil)
cached = false
assert(GP.GetItemGP("item:123") == nil)
print("GP tests passed")
