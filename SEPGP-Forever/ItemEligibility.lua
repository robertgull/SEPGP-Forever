-- Vanilla class proficiencies, independent of the player's current weapon skill.
SEPGP.ItemEligibility = {}
local Eligibility = SEPGP.ItemEligibility
local armorMaximum = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3,
    ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local weapons = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID = { 4, 5, 10, 13, 15 },
}
local weaponSets = {}
for class, subclasses in pairs(weapons) do
    weaponSets[class] = {}
    for _, subclass in ipairs(subclasses) do weaponSets[class][subclass] = true end
end
local shields = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local relics = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

function Eligibility.GetInfo(link)
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getInfo then return {} end
    local name, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = getInfo(link)
    -- Instant metadata can resolve the class/subclass while the full item is uncached.
    local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if getInstant then
        local itemID, _, _, instantEquipLoc, _, instantClass, instantSubclass = getInstant(link)
        if itemID and instantClass ~= nil then
            return { equipLoc = instantEquipLoc, classID = instantClass, subclassID = instantSubclass }
        end
    end
    if not name then return nil end
    return { equipLoc = equipLoc, classID = classID, subclassID = subclassID }
end

function Eligibility.CanClassUse(class, info)
    if not info or not armorMaximum[class] then return true end
    -- Trade goods, consumables, and other non-equipment are open to every class.
    if info.classID ~= 2 and info.classID ~= 4 then return true end
    if info.classID == 4 then -- Armor, including shields and class relics.
        local subclass = info.subclassID
        if subclass and subclass >= 1 and subclass <= 4 then
            return subclass <= armorMaximum[class]
        elseif subclass == 6 then return shields[class] or false
        elseif relics[subclass] then return relics[subclass] == class end
    elseif info.classID == 2 and info.subclassID ~= nil then -- Weapons.
        -- Fishing poles and miscellaneous weapons do not have class restrictions.
        if info.subclassID == 20 or info.subclassID == 14 then return true end
        return weaponSets[class][info.subclassID] or false
    end
    return true
end

function Eligibility.CanPlayerUse(link)
    local info = Eligibility.GetInfo(link)
    if not info then return nil end -- Wait for the game's item data before deciding.
    local _, class
    if UnitClass then _, class = UnitClass("player") end
    if not Eligibility.CanClassUse(class, info) then return false end
    -- Current usability also depends on level and trained skills, which should
    -- not prevent bidding on an item the class can equip after leveling/training.
    return true
end
