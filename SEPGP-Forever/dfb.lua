-- Distribute from bags or the loot window. The master computes all standings/GP.
SEPGP.DFB = {}
local DFB = SEPGP.DFB
local PREFIX = "SEPGPF_DFB"
local AceComm = LibStub("AceComm-3.0")
AceComm:Embed(DFB)

DFB.choices = {
    { label = "BiS", percent = 100 },
    { label = "Alternative", percent = 80 },
    { label = "Upgrade", percent = 50 },
    { label = "Off Spec", percent = 0 },
    { label = "Pass", percent = 0 },
}
DFB.seen = {}

local function NameKey(name)
    if type(name) ~= "string" then return nil end
    if not name:find("-", 1, true) then
        name = name .. "-" .. GetNormalizedRealmName()
    end
    return string.lower(name)
end

-- Keep assignments local to the owning character and keyed by item instance,
-- so moving an item or holding several identical copies cannot mix recipients.
function DFB.GetBagAwards()
    local owner = NameKey(GetUnitName("player", true))
    if not owner then return {} end
    SEPGP_DB.bagAwards = SEPGP_DB.bagAwards or {}
    SEPGP_DB.bagAwards[owner] = SEPGP_DB.bagAwards[owner] or {}
    return SEPGP_DB.bagAwards[owner]
end

function DFB.GetBagItemGUID(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number"
        or not ItemLocation or not C_Item or not C_Item.GetItemGUID then return nil end
    return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
end

function DFB.GetAwardRecipient(guid)
    if not guid then return nil end
    local award = DFB.GetBagAwards()[guid]
    return award and award.winner
end

function DFB.PruneBagAwards()
    if not C_Item or not C_Item.GetItemLocation or not C_Item.GetItemGUID then return end
    local awards = DFB.GetBagAwards()
    for guid in pairs(awards) do
        local location = C_Item.GetItemLocation(guid)
        if not location or C_Item.GetItemGUID(location) ~= guid then
            awards[guid] = nil
        end
    end
end

function DFB.GetRoster()
    local roster = {}
    local function add(unit)
        local name = GetUnitName(unit, true)
        if name then roster[NameKey(name)] = name end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    end
    return roster
end

function DFB.GetMaster()
    if not IsInGroup() then return nil end
    local getLootMethod = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
    if not getLootMethod then return nil end
    local method, partyIndex, raidIndex = getLootMethod()
    local masterMethod = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
    if method ~= "master" and (not masterMethod or method ~= masterMethod) then return nil end
    local unit
    if raidIndex and raidIndex > 0 then
        unit = "raid" .. raidIndex
    elseif partyIndex == 0 then
        unit = "player"
    elseif partyIndex and partyIndex > 0 then
        unit = "party" .. partyIndex
    end
    return unit and GetUnitName(unit, true)
end

function DFB.IsMaster()
    local master = DFB.GetMaster()
    return master and NameKey(master) == NameKey(GetUnitName("player", true))
end

local function Channel()
    return IsInRaid() and "RAID" or "PARTY"
end

function DFB.Send(payload, target)
    if not target and not IsInGroup() then return end
    payload.version = 1
    DFB:SendCommMessage(PREFIX, SEPGP:Serialize(payload),
        target and "WHISPER" or Channel(), target, "NORMAL")
end

-- Existing databases also contain same-realm names without a realm suffix.
local function StandingName(name)
    local key = NameKey(name)
    if SEPGP.GetPlayer(key) then return key end
    local short, realm = key:match("^([^-]+)%-(.+)$")
    if realm == string.lower(GetNormalizedRealmName()) and SEPGP.GetPlayer(short) then
        return short
    end
    return key
end

function DFB.GetRankedBids()
    local bids = {}
    local round = DFB.round
    if not round then return bids end
    local roster = DFB.GetRoster()
    for key, choice in pairs(round.responses) do
        if choice < 5 and roster[key] then
            local name = round.eligible[key]
            bids[#bids + 1] = {
                name = name, player = StandingName(name), choice = choice,
                pr = SEPGP.GetPR(StandingName(name)),
            }
        end
    end
    table.sort(bids, function(a, b)
        if a.choice ~= b.choice then return a.choice < b.choice end
        if a.pr ~= b.pr then return a.pr > b.pr end
        return NameKey(a.name) < NameKey(b.name)
    end)
    return bids
end

local function Cost(gp, choice)
    return math.floor(gp * DFB.choices[choice].percent / 100 + 0.5)
end

local function Label(frame, text, x, y, width)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Button(frame, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function Window(name, title, width, height)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
        tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Label(frame, title, 20, -18, width - 60)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:Hide()
    return frame
end

function DFB.Refresh()
    local frame = DFB.masterFrame
    if not frame then return end
    local round = DFB.round
    if not round then
        frame.itemDetails:Hide()
        frame:SetHeight(470)
        frame.item:SetText("Shift-click an item in your bags or the loot window to start bidding.")
        frame.status:SetText("Award assigns corpse loot automatically. Trade bag items after awarding.")
        frame.bids:SetText("")
        frame.award:Disable()
        frame.cancel:Disable()
        return
    end
    frame.item:SetText(round.link .. "\nBase GP: " .. round.gp)
    -- Use the game's complete item tooltip rather than reconstructing stats,
    -- bonuses, sockets and item type from partial item-info APIs.
    local details = frame.itemDetails
    details:SetOwner(frame, "ANCHOR_NONE")
    details:ClearLines()
    if round.bagGUID and details.SetItemByGUID then
        details:SetItemByGUID(round.bagGUID)
    else
        details:SetHyperlink(round.link)
    end
    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", frame, "TOPLEFT", 590, -55)
    details:Show()
    frame:SetHeight(math.max(470, (details:GetHeight() or 0) + 85))
    if round.pendingAward then
        frame.status:SetText("Assigning loot to " .. round.pendingAward.name .. "...")
        frame.award:Disable()
        frame.cancel:Disable()
        return
    end
    local count, total = 0, 0
    for _ in pairs(round.eligible) do total = total + 1 end
    for _ in pairs(round.responses) do count = count + 1 end
    frame.status:SetText(string.format("Responses: %d/%d. Highest category wins, then EP/GP.\nEqual ratios use alphabetical name order. Close bidding with Award.", count, total))
    local lines = {}
    local ranked = DFB.GetRankedBids()
    for i, bid in ipairs(ranked) do
        lines[#lines + 1] = string.format("%d. %s - %s | PR %.3f | %d GP", i,
            bid.name, DFB.choices[bid.choice].label, bid.pr, Cost(round.gp, bid.choice))
    end
    for key, choice in pairs(round.responses) do
        if choice == 5 then lines[#lines + 1] = round.eligible[key] .. " - Pass" end
    end
    frame.bids:SetText(table.concat(lines, "\n"))
    frame.bids:SetHeight(math.max(260, #lines * 18))
    if #ranked > 0 then frame.award:Enable() else frame.award:Disable() end
    frame.cancel:Enable()
end

function DFB.CloseRound(winner, amount)
    local round = DFB.round
    if not round then return end
    if round.pendingAward then return end
    DFB.round = nil
    DFB.Send({ kind = "CLOSE", id = round.id, winner = winner, amount = amount })
    if DFB.offer and DFB.offer.id == round.id then
        DFB.offer = nil
        if DFB.bidFrame then DFB.bidFrame:Hide() end
    end
    DFB.Refresh()
end

function DFB.CompleteAward(round, winner)
    if DFB.round ~= round then return end
    round.pendingAward = nil
    local amount = Cost(round.gp, winner.choice)
    local reason = "DFB: " .. round.link .. " (" .. DFB.choices[winner.choice].label .. ")"
    -- AddGP clamps GP to BASE_GP; a free award must preserve decayed GP too.
    if amount > 0 and not SEPGP.AddGP(winner.player, amount, reason) then return end
    if round.bagGUID then
        DFB.GetBagAwards()[round.bagGUID] = { winner = winner.name, link = round.link }
    end
    DFB.CloseRound(winner.name, amount)
    local message = string.format("SEPGP: %s awarded to %s (%s, %d GP).",
        round.link, winner.name, DFB.choices[winner.choice].label, amount)
    SendChatMessage(message, Channel())
    print(message .. (round.lootSlot and "" or " Trade the item to the winner."))
end

function DFB.Award()
    local round = DFB.round
    if not round or round.pendingAward then return end
    if not DFB.IsMaster() then DFB.CloseRound(); return end
    local winner = DFB.GetRankedBids()[1]
    if not winner then print("SEPGP: No eligible bids. Cancel or wait for responses."); return end
    if not round.lootSlot then DFB.CompleteAward(round, winner); return end
    if not DFB.lootOpen or round.lootSession ~= DFB.lootSession
        or GetLootSlotLink(round.lootSlot) ~= round.link then
        print("SEPGP: That corpse item is no longer available. No GP charged.")
        DFB.CloseRound()
        return
    end
    if not GetMasterLootCandidate or not GiveMasterLoot then
        print("SEPGP: Master-loot assignment is unavailable. No GP charged.")
        return
    end
    for index = 1, (MAX_RAID_MEMBERS or 40) do
        local candidate = GetMasterLootCandidate(round.lootSlot, index)
        if candidate and NameKey(candidate) == NameKey(winner.name) then
            -- Charge/announce only after the server clears this loot slot.
            round.pendingAward = winner
            DFB.Refresh()
            local success, err = pcall(GiveMasterLoot, round.lootSlot, index)
            if not success then
                round.pendingAward = nil
                DFB.Refresh()
                print("SEPGP: Could not assign loot: " .. tostring(err) .. ". No GP charged.")
            end
            return
        end
    end
    print("SEPGP: " .. winner.name .. " cannot receive this item through master loot. No GP charged.")
end

function DFB.Open()
    if not DFB.IsMaster() then
        print("SEPGP: /sep dfb requires you to be the group's master looter.")
        return
    end
    if not DFB.masterFrame then
        local frame = Window("SEPGPDFBMaster", "SEPGP - Distribute from bags", 960, 470)
        DFB.masterFrame = frame
        frame.item = Label(frame, "", 20, -55, 530)
        frame.status = Label(frame, "", 20, -103, 530)
        frame.itemDetails = CreateFrame("GameTooltip", "SEPGPDFBItemDetails", frame, "GameTooltipTemplate")
        frame.itemDetails:HookScript("OnSizeChanged", function(_, width, height)
            if not DFB.round then return end
            frame:SetWidth(math.max(960, 610 + width))
            frame:SetHeight(math.max(470, 85 + height))
        end)
        frame.itemDetails:Hide()
        local itemHover = CreateFrame("Frame", nil, frame)
        itemHover:SetPoint("TOPLEFT", 20, -55)
        itemHover:SetSize(530, 45)
        itemHover:EnableMouse(true)
        itemHover:SetScript("OnEnter", function(self)
            if not DFB.round then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(DFB.round.link)
            GameTooltip:Show()
        end)
        itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        itemHover:SetScript("OnHide", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        frame.itemHover = itemHover
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -160)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 550, 55)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(500, 260)
        scroll:SetScrollChild(content)
        frame.bids = Label(content, "", 0, 0, 500)
        frame.bids:SetFontObject("GameFontHighlightSmall")
        frame.award = Button(frame, "Award", 20, -425, 130, DFB.Award)
        frame.cancel = Button(frame, "Cancel bidding", 165, -425, 150, function() DFB.CloseRound() end)
        frame.award:ClearAllPoints()
        frame.award:SetPoint("BOTTOMLEFT", 20, 19)
        frame.cancel:ClearAllPoints()
        frame.cancel:SetPoint("BOTTOMLEFT", 165, 19)
        frame:SetScript("OnHide", function() DFB.CloseRound() end)
    end
    DFB.Refresh()
    DFB.masterFrame:Show()
end

function DFB.Respond(choice)
    local offer = DFB.offer
    if not offer or not DFB.choices[choice] then return end
    if NameKey(DFB.GetMaster()) ~= NameKey(offer.master) then return end
    offer.responded = true
    if DFB.IsMaster() then
        DFB.RecordResponse(offer.id, GetUnitName("player", true), choice)
    else
        DFB.Send({ kind = "BID", id = offer.id, choice = choice }, offer.master)
    end
    if DFB.bidFrame then DFB.bidFrame:Hide() end
end

function DFB.ShowOffer(offer)
    DFB.offer = offer
    if not DFB.bidFrame then
        local frame = Window("SEPGPDFBBid", "SEPGP - Choose your bid", 780, 230)
        DFB.bidFrame = frame
        frame.item = Label(frame, "", 20, -55, 740)
        for i, choice in ipairs(DFB.choices) do
            local index = i
            Button(frame, choice.label .. (i < 5 and " (" .. choice.percent .. "% GP)" or ""),
                20 + (i - 1) * 148, -145, 146, function() DFB.Respond(index) end)
        end
        Label(frame, "Category priority: BiS > Alternative > Upgrade > Off Spec. Pass excludes you.", 20, -185, 740)
        frame:SetScript("OnHide", function()
            -- Closing without choosing is a pass, so the master sees a response.
            if DFB.offer and not DFB.offer.responded then DFB.Respond(5) end
        end)
    end
    DFB.offer.responded = false
    DFB.bidFrame.item:SetText(offer.link .. "\nBase GP: " .. offer.gp .. " | Master looter: " .. offer.master)
    DFB.bidFrame:Show()
end

function DFB.RecordResponse(id, sender, choice)
    local round = DFB.round
    local key = NameKey(sender)
    if not DFB.IsMaster() or not round or round.pendingAward or round.id ~= id
        or not round.eligible[key] or not DFB.GetRoster()[key]
        or type(choice) ~= "number" or choice % 1 ~= 0 or not DFB.choices[choice] then return end
    round.responses[key] = choice
    DFB.Refresh()
    return true
end

function DFB.HandleWhisper(message, sender)
    local round = DFB.round
    if not round or type(message) ~= "string" then return end
    local bid = message:match("^%s*(.-)%s*$"):lower():gsub("%s+", " ")
    if bid == "offspec" then bid = "off spec" end
    for index, choice in ipairs(DFB.choices) do
        if bid == choice.label:lower() then
            if DFB.RecordResponse(round.id, sender, index) then
                -- Close an installed addon's popup after a whisper bid, so
                -- dismissing it cannot accidentally replace the bid with Pass.
                DFB.Send({ kind = "BID_ACK", id = round.id, choice = index }, sender)
                if NameKey(sender) == NameKey(GetUnitName("player", true))
                    and DFB.offer and DFB.offer.id == round.id then
                    DFB.offer.responded = true
                    if DFB.bidFrame then DFB.bidFrame:Hide() end
                end
            end
            return
        end
    end
end

function DFB.Start(link, bag, slot, lootSlot)
    if not DFB.IsMaster() or not DFB.masterFrame or not DFB.masterFrame:IsShown() then return end
    if DFB.round then print("SEPGP: Award or cancel the current item first."); return end
    local gp, err = SEPGP.GP.GetItemGP(link)
    if not gp then print("SEPGP: Cannot distribute this item: " .. tostring(err)); return end
    local id = SEPGP.GenerateActionID()
    DFB.round = { id = id, link = link, gp = gp, eligible = DFB.GetRoster(), responses = {},
        bagGUID = DFB.GetBagItemGUID(bag, slot), lootSlot = lootSlot, lootSession = DFB.lootSession }
    DFB.seen[id] = true
    DFB.Send({ kind = "START", id = id, link = link, gp = gp })
    DFB.ShowOffer({ id = id, link = link, gp = gp, master = GetUnitName("player", true) })
    DFB.Refresh()
    SendChatMessage("SEPGP: Distributing " .. link .. " (" .. gp .. " base GP).", Channel())
    local choices = {}
    for index, choice in ipairs(DFB.choices) do
        choices[#choices + 1] = choice.label
            .. (index < 5 and " (" .. choice.percent .. "% GP)" or "")
    end
    SendChatMessage("SEPGP: Click a button or whisper me: " .. table.concat(choices, ", ") .. ".", Channel())
end

function DFB:OnCommReceived(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    local success, payload = SEPGP:Deserialize(message)
    if not success or type(payload) ~= "table" or payload.version ~= 1
        or type(payload.id) ~= "string" or #payload.id > 80 or payload.id == "" then return end
    if payload.kind == "BID" then
        if channel == "WHISPER" then DFB.RecordResponse(payload.id, sender, payload.choice) end
        return
    end
    if payload.kind == "BID_ACK" then
        local offer = DFB.offer
        if channel == "WHISPER" and offer and offer.id == payload.id
            and NameKey(sender) == NameKey(offer.master)
            and NameKey(sender) == NameKey(DFB.GetMaster())
            and type(payload.choice) == "number" and DFB.choices[payload.choice] then
            offer.responded = true
            if DFB.bidFrame then DFB.bidFrame:Hide() end
        end
        return
    end
    if channel ~= Channel() or NameKey(sender) ~= NameKey(DFB.GetMaster())
        or not DFB.GetRoster()[NameKey(sender)] then return end
    if payload.kind == "START" then
        if DFB.seen[payload.id] or type(payload.link) ~= "string"
            or #payload.link > 1024 or not payload.link:match("|Hitem:%d+:")
            or type(payload.gp) ~= "number" or payload.gp < 0
            or payload.gp ~= payload.gp or payload.gp == math.huge then return end
        DFB.seen[payload.id] = true
        DFB.ShowOffer({ id = payload.id, link = payload.link, gp = payload.gp, master = sender })
    elseif payload.kind == "CLOSE" then
        DFB.seen[payload.id] = true
        if DFB.offer and DFB.offer.id == payload.id then
            local link = DFB.offer.link
            DFB.offer = nil
            if DFB.bidFrame then DFB.bidFrame:Hide() end
            if type(payload.winner) == "string" and type(payload.amount) == "number" then
                print(string.format("SEPGP: %s wins %s for %g GP.", payload.winner, link, payload.amount))
            else print("SEPGP: Bidding cancelled for " .. link) end
        end
    end
end

local function BagClick(button, mouseButton)
    if mouseButton ~= "LeftButton" or not IsShiftKeyDown() then return end
    if not DFB.masterFrame or not DFB.masterFrame:IsShown() then return end
    local bag = button.GetBagID and button:GetBagID() or button:GetParent():GetID()
    local slot = button:GetID()
    if type(bag) ~= "number" or bag < 0
        or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) then return end
    local link = C_Container and C_Container.GetContainerItemLink(bag, slot)
        or (GetContainerItemLink and GetContainerItemLink(bag, slot))
    if link then DFB.Start(link, bag, slot) end
end

local function InstallItemHooks()
    if ContainerFrameItemButton_OnModifiedClick and not DFB.legacyHook then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", BagClick)
        DFB.legacyHook = true
    end
    -- Modified loot clicks pass no ItemLocation. Verify the focused button
    -- belongs to LootFrame and its current slot matches the clicked link.
    local function GetClickedLootSlot(link)
        if not LootFrame or not GetLootSlotLink then return nil end
        local foci = GetMouseFoci and GetMouseFoci()
            or { GetMouseFocus and GetMouseFocus() }
        for _, focus in ipairs(foci) do
            local slot
            while focus do
                slot = slot or focus.slot
                    or (focus.GetSlotIndex and focus:GetSlotIndex())
                if focus == LootFrame then
                    if type(slot) == "number" and GetLootSlotLink(slot) == link then return slot end
                    break
                end
                focus = focus.GetParent and focus:GetParent()
            end
        end
        return nil
    end
    -- Modern bag buttons copy mixin methods when created. Hook the shared
    -- item-click function, filtering to bag locations or loot-window buttons.
    if HandleModifiedItemClick and not DFB.itemHook then
        hooksecurefunc("HandleModifiedItemClick", function(link, location)
            if not IsShiftKeyDown() or not link then return end
            if not DFB.masterFrame or not DFB.masterFrame:IsShown() then return end
            if location and location:IsBagAndSlot() then
                local bag, slot = location:GetBagAndSlot()
                if bag and bag >= 0
                    and bag <= (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) then
                    DFB.Start(link, bag, slot)
                end
            elseif not location then
                local lootSlot = GetClickedLootSlot(link)
                if lootSlot then DFB.Start(link, nil, nil, lootSlot) end
            end
        end)
        DFB.itemHook = true
    end
end

local previousSlash = SlashCmdList.SEPGP
SlashCmdList.SEPGP = function(msg)
    if (msg or ""):match("^%s*(.-)%s*$"):lower() == "dfb" then DFB.Open(); return end
    previousSlash(msg)
    if not msg or msg == "" then print("/sep dfb - distribute an item from bags or the loot window") end
end

function DFB.TryAutoOpen()
    if not DFB.lootOpen or DFB.autoOpened or not DFB.IsMaster() then return end
    local getThreshold = GetLootThreshold or (C_PartyInfo and C_PartyInfo.GetLootThreshold)
    if not getThreshold then return end
    local threshold = getThreshold()
    if type(threshold) ~= "number" then return end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        -- Money and currencies must not trigger distribution.
        if type(link) == "string" and link:match("|Hitem:%d+:") then
            local _, _, _, fourth, fifth = GetLootSlotInfo(slot)
            -- Older clients return quality fourth; newer clients insert a
            -- currency ID before quality. Locked is boolean on older clients.
            local quality = type(fifth) == "number" and fifth or fourth
            if type(quality) == "number" and quality >= threshold then
                DFB.autoOpened = true
                DFB.Open()
                return
            end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_SLOT_CHANGED")
events:RegisterEvent("LOOT_SLOT_CLEARED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("CHAT_MSG_WHISPER")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        local round = DFB.round
        if round and round.pendingAward then
            for _, name in ipairs({ "ERR_LOOT_MASTER_INV_FULL", "ERR_LOOT_MASTER_UNIQUE_ITEM",
                "ERR_LOOT_MASTER_OTHER", "ERR_LOOT_PLAYER_NOT_FOUND", "ERR_LOOT_TOO_FAR",
                "ERR_LOOT_GONE", "ERR_LOOT_CANT_LOOT_THAT_NOW" }) do
                if _G[name] and message == _G[name] then
                    round.pendingAward = nil
                    DFB.Refresh()
                    print("SEPGP: Could not assign loot: " .. message .. ". No GP charged.")
                    break
                end
            end
        end
        return
    end
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        DFB.PruneBagAwards()
        return
    end
    if event == "CHAT_MSG_WHISPER" then
        local message, sender = ...
        DFB.HandleWhisper(message, sender)
        return
    end
    if event == "LOOT_OPENED" then
        -- Opening another corpse must never reuse a previous corpse's slot.
        if DFB.round and DFB.round.lootSlot then
            DFB.round.pendingAward = nil
            DFB.CloseRound()
        end
        DFB.lootSession = (DFB.lootSession or 0) + 1
        DFB.lootOpen, DFB.autoOpened = true, false
        DFB.TryAutoOpen()
        return
    elseif event == "LOOT_SLOT_CHANGED" then
        DFB.TryAutoOpen()
        return
    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        local round = DFB.round
        if round and round.lootSlot == slot then
            if round.pendingAward then
                DFB.CompleteAward(round, round.pendingAward)
            else
                DFB.CloseRound()
                print("SEPGP: The item was removed from the corpse. Bidding cancelled.")
            end
        end
        return
    elseif event == "LOOT_CLOSED" then
        DFB.lootOpen, DFB.autoOpened = false, false
        if DFB.round and DFB.round.lootSlot then
            DFB.round.pendingAward = nil
            DFB.CloseRound()
        end
        return
    end
    if event == "ADDON_LOADED" then
        if not DFB.registered then
            DFB:RegisterComm(PREFIX, "OnCommReceived")
            DFB.registered = true
        end
        InstallItemHooks()
        return
    end
    if DFB.round and not DFB.IsMaster() then
        DFB.round.pendingAward = nil
        DFB.CloseRound()
    end
    if DFB.offer and NameKey(DFB.offer.master) ~= NameKey(DFB.GetMaster()) then
        DFB.offer = nil
        if DFB.bidFrame then DFB.bidFrame:Hide() end
    end
    DFB.Refresh()
    DFB.TryAutoOpen()
end)
