-- Rankings, roster filters, and officer awards for /sep show.
SEPGP.UI = SEPGP.UI or {}
local UI = SEPGP.UI
UI.standingsFilter = "guild"

local function PlayerKey(name)
    return SEPGP.NormalizeName(name)
end

local function Roster()
    local guild, raid, classes = {}, {}, {}
    local function add(target, name, class)
        if not name or name == "" then return end
        local key = PlayerKey(name)
        target[key] = name
        if class then classes[key] = class end
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        for index = 1, GetNumGuildMembers(true) do
            local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(index)
            add(guild, name, class)
        end
    end
    if IsInRaid and IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local unit = "raid" .. index
            local _, class
            if UnitClass then _, class = UnitClass(unit) end
            add(raid, GetUnitName(unit, true), class)
        end
    end
    return guild, raid, classes
end

function SEPGP.GetStandings()
    local guild, raid, classes = Roster()
    local names = UI.standingsFilter == "raid" and raid or guild
    -- Keep saved standings available while the guild roster is unavailable.
    if UI.standingsFilter ~= "raid" and not next(guild) then
        names = {}
        for name in pairs(SEPGP_DB.players) do names[name] = name end
    end
    local standings = {}
    for key, name in pairs(names) do
        local player = SEPGP.GetPlayer(key) or { EP = 0, GP = SEPGP.BASE_GP }
        if not UI.standingsClasses or UI.standingsClasses[classes[key]] then
            standings[#standings + 1] = { name = SEPGP.DisplayName(name),
                key = key, class = classes[key], EP = player.EP, GP = player.GP,
                PR = player.GP > 0 and player.EP / player.GP or 0 }
        end
    end
    table.sort(standings, function(a, b)
        if a.PR == b.PR then return a.key < b.key end
        return a.PR > b.PR
    end)
    return standings
end

local function Text(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
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

local function Input(parent, x, y, width)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", x, y)
    input:SetSize(width, 24)
    input:SetAutoFocus(false)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return input
end

local function Background(frame)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(0.05, 0.05, 0.05, 0.95)
end

local function ClassName(class)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class])
        or class:sub(1, 1) .. class:sub(2):lower()
end

local function UpdateClassFilter()
    local names = {}
    for class in pairs(UI.standingsClasses or {}) do names[#names + 1] = ClassName(class) end
    table.sort(names)
    UI.classFilter:SetText(#names == 0 and "All classes"
        or (#names <= 2 and table.concat(names, ", ") or string.format("%d classes selected", #names)))
    if UI.classMenu then
        for _, button in ipairs(UI.classMenu.buttons) do
            button:SetChecked(button.class and UI.standingsClasses and UI.standingsClasses[button.class]
                or (not button.class and not UI.standingsClasses) or false)
        end
    end
end

local function ToggleClassMenu()
    if UI.classMenu and UI.classMenu:IsShown() then UI.classMenu:Hide(); return end
    if not UI.classMenu then
        UI.classMenu = CreateFrame("Frame", nil, UI.standingsFrame)
        UI.classMenu:SetPoint("TOPLEFT", 185, -72)
        -- Standings rows also use DIALOG; the popup must receive clicks above them.
        UI.classMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        UI.classMenu:EnableMouse(true)
        Background(UI.classMenu)
        UI.classMenu.buttons = {}
    end
    local _, _, rosterClasses = Roster()
    local classes, seen = {}, {}
    for _, class in pairs(rosterClasses) do
        if not seen[class] then classes[#classes + 1], seen[class] = class, true end
    end
    table.sort(classes, function(a, b) return ClassName(a) < ClassName(b) end)
    for _, button in ipairs(UI.classMenu.buttons) do button:Hide() end
    for index = 1, #classes + 1 do
        local class = classes[index - 1]
        local button = UI.classMenu.buttons[index]
        if not button then
            button = CreateFrame("CheckButton", nil, UI.classMenu, "UICheckButtonTemplate")
            button:SetPoint("TOPLEFT", 5, -5 - (index - 1) * 28)
            button:SetSize(26, 26)
            button:SetHitRectInsets(0, -144, 0, 0)
            button.label = Text(button, "", 30, -7, 135)
        end
        UI.classMenu.buttons[index] = button
        button.class = class or false
        button.label:SetText(class and ClassName(class) or "All classes")
        button:SetScript("OnClick", function()
            if class then
                UI.standingsClasses = UI.standingsClasses or {}
                UI.standingsClasses[class] = not UI.standingsClasses[class] or nil
                if not next(UI.standingsClasses) then UI.standingsClasses = nil end
            else UI.standingsClasses = nil end
            UI.scroll:SetVerticalScroll(0)
            SEPGP.RefreshStandingsWindow()
        end)
        button:Show()
    end
    UI.classMenu:SetSize(180, (#classes + 1) * 28 + 10)
    UpdateClassFilter()
    UI.classMenu:Show()
end

function SEPGP.SubmitStandingsAward(kind)
    local dialog = UI.awardDialog
    if not dialog or not SEPGP.CanEditOfficerSettings() then return false end
    local amount = tonumber(dialog.amount:GetText())
    local reason = dialog.reason:GetText()
    if dialog.mode == "decay" then
        if not SEPGP.IsValidDecay(amount) then
            dialog.status:SetText("Enter a decay percentage from 0 to 100."); return false
        end
    elseif type(amount) ~= "number" or amount == 0 or math.abs(amount) >= math.huge
        or amount % 1 ~= 0 or (dialog.mode ~= "member" and amount < 0) then
        dialog.status:SetText(dialog.mode == "member" and "Enter a non-zero whole amount."
            or "Enter a positive whole amount."); return false
    end
    local result
    if dialog.mode == "raid" then
        result = SEPGP.AwardRaidEP(amount, reason)
    elseif dialog.mode == "decay" then
        result = SEPGP.Decay(amount, reason ~= "" and reason or "Standings decay")
    elseif dialog.mode == "member" and dialog.player and (kind == "EP" or kind == "GP") then
        local award = kind == "EP" and SEPGP.AddEP or SEPGP.AddGP
        result = award(dialog.player.key, amount, reason ~= "" and reason or "Standings award")
    end
    if not result then
        dialog.status:SetText("Award could not be applied. Check your raid and try again.")
        return false
    end
    dialog:Hide()
    SEPGP.RefreshStandingsWindow()
    return true
end

function SEPGP.OpenStandingsAward(mode, player)
    if not SEPGP.CanEditOfficerSettings() then return end
    if mode == "raid" and not IsInRaid() then return end
    if mode == "member" and not player then return end
    if not UI.awardDialog then
        local dialog = CreateFrame("Frame", nil, UI.standingsFrame)
        dialog:SetSize(330, 250)
        dialog:SetPoint("TOPLEFT", UI.standingsFrame, "TOPRIGHT", 8, 0)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        Background(dialog)
        dialog.title = Text(dialog, "", 16, -16, 300, "GameFontNormal")
        dialog.description = Text(dialog, "", 16, -42, 300)
        Text(dialog, "Amount / decay %", 16, -84, 140)
        dialog.amount = Input(dialog, 165, -78, 140)
        Text(dialog, "Reason (optional)", 16, -116, 300)
        dialog.reason = Input(dialog, 20, -136, 285)
        dialog.status = Text(dialog, "", 16, -174, 300)
        dialog.ep = Button(dialog, "Add EP", 16, -210, 88, function() SEPGP.SubmitStandingsAward("EP") end)
        dialog.gp = Button(dialog, "Add GP", 112, -210, 88, function() SEPGP.SubmitStandingsAward("GP") end)
        dialog.apply = Button(dialog, "Apply", 16, -210, 184, function() SEPGP.SubmitStandingsAward() end)
        Button(dialog, "Cancel", 216, -210, 96, function() dialog:Hide() end)
        UI.awardDialog = dialog
    end
    local dialog = UI.awardDialog
    dialog.mode, dialog.player = mode, player
    dialog.title:SetText(mode == "member" and ("Award to " .. player.name)
        or mode == "raid" and "Add raid EP" or "Apply decay")
    dialog.description:SetText(mode == "decay" and "Reduce EP and GP for all saved players, including those outside the displayed roster."
        or mode == "raid" and "Award EP to every member of the current raid."
        or "Add EP or GP to this member. Use a negative amount to subtract points.")
    dialog.amount:SetText("")
    dialog.reason:SetText("")
    dialog.status:SetText("")
    if mode == "member" then dialog.ep:Show(); dialog.gp:Show(); dialog.apply:Hide()
    else
        dialog.ep:Hide(); dialog.gp:Hide(); dialog.apply:Show()
        dialog.apply:SetText(mode == "raid" and "Add raid EP" or "Apply decay")
    end
    dialog:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, UI.content)
    row:SetSize(475, 22)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.rank = Text(row, "", 0, -4, 30)
    row.name = Text(row, "", 35, -4, 190)
    row.name:SetWordWrap(false)
    row.ep = Text(row, "", 225, -4, 70)
    row.gp = Text(row, "", 305, -4, 70)
    row.pr = Text(row, "", 385, -4, 70)
    row.ep:SetJustifyH("RIGHT")
    row.gp:SetJustifyH("RIGHT")
    row.pr:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self) SEPGP.OpenStandingsAward("member", self.player) end)
    UI.rows[index] = row
    return row
end

function SEPGP.RefreshStandingsWindow()
    if not UI.standingsFrame then return end
    local standings = SEPGP.GetStandings()
    local officer = SEPGP.CanEditOfficerSettings()
    for index = 1, math.max(20, #standings, #UI.rows) do
        local row = UI.rows[index] or CreateRow(index)
        local player = standings[index]
        row.player = player
        if player then
            row.rank:SetText(index)
            row.name:SetText(player.name)
            local color = player.class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[player.class])
                or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[player.class]))
            row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
            row.ep:SetText(string.format("%g", player.EP))
            row.gp:SetText(string.format("%g", player.GP))
            row.pr:SetText(string.format("%.2f", player.PR))
            row:EnableMouse(officer)
            row:Show()
        else row:Hide() end
    end
    UI.content:SetHeight(math.max(380, #standings * 22))
    UI.count:SetText(string.format("%d players", #standings))
    UI.filter:SetText(UI.standingsFilter == "raid" and "Show whole guild" or "Show raid only")
    UpdateClassFilter()
    for _, button in ipairs(UI.officerButtons) do
        if officer then button:Show() else button:Hide() end
    end
    if officer and IsInRaid() then UI.raidEP:Enable() else UI.raidEP:Disable() end
    if not officer and UI.awardDialog then UI.awardDialog:Hide() end
end

function SEPGP.CreateStandingsWindow()
    if UI.standingsFrame then return end
    local frame = CreateFrame("Frame", "SEPGPStandingsFrame", UIParent, "BackdropTemplate")
    UI.standingsFrame = frame
    frame:SetSize(520, 590)
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
    Text(frame, "SEPGP Forever", 20, -18, 430, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    UI.filter = Button(frame, "Show raid only", 15, -42, 155, function()
        UI.standingsFilter = UI.standingsFilter == "raid" and "guild" or "raid"
        if UI.classMenu then UI.classMenu:Hide() end
        UI.scroll:SetVerticalScroll(0)
        SEPGP.RefreshStandingsWindow()
    end)
    UI.classFilter = Button(frame, "All classes", 185, -42, 180, ToggleClassMenu)
    for _, definition in ipairs({ { "#", 15, 30 }, { "Name", 50, 190 },
        { "EP", 240, 70 }, { "GP", 320, 70 }, { "PR", 400, 70 } }) do
        local header = Text(frame, definition[1], definition[2], -84, definition[3], "GameFontNormal")
        if definition[1] == "EP" or definition[1] == "GP" or definition[1] == "PR" then header:SetJustifyH("RIGHT") end
    end
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    UI.scroll = scroll
    scroll:SetPoint("TOPLEFT", 15, -108)
    scroll:SetPoint("BOTTOMRIGHT", -32, 88)
    UI.content = CreateFrame("Frame", nil, scroll)
    UI.content:SetSize(475, 380)
    scroll:SetScrollChild(UI.content)
    UI.rows = {}
    UI.raidEP = Button(frame, "Add raid EP", 15, -518, 120, function() SEPGP.OpenStandingsAward("raid") end)
    UI.decay = Button(frame, "Decay", 145, -518, 100, function() SEPGP.OpenStandingsAward("decay") end)
    UI.officerButtons = { UI.raidEP, UI.decay }
    UI.count = Text(frame, "", 15, -564, 300, "GameFontNormalSmall")
    UI.refresh = Button(frame, "Refresh", 420, -554, 85, function()
        SEPGP.RequestStandings()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        SEPGP.RefreshStandingsWindow()
    end)
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function() if frame:IsShown() then SEPGP.RefreshStandingsWindow() end end)
    frame:SetScript("OnShow", function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        SEPGP.RefreshStandingsWindow()
    end)
    frame:SetScript("OnHide", function()
        if UI.awardDialog then UI.awardDialog:Hide() end
        if UI.classMenu then UI.classMenu:Hide() end
    end)
    frame:Hide()
end

function SEPGP.ToggleStandingsWindow()
    SEPGP.CreateStandingsWindow()
    if UI.standingsFrame:IsShown() then UI.standingsFrame:Hide()
    else SEPGP.RefreshStandingsWindow(); UI.standingsFrame:Show() end
end
