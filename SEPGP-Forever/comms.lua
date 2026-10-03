-- =========================================================
-- SEPGP Forever - Communications
-- =========================================================

SEPGP = SEPGP or {}
local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

AceComm:Embed(SEPGP)
AceSerializer:Embed(SEPGP)

local PROTOCOL_VERSION = 1

-- Lets us distinguish compressed binary payloads from plain control messages.
local COMPRESSED_PREFIX = "Z:"

-- =========================================================
-- Initialization
-- =========================================================

function SEPGP.InitializeComms()
    SEPGP:RegisterComm(
        SEPGP.PREFIX,
        "OnCommReceived"
    )

    print("SEPGP AceComm registered.")
end



function SEPGP:OnCommReceived(
        prefix,
        message,
        distribution,
        sender
)
    SEPGP.HandleAddonMessage(
            prefix,
            message,
            distribution,
            sender
    )

end


-- =========================================================
-- Serialization / compression
-- =========================================================

function SEPGP.EncodePayload(data)
    local serialized = SEPGP:Serialize(data)

    local compressed =
        LibDeflate:CompressDeflate(serialized)

    if not compressed then
        return nil
    end

    local encoded =
        LibDeflate:EncodeForWoWAddonChannel(compressed)

    if not encoded then
        return nil
    end

    return COMPRESSED_PREFIX .. encoded,
        #serialized,
        #compressed,
        #encoded
end


function SEPGP.DecodePayload(message)
    if message:sub(1, #COMPRESSED_PREFIX) ~= COMPRESSED_PREFIX then
        return nil, "Not a compressed SEPGP payload"
    end

    local encoded =
        message:sub(#COMPRESSED_PREFIX + 1)

    local decoded =
        LibDeflate:DecodeForWoWAddonChannel(encoded)

    if not decoded then
        return nil, "Failed to decode addon-channel payload"
    end

    local decompressed =
        LibDeflate:DecompressDeflate(decoded)

    if not decompressed then
        return nil, "Failed to decompress payload"
    end

    local success, data =
        SEPGP:Deserialize(decompressed)

    if not success then
        return nil, tostring(data)
    end

    return data
end

-- =========================================================
-- Sending
-- =========================================================

function SEPGP.SendPayload(
        data,
        channel,
        target,
        priority
)
    local message,
          serializedSize,
          compressedSize,
          encodedSize =
        SEPGP.EncodePayload(data)

    if not message then
        print("SEPGP: Failed to encode payload.")
        return false
    end

    SEPGP:SendCommMessage(
        SEPGP.PREFIX,
        message,
        channel,
        target,
        priority or "NORMAL"
    )

    return true,
        serializedSize,
        compressedSize,
        encodedSize
end

function SEPGP.SendAction(
        action,
        channel,
        target,
        priority
)
    local payload = {
        version = PROTOCOL_VERSION,
        kind = "ACTION",
        action = action,
    }

    return SEPGP.SendPayload(
        payload,
        channel,
        target,
        priority or "NORMAL"
    )
end

function SEPGP.SendActions(
        actions,
        channel,
        target
)
    local payload = {
        version = PROTOCOL_VERSION,
        kind = "ACTIONS",
        actions = actions,
    }

    local success,
          serializedSize,
          compressedSize,
          encodedSize =
        SEPGP.SendPayload(
            payload,
            channel,
            target,
            "BULK"
        )

    if not success then
        return false
    end

    print(
        string.format(
            "SEPGP: Sending %d actions (%d serialized -> %d compressed -> %d encoded bytes)",
            #actions,
            serializedSize,
            compressedSize,
            encodedSize
        )
    )

    return true
end

function SEPGP.BroadcastAction(action)
    SEPGP.SendAction(
        action,
        "OFFICER",
        nil,
        "NORMAL"
    )
end

function SEPGP.RequestSync()
    if not C_GuildInfo.IsGuildOfficer() then
        print("SEPGP: Full sync is only available to officers.")
        return
    end

    -- Ask other officers to contribute their action histories.
    SEPGP:SendCommMessage(
        SEPGP.PREFIX,
        "SYNC_REQUEST",
        "OFFICER",
        nil,
        "NORMAL"
    )

    -- Contribute everything we currently know.
    local actions = SEPGP.GetSortedActions()

    if #actions > 0 then
        SEPGP.SendActions(
            actions,
            "OFFICER"
        )
    end

    print(
        string.format(
            "SEPGP: Sync started, contributing %d actions.",
            #actions
        )
    )
end

function SEPGP.RequestStandings()
    SEPGP:SendCommMessage(
        SEPGP.PREFIX,
        "STANDINGS_REQUEST",
        "GUILD",
        nil,
        "NORMAL"
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

        SEPGP:SendCommMessage(
            SEPGP.PREFIX,
            message,
            "WHISPER",
            target,
            "BULK"
        )
    end

    SEPGP:SendCommMessage(
        SEPGP.PREFIX,
        "STANDINGS_DONE",
        "WHISPER",
        target,
        "BULK"
    )
end


-- =========================================================
-- Protocol parsing
-- =========================================================



function SEPGP.HandleCompressedPayload(
        message,
        channel,
        sender
)
    local payload, err =
        SEPGP.DecodePayload(message)

    if not payload then
        print(
            "SEPGP: Failed decoding payload:",
            tostring(err)
        )
        return
    end

    if type(payload) ~= "table" then
        print("SEPGP: Invalid payload.")
        return
    end

    if payload.version ~= PROTOCOL_VERSION then
        print(
            string.format(
                "SEPGP: Unsupported protocol version %s from %s",
                tostring(payload.version),
                tostring(sender)
            )
        )
        return
    end

    -- Actions are officer-only data.
    if payload.kind == "ACTION"
        or payload.kind == "ACTIONS" then

        if channel ~= "OFFICER" then
            return
        end

        if not C_GuildInfo.IsGuildOfficer() then
            return
        end
    end

    if payload.kind == "ACTION" then
        local action = payload.action

        if not SEPGP.ValidateAction(action) then
            print(
                "SEPGP: Invalid action received from",
                tostring(sender)
            )
            return
        end

        if SEPGP.ApplyAction(action) then
            print(
                string.format(
                    "SEPGP sync: %s %+d %s from %s",
                    action.player,
                    action.amount,
                    action.type,
                    sender
                )
            )
        end

        return
    end

    if payload.kind == "ACTIONS" then
        if type(payload.actions) ~= "table" then
            print(
                "SEPGP: Invalid action history from",
                tostring(sender)
            )
            return
        end

        local received = #payload.actions
        local applied = 0
        local invalid = 0

        for _, action in ipairs(payload.actions) do
            if SEPGP.ValidateAction(action) then
                if SEPGP.ApplyAction(action) then
                    applied = applied + 1
                end
            else
                invalid = invalid + 1
            end
        end

        print(
            string.format(
                "SEPGP: Received %d actions from %s; %d new, %d invalid.",
                received,
                tostring(sender),
                applied,
                invalid
            )
        )

        if SEPGP.UI
            and SEPGP.UI.standingsFrame
            and SEPGP.UI.standingsFrame:IsShown() then

            SEPGP.RefreshStandingsWindow()
        end

        return
    end

    print(
        "SEPGP: Unknown payload kind:",
        tostring(payload.kind)
    )
end
-- =========================================================
-- Receiving
-- =========================================================

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...

        if addonName == "SEPGP-Forever" then
            SEPGP.InitializeComms()
        end
    end
end)

function SEPGP.HandleAddonMessage(
        prefix,
        message,
        channel,
        sender
)
    if prefix ~= SEPGP.PREFIX then
        return
    end

    -- Serialized/compressed protocol message.
    if message:sub(1, #COMPRESSED_PREFIX)
        == COMPRESSED_PREFIX then

        SEPGP.HandleCompressedPayload(
            message,
            channel,
            sender
        )

        return
    end

    -- Everything below this point is a small,
    -- human-readable control message.

    local debugMessage =
        message:gsub("|", "||")

    print(
        "SEPGP COMM:",
        tostring(prefix),
        debugMessage,
        tostring(channel),
        tostring(sender)
    )

    local command =
        strsplit("|", message)

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



    local actions =
        SEPGP.GetSortedActions()

    if #actions > 0 then
        SEPGP.SendActions(
            actions,
            "OFFICER"
        )
    end

        return
    end

end
