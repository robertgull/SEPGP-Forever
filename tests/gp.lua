-- Run from the repository root: lua tests/gp.lua
SEPGP = {}
C_GuildInfo = { IsGuildOfficer = function() return true end }
dofile("SEPGP-Forever/SettingsData.lua")
SEPGP_DB = { players = { existing = { EP = 10, GP = 100 } } }
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

-- Formula controls affect real item costs and use floor, including fractional GP.
assert(GP.Calculate(100, 4, 1) == 115)
assert(GP.SetFormulaSettings(10, 3, 0.5))
cached, quality, slot, detailed = true, 4, "INVTYPE_HEAD", 26
assert(GP.GetItemGP("item:123") == 15)
assert(SEPGP_DB.players.existing.GP == 100)
assert(not GP.SetFormulaSettings(99, 0, 1))
assert(not GP.SetFormulaSettings(-1, 2, 1))
assert(not GP.SetFormulaSettings(8, 2, -1))
assert(not GP.SetFormulaSettings("8", 2, 1))
assert(not GP.SetFormulaSettings(math.huge, 2, 1))
assert(not GP.SetFormulaSettings(8, 0 / 0, 1))
assert(GP.GetItemGP("item:123") == 15) -- Invalid edits leave all values intact.
SEPGP.GP = {}
dofile("SEPGP-Forever/GP.lua")
GP = SEPGP.GP
assert(GP.GetItemGP("item:123") == 15) -- Saved settings survive module reload.
SEPGP_DB.settings.gp.Multiplier = "invalid"
assert(GP.GetFormulaSettings().Multiplier == 2)
assert(GP.GetFormulaSettings().Base == 10)
assert(GP.SetFormulaSettings(0, 2, 1))
assert(GP.Calculate(26, 4, 1) == 0)
assert(GP.ResetFormulaSettings())
assert(GP.Calculate(26, 4, 1) == 16)
assert(GP.SetFormulaSettings(8, 1e308, 1))
assert(GP.Calculate(104, 4, 1) == nil) -- Overflow must not become an item cost.
GP.ResetFormulaSettings()
print("GP tests passed")
