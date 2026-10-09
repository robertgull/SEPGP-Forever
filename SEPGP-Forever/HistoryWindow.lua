-- Officer history browser. Reuse visible rows rather than creating a frame for
-- every action in a potentially very large ledger.
SEPGP.UI = SEPGP.UI or {}
local UI = SEPGP.UI
local ROW_HEIGHT = 46
local function Timestamp(value)
    if type(value) ~= "number" then return "?" end
    return date and date("%Y-%m-%d %H:%M:%S", value) or tostring(value)
end
local function Text(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    return label
end
local function Button(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 26)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end
local function CreateRow(frame)
    local row = CreateFrame("Frame", nil, frame.content)
    row:SetSize(730, ROW_HEIGHT)
    row:EnableMouse(true)
    row.time = Text(row, "", 0, -4, 140)
    row.player = Text(row, "", 145, -4, 145)
    row.kind = Text(row, "", 295, -4, 55)
    row.amount = Text(row, "", 355, -4, 70)
    row.actor = Text(row, "", 435, -4, 285)
    row.detail = CreateFrame("ScrollingMessageFrame", nil, row)
    row.detail:SetPoint("TOPLEFT", 0, -23)
    row.detail:SetSize(720, 20)
    row.detail:SetFontObject(GameFontHighlightSmall)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetFading(false)
    row.detail:SetMaxLines(1)
    row.detail:EnableMouseWheel(false)
    row.detail:SetHyperlinksEnabled(true)
    row.detail:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if link:match("^item:") then SetItemRef(link, text, button, self) end
    end)
    row.detail:SetScript("OnHyperlinkEnter", function(self, link)
        if not link:match("^item:") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    row.detail:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    row.labels = { row.time, row.player, row.kind, row.amount, row.actor }
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)
    row:SetScript("OnEnter", function(self)
        if not self.action then return end
        local action = self.action
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SEPGP.DisplayName(action.player) .. " - " .. action.type)
        GameTooltip:AddLine("Time: " .. Timestamp(action.timestamp), 1, 1, 1)
        GameTooltip:AddLine("Officer: " .. SEPGP.DisplayName(action.actor), 1, 1, 1)
        GameTooltip:AddLine("Reason: " .. (action.reason and action.reason ~= "" and action.reason or "Not recorded"), 1, 1, 1, true)
        GameTooltip:AddLine("Action: " .. action.id, 0.7, 0.7, 0.7, true)
        if action.before and action.after then
            GameTooltip:AddLine(string.format("EP: %g -> %g   GP: %g -> %g",
                action.before.EP, action.after.EP, action.before.GP, action.after.GP), 1, 1, 1)
        end
        if self.checkpoint then GameTooltip:AddLine("Current checkpoint timestamp (shared by actions in this second)", 1, 0.82, 0.2, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end
local function Render(frame)
    local first = math.floor(frame.scroll:GetVerticalScroll() / ROW_HEIGHT) + 1
    local visible = math.ceil(math.max(1, frame.scroll:GetHeight()) / ROW_HEIGHT) + 1
    for slot = 1, math.max(visible, #frame.rows) do
        local row = frame.rows[slot]
        local index = first + slot - 1
        local action = slot <= visible and frame.actions[index]
        if action then
            row = row or CreateRow(frame)
            frame.rows[slot] = row
            row.action, row.checkpoint = action, frame.checkpoint == action.timestamp
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row.time:SetText(Timestamp(action.timestamp))
            row.player:SetText(SEPGP.DisplayName(action.player))
            row.kind:SetText(action.type)
            row.amount:SetText(string.format(action.type == "DECAY" and "%g%%" or "%+g", action.amount))
            row.actor:SetText(SEPGP.DisplayName(action.actor))
            local reason = action.reason and action.reason ~= "" and action.reason or "No reason recorded"
            row.detail:Clear()
            row.detail:AddMessage((row.checkpoint and "Checkpoint | " or "") .. "Reason: " .. reason,
                1, row.checkpoint and 0.82 or 1, row.checkpoint and 0.2 or 1)
            for _, label in ipairs(row.labels) do
                label:SetTextColor(1, row.checkpoint and 0.82 or 1, row.checkpoint and 0.2 or 1)
            end
            row.background:SetColorTexture(row.checkpoint and 0.35 or 0,
                row.checkpoint and 0.24 or 0, 0, row.checkpoint and 0.5 or (index % 2 == 0 and 0.2 or 0))
            row:Show()
        elseif row then row.action = nil; row:Hide() end
    end
end
local function SearchText(action)
    local values = { Timestamp(action.timestamp) }
    local function Collect(value)
        if type(value) == "table" then
            for key, child in pairs(value) do
                values[#values + 1] = tostring(key)
                Collect(child)
            end
        elseif value ~= nil then values[#values + 1] = tostring(value) end
    end
    Collect(action)
    -- Keep visible item names, without hyperlink IDs or color/texture markup.
    return table.concat(values, " "):gsub("|H.-|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):lower()
end
local function FilterHistory(frame, resetScroll)
    if not SEPGP.CanEditOfficerSettings() then frame:Hide(); return end
    local terms = {}
    for term in frame.search:GetText():lower():gmatch("%S+") do terms[#terms + 1] = term end
    frame.actions = {}
    for _, entry in ipairs(frame.searchEntries or {}) do
        local matches = true
        for _, term in ipairs(terms) do
            if not entry.text:find(term, 1, true) then matches = false; break end
        end
        if matches then frame.actions[#frame.actions + 1] = entry.action end
    end
    local total = #(frame.searchEntries or {})
    frame.count:SetText(#terms > 0 and string.format("%d of %d actions", #frame.actions, total)
        or string.format("%d actions", total))
    frame.empty:SetText(total == 0 and "No history saved. Use Sync history to request officer history."
        or (#frame.actions == 0 and "No matching history." or ""))
    frame.content:SetHeight(math.max(frame.scroll:GetHeight(), #frame.actions * ROW_HEIGHT))
    local maximum = math.max(0, #frame.actions * ROW_HEIGHT - frame.scroll:GetHeight())
    if resetScroll then frame.scroll:SetVerticalScroll(0)
    elseif frame.scroll:GetVerticalScroll() > maximum then frame.scroll:SetVerticalScroll(maximum) end
    Render(frame)
end
function SEPGP.RefreshHistoryWindow()
    local frame = UI.historyFrame
    if not frame then return end
    if not SEPGP.CanEditOfficerSettings() then frame:Hide(); return end
    local sorted = SEPGP.GetSortedActions()
    frame.searchEntries = {}
    for index = #sorted, 1, -1 do
        local action = sorted[index]
        frame.searchEntries[#frame.searchEntries + 1] = { action = action, text = SearchText(action) }
    end
    frame.checkpoint = SEPGP.GetSyncCheckpoint()
    frame.checkpointText:SetText(frame.checkpoint and ("Current checkpoint: " .. Timestamp(frame.checkpoint)
        .. " | History through this second is confirmed; gold rows share this timestamp.") or "No current checkpoint confirmed.")
    frame.revision, frame.savedActions, frame.savedCheckpoint = SEPGP_DB.revision, SEPGP_DB.actions, SEPGP_DB.syncCheckpoint
    FilterHistory(frame)
end
function SEPGP.CreateHistoryWindow()
    if UI.historyFrame then return end
    local frame = CreateFrame("Frame", "SEPGPHistoryFrame", UIParent, "BackdropTemplate")
    UI.historyFrame = frame
    frame:SetSize(780, 590)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
        tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    Text(frame, "SEPGP Forever - History", 20, -18, 650, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.checkpointText = Text(frame, "", 15, -48, 735)
    frame.checkpointText:SetTextColor(1, 0.82, 0.2)
    Text(frame, "Search all fields", 15, -78, 115, "GameFontNormal")
    frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetPoint("TOPLEFT", 140, -72)
    frame.search:SetSize(520, 24)
    frame.search:SetAutoFocus(false)
    frame.search:SetText("")
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Button(frame, "Clear", 670, -72, 95, function() frame.search:SetText("") end)
    for _, header in ipairs({ { "Time", 15, 140 }, { "Player", 160, 145 }, { "Type", 310, 55 },
        { "Amount", 370, 70 }, { "Officer", 450, 285 } }) do
        Text(frame, header[1], header[2], -112, header[3], "GameFontNormal")
    end
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 15, -136)
    frame.scroll:SetPoint("BOTTOMRIGHT", -32, 66)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(730, 388)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows, frame.actions = {}, {}
    frame.empty = Text(frame, "", 15, -160, 710)
    frame.count = Text(frame, "", 15, -554, 290, "GameFontNormalSmall")
    Button(frame, "Sync history", 535, -550, 125, function() SEPGP.RequestSync() end)
    Button(frame, "Refresh", 670, -550, 95, SEPGP.RefreshHistoryWindow)
    frame.scroll:HookScript("OnVerticalScroll", function() Render(frame) end)
    frame.search:SetScript("OnTextChanged", function() FilterHistory(frame, true) end)
    frame:SetScript("OnShow", SEPGP.RefreshHistoryWindow)
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function() if frame:IsShown() then SEPGP.RefreshHistoryWindow() end end)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        if frame.revision ~= SEPGP_DB.revision or frame.savedActions ~= SEPGP_DB.actions
            or frame.savedCheckpoint ~= SEPGP_DB.syncCheckpoint then SEPGP.RefreshHistoryWindow() end
    end)
    frame:Hide()
end
function SEPGP.ToggleHistoryWindow()
    if not SEPGP.CanEditOfficerSettings() then print("SEPGP: History is officer only."); return end
    SEPGP.CreateHistoryWindow()
    if UI.historyFrame:IsShown() then UI.historyFrame:Hide()
    else SEPGP.RefreshHistoryWindow(); UI.historyFrame:Show() end
end
