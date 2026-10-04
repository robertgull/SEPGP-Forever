-- Collect corpse loot into the master looter's bags for later DFB awards.
SEPGP.LootCollect = {}
local Collect = SEPGP.LootCollect

local function NameKey(name)
    if not name then return nil end
    if not name:find("-", 1, true) then name = name .. "-" .. GetNormalizedRealmName() end
    return name:lower()
end

function Collect.UpdateButton()
    if not Collect.button and LootFrame then
        local button = CreateFrame("Button", nil, LootFrame, "UIPanelButtonTemplate")
        button:SetSize(150, 26)
        button:SetPoint("TOP", LootFrame, "BOTTOM", 0, 0)
        button:SetScript("OnClick", function() Collect.TakeEverything() end)
        Collect.button = button
    end
    local button = Collect.button
    if not button then return end
    if Collect.open and SEPGP.DFB.IsMaster() then
        button:Show()
        button:SetText(Collect.queue and "Collecting..." or "Take everything")
        local round = SEPGP.DFB.round
        if Collect.queue or (round and round.lootSlot and round.pendingAward) then button:Disable()
        else button:Enable() end
    else button:Hide() end
end

local function Stop(message)
    Collect.queue = nil
    Collect.UpdateButton()
    if message then print("SEPGP: " .. message) end
end

function Collect.Next()
    local queue = Collect.queue
    if not queue or queue.pending then return end
    if not Collect.open or queue.session ~= Collect.session or not SEPGP.DFB.IsMaster() then Stop(); return end
    while #queue.items > 0 do
        local item = table.remove(queue.items, 1)
        local currentLink = GetLootSlotLink(item.slot)
        local slotType = GetLootSlotType and GetLootSlotType(item.slot)
        local present = currentLink ~= nil
        if slotType ~= nil then present = slotType ~= 0 end
        if present and currentLink == item.link then
            local _, _, _, fourth, fifth, sixth = GetLootSlotInfo(item.slot)
            local quality = type(fifth) == "number" and fifth or fourth
            local locked = type(fifth) == "boolean" and fifth or sixth
            if not locked then
                local candidate
                if item.link and item.link:match("|Hitem:%d+:") and GetMasterLootCandidate then
                    for index = 1, (MAX_RAID_MEMBERS or 40) do
                        if NameKey(GetMasterLootCandidate(item.slot, index)) == queue.owner then candidate = index; break end
                    end
                end
                local getThreshold = GetLootThreshold or (C_PartyInfo and C_PartyInfo.GetLootThreshold)
                local threshold = getThreshold and getThreshold()
                local requiresMaster = item.link and item.link:match("|Hitem:%d+:")
                    and type(quality) == "number" and type(threshold) == "number" and quality >= threshold
                if requiresMaster and not candidate then
                    queue.skipped = queue.skipped + 1
                else
                    queue.pending = item
                    local ok, err
                    if candidate and GiveMasterLoot then ok, err = pcall(GiveMasterLoot, item.slot, candidate)
                    elseif not requiresMaster and LootSlot then ok, err = pcall(LootSlot, item.slot)
                    else ok, err = false, "Loot assignment is unavailable" end
                    if not ok then Stop("Could not collect loot: " .. tostring(err)); return end
                    return -- Continue only after the game confirms this slot was cleared.
                end
            else queue.skipped = queue.skipped + 1 end
        end
    end
    local message = queue.skipped > 0 and (queue.skipped .. " loot slots could not be collected. They remain on the corpse.") or nil
    Stop(message)
end

function Collect.TakeEverything()
    if not Collect.open or Collect.queue or not SEPGP.DFB.IsMaster() then return end
    local owner = NameKey(GetUnitName("player", true))
    if not owner then return end
    local round = SEPGP.DFB.round
    if round and round.lootSlot then
        if round.pendingAward then return end
        SEPGP.DFB.CloseRound() -- Cancel unawarded corpse bids before moving their items.
    end
    local queue = { session = Collect.session, owner = owner, items = {}, skipped = 0 }
    for slot = GetNumLootItems(), 1, -1 do
        queue.items[#queue.items + 1] = { slot = slot, link = GetLootSlotLink(slot) }
    end
    Collect.queue = queue
    Collect.UpdateButton()
    Collect.Next()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "LOOT_OPENED", "LOOT_CLOSED",
    "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_BIND_CONFIRM", "UI_ERROR_MESSAGE",
    "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "LOOT_OPENED" then
        Collect.queue = nil
        Collect.session = (Collect.session or 0) + 1
        Collect.open = true
    elseif event == "LOOT_CLOSED" then
        Collect.open, Collect.queue = false, nil
    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        local queue = Collect.queue
        if queue and queue.pending and queue.pending.slot == slot then
            queue.pending = nil
            Collect.Next()
        end
    elseif event == "LOOT_BIND_CONFIRM" then
        local slot = ...
        local queue = Collect.queue
        if queue and queue.pending and queue.pending.slot == slot and ConfirmLootSlot then ConfirmLootSlot(slot) end
    elseif event == "UI_ERROR_MESSAGE" and Collect.queue then
        local _, message = ...
        for _, name in ipairs({ "ERR_INV_FULL", "ERR_ITEM_MAX_COUNT", "ERR_LOOT_MASTER_INV_FULL",
            "ERR_LOOT_MASTER_UNIQUE_ITEM", "ERR_LOOT_MASTER_OTHER", "ERR_LOOT_GONE", "ERR_LOOT_LOCKED",
            "ERR_LOOT_CANT_LOOT_THAT_NOW", "ERR_LOOT_TOO_FAR", "ERR_LOOT_PLAYER_NOT_FOUND" }) do
            if _G[name] and message == _G[name] then Stop("Collection stopped: " .. message); break end
        end
    elseif event == "PARTY_LOOT_METHOD_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
        if Collect.queue and not SEPGP.DFB.IsMaster() then Stop() end
    end
    Collect.UpdateButton()
end)
