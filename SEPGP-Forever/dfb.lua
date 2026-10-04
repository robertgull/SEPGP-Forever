-- Distribute from bags or the loot window. The master computes all standings/GP.
SEPGP.DFB = {}
local DFB = SEPGP.DFB
local PREFIX = "SEPGPF_DFB"
local AceComm = LibStub("AceComm-3.0")
AceComm:Embed(DFB)

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
        if not (DFB.trade and DFB.trade.reserved[guid])
            and (not location or C_Item.GetItemGUID(location) ~= guid) then
            awards[guid] = nil
        end
    end
end

-- Fill ordinary trade slots with the exact awarded instances, never the enchant slot.
function DFB.FillAwardedTrade()
    local trade = DFB.trade
    if not trade or trade.busy or not GetCursorInfo or GetCursorInfo()
        or not GetTradePlayerItemLink or not ClickTradeButton
        or not C_Item or not C_Item.GetItemLocation then return end
    if TradeFrame and not TradeFrame:IsShown() then return end
    local partner = NameKey(GetUnitName("NPC", true))
    if not partner then return end
    trade.partner = trade.partner or partner
    if trade.partner ~= partner then return end
    local pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem
    if not pickup then return end
    local candidates = {}
    for guid, award in pairs(DFB.GetBagAwards()) do
        if NameKey(award.winner) == partner and not trade.attempted[guid] then
            candidates[#candidates + 1] = guid
        end
    end
    table.sort(candidates)
    trade.busy = true
    for _, guid in ipairs(candidates) do
        -- Never displace an existing cursor item or an item already offered for trade.
        if DFB.trade ~= trade or NameKey(GetUnitName("NPC", true)) ~= partner or GetCursorInfo() then break end
        local tradeSlot
        for slot = 1, (TRADE_ENCHANT_SLOT or 7) - 1 do
            if not trade.slots[slot] and not GetTradePlayerItemLink(slot) then tradeSlot = slot; break end
        end
        if not tradeSlot then break end
        local location = C_Item.GetItemLocation(guid)
        if location and location.IsBagAndSlot and location:IsBagAndSlot() then
            local bag, slot = location:GetBagAndSlot()
            local locked
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                locked = info and info.isLocked
            elseif GetContainerItemInfo then
                local _, _, isLocked = GetContainerItemInfo(bag, slot)
                locked = isLocked
            end
            if not locked and DFB.GetBagItemGUID(bag, slot) == guid then
                trade.attempted[guid], trade.reserved[guid] = true, true
                trade.slots[tradeSlot] = guid
                pickup(bag, slot)
                if GetCursorInfo() == "item" then
                    ClickTradeButton(tradeSlot)
                    -- Failed placement leaves our item on the cursor; return it to its bag.
                    if GetCursorInfo() == "item" then
                        if ClearCursor then ClearCursor() end
                        trade.slots[tradeSlot], trade.reserved[guid] = nil, nil
                    end
                elseif not GetTradePlayerItemLink(tradeSlot) then
                    trade.slots[tradeSlot], trade.reserved[guid] = nil, nil
                end
            end
        end
    end
    trade.busy = false
end

function DFB.BeginAwardedTrade()
    local trade = { attempted = {}, reserved = {}, slots = {} }
    DFB.trade = trade
    -- Let the game's trade window and NPC unit initialize first.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if DFB.trade == trade then DFB.FillAwardedTrade() end end)
    else DFB.FillAwardedTrade() end
end

function DFB.GetRoster()
    local roster = {}
    local classes = {}
    local function add(unit)
        local name = GetUnitName(unit, true)
        if name then
            local key = NameKey(name)
            roster[key] = name
            if UnitClass then
                local _, class = UnitClass(unit)
                classes[key] = class
            end
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    end
    return roster, classes
end

local function BidderName(name, classes)
    local class = classes[NameKey(name)]
    local color = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if not color then return name end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5), name)
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
        if choice < 5 and round.choices[choice].active and roster[key] then
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

local function Cost(round, choice)
    return math.floor(round.gp * round.choices[choice].percent / 100 + 0.5)
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
    frame.title = Label(frame, title, 20, -18, width - 60)
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
        frame.item:SetText(frame.compactLayout and "Shift-click a bag or loot item to start."
            or "Shift-click an item in your bags or the loot window to start bidding.")
        frame.status:SetText(frame.compactLayout and "Corpse loot is assigned. Trade bag items."
            or "Award assigns corpse loot automatically. Trade bag items after awarding.")
        frame.bids:SetText("")
        frame.award:Disable()
        frame.cancel:Disable()
        return
    end
    frame.item:SetText(round.link .. "\nBase GP: " .. round.gp)
    if round.pendingAward then
        frame.status:SetText("Assigning loot to " .. round.pendingAward.name .. "...")
        frame.award:Disable()
        frame.cancel:Disable()
        return
    end
    local count, total = 0, 0
    for _ in pairs(round.eligible) do total = total + 1 end
    for _ in pairs(round.responses) do count = count + 1 end
    frame.status:SetText(string.format(frame.compactLayout
        and "Responses: %d/%d\nPriority: category, then EP/GP."
        or "Responses: %d/%d. Priority: category, then EP/GP.\nEqual ratios use name order. Award closes bidding.", count, total))
    local lines = {}
    local _, classes = DFB.GetRoster()
    local ranked = DFB.GetRankedBids()
    for i, bid in ipairs(ranked) do
        lines[#lines + 1] = string.format("%d. %s\n   %s | PR %.3f | %d GP", i,
            BidderName(bid.name, classes), round.choices[bid.choice].label, bid.pr, Cost(round, bid.choice))
    end
    for key, choice in pairs(round.responses) do
        if choice == 5 then
            lines[#lines + 1] = BidderName(round.eligible[key], classes) .. " - " .. round.choices[5].label
        end
    end
    frame.bids:SetText(table.concat(lines, "\n"))
    local height = math.max(140, frame.bids:GetStringHeight() or #lines * 32)
    frame.bids:SetHeight(height)
    frame.bidContent:SetHeight(height)
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
    local amount = Cost(round, winner.choice)
    local reason = "DFB: " .. round.link .. " (" .. round.choices[winner.choice].label .. ")"
    -- AddGP clamps GP to BASE_GP; a free award must preserve decayed GP too.
    if amount > 0 and not SEPGP.AddGP(winner.player, amount, reason) then return end
    if round.bagGUID then
        DFB.GetBagAwards()[round.bagGUID] = { winner = winner.name, link = round.link }
    end
    DFB.CloseRound(winner.name, amount)
    local message = string.format("SEPGP: %s awarded to %s (%s, %d GP).",
        round.link, winner.name, round.choices[winner.choice].label, amount)
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
        local frame = Window("SEPGPDFBMaster", "SEPGP - Distribute loot", 330, 340)
        DFB.masterFrame = frame
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", UIParent, "LEFT", 12, 80)
        frame:SetClampedToScreen(true)
        frame.item = Label(frame, "", 20, -50, 290)
        frame.status = Label(frame, "", 20, -108, 290)
        frame.status:SetFontObject("GameFontHighlightSmall")
        local itemHover = CreateFrame("Frame", nil, frame)
        itemHover:SetPoint("TOPLEFT", 20, -50)
        itemHover:SetSize(290, 50)
        itemHover:EnableMouse(true)
        itemHover:SetScript("OnEnter", function(self)
            if not DFB.round then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if DFB.round.bagGUID and GameTooltip.SetItemByGUID then
                GameTooltip:SetItemByGUID(DFB.round.bagGUID)
            else
                GameTooltip:SetHyperlink(DFB.round.link)
            end
            GameTooltip:Show()
        end)
        itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        itemHover:SetScript("OnHide", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        frame.itemHover = itemHover
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -150)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 55)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(250, 140)
        frame.bidContent = content
        scroll:SetScrollChild(content)
        frame.bids = Label(content, "", 0, 0, 250)
        frame.bids:SetFontObject("GameFontHighlightSmall")
        frame.award = Button(frame, "Award", 20, -295, 110, DFB.Award)
        frame.cancel = Button(frame, "Cancel bidding", 140, -295, 150, function() DFB.CloseRound() end)
        frame.award:ClearAllPoints()
        frame.award:SetPoint("BOTTOMLEFT", 20, 19)
        frame.cancel:ClearAllPoints()
        frame.cancel:SetPoint("BOTTOMLEFT", 140, 19)
        frame:SetResizable(true)
        if frame.SetResizeBounds then frame:SetResizeBounds(260, 260, 900, 800)
        else
            frame:SetMinResize(260, 260)
            frame:SetMaxResize(900, 800)
        end
        frame:SetScript("OnSizeChanged", function(self, width)
            self.compactLayout = width < 330
            self.title:SetWidth(width - 60)
            self.item:SetWidth(width - 40)
            self.status:SetWidth(width - 40)
            self.itemHover:SetWidth(width - 40)
            self.bidContent:SetWidth(width - 80)
            self.bids:SetWidth(width - 80)
            local buttonWidth = (width - 50) / 2
            self.award:SetWidth(buttonWidth)
            self.cancel:SetWidth(buttonWidth)
            self.cancel:ClearAllPoints()
            self.cancel:SetPoint("BOTTOMLEFT", 30 + buttonWidth, 19)
            DFB.Refresh()
        end)
        local resize = CreateFrame("Button", nil, frame)
        resize:SetSize(20, 20)
        resize:SetPoint("BOTTOMRIGHT", -4, 4)
        resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        resize:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
        end)
        resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
        frame.resizeHandle = resize
        frame:SetScript("OnHide", function()
            frame:StopMovingOrSizing()
            DFB.CloseRound()
        end)
    end
    DFB.Refresh()
    DFB.masterFrame:Show()
end

function DFB.Respond(choice, automaticPass)
    local offer = DFB.offer
    if not offer or not offer.choices[choice]
        or (not offer.choices[choice].active and not (automaticPass and choice == 5)) then return end
    if NameKey(DFB.GetMaster()) ~= NameKey(offer.master) then return end
    if choice ~= 5 and SEPGP.ItemEligibility.CanPlayerUse(offer.link) ~= true then return end
    offer.responded = true
    if DFB.IsMaster() then
        DFB.RecordResponse(offer.id, GetUnitName("player", true), choice)
    else
        DFB.Send({ kind = "BID", id = offer.id, choice = choice }, offer.master)
    end
    if DFB.bidFrame then DFB.bidFrame:Hide() end
end

function DFB.ShowOffer(offer)
    offer.choices = offer.choices or SEPGP.Bids.GetDefaultChoices()
    DFB.offer = offer
    local usable = SEPGP.ItemEligibility.CanPlayerUse(offer.link)
    offer.waitingData = usable == nil
    if usable == nil then
        if DFB.bidFrame then DFB.bidFrame:Hide() end
        local itemID = tonumber(offer.link:match("item:(%d+)"))
        if itemID and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return
    elseif not usable then
        DFB.Respond(5, true)
        return
    end
    if not DFB.bidFrame then
        local frame = Window("SEPGPDFBBid", "SEPGP - Choose your bid", 780, 280)
        DFB.bidFrame = frame
        frame.item = Label(frame, "", 20, -55, 740)
        frame.buttons = {}
        for i = 1, 5 do
            local index = i
            frame.buttons[i] = Button(frame, "",
                20 + (i - 1) * 148, -145, 146, function() DFB.Respond(index) end)
            frame.buttons[i]:SetHeight(60)
            frame.buttons[i]:SetNormalFontObject("GameFontNormalSmall")
            local text = frame.buttons[i]:GetFontString()
            if text then
                text:SetWidth(138)
                text:SetWordWrap(true)
            end
        end
        frame.priority = Label(frame, "", 20, -220, 740)
        frame:SetScript("OnHide", function()
            -- Closing without choosing is a pass, so the master sees a response.
            if DFB.offer and not DFB.offer.responded and not DFB.offer.waitingData then DFB.Respond(5, true) end
        end)
    end
    local frame = DFB.bidFrame
    local compact = DFB.IsMaster() and true or false
    frame:SetSize(compact and 330 or 780, compact and 320 or 280)
    frame:SetClampedToScreen(true)
    frame.title:SetWidth(compact and 270 or 720)
    frame.item:SetWidth(compact and 290 or 740)
    frame.priority:SetWidth(compact and 290 or 740)
    frame.priority:ClearAllPoints()
    frame.priority:SetPoint("TOPLEFT", 20, compact and -278 or -220)
    if frame.compact ~= compact then
        frame:ClearAllPoints()
        if compact and DFB.masterFrame then
            frame:SetPoint("TOPLEFT", DFB.masterFrame, "TOPRIGHT", 8, 0)
        elseif compact then frame:SetPoint("LEFT", UIParent, "LEFT", 12, -280)
        else frame:SetPoint("CENTER") end
        frame.compact = compact
    end
    local priority = {}
    for index, choice in ipairs(offer.choices) do
        local button = DFB.bidFrame.buttons[index]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", compact and (20 + ((index - 1) % 2) * 148) or (20 + (index - 1) * 148),
            compact and (-125 - math.floor((index - 1) / 2) * 48) or -145)
        button:SetHeight(compact and 44 or 60)
        button:SetText(choice.label .. (index < 5 and "\n(" .. choice.percent .. "% GP)" or ""))
        if choice.active then
            button:Show()
            if index < 5 then priority[#priority + 1] = choice.label end
        else button:Hide() end
    end
    DFB.bidFrame.priority:SetText("Category priority: " .. table.concat(priority, " > ") .. ". Closing declines.")
    DFB.offer.responded = false
    DFB.bidFrame.item:SetText(offer.link .. "\nBase GP: " .. offer.gp
        .. (compact and "" or " | Master looter: " .. offer.master))
    DFB.bidFrame:Show()
end

function DFB.RecordResponse(id, sender, choice)
    local round = DFB.round
    local key = NameKey(sender)
    if not DFB.IsMaster() or not round or round.pendingAward or round.id ~= id
        or not round.eligible[key] or not DFB.GetRoster()[key]
        or type(choice) ~= "number" or choice % 1 ~= 0 or not round.choices[choice]
        or (choice ~= 5 and not round.choices[choice].active) then return end
    if choice ~= 5 and not SEPGP.ItemEligibility.CanClassUse(round.classes[key], round.itemInfo) then return end
    round.responses[key] = choice
    DFB.Refresh()
    return true
end

function DFB.HandleWhisper(message, sender)
    local round = DFB.round
    if not round or type(message) ~= "string" then return end
    local bid = SEPGP.Bids.Key(message)
    for index, choice in ipairs(round.choices) do
        if choice.active and bid == SEPGP.Bids.Key(choice.label) then
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
    local roster, classes = DFB.GetRoster()
    DFB.round = { id = id, link = link, gp = gp, eligible = roster, classes = classes, responses = {},
        itemInfo = SEPGP.ItemEligibility.GetInfo(link),
        choices = SEPGP.Bids.GetChoices(),
        bagGUID = DFB.GetBagItemGUID(bag, slot), lootSlot = lootSlot, lootSession = DFB.lootSession }
    DFB.seen[id] = true
    DFB.Send({ kind = "START", id = id, link = link, gp = gp, choices = DFB.round.choices })
    DFB.ShowOffer({ id = id, link = link, gp = gp, master = GetUnitName("player", true), choices = DFB.round.choices })
    DFB.Refresh()
    SendChatMessage("SEPGP: Distributing " .. link .. " (" .. gp .. " base GP).", Channel())
    local choices = {}
    for index, choice in ipairs(DFB.round.choices) do
        if choice.active then
            choices[#choices + 1] = choice.label
                .. (index < 5 and " (" .. choice.percent .. "% GP)" or "")
        end
    end
    local prefix = "SEPGP: Click a button or whisper me: "
    local message = prefix
    for _, choice in ipairs(choices) do
        local separator = message == prefix and "" or ", "
        if #message + #separator + #choice + 1 > 255 then
            SendChatMessage(message .. ".", Channel())
            message, separator = prefix, ""
        end
        message = message .. separator .. choice
    end
    if message ~= prefix then SendChatMessage(message .. ".", Channel()) end
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
            and type(payload.choice) == "number" and offer.choices[payload.choice] then
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
        if payload.choices ~= nil and not SEPGP.Bids.Validate(payload.choices) then return end
        local choices = payload.choices and SEPGP.Bids.GetChoices(payload.choices)
            or SEPGP.Bids.GetDefaultChoices()
        DFB.seen[payload.id] = true
        DFB.ShowOffer({ id = payload.id, link = payload.link, gp = payload.gp, master = sender, choices = choices })
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
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("TRADE_SHOW")
events:RegisterEvent("TRADE_CLOSED")
events:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "TRADE_SHOW" then DFB.BeginAwardedTrade(); return end
    if event == "TRADE_CLOSED" then
        DFB.trade = nil
        if C_Timer and C_Timer.After then C_Timer.After(0.1, DFB.PruneBagAwards) end
        return
    end
    if event == "TRADE_PLAYER_ITEM_CHANGED" or event == "ITEM_LOCK_CHANGED" then
        DFB.FillAwardedTrade()
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        local offer = DFB.offer
        if offer and offer.waitingData and not offer.responded
            and tonumber(offer.link:match("item:(%d+)")) == itemID
            and NameKey(offer.master) == NameKey(DFB.GetMaster()) then
            -- Failed data loads do not establish that an item is unusable.
            if success or SEPGP.ItemEligibility.CanPlayerUse(offer.link) ~= nil then
                DFB.ShowOffer(offer)
            end
        end
        return
    end
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
        DFB.FillAwardedTrade()
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
