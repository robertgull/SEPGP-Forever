-- Missing-action synchronization with a checkpoint confirmed by every officer.
local PREFIX = "SEP_HISTORY"
local deflate = LibStub("LibDeflate")
local active, counter
counter = 0
local packetCounter, fragments = 0, {}
local NameKey = SEPGP.GuildNameKey
local function Me() return NameKey(GetUnitName("player", true)) end
local function Finite(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function Roster()
    local officers, complete = {}, true
    for index = 1, GetNumGuildMembers(true) do
        local name, _, rank, _, _, _, _, _, online, _, _, _, _, mobile = GetGuildRosterInfo(index)
        if not name or rank == nil then complete = false
        else
            local isOfficer = SEPGP.IsGuildOfficerName(name)
            if rank ~= 0 then
                if not C_GuildInfo or not C_GuildInfo.GuildControlGetRankFlags then complete = false
                else
                    local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rank + 1)
                    if not ok or type(flags) ~= "table" or type(flags[12]) ~= "boolean" then complete = false end
                end
            end
            if isOfficer then officers[NameKey(name)] = online and not mobile and true or false end
        end
    end
    if officers[Me()] == nil then complete = false end
    local names, allOnline = {}, true
    for name, online in pairs(officers) do
        names[#names + 1] = name
        if not online then allOnline = false end
    end
    table.sort(names)
    local guild = GetGuildInfo("player") or ""
    return officers, guild .. ":" .. table.concat(names, ","), complete and allOnline, complete
end

-- Exclude local before/after snapshots and optional display reasons: old wire
-- actions did not carry reasons, and snapshots depend on arrival order.
local function Signature(action)
    return SEPGP:Serialize({ action.id, action.timestamp, action.type,
        SEPGP.NormalizeName(action.player), action.amount, action.actor or "Unknown" })
end
local function Summary(cutoff, exclusive)
    local entries, count = {}, 0
    for _, action in ipairs(SEPGP.GetSortedActions()) do
        if action.timestamp < cutoff or (not exclusive and action.timestamp == cutoff) then
            entries[#entries + 1] = Signature(action)
            count = count + 1
        end
    end
    return tostring(count) .. ":" .. tostring(deflate:Adler32(table.concat(entries, "\n")))
end
local function Checkpoint(roster)
    local cp = SEPGP_DB.syncCheckpoint
    if type(cp) == "table" and Finite(cp.timestamp) and cp.roster == roster
        and cp.summary == Summary(cp.timestamp) then return cp.timestamp end
    return 0
end
function SEPGP.GetSyncCheckpoint()
    local cp = SEPGP_DB.syncCheckpoint
    if type(cp) ~= "table" then return nil end
    local _, roster, _, complete = Roster()
    if complete and cp.roster == roster and Finite(cp.timestamp)
        and cp.summary == Summary(cp.timestamp) then return cp.timestamp end
    return nil
end

-- Printable payloads avoid control characters and arbitrary binary bytes in
-- the server's addon whisper path. Continue accepting the older Z: encoding.
local function EncodeHistoryPayload(payload)
    local compressed = deflate:CompressDeflate(SEPGP:Serialize(payload))
    return compressed and ("P:" .. deflate:EncodeForPrint(compressed))
end
function SEPGP.DecodeHistoryPayload(message)
    if message:sub(1, 2) ~= "P:" then return SEPGP.DecodePayload(message) end
    local compressed = deflate:DecodeForPrint(message:sub(3))
    local serialized = compressed and deflate:DecompressDeflate(compressed)
    if not serialized then return nil, "Invalid printable history payload" end
    local success, payload = SEPGP:Deserialize(serialized)
    if not success then return nil, tostring(payload) end
    return payload
end

local function Send(kind, values, target)
    if not active then return end
    -- Identity keys may contain an inferred/normalized realm. They are not
    -- whisper addresses: reply using the exact sender name supplied by WoW.
    local address = target and active.addresses[target]
    if target and not address then return end
    local payload = values or {}
    payload.version, payload.kind, payload.session = 1, kind, active.id
    local encoded = EncodeHistoryPayload(payload)
    if not encoded then return end
    active.progress = GetTime()
    -- One priority preserves DATA-before-VERIFY ordering through AceComm/CTL.
    local channel = target and "WHISPER" or "OFFICER"
    if kind == "INVENTORY" then
        local count = 0
        for _ in pairs(payload.ids) do count = count + 1 end
        print("SEPGP: Sending inventory of " .. count .. " actions to " .. SEPGP.DisplayName(address) .. ".")
    end
    -- Keep each physical message small. Large inventories previously depended
    -- on AceComm's control-byte multipart framing, which some server transports
    -- do not deliver intact even though the small HELLO exchange succeeds.
    if #encoded <= 200 then
        SEPGP:SendCommMessage(PREFIX, encoded, channel, address, "BULK")
    else
        packetCounter = packetCounter + 1
        local total = math.ceil(#encoded / 200)
        for part = 1, total do
            local chunk = "H:" .. packetCounter .. ":" .. part .. ":" .. total .. ":"
                .. encoded:sub((part - 1) * 200 + 1, part * 200)
            SEPGP:SendCommMessage(PREFIX, chunk, channel, address, "BULK")
        end
    end
end

local function ReceivePacket(message, channel, sender)
    if message:sub(1, 2) ~= "H:" then return SEPGP.DecodeHistoryPayload(message) end
    local id, part, total, data = message:match("^H:(%d+):(%d+):(%d+):(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not part or not total or part < 1 or part > total or total > 10000 or #data > 200 then return end
    local key = sender .. ":" .. channel .. ":" .. id
    for stored, pending in pairs(fragments) do
        if GetTime() - pending.updated > 300 then fragments[stored] = nil end
    end
    local packet = fragments[key]
    if not packet then
        packet = { total = total, count = 0, data = {}, updated = GetTime() }
        fragments[key] = packet
    end
    if packet.total ~= total or (packet.data[part] and packet.data[part] ~= data) then
        fragments[key] = nil
        return nil, "Conflicting history fragment " .. part .. "/" .. total
    end
    if not packet.data[part] then
        packet.data[part], packet.count = data, packet.count + 1
        packet.updated = GetTime()
        if active and active.peers[sender] then active.progress = GetTime() end
    end
    if packet.count < total then return end
    fragments[key] = nil
    return SEPGP.DecodeHistoryPayload(table.concat(packet.data, "", 1, total))
end
local function Stop(message)
    active = nil
    if message then print("SEPGP: " .. message) end
end
function SEPGP.CancelHistorySync()
    if not active then return end
    Send("ABORT")
    Stop()
end
local function Complete(checkpointConfirmed)
    local count = active.newActions or 0
    local message = string.format("SEPGP: Sync complete - %d new actions received. %s", count,
        checkpointConfirmed and "Checkpoint confirmed by all officers."
            or "Checkpoint unchanged: not all officers are online and confirmed.")
    Stop()
    print("|cff33ff99" .. message .. "|r")
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("SEPGP: Sync complete", 0.2, 1, 0.6)
    end
end
local function WaitingFor()
    local values = active.phase == "hello" and active.hello
        or active.phase == "inventory" and active.inventories
        or active.phase == "verify" and active.acks
    local names, seen = {}, {}
    for name in pairs(active.peers) do
        local missing = values and not values[name]
        if active.phase == "gather" then
            for id, source in pairs(active.wanted or {}) do
                if source == name and not active.received[id] then missing = true; break end
            end
        elseif active.leader ~= Me() then
            missing = name == active.leader
        end
        if missing and not seen[name] then names[#names + 1] = SEPGP.DisplayName(name); seen[name] = true end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ", ") or "officer confirmation"
end
local function GuardPhase()
    local session, phase = active, active.phase
    local function CheckTimeout()
        if active == session and active.phase == phase then
            local remaining = 300 - (GetTime() - active.progress)
            if remaining > 0 then C_Timer.After(remaining, CheckTimeout)
            else
                local reason = "Sync timed out during " .. active.phase .. "; waiting for " .. WaitingFor()
                    .. ". Checkpoint unchanged. Run /sep sync again."
                Send("ABORT", { reason = reason })
                Stop(reason)
            end
        end
    end
    C_Timer.After(300, CheckTimeout)
end
local function SetPhase(phase)
    active.phase = phase
    active.progress = GetTime()
    GuardPhase()
end
local function Everyone(values)
    for name in pairs(active.peers) do if not values[name] then return false end end
    return true
end
local function Inventory(floor, cutoff)
    local ids = {}
    for _, action in ipairs(SEPGP.GetSortedActions()) do
        -- Include the boundary second to avoid losing equal-timestamp actions.
        if action.timestamp >= floor and action.timestamp <= cutoff then
            ids[action.id] = action.timestamp
        end
    end
    return ids
end
local function ValidAction(action)
    return type(action) == "table" and type(action.id) == "string" and action.id ~= ""
        and type(action.player) == "string" and action.player ~= ""
        and type(action.actor) == "string" and Finite(action.timestamp)
        and (action.reason == nil or type(action.reason) == "string")
        and type(action.amount) == "number" and action.amount == action.amount
        and math.abs(action.amount) < math.huge
        and (action.type == "EP" or action.type == "GP"
            or (action.type == "DECAY" and SEPGP.IsValidDecay(action.amount)))
end
-- Live awards also use the compressed transport. Item hyperlinks contain pipes
-- and can exceed the old 255-byte ACTION packet; serialize them intact.
function SEPGP.SendAction(action, channel, target)
    local encoded = SEPGP.EncodePayload({ version = 1, kind = "ACTION", action = action })
    if not encoded then return -1 end
    SEPGP:SendCommMessage(PREFIX, encoded, channel or "OFFICER", target, "NORMAL")
    return 0 -- Accepted into AceComm's throttled queue, as expected by the core.
end
local function SendRecords(ids, target)
    local batch = {}
    for _, action in ipairs(SEPGP.GetSortedActions()) do
        if ids[action.id] then
            batch[#batch + 1] = action
            if #batch == 40 then Send("DATA", { actions = batch }, target); batch = {} end
        end
    end
    if #batch > 0 then Send("DATA", { actions = batch }, target) end
end

-- Missing history can precede live awards or standings already received by a
-- newly promoted officer. Adding it to current totals applies decay in arrival
-- order. Rebuild affected accounts from the first recorded baseline instead.
local function ImportRecords(actions, rebuildAll)
    local affected = {}
    for _, action in ipairs(actions) do
        if SEPGP.ApplyAction(action) then
            active.newActions = (active.newActions or 0) + 1
            affected[SEPGP.NormalizeName(action.player)] = true
        end
    end
    local rebuilt = {}
    for _, action in ipairs(SEPGP.GetSortedActions()) do
        local key = SEPGP.NormalizeName(action.player)
        if rebuildAll or affected[key] then
            local player = rebuilt[key]
            if not player then
                local before = action.before
                player = { EP = before and before.EP or 0, GP = before and before.GP or SEPGP.BASE_GP }
                rebuilt[key] = player
            end
            if action.type == "EP" then player.EP = math.max(0, player.EP + action.amount)
            elseif action.type == "GP" and action.amount ~= 0 then
                player.GP = math.max(SEPGP.BASE_GP, player.GP + action.amount)
            elseif action.type == "DECAY" and SEPGP.IsValidDecay(action.amount) then
                local multiplier = 1 - action.amount / 100
                player.EP, player.GP = player.EP * multiplier, player.GP * multiplier
            end
        end
    end
    local changed = false
    for key, player in pairs(rebuilt) do
        local current = SEPGP_DB.players[key]
        if not current or current.EP ~= player.EP or current.GP ~= player.GP then
            SEPGP_DB.players[key] = player
            changed = true
        end
    end
    if changed then SEPGP_DB.revision = SEPGP_DB.revision + 1 end
end

local BeginInventory, Gather, Verify, Finish, Acknowledge
BeginInventory = function(floor)
    active.floor, active.inventories, active.prefixes = floor, {}, {}
    SetPhase("inventory")
    active.inventories[Me()] = Inventory(floor, active.cutoff)
    active.prefixes[Me()] = Summary(floor, true)
    Send("INVENTORY_REQUEST", { floor = floor, cutoff = active.cutoff })
    if Everyone(active.inventories) then Gather() end
end
Gather = function()
    local prefix = active.prefixes[Me()]
    for name in pairs(active.peers) do
        if active.prefixes[name] ~= prefix then
            if active.floor > 0 then BeginInventory(0)
            else Stop("Histories disagree below the checkpoint; checkpoint unchanged.") end
            return
        end
    end
    SetPhase("gather")
    active.union, active.wanted, active.received = {}, {}, {}
    for name in pairs(active.peers) do
        for id, timestamp in pairs(active.inventories[name]) do
            if active.union[id] and active.union[id] ~= timestamp then
                Stop("Conflicting action timestamps; checkpoint unchanged."); return
            end
            active.union[id] = timestamp
            if not SEPGP_DB.actions[id] and not active.wanted[id] then active.wanted[id] = name end
        end
    end
    local requests = {}
    for id, source in pairs(active.wanted) do
        requests[source] = requests[source] or {}
        requests[source][id] = true
    end
    for source, ids in pairs(requests) do Send("FETCH", { ids = ids }, source) end
    if next(active.wanted) == nil then Verify() end
end
Verify = function()
    local actions = {}
    for _, action in pairs(active.received) do actions[#actions + 1] = action end
    table.sort(actions, function(a, b)
        return a.timestamp < b.timestamp or (a.timestamp == b.timestamp and a.id < b.id)
    end)
    ImportRecords(actions, true)
    local candidate = 0
    for _, action in ipairs(SEPGP.GetSortedActions()) do
        if action.timestamp <= active.cutoff then candidate = math.max(candidate, action.timestamp) end
    end
    active.candidate, active.summary, active.acks = candidate, Summary(candidate), { [Me()] = true }
    SetPhase("verify")
    for name in pairs(active.peers) do
        if name ~= Me() then
            local missing = {}
            for id in pairs(active.union) do
                if not active.inventories[name][id] then missing[id] = true end
            end
            SendRecords(missing, name)
            Send("VERIFY", { timestamp = candidate, summary = active.summary, roster = active.roster }, name)
        end
    end
    if Everyone(active.acks) then Finish() end
end
local function CanCommit()
    local officers, roster, allOnline = Roster()
    if not allOnline or roster ~= active.roster then return false end
    for name in pairs(officers) do if not active.peers[name] then return false end end
    return Summary(active.candidate) == active.summary
end
Finish = function()
    if CanCommit() then
        Send("COMMIT", { timestamp = active.candidate, summary = active.summary, roster = active.roster })
        SEPGP_DB.syncCheckpoint = { timestamp = active.candidate, summary = active.summary, roster = active.roster }
        Complete(true)
    else
        Send("DONE")
        Complete(false)
    end
end
Acknowledge = function()
    if active.phase ~= "verify" or not active.summary then return end
    if Summary(active.candidate) ~= active.summary then return end
    -- A retry also repairs totals left by an earlier arrival-order replay, even
    -- when all history IDs are already present and no DATA needs transferring.
    ImportRecords({}, true)
    Send("ACK", { timestamp = active.candidate, summary = active.summary }, active.leader)
    active.acknowledged = true
end
local function StartExchange()
    if not active or active.phase ~= "hello" then return end
    -- Officers who do not respond cannot participate or approve a checkpoint.
    local missing = {}
    for name in pairs(active.peers) do
        if not active.hello[name] then
            missing[#missing + 1] = SEPGP.DisplayName(name)
            active.peers[name] = nil
        end
    end
    if #missing > 0 then
        table.sort(missing)
        print("SEPGP: No history sync reply from " .. table.concat(missing, ", ")
            .. ". Check that these officers have the updated addon; checkpoint cannot advance.")
    end
    local floor = active.cutoff
    for name in pairs(active.peers) do floor = math.min(floor, active.hello[name]) end
    BeginInventory(floor)
end

function SEPGP.RequestSync()
    if not SEPGP.CanEditOfficerSettings() then print("SEPGP: Sync is officer only."); return false end
    if active then print("SEPGP: A sync is already in progress."); return false end
    local officers, roster, _, complete = Roster()
    if not IsInGuild() or not complete then
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        print("SEPGP: Guild officer roster is not ready. Try /sep sync again shortly.")
        return false
    end
    local peers = {}
    for name, online in pairs(officers) do if online then peers[name] = true end end
    if not peers[Me()] then print("SEPGP: Officer roster is not ready."); return false end
    counter = counter + 1
    local cutoff = math.max(0, time())
    active = { id = Me() .. ":" .. tostring(GetTime()) .. ":" .. counter, leader = Me(),
        peers = peers, roster = roster, cutoff = cutoff, hello = {}, addresses = {} }
    active.hello[Me()] = math.min(Checkpoint(roster), cutoff)
    SetPhase("hello")
    Send("HELLO", { cutoff = cutoff, roster = roster })
    print("SEPGP: Sync started; exchanging missing actions after the shared checkpoint.")
    local session = active
    C_Timer.After(15, function() if active == session then StartExchange() end end)
    if Everyone(active.hello) then StartExchange() end
    return true
end

function SEPGP:OnHistoryCommReceived(prefix, message, channel, sender)
    if prefix ~= PREFIX or not SEPGP.CanEditOfficerSettings() or not IsInGuild()
        or (channel ~= "OFFICER" and channel ~= "WHISPER")
        or not SEPGP.IsGuildOfficerName(sender) then return end
    local address = sender
    sender = NameKey(sender)
    if sender == Me() then return end
    local payload, decodeError = ReceivePacket(message, channel, sender)
    if type(payload) ~= "table" or payload.version ~= 1 then
        if active and decodeError then
            print("SEPGP: Could not decode history packet from " .. SEPGP.DisplayName(address) .. ": " .. decodeError)
        end
        return
    end
    if payload.kind == "ACTION" then
        if channel ~= "OFFICER" or not ValidAction(payload.action) then return end
        local action = payload.action
        if action.reason ~= nil and type(action.reason) ~= "string" then return end
        local existing = SEPGP_DB.actions[action.id]
        if existing then
            if Signature(existing) == Signature(action) and (not existing.reason or existing.reason == "")
                and action.reason and action.reason ~= "" then
                existing.reason = action.reason
                SEPGP_DB.revision = SEPGP_DB.revision + 1
            end
        else SEPGP.ApplyAction(action) end
        return
    end
    if type(payload.session) ~= "string" then return end
    if payload.kind == "HELLO" then
        if channel ~= "OFFICER" or active or not Finite(payload.cutoff) or payload.cutoff > time() then return end
        local officers, roster, _, complete = Roster()
        if not complete or roster ~= payload.roster then return end
        active = { id = payload.session, leader = sender, roster = roster, cutoff = payload.cutoff,
            peers = {}, addresses = { [sender] = address } }
        for name, online in pairs(officers) do if online then active.peers[name] = true end end
        SetPhase("hello")
        print("SEPGP: Sync joined; exchanging history with " .. SEPGP.DisplayName(address) .. ".")
        Send("HELLO_REPLY", { checkpoint = math.min(Checkpoint(roster), active.cutoff) }, sender)
        return
    end
    if not active or payload.session ~= active.id or not active.peers[sender] then return end
    active.addresses[sender] = address
    active.progress = GetTime()
    if payload.kind == "ABORT" and channel == "OFFICER" then
        if type(payload.reason) == "string" then Stop("Sync cancelled: " .. payload.reason)
        else Stop("Sync cancelled: " .. SEPGP.DisplayName(address) .. " cleared their database. Checkpoint unchanged.") end
        return
    end
    local leader = active.leader == Me()
    if payload.kind == "HELLO_REPLY" and leader and active.phase == "hello" and channel == "WHISPER" then
        if not Finite(payload.checkpoint) or payload.checkpoint > active.cutoff then return end
        active.hello[sender] = payload.checkpoint
        if Everyone(active.hello) then StartExchange() end
    elseif payload.kind == "INVENTORY_REQUEST" and not leader and sender == active.leader and channel == "OFFICER" then
        if not Finite(payload.floor) or payload.floor > active.cutoff or payload.cutoff ~= active.cutoff then return end
        active.floor = payload.floor
        SetPhase("inventory")
        Send("INVENTORY", { floor = active.floor, ids = Inventory(active.floor, active.cutoff),
            prefix = Summary(active.floor, true) }, sender)
    elseif payload.kind == "INVENTORY" and leader and active.phase == "inventory" and channel == "WHISPER" then
        if payload.floor ~= active.floor or type(payload.ids) ~= "table" or type(payload.prefix) ~= "string" then
            print("SEPGP: Rejected inventory from " .. SEPGP.DisplayName(address) .. ": invalid boundary or fields.")
            return
        end
        for id, timestamp in pairs(payload.ids) do
            if type(id) ~= "string" or id == "" or not Finite(timestamp)
                or timestamp < active.floor or timestamp > active.cutoff then
                print("SEPGP: Rejected inventory from " .. SEPGP.DisplayName(address)
                    .. ": invalid action timestamp for " .. tostring(id) .. ".")
                return
            end
        end
        active.inventories[sender], active.prefixes[sender] = payload.ids, payload.prefix
        print("SEPGP: Received inventory from " .. SEPGP.DisplayName(address) .. ".")
        if Everyone(active.inventories) then Gather() end
    elseif payload.kind == "FETCH" and not leader and sender == active.leader and channel == "WHISPER" then
        if active.phase ~= "inventory" or type(payload.ids) ~= "table" then return end
        local ids = Inventory(active.floor, active.cutoff)
        for id in pairs(payload.ids) do if not ids[id] then return end end
        SendRecords(payload.ids, sender)
    elseif payload.kind == "DATA" and channel == "WHISPER" then
        if type(payload.actions) ~= "table" then return end
        if leader and active.phase ~= "gather" then return end
        if not leader and (sender ~= active.leader or (active.phase ~= "inventory" and active.phase ~= "verify")) then return end
        for _, action in ipairs(payload.actions) do
            if not ValidAction(action) or action.timestamp < active.floor or action.timestamp > active.cutoff then
                local id = type(action) == "table" and tostring(action.id) or "unknown"
                local kind = type(action) == "table" and tostring(action.type) or "unknown"
                local reason = "Invalid history action " .. id .. " (" .. kind .. ") from "
                    .. SEPGP.DisplayName(address) .. "; checkpoint unchanged."
                Send("ABORT", { reason = reason })
                Stop(reason)
                return
            end
            if leader and (active.wanted[action.id] ~= sender or active.union[action.id] ~= action.timestamp) then return end
            local existing = SEPGP_DB.actions[action.id]
            if existing and Signature(existing) ~= Signature(action) then Stop("Conflicting action data; checkpoint unchanged."); return end
        end
        for _, action in ipairs(payload.actions) do
            if leader then active.received[action.id] = action
            end
        end
        if not leader then ImportRecords(payload.actions) end
        if leader then
            for id in pairs(active.wanted) do if not active.received[id] then return end end
            Verify()
        else Acknowledge() end
    elseif payload.kind == "VERIFY" and not leader and sender == active.leader and channel == "WHISPER" then
        if not Finite(payload.timestamp) or payload.timestamp > active.cutoff
            or type(payload.summary) ~= "string" or payload.roster ~= active.roster then return end
        active.candidate, active.summary = payload.timestamp, payload.summary
        SetPhase("verify")
        Acknowledge()
    elseif payload.kind == "ACK" and leader and active.phase == "verify" and channel == "WHISPER" then
        if payload.timestamp ~= active.candidate or payload.summary ~= active.summary then return end
        active.acks[sender] = true
        if Everyone(active.acks) then Finish() end
    elseif payload.kind == "COMMIT" and not leader and sender == active.leader and channel == "OFFICER" then
        if not active.acknowledged or payload.timestamp ~= active.candidate or payload.summary ~= active.summary
            or payload.roster ~= active.roster or Summary(active.candidate) ~= active.summary then return end
        local confirmed = CanCommit()
        if confirmed then
            SEPGP_DB.syncCheckpoint = { timestamp = active.candidate, summary = active.summary, roster = active.roster }
        end
        Complete(confirmed)
    elseif payload.kind == "DONE" and not leader and sender == active.leader and channel == "OFFICER" then
        if not active.acknowledged or Summary(active.candidate) ~= active.summary then return end
        Complete(false)
    end
end

-- A late historical action invalidates the shortcut, forcing a full ID exchange.
local previousApply = SEPGP.ApplyAction
SEPGP.ApplyAction = function(action)
    local applied = previousApply(action)
    local cp = SEPGP_DB.syncCheckpoint
    if applied and cp and action.timestamp <= cp.timestamp then SEPGP_DB.syncCheckpoint = nil end
    return applied
end
local previousReceive = SEPGP.HandleAddonMessage
SEPGP.HandleAddonMessage = function(prefix, message, channel, sender)
    if prefix == SEPGP.PREFIX and message == "SYNC_REQUEST" then
        -- Old clients do not support acknowledgments and cannot approve a checkpoint.
        if SEPGP.CanEditOfficerSettings() then
            print("SEPGP: An officer requested legacy sync. All officers need the updated addon for checkpoint sync.")
        end
        return
    end
    return previousReceive(prefix, message, channel, sender)
end
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == "SEPGP-Forever" then
        SEPGP:RegisterComm(PREFIX, "OnHistoryCommReceived")
    elseif active then
        local _, roster = Roster()
        if roster ~= active.roster or not SEPGP.CanEditOfficerSettings() then
            Stop("Officer membership changed during sync; checkpoint unchanged.")
        end
    end
end)
