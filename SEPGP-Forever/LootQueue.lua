-- Queue equipment still available on the current corpse, in loot slot order.
SEPGP.LootQueue = { items = {}, handled = {} }
local Queue, DFB = SEPGP.LootQueue, SEPGP.DFB

function Queue.Scan()
    if not DFB.lootOpen or not DFB.IsMaster() then
        Queue.items, Queue.handled = {}, {}
        Queue.Refresh(); return
    end
    if Queue.session ~= DFB.lootSession then
        Queue.session, Queue.items, Queue.handled = DFB.lootSession, {}, {}
    end
    local getThreshold = GetLootThreshold or (C_PartyInfo and C_PartyInfo.GetLootThreshold)
    local threshold = getThreshold and getThreshold()
    if type(threshold) ~= "number" then return end
    Queue.items = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and link:match("|Hitem:%d+:") and Queue.handled[slot] ~= link then
            local _, _, _, fourth, fifth = GetLootSlotInfo(slot)
            local quality = type(fifth) == "number" and fifth or fourth
            local info = SEPGP.ItemEligibility.GetInfo(link)
            if type(quality) == "number" and quality >= threshold and info
                and (info.classID == 2 or info.classID == 4) and info.equipLoc and info.equipLoc ~= "" then
                Queue.items[#Queue.items + 1] = { slot = slot, link = link }
            end
        end
    end
    Queue.Refresh()
end

local function Ready()
    return DFB.IsMaster() and not DFB.round and not (SEPGP.LootCollect and SEPGP.LootCollect.queue)
end
function Queue.BidNext()
    Queue.Scan()
    if not Ready() then return end
    local item = Queue.items[1]
    if not item then return end
    DFB.Start(item.link, nil, nil, item.slot)
    if DFB.round and DFB.round.lootSlot == item.slot and DFB.round.link == item.link then
        Queue.handled[item.slot] = item.link
        table.remove(Queue.items, 1)
    end
    Queue.Refresh()
end
function Queue.Skip()
    Queue.Scan()
    if not Ready() then return end
    local item = table.remove(Queue.items, 1)
    if item then Queue.handled[item.slot] = item.link end
    Queue.Refresh()
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "SEPGPLootQueue", UIParent, "BackdropTemplate")
    Queue.frame = frame
    frame:SetSize(250, 180)
    frame:SetPoint("TOPLEFT", DFB.masterFrame, "TOPRIGHT", 8, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", frame.StopMovingOrSizing)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(200, 130, 600, 600)
    else frame:SetMinResize(200, 130); frame:SetMaxResize(600, 600) end
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 15, -16)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 15, -40)
    frame.scroll:SetPoint("BOTTOMRIGHT", -32, 52)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(190, 22)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows = {}
    local function Button(text, x, callback)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetPoint("BOTTOMLEFT", x, 16)
        button:SetSize(100, 26)
        button:SetText(text)
        button:SetScript("OnClick", callback)
        return button
    end
    frame.bid = Button("Bid next", 15, Queue.BidNext)
    frame.skip = Button("Skip", 125, Queue.Skip)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT", -3, 3)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    frame.resizeHandle = resize
    frame:SetScript("OnSizeChanged", function(self, width)
        self.title:SetWidth(width - 30)
        self.content:SetWidth(width - 60)
        local buttonWidth = (width - 40) / 2
        self.bid:SetWidth(buttonWidth); self.skip:SetWidth(buttonWidth)
        self.skip:ClearAllPoints(); self.skip:SetPoint("BOTTOMLEFT", 25 + buttonWidth, 16)
        for _, row in ipairs(self.rows) do row:SetWidth(width - 60) end
    end)
end

function Queue.Refresh()
    if not DFB.masterFrame or not DFB.masterFrame:IsShown() or not DFB.IsMaster() then
        if Queue.frame then Queue.frame:Hide() end
        return
    end
    if not Queue.frame then CreateWindow() end
    local frame = Queue.frame
    frame.title:SetText("Loot queue (" .. #Queue.items .. ")")
    for index = 1, math.max(1, #Queue.items, #frame.rows) do
        local row = frame.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, frame.content)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
            row:SetSize(frame:GetWidth() - 60, 22)
            row:EnableMouse(true)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetAllPoints(row); row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
            row:SetScript("OnEnter", function(self)
                if self.item then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.item.link); GameTooltip:Show() end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
            frame.rows[index] = row
        end
        row.item = Queue.items[index] or false
        if row.item then row.label:SetText(index .. ". " .. row.item.link); row:Show()
        elseif index == 1 then row.label:SetText("No queued loot"); row:Show()
        else row:Hide() end
    end
    frame.content:SetHeight(math.max(22, #Queue.items * 22))
    local maximum = math.max(0, #Queue.items * 22 - frame.scroll:GetHeight())
    if frame.scroll:GetVerticalScroll() > maximum then frame.scroll:SetVerticalScroll(maximum) end
    if #Queue.items > 0 and Ready() then frame.bid:Enable(); frame.skip:Enable()
    else frame.bid:Disable(); frame.skip:Disable() end
    frame:Show()
end

local previousRefresh = DFB.Refresh
DFB.Refresh = function(...) previousRefresh(...); Queue.Refresh() end
local previousOpen = DFB.Open
DFB.Open = function(...)
    previousOpen(...)
    if DFB.masterFrame and not Queue.hooked then
        DFB.masterFrame:HookScript("OnHide", Queue.Refresh)
        Queue.hooked = true
    end
    Queue.Scan()
end
local events = CreateFrame("Frame")
for _, event in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED",
    "GET_ITEM_INFO_RECEIVED", "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function() Queue.Scan() end)
