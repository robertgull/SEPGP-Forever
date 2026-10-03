-- =========================================================
-- SEPGP Forever
-- =========================================================
SEPGP = SEPGP or {}

SEPGP.PREFIX = "SEPGPF"
SEPGP.BASE_GP = 100


-- =========================================================
-- Saved Variables
-- =========================================================

SEPGP_DB = SEPGP_DB or {}

SEPGP_DB.revision = SEPGP_DB.revision or 0
SEPGP_DB.localCounter = SEPGP_DB.localCounter or 0
SEPGP_DB.players = SEPGP_DB.players or {}
SEPGP_DB.actions = SEPGP_DB.actions or {}


local ID_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"




-- =========================================================
-- InitializeRandomSeed

function SEPGP.RandomToken(length)
    local result = {}

    for i = 1, length do
        local index = math.random(1, #ID_CHARS)
        result[i] = ID_CHARS:sub(index, index)
    end

    return table.concat(result)
end

function SEPGP.GenerateActionID()
    SEPGP_DB.localCounter = (SEPGP_DB.localCounter or 0) + 1

    return string.format(
        "%d-%s",
        SEPGP_DB.localCounter,
        SEPGP.RandomToken(8)
    )
end

-- =========================================================
-- Player / EPGP functions
-- =========================================================
function SEPGP.NormalizeName(name)
    if not name then
        return nil
    end

    return string.lower(name)
end

function SEPGP.GetPlayer(name)
    name = SEPGP.NormalizeName(name)
    return SEPGP_DB.players[name]
end


function SEPGP.EnsurePlayer(name)
    name = SEPGP.NormalizeName(name)
    if not SEPGP_DB.players[name] then
        SEPGP_DB.players[name] = {
            EP = 0,
            GP = SEPGP.BASE_GP,
        }
    end

    return SEPGP_DB.players[name]
end


function SEPGP.GetPR(name)
    local player = SEPGP.GetPlayer(name)

    if not player then
        return 0
    end

    return player.EP / player.GP
end


function SEPGP.ValidateAction(action)
    if type(action) ~= "table" then
        return false
    end

    if type(action.id) ~= "string"
        or action.id == "" then
        return false
    end

    if action.type ~= "EP"
        and action.type ~= "GP" then
        return false
    end

    if type(action.player) ~= "string"
        or action.player == "" then
        return false
    end

    if type(action.amount) ~= "number" then
        return false
    end

    if type(action.timestamp) ~= "number" then
        return false
    end

    if type(action.actor) ~= "string" then
        action.actor = "Unknown"
    end

    action.player =
        SEPGP.NormalizeName(action.player)

    return true
end

function SEPGP.CreateAction(actionType, playerName, amount, reason)
    local action = {
        id = SEPGP.GenerateActionID(),
        actor = GetUnitName("player", true) or "Unknown",
        timestamp = time(),
        type = actionType,
        player = SEPGP.NormalizeName(playerName),
        amount = amount,
        reason = reason or "",
    }

    return action
end

function SEPGP.ApplyAction(action)
    if SEPGP_DB.actions[action.id] then
        return false
    end

    local player = SEPGP.EnsurePlayer(action.player)

    local beforeEP = player.EP
    local beforeGP = player.GP

    if not action.before then
        action.before = {
            EP = beforeEP,
            GP = beforeGP,
        }
    end

    if action.type == "EP" then
        player.EP = math.max(
            0,
            player.EP + action.amount
        )

    elseif action.type == "GP" then
        player.GP = math.max(
            SEPGP.BASE_GP,
            player.GP + action.amount
        )

    else
        print("SEPGP: Unknown action type:", tostring(action.type))
        return false
    end

    if not action.after then
        action.after = {
            EP = player.EP,
            GP = player.GP,
        }
    end

    SEPGP_DB.actions[action.id] = action
    SEPGP_DB.revision = SEPGP_DB.revision + 1

    return true
end

function SEPGP.AddEP(name, amount, reason)
    local action = SEPGP.CreateAction(
        "EP",
        name,
        amount,
        reason
    )

    if SEPGP.ApplyAction(action) then
        SEPGP.BroadcastAction(action)
        return action
    end

    return nil
end


function SEPGP.AddGP(name, amount, reason)
    local action = SEPGP.CreateAction(
        "GP",
        name,
        amount,
        reason
    )

    if SEPGP.ApplyAction(action) then
        SEPGP.BroadcastAction(action)
        return action
    end

    return nil
end

-- =========================================================
-- Syncing and history
-- =========================================================
function SEPGP.GetSortedActions()
    local actions = {}

    for _, action in pairs(SEPGP_DB.actions) do
        table.insert(actions, action)
    end

    table.sort(actions, function(a, b)
        if a.timestamp == b.timestamp then
            return a.id < b.id
        end

        return a.timestamp < b.timestamp
    end)

    return actions
end


function SEPGP.PrintHistory()
    local actions = SEPGP.GetSortedActions()

    if #actions == 0 then
        print("SEPGP: No action history.")
        return
    end

    print("=== SEPGP Action History ===")

    for _, action in ipairs(actions) do
        local beforeEP = action.before and action.before.EP or "?"
        local beforeGP = action.before and action.before.GP or "?"
        local afterEP = action.after and action.after.EP or "?"
        local afterGP = action.after and action.after.GP or "?"

        print(
            string.format(
                "[%s] %+d %s -> %s | %s/%s -> %s/%s | by %s",
                action.id or "?",
                action.amount or 0,
                action.type or "?",
                action.player or "?",
                tostring(beforeEP),
                tostring(beforeGP),
                tostring(afterEP),
                tostring(afterGP),
                action.actor or "?"
            )
        )
    end

    print("=== " .. #actions .. " actions ===")
end

function SEPGP.PrintStandings()
    local standings = {}

    for name, player in pairs(SEPGP_DB.players) do
        table.insert(standings, {
            name = name,
            EP = player.EP,
            GP = player.GP,
            PR = player.GP > 0 and player.EP / player.GP or 0,
        })
    end

    table.sort(standings, function(a, b)
        if a.PR == b.PR then
            return a.name < b.name
        end

        return a.PR > b.PR
    end)

    if #standings == 0 then
        print("SEPGP: No standings.")
        return
    end

    print("=== SEPGP Standings ===")

    for index, player in ipairs(standings) do
        print(
            string.format(
                "%d. %s | EP: %d | GP: %d | PR: %.2f",
                index,
                player.name,
                player.EP,
                player.GP,
                player.PR
            )
        )
    end

    print("=== " .. #standings .. " players ===")
end



-- =========================================================
-- Slash commands
-- =========================================================

SLASH_SEPGP1 = "/sep"
SLASH_SEPGP2 = "/sepgp"


SlashCmdList["SEPGP"] = function(msg)
    msg = msg or ""

    if msg == "" then
        print("SEPGP Forever")
        print("/sep sync")
        print("/sep standings")
        print("/sep history")
        print("/sep addep <player> <amount>")
        print("/sep addgp <player> <amount>")
        print("/sep get <player>")
        print("/sep me")
        print("/sep testid")
        return
    end

    -- /sep me
    if string.lower(msg) == "me" then
        local name = GetUnitName("player", true)

        print("Your SEPGP name is: " .. tostring(name))
        return
    end

    -- /sep testid
    if string.lower(msg) == "testid" then
        local id = SEPGP.GenerateActionID()

        print("Generated action ID:", id)
        return
    end


    -- /sep get Ducky Dru
    local getName =
        msg:match("^[Gg][Ee][Tt]%s+(.+)$")

    if getName then
        local player = SEPGP.GetPlayer(getName)

        if not player then
            print("No SEPGP data for " .. getName)
            return
        end

        local pr = SEPGP.GetPR(getName)

        print(
            string.format(
                "%s: %d EP / %d GP / %.2f PR",
                getName,
                player.EP,
                player.GP,
                pr
            )
        )

        return
    end

    -- /sep addep Ducky Dru 100
    local epName, epAmount =
        msg:match("^[Aa][Dd][Dd][Ee][Pp]%s+(.+)%s+([%-]?%d+)$")

    if epName and epAmount then
        epAmount = tonumber(epAmount)

        local action = SEPGP.AddEP(epName, epAmount)

        if action then
            local player = SEPGP.GetPlayer(epName)

            print(
                string.format(
                    "SEPGP: %s %+d EP -> %d EP (Action %s)",
                    epName,
                    epAmount,
                    player.EP,
                    action.id
                )
            )
        end

        return
    end

    -- /sep addgp Ducky Dru 250
    local gpName, gpAmount =
        msg:match("^[Aa][Dd][Dd][Gg][Pp]%s+(.+)%s+([%-]?%d+)$")

    if gpName and gpAmount then
        gpAmount = tonumber(gpAmount)

        local action = SEPGP.AddGP(gpName, gpAmount)

        if action then
            local player = SEPGP.GetPlayer(gpName)

            print(
                string.format(
                    "SEPGP: %s %+d GP -> %d GP (Action %s)",
                    gpName,
                    gpAmount,
                    player.GP,
                    action.id
                )
            )
        end

        return
    end

    -- /sep history
    if string.lower(msg) == "history" then
        SEPGP.PrintHistory()
        return
    end

    if string.lower(msg) == "cleardb" then -- TODO: REMOVE LATER, DANGEROUS
        SEPGP_DB = {
            revision = 0,
            localCounter = 0,
            players = {},
            actions = {},
        }

        print("SEPGP database cleared.")
        return
    end

    -- /sep standings
    if string.lower(msg) == "standings" then
        SEPGP.PrintStandings()
        return
    end

    -- /sep sync
    if string.lower(msg) == "sync" then
        print(
            "IsGuildOfficer:",
            tostring(C_GuildInfo.IsGuildOfficer())
        )
        SEPGP.RequestSync()
        return
    end

    -- /sep update
    if string.lower(msg) == "update" then
        SEPGP.RequestStandings()
        return
    end

    if string.lower(msg) == "show" then
        SEPGP.ToggleStandingsWindow()
        return
    end

    print("Unknown SEPGP command.")
end