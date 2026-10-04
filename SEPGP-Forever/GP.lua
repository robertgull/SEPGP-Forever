-- =========================================================
-- SEPGP Forever - GP Calculation
-- =========================================================

SEPGP = SEPGP or {}
SEPGP.GP = SEPGP.GP or {}

local FORMULA_DEFAULTS = { Base = 8, Multiplier = 2, Mod = 1 }

function SEPGP.GP.IsValidFormulaValue(key, value)
    return FORMULA_DEFAULTS[key] ~= nil
        and type(value) == "number"
        and value == value and value < math.huge
        and (value > 0 or (value == 0 and key ~= "Multiplier"))
end

function SEPGP.GP.GetFormulaSettings()
    SEPGP_DB = SEPGP_DB or {}
    if type(SEPGP_DB.settings) ~= "table" then SEPGP_DB.settings = {} end
    if type(SEPGP_DB.settings.gp) ~= "table" then SEPGP_DB.settings.gp = {} end
    local settings = SEPGP_DB.settings.gp
    for key, default in pairs(FORMULA_DEFAULTS) do
        if not SEPGP.GP.IsValidFormulaValue(key, settings[key]) then
            settings[key] = default
        end
    end
    return settings
end

function SEPGP.GP.SetFormulaSettings(base, multiplier, mod)
    if not SEPGP.CanEditOfficerSettings() then
        return false, "Only guild officers can change the GP formula."
    end
    if not SEPGP.GP.IsValidFormulaValue("Base", base)
        or not SEPGP.GP.IsValidFormulaValue("Multiplier", multiplier)
        or not SEPGP.GP.IsValidFormulaValue("Mod", mod) then
        return false, "Base and mod must be finite numbers >= 0; multiplier must be > 0."
    end
    local settings = SEPGP.GP.GetFormulaSettings()
    settings.Base, settings.Multiplier, settings.Mod = base, multiplier, mod
    return true
end

function SEPGP.GP.ResetFormulaSettings()
    return SEPGP.GP.SetFormulaSettings(
        FORMULA_DEFAULTS.Base, FORMULA_DEFAULTS.Multiplier, FORMULA_DEFAULTS.Mod)
end

local SLOT_MODIFIERS = {
    INVTYPE_HEAD = 1.00,
    INVTYPE_NECK = 0.50,
    INVTYPE_SHOULDER = 0.75,
    INVTYPE_CLOAK = 0.50,
    INVTYPE_CHEST = 1.00,
    INVTYPE_ROBE = 1.00,
    INVTYPE_WRIST = 0.50,
    INVTYPE_HAND = 0.75,
    INVTYPE_WAIST = 0.75,
    INVTYPE_LEGS = 1.00,
    INVTYPE_FEET = 0.75,

    INVTYPE_FINGER = 0.50,
    INVTYPE_TRINKET = 0.75,

    INVTYPE_WEAPONMAINHAND = 1.50,
    INVTYPE_WEAPONOFFHAND = 0.50,
    INVTYPE_HOLDABLE = 0.50,
    INVTYPE_WEAPON = 1.50,
    INVTYPE_2HWEAPON = 2.00,

    INVTYPE_SHIELD = 0.50,

    INVTYPE_RANGED = 2.00,
    INVTYPE_THROWN = 0.50,
    INVTYPE_RELIC = 0.50,
    INVTYPE_RANGEDRIGHT = 0.50,
}



function SEPGP.GP.GetSlotModifier(equipLoc)
    return SLOT_MODIFIERS[equipLoc] or 0.50
end



function SEPGP.GP.Calculate(itemLevel, rarity, slotModifier)
    if type(itemLevel) ~= "number" then
        return nil, "Invalid item level"
    end

    if type(rarity) ~= "number" then
        return nil, "Invalid rarity"
    end

    if type(slotModifier) ~= "number" then
        return nil, "Invalid slot modifier"
    end

    local settings = SEPGP.GP.GetFormulaSettings()
    local gp = settings.Base
        * (settings.Multiplier ^ ((itemLevel / 26) + (rarity - 4)))
        * slotModifier * settings.Mod

    if gp ~= gp or gp == math.huge or gp == -math.huge then
        return nil, "GP formula result is not finite"
    end

    -- Store/display GP as an integer.
    return math.floor(gp)
end


function SEPGP.GP.GetItemGP(itemLink)
    if not itemLink then
        return nil, "No item link"
    end

    local itemName,
          _,
          itemQuality,
          baseItemLevel,
          _,
          _,
          _,
          _,
          itemEquipLoc,
          _,
          _,
          classID,
          subclassID =
        C_Item.GetItemInfo(itemLink)

    if not itemName then
        return nil, "Item information not available"
    end

    -- GP is defined for Poor (gray) -> Legendary.
    if not itemQuality
        or itemQuality < 0
        or itemQuality > 5 then
        return nil, "Unsupported item quality"
    end

    local slotModifier = SEPGP.GP.GetSlotModifier(itemEquipLoc)

    local itemLevel =
        C_Item.GetDetailedItemLevelInfo(itemLink)

    -- Fallback just in case detailed item level isn't available.
    itemLevel = itemLevel or baseItemLevel

    if not itemLevel then
        return nil, "Item level not available"
    end

    local gp, err =
        SEPGP.GP.Calculate(
            itemLevel,
            itemQuality,
            slotModifier
        )

    if not gp then
        return nil, err
    end

    return gp, {
        itemLevel = itemLevel,
        rarity = itemQuality,
        equipLoc = itemEquipLoc,
        slotModifier = slotModifier,
        classID = classID,
        subclassID = subclassID,
    }
end
