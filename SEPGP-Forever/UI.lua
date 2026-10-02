SEPGP = SEPGP or {}

SEPGP.UI = SEPGP.UI or {}

-- =========================================================
-- Standings UI
-- =========================================================

SEPGP.UI = SEPGP.UI or {}

local MAX_STANDING_ROWS = 20

function SEPGP.GetStandings()
    local standings = {}

    for name, player in pairs(SEPGP_DB.players) do
        local pr = 0

        if player.GP > 0 then
            pr = player.EP / player.GP
        end

        table.insert(standings, {
            name = name,
            EP = player.EP,
            GP = player.GP,
            PR = pr,
        })
    end

    table.sort(standings, function(a, b)
        if a.PR == b.PR then
            return a.name < b.name
        end

        return a.PR > b.PR
    end)

    return standings
end


function SEPGP.RefreshStandingsWindow()
    if not SEPGP.UI.standingsFrame then
        return
    end

    local standings = SEPGP.GetStandings()

    for i = 1, MAX_STANDING_ROWS do
        local row = SEPGP.UI.rows[i]
        local player = standings[i]

        if player then
            row.rank:SetText(i)
            row.name:SetText(player.name)
            row.ep:SetText(player.EP)
            row.gp:SetText(player.GP)
            row.pr:SetText(string.format("%.2f", player.PR))

            row:Show()
        else
            row:Hide()
        end
    end

    SEPGP.UI.count:SetText(
        string.format("%d players", #standings)
    )
end


function SEPGP.CreateStandingsWindow()
    if SEPGP.UI.standingsFrame then
        return
    end

    local frame = CreateFrame(
        "Frame",
        "SEPGPStandingsFrame",
        UIParent
    )

    frame:SetSize(520, 500)
    frame:SetPoint("CENTER")

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    -- Background
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.05, 0.05, 0.05, 0.95)

    -- Title bar
    local titleBackground = frame:CreateTexture(nil, "BORDER")
    titleBackground:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBackground:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBackground:SetHeight(34)
    titleBackground:SetColorTexture(0.12, 0.12, 0.12, 1)

    local title = frame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )

    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -9)
    title:SetText("SEPGP Forever")

    -- Close button
    local closeButton = CreateFrame("Button", nil, frame)

    closeButton:SetSize(28, 28)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -3)

    local closeText = closeButton:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )

    closeText:SetPoint("CENTER")
    closeText:SetText("X")

    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Column headers
    local headerY = -50

    local function CreateHeader(text, x, width, justify)
        local header = frame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

        header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, headerY)
        header:SetWidth(width)
        header:SetJustifyH(justify or "LEFT")
        header:SetText(text)

        return header
    end

    CreateHeader("#",    15,  30, "LEFT")
    CreateHeader("Name", 50, 210, "LEFT")
    CreateHeader("EP",  270,  70, "RIGHT")
    CreateHeader("GP",  350,  70, "RIGHT")
    CreateHeader("PR",  430,  70, "RIGHT")

    -- Separator
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -72)
    separator:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -72)
    separator:SetHeight(1)
    separator:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- Rows
    SEPGP.UI.rows = {}

    for i = 1, MAX_STANDING_ROWS do
        local row = CreateFrame("Frame", nil, frame)

        row:SetSize(490, 19)
        row:SetPoint(
            "TOPLEFT",
            frame,
            "TOPLEFT",
            15,
            -78 - ((i - 1) * 19)
        )

        row.rank = row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

        row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.rank:SetWidth(30)
        row.rank:SetJustifyH("LEFT")

        row.name = row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

        row.name:SetPoint("LEFT", row, "LEFT", 35, 0)
        row.name:SetWidth(210)
        row.name:SetJustifyH("LEFT")

        row.ep = row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

        row.ep:SetPoint("LEFT", row, "LEFT", 255, 0)
        row.ep:SetWidth(70)
        row.ep:SetJustifyH("RIGHT")

        row.gp = row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

        row.gp:SetPoint("LEFT", row, "LEFT", 335, 0)
        row.gp:SetWidth(70)
        row.gp:SetJustifyH("RIGHT")

        row.pr = row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

        row.pr:SetPoint("LEFT", row, "LEFT", 415, 0)
        row.pr:SetWidth(70)
        row.pr:SetJustifyH("RIGHT")

        SEPGP.UI.rows[i] = row
    end

    -- Footer
    local count = frame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )

    count:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 12)

    SEPGP.UI.count = count

    -- Refresh button
    local refresh = CreateFrame(
        "Button",
        nil,
        frame,
        "UIPanelButtonTemplate"
    )

    refresh:SetSize(80, 24)
    refresh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 8)
    refresh:SetText("Refresh")

    refresh:SetScript("OnClick", function()
        SEPGP.RefreshStandingsWindow()
    end)

    frame:Hide()

    SEPGP.UI.standingsFrame = frame
end


function SEPGP.ToggleStandingsWindow()
    if not SEPGP.UI.standingsFrame then
        SEPGP.CreateStandingsWindow()
    end

    local frame = SEPGP.UI.standingsFrame

    if frame:IsShown() then
        frame:Hide()
    else
        SEPGP.RefreshStandingsWindow()
        frame:Show()
    end
end