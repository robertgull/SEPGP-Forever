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

    return player.GP > 0 and player.EP / player.GP or 0
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

    if action.type == "DECAY" and not SEPGP.IsValidDecay(action.amount) then
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

    elseif action.type == "DECAY" then
        local multiplier = 1 - action.amount / 100
        player.EP = player.EP * multiplier
        player.GP = player.GP * multiplier

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

function SEPGP.IsValidDecay(percent)
    return type(percent) == "number" and percent >= 0 and percent <= 100
end

function SEPGP.Decay(percent, reason)
    if not SEPGP.IsValidDecay(percent) then
        print("SEPGP: Decay percentage must be between 0 and 100.")
        return nil
    end

    local count = 0
    for name in pairs(SEPGP_DB.players) do
        local action = SEPGP.CreateAction("DECAY", name, percent, reason)
        if SEPGP.ApplyAction(action) then
            SEPGP.QueueAction(action)
            count = count + 1
        end
    end

    if SEPGP.UI
        and SEPGP.UI.standingsFrame
        and SEPGP.UI.standingsFrame:IsShown() then
        SEPGP.RefreshStandingsWindow()
    end

    return count
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

function SEPGP.RequestStandings()
    C_ChatInfo.SendAddonMessage(
        SEPGP.PREFIX,
        "STANDINGS_REQUEST",
        "GUILD"
    )

    print("SEPGP: Standings requested.")
end

function SEPGP.SendStandings(target)
    for name, player in pairs(SEPGP_DB.players) do
        local message = table.concat({
            "STANDING",
            name,
            tostring(player.EP),
            tostring(player.GP),
        }, "|")

        C_ChatInfo.SendAddonMessage(
            SEPGP.PREFIX,
            message,
            "WHISPER",
            target
        )
    end

    C_ChatInfo.SendAddonMessage(
        SEPGP.PREFIX,
        "STANDINGS_DONE",
        "WHISPER",
        target
    )
end

function SEPGP.RequestSync()
    if not C_GuildInfo.IsGuildOfficer() then
        print("SEPGP: Full sync is only available to officers.")
        return
    end

    -- Ask the other officers to contribute their actions.
    local result = C_ChatInfo.SendAddonMessage(
        SEPGP.PREFIX,
        "SYNC_REQUEST",
        "OFFICER"
    )

    if result ~= 0 then
        print(
            "SEPGP: Could not request sync. Result:",
            tostring(result)
        )
        return
    end

    -- Contribute everything we know as well.
    local actions = SEPGP.GetSortedActions()

    for _, action in ipairs(actions) do
        SEPGP.QueueAction(action)
    end

    print(
        string.format(
            "SEPGP: Sync started, contributing %d actions.",
            #actions
        )
    )
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
                "[%s] %+g %s -> %s | %s/%s -> %s/%s | by %s",
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
                "%d. %s | EP: %g | GP: %g | PR: %.2f",
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
-- Communication
-- =========================================================
SEPGP.sendQueue = SEPGP.sendQueue or {}
SEPGP.isSending = false

function SEPGP.QueueAction(action)
    table.insert(SEPGP.sendQueue, action)
    SEPGP.ProcessSendQueue()
end

function SEPGP.ProcessSendQueue()
    if SEPGP.isSending then
        return
    end

    if #SEPGP.sendQueue == 0 then
        return
    end

    SEPGP.isSending = true

    -- Peek. Do NOT remove it yet.
    local action = SEPGP.sendQueue[1]

    local result = SEPGP.BroadcastAction(action)

    local delay

    if result == 0 then
        -- Successfully accepted for sending.
        table.remove(SEPGP.sendQueue, 1)

        -- Try the next one quickly while we still have allowance.
        delay = 0.1

    elseif result == 3 or result == 8 then
        -- 3 = AddonMessageThrottle
        -- 8 = ChannelThrottle
        --
        -- Leave the action at position 1 and retry later.
        delay = 1.1

    else
        print(
            "SEPGP: Failed sending action",
            tostring(action.id),
            "result:",
            tostring(result)
        )

        -- Permanent/unknown failure: discard so we don't lock the queue.
        table.remove(SEPGP.sendQueue, 1)

        delay = 0.5
    end

    C_Timer.After(delay, function()
        SEPGP.isSending = false
        SEPGP.ProcessSendQueue()
    end)
end


function SEPGP.SendAction(action, channel, target)
    local beforeEP = action.before and action.before.EP or ""
    local beforeGP = action.before and action.before.GP or ""
    local afterEP = action.after and action.after.EP or ""
    local afterGP = action.after and action.after.GP or ""

    local message = table.concat({
        "ACTION",
        action.id,
        action.type,
        action.player,
        tostring(action.amount),
        action.actor,
        tostring(action.timestamp),
        tostring(beforeEP),
        tostring(beforeGP),
        tostring(afterEP),
        tostring(afterGP),
    }, "|")

    return C_ChatInfo.SendAddonMessage(
        SEPGP.PREFIX,
        message,
        channel,
        target
    )
end

function SEPGP.ParseAction(message)
    local command, id, actionType, playerName,
          amount, actor, timestamp,
          beforeEP, beforeGP,
          afterEP, afterGP =
        strsplit("|", message)


    if command ~= "ACTION" then
        return nil
    end

    local action = {
        id = id,
        type = actionType,
        player = SEPGP.NormalizeName(playerName),
        amount = tonumber(amount),
        actor = actor,
        timestamp = tonumber(timestamp),
    }

    if beforeEP ~= "" and beforeGP ~= "" then
        action.before = {
            EP = tonumber(beforeEP),
            GP = tonumber(beforeGP),
        }
    end

    if afterEP ~= "" and afterGP ~= "" then
        action.after = {
            EP = tonumber(afterEP),
            GP = tonumber(afterGP),
        }
    end

    if not id
        or not actionType
        or not playerName
        or not amount
        or not timestamp then
        return nil
    end

    if actionType ~= "EP" and actionType ~= "GP" and actionType ~= "DECAY" then
        return nil
    end

    if actionType == "DECAY" and not SEPGP.IsValidDecay(action.amount) then
        return nil
    end

    return action
end

function SEPGP.BroadcastAction(action)
    return SEPGP.SendAction(action, "OFFICER")
end

function SEPGP.InitializeComms()
    local result = C_ChatInfo.RegisterAddonMessagePrefix(SEPGP.PREFIX)

    print("SEPGP comm prefix registered:", tostring(result))
end


-- =========================================================
-- Receive actions
-- =========================================================
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...

        if addonName == "SEPGP-Forever" then
            SEPGP.InitializeComms()
        end

    elseif event == "CHAT_MSG_ADDON" then
        SEPGP.HandleAddonMessage(...)
    end
end)

function SEPGP.HandleAddonMessage(prefix, message, channel, sender)
local debugMessage = message:gsub("|", "||")

    print(
        "CHAT_MSG_ADDON:",
        tostring(prefix),
        debugMessage,
        tostring(channel),
        tostring(sender)
    )
    if prefix ~= SEPGP.PREFIX then
        return
    end

    local command = strsplit("|", message)

    if command == "STANDINGS_REQUEST" then
        local isOfficer = C_GuildInfo.IsGuildOfficer()

        print(
            "STANDINGS_REQUEST from:",
            tostring(sender),
            "channel:",
            tostring(channel),
            "officer:",
            tostring(isOfficer)
        )

        if not isOfficer then
            return
        end

        print("SEPGP: Sending standings to", sender)
        SEPGP.SendStandings(sender)
        return
    end

    if command == "STANDINGS_DONE" then
        print("SEPGP: Standings updated.")

        if SEPGP.UI
            and SEPGP.UI.standingsFrame
            and SEPGP.UI.standingsFrame:IsShown() then
            SEPGP.RefreshStandingsWindow()
        end

        return
    end

    if command == "STANDING" then
        local _, playerName, ep, gp =
            strsplit("|", message)

        playerName = SEPGP.NormalizeName(playerName)

        SEPGP_DB.players[playerName] = {
            EP = tonumber(ep),
            GP = tonumber(gp),
        }

        return
    end

    if command == "SYNC_REQUEST" then
        local isOfficer = C_GuildInfo.IsGuildOfficer()

        print(
            "SYNC_REQUEST from:",
            tostring(sender),
            "channel:",
            tostring(channel),
            "officer:",
            tostring(isOfficer)
        )
        if channel ~= "OFFICER" then
            return
        end

        if not isOfficer then
            return
        end

        local me = GetUnitName("player", true)

        -- We already broadcast our actions when we initiated the sync.
        if SEPGP.NormalizeName(sender) == SEPGP.NormalizeName(me) then
            return
        end

        local actions = SEPGP.GetSortedActions()

        for _, action in ipairs(actions) do
            SEPGP.QueueAction(action)
        end

        return
    end
    if command == "ACTION" then
        if channel ~= "OFFICER" then
            return
        end

        if not C_GuildInfo.IsGuildOfficer() then
            return
        end
        local action = SEPGP.ParseAction(message)

        if not action then
            return
        end

        if SEPGP.ApplyAction(action) then
            print(
                string.format(
                    "SEPGP sync: %s %+g %s from %s",
                    action.player,
                    action.amount,
                    action.type,
                    sender
                )
            )
        end

        return
    end
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
        print("/sep decay <percent>")
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
                "%s: %g EP / %g GP / %.2f PR",
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
                    "SEPGP: %s %+d EP -> %g EP (Action %s)",
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
                    "SEPGP: %s %+d GP -> %g GP (Action %s)",
                    gpName,
                    gpAmount,
                    player.GP,
                    action.id
                )
            )
        end

        return
    end

    -- /sep decay 20
    local decayCommand, decayAmount = msg:match("^(%S+)%s*(.-)%s*$")
    if decayCommand and string.lower(decayCommand) == "decay" then
        local percent = tonumber(decayAmount)
        if not SEPGP.IsValidDecay(percent) then
            print("Usage: /sep decay <percent> (0 to 100)")
            return
        end

        local count = SEPGP.Decay(percent)
        if count then
            print(string.format("SEPGP: Applied %g%% decay to %d players.", percent, count))
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
