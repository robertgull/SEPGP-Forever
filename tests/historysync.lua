-- Multiple isolated addon clients using the real serializer/compressor.
local output = print
dofile("SEPGP-Forever/libs/LibStub/LibStub.lua")
dofile("SEPGP-Forever/libs/AceSerializer-3.0/AceSerializer-3.0.lua")
dofile("SEPGP-Forever/libs/LibDeflate-1.0.2-release/LibDeflate.lua")
local clients, queue, traffic, roster, now, drop = {}, {}, {}, {}, 100, nil
local transportLimit, loggedFragments = nil, {}
local transportPrintableOnly = false
local reverseFragments, duplicateFragments = false, false
local comm = LibStub:NewLibrary("AceComm-3.0", 999)
function comm:Embed(target)
    function target:RegisterComm(prefix, callback) self._client.registrations[prefix] = callback end
    function target:SendCommMessage(prefix, message, channel, recipient)
        local payload = self.DecodeHistoryPayload and self.DecodeHistoryPayload(message) or self.DecodePayload(message)
        if message:sub(1, 2) == "H:" then
            local id, part, total, data = message:match("^H:(%d+):(%d+):(%d+):(.*)$")
            local key = self._client.name .. ":" .. channel .. ":" .. tostring(recipient) .. ":" .. id
            loggedFragments[key] = loggedFragments[key] or {}
            loggedFragments[key][tonumber(part)] = data
            if part == total then
                payload = self.DecodeHistoryPayload(table.concat(loggedFragments[key]))
                loggedFragments[key] = nil
            else payload = { kind = "FRAGMENT" } end
        end
        local packet = { prefix = prefix, message = message, channel = channel,
            sender = self._client.name, target = recipient, payload = payload }
        if transportLimit and #message + #prefix > transportLimit then return end
        if transportPrintableOnly and message:find("[^\032-\126]") then return end
        queue[#queue + 1], traffic[#traffic + 1] = packet, packet
    end
end
local function Load(env, name)
    local chunk = assert(loadfile("SEPGP-Forever/" .. name .. ".lua"))
    setfenv(chunk, env)()
end
local function Client(name)
    local client = { name = name, timers = {}, frames = {}, registrations = {}, messages = {}, notices = {} }
    local env = setmetatable({}, { __index = _G })
    client.env = env
    env.SEPGP, env.SEPGP_DB, env.SlashCmdList = {}, {}, {}
    env.print = function(message) client.messages[#client.messages + 1] = message end
    env.UIErrorsFrame = { AddMessage = function(_, message) client.notices[#client.notices + 1] = message end }
    env.time, env.GetTime = function() return now end, function() return now end
    env.GetUnitName = function() return name end
    env.GetRealmName = function() return client.realm or "Realm" end
    env.GetGuildInfo = function() return "Guild" end
    env.IsInGuild = function() return true end
    env.GetNumGuildMembers = function() return #roster end
    env.GetGuildRosterInfo = function(index)
        local row = roster[index]
        return row.name, "", row.rank, nil, nil, nil, nil, nil, row.online, nil, nil, nil, nil, row.mobile
    end
    env.C_GuildInfo = {
        IsGuildOfficer = function() return client.officer ~= false end,
        GuildControlGetRankFlags = function(rank) return { [12] = rank == 2 } end,
        GuildRoster = function() end,
    }
    env.C_Timer = { After = function(delay, callback) client.timers[#client.timers + 1] = { delay, callback } end }
    env.C_ChatInfo = { SendAddonMessage = function() return 0 end, RegisterAddonMessagePrefix = function() return true end }
    env.CreateFrame = function()
        local frame = { RegisterEvent = function() end, SetScript = function(self, _, callback) self.callback = callback end }
        client.frames[#client.frames + 1] = frame
        return frame
    end
    env.strsplit = function(delimiter, value)
        local values = {}
        for part in (value .. delimiter):gmatch("(.-)" .. delimiter) do values[#values + 1] = part end
        return unpack(values)
    end
    Load(env, "EPGP")
    env.SEPGP._client = client
    Load(env, "SettingsData")
    Load(env, "comms")
    Load(env, "UI") -- Actual active core overrides the older functions.
    Load(env, "PlayerNames")
    Load(env, "SettingsSync")
    Load(env, "HistorySync")
    local events = client.frames[#client.frames]
    events.callback(events, "ADDON_LOADED", "SEPGP-Forever")
    clients[name:lower()] = client
    return client
end
local function Online(name)
    for _, row in ipairs(roster) do if row.name:lower() == name:lower() then return row.online and not row.mobile end end
end
local function Drain()
    local iterations = 0
    while #queue > 0 do
        iterations = iterations + 1
        assert(iterations < 10000, "Protocol did not settle")
        if reverseFragments and queue[1].message:sub(1, 2) == "H:" and not queue[1].reordered then
            local first, batch = queue[1], {}
            local id = first.message:match("^H:(%d+):")
            for index = #queue, 1, -1 do
                local candidate = queue[index]
                if candidate.sender == first.sender and candidate.channel == first.channel
                    and candidate.target == first.target and candidate.message:match("^H:(%d+):") == id then
                    candidate.reordered = true
                    batch[#batch + 1] = table.remove(queue, index)
                end
            end
            for index = #batch, 1, -1 do table.insert(queue, 1, batch[index]) end
        end
        local packet = table.remove(queue, 1)
        for key, client in pairs(clients) do
            local callback = client.registrations[packet.prefix]
            if callback and Online(client.name) and (packet.channel == "OFFICER" or key == packet.target:lower())
                and not (drop and drop(packet, client)) then
                client.env.SEPGP[callback](client.env.SEPGP, packet.prefix, packet.message, packet.channel, packet.sender)
                if duplicateFragments and packet.message:sub(1, 2) == "H:" then
                    client.env.SEPGP[callback](client.env.SEPGP, packet.prefix, packet.message, packet.channel, packet.sender)
                end
            end
        end
    end
end
local function Timer(client, delay)
    local callbacks = {}
    for _, timer in ipairs(client.timers) do if timer[1] == delay then callbacks[#callbacks + 1] = timer[2] end end
    client.timers = {}
    now = now + delay
    for _, callback in ipairs(callbacks) do callback() end
end
local function Action(client, id, timestamp, kind, amount)
    assert(client.env.SEPGP.ApplyAction({ id = id, timestamp = timestamp, type = kind or "EP",
        player = "alice", amount = amount or 10, actor = "A-Realm", reason = "Award" }))
end
local function New()
    clients, queue, traffic, drop = {}, {}, {}, nil
    roster = { { name = "A-Realm", rank = 0, online = true },
        { name = "B-Realm", rank = 1, online = true }, { name = "C-Realm", rank = 1, online = true },
        { name = "Member-Realm", rank = 2, online = true } }
    return Client("A-Realm"), Client("B-Realm"), Client("C-Realm")
end
local function DataIDs()
    local ids = {}
    for _, packet in ipairs(traffic) do
        if packet.payload.kind == "DATA" then
            for _, action in ipairs(packet.payload.actions) do ids[#ids + 1] = action.id end
        end
    end
    return ids
end
local function Check(client, timestamp)
    assert(client.env.SEPGP_DB.syncCheckpoint and client.env.SEPGP_DB.syncCheckpoint.timestamp == timestamp)
    assert(client.env.SEPGP.GetSyncCheckpoint() == timestamp)
end
local a, b, c = New()
Action(a, "a", 10)
Action(b, "b", 20, "GP")
Action(c, "a", 10)
Action(c, "b", 20, "GP")
assert(a.env.SEPGP.RequestSync())
assert(not a.env.SEPGP.RequestSync())
Drain()
for _, client in ipairs({ a, b, c }) do
    Check(client, 20)
    assert(client.env.SEPGP_DB.actions.a and client.env.SEPGP_DB.actions.b)
    assert(client.messages[#client.messages]:find("Sync complete", 1, true))
    assert(client.notices[#client.notices] == "SEPGP: Sync complete")
end
assert(a.messages[#a.messages]:find("1 new actions received", 1, true))
assert(b.messages[#b.messages]:find("1 new actions received", 1, true))
assert(c.messages[#c.messages]:find("0 new actions received", 1, true))
assert(b.messages[1]:find("Sync joined", 1, true) and c.messages[1]:find("Sync joined", 1, true))
assert(#DataIDs() == 2) -- Fetch b once, send a only to B; C already has both.
-- A second sync with no new actions transfers no history records.
traffic = {}
assert(a.env.SEPGP.RequestSync()); Drain()
assert(#DataIDs() == 0)
for _, client in ipairs({ a, b, c }) do
    assert(client.messages[#client.messages]:find("Sync complete - 0 new actions received", 1, true))
end
for _, packet in ipairs(traffic) do
    if packet.payload.kind == "INVENTORY_REQUEST" then assert(packet.payload.floor == 20) end
    if packet.payload.kind == "INVENTORY" then assert(not packet.payload.ids.a) end
end
-- Equal-timestamp late awards invalidate the shortcut and still synchronize.
Action(b, "equal", 20)
assert(not b.env.SEPGP_DB.syncCheckpoint)
traffic = {}
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 20); assert(client.env.SEPGP_DB.actions.equal) end
assert(#DataIDs() == 2) -- Fetch equal, send it to C; existing holders receive nothing.
-- Newer actions use the existing checkpoint; all officers confirm the last action.
Action(a, "new", 80)
traffic = {}
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 80); assert(client.env.SEPGP_DB.actions.new) end
for _, id in ipairs(DataIDs()) do assert(id == "new") end
-- Offline officers prevent advancement but available officers still exchange data.
roster[3].online = false
Action(a, "offline", 90)
assert(a.env.SEPGP.RequestSync()); Drain()
Check(a, 80); Check(b, 80); Check(c, 80)
for _, client in ipairs({ a, b }) do
    assert(client.messages[#client.messages]:find("Sync complete", 1, true))
    assert(client.messages[#client.messages]:find("Checkpoint unchanged", 1, true))
end
assert(b.env.SEPGP_DB.actions.offline and not c.env.SEPGP_DB.actions.offline)
roster[3].online = true
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 90); assert(client.env.SEPGP_DB.actions.offline) end
-- A promoted/new officer has no checkpoint, so old missing history is restored.
roster[#roster + 1] = { name = "D-Realm", rank = 1, online = true }
local d = Client("D-Realm")
assert(a.env.SEPGP.RequestSync()); Drain()
Check(d, 90)
assert(d.env.SEPGP_DB.actions.a and d.env.SEPGP_DB.actions.offline)
for _, client in ipairs({ a, b, c }) do Check(client, 90) end
-- Lost ACK means the coordinator cannot commit, even when all appear online.
a, b, c = New()
Action(a, "award", 50)
drop = function(packet) return packet.payload.kind == "ACK" and packet.sender == "C-Realm" end
assert(a.env.SEPGP.RequestSync()); Drain()
assert(not a.env.SEPGP_DB.syncCheckpoint and not b.env.SEPGP_DB.syncCheckpoint and not c.env.SEPGP_DB.syncCheckpoint)
assert(c.env.SEPGP_DB.actions.award) -- Data delivered, but no completion proof.
assert(#a.notices == 0 and #b.notices == 0 and #c.notices == 0)
Timer(a, 300)
assert(a.messages[#a.messages]:lower():find("timed out during verify; waiting for c", 1, true), a.messages[#a.messages])
Timer(b, 300); Timer(c, 300)
drop = nil
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 50) end
-- An online officer with no compatible addon cannot approve a checkpoint.
a, b, c = New()
clients["c-realm"] = nil
Action(a, "award", 50)
assert(a.env.SEPGP.RequestSync()); Drain()
Timer(a, 15); Drain()
assert(b.env.SEPGP_DB.actions.award and not a.env.SEPGP_DB.syncCheckpoint)
-- An officer disconnecting during verification prevents commit.
a, b, c = New()
Action(a, "award", 50)
drop = function(packet)
    if packet.payload.kind == "ACK" and packet.sender == "C-Realm" then roster[3].online = false end
    return false
end
assert(a.env.SEPGP.RequestSync()); Drain()
assert(not a.env.SEPGP_DB.syncCheckpoint and not b.env.SEPGP_DB.syncCheckpoint)
-- Conflicting content under the same action ID never creates a checkpoint.
a, b, c = New()
Action(a, "conflict", 10, "EP", 10)
Action(b, "conflict", 10, "EP", 20)
assert(a.env.SEPGP.RequestSync()); Drain()
assert(not a.env.SEPGP_DB.syncCheckpoint and not b.env.SEPGP_DB.syncCheckpoint)
-- Checkpoint metadata cannot hide deleted historical records.
a, b, c = New()
for _, client in ipairs({ a, b, c }) do Action(client, "old", 10); Action(client, "last", 20) end
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 20) end
b.env.SEPGP_DB.actions.old = nil
traffic = {}
assert(a.env.SEPGP.RequestSync()); Drain()
assert(b.env.SEPGP_DB.actions.old)
for _, client in ipairs({ a, b, c }) do Check(client, 20) end
-- Backdated actions invalidate checkpoints; current-second actions are included.
Action(c, "backdated", 5)
assert(not c.env.SEPGP_DB.syncCheckpoint)
Action(a, "current", now)
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, now); assert(client.env.SEPGP_DB.actions.backdated) end
-- Never checkpoint until an officer has actually received all missing packets.
a, b, c = New()
Action(a, "award", 50)
drop = function(packet, client) return packet.payload.kind == "DATA" and client == c end
assert(a.env.SEPGP.RequestSync()); Drain()
assert(not c.env.SEPGP_DB.actions.award and not a.env.SEPGP_DB.syncCheckpoint)
-- Members and legacy commands cannot initiate the new protocol or advance it.
a.officer = false
assert(not a.env.SEPGP.RequestSync())
local before = #traffic
a.env.SEPGP.HandleAddonMessage(a.env.SEPGP.PREFIX, "SYNC_REQUEST", "OFFICER", "B-Realm")
assert(#traffic == before)
-- Larger histories arrive in bounded batches before completion is acknowledged.
a, b, c = New()
for index = 1, 105 do Action(a, "batch" .. index, index) end
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 105) end
assert(#DataIDs() == 210)
for _, packet in ipairs(traffic) do
    if packet.payload.kind == "DATA" then assert(#packet.payload.actions <= 40) end
end
-- The saved checkpoint remains usable after the sync module is reloaded.
Load(b.env, "HistorySync")
traffic = {}
assert(a.env.SEPGP.RequestSync()); Drain()
assert(#DataIDs() == 0)
for _, client in ipairs({ a, b, c }) do Check(client, 105) end
-- Unknown rank permissions cannot silently exclude an officer from consensus.
a, b, c = New()
a.env.C_GuildInfo.GuildControlGetRankFlags = function() return {} end
assert(not a.env.SEPGP.RequestSync() and not a.env.SEPGP_DB.syncCheckpoint)
-- Same-realm senders can be bare names. Never append a synthetic realm to
-- the whisper address, including on servers whose realm name contains spaces.
for _, name in ipairs({ "Chartsignerone", "Chartsigner one" }) do
    clients, queue, traffic, drop = {}, {}, {}, nil
    roster = { { name = name, rank = 0, online = true },
        { name = "OtherOfficer", rank = 1, online = true } }
    a, b = Client(name), Client("OtherOfficer")
    a.realm, b.realm = "Classic Beta PvP", "Classic Beta PvP"
    Action(a, "first", 10)
    Action(b, "second", 20)
    assert(a.env.SEPGP.RequestSync()); Drain()
    Check(a, 20); Check(b, 20)
    for _, packet in ipairs(traffic) do
        if packet.channel == "WHISPER" then
            assert(packet.target == name or packet.target == "OtherOfficer", "Changed a real whisper address")
        end
    end
    assert(b.env.SEPGP_DB.actions.first and a.env.SEPGP_DB.actions.second)
    traffic = {}
    assert(b.env.SEPGP.RequestSync()); Drain()
    assert(#DataIDs() == 0)
end
-- Old realm-qualified action recipients and new plain recipients compare alike.
a, b, c = New()
Action(a, "legacy-name", 10)
a.env.SEPGP_DB.actions["legacy-name"].player = "alice-Realm"
Action(b, "legacy-name", 10)
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 10) end
assert(c.env.SEPGP.GetPlayer("Alice").EP == 10)
assert(not c.env.SEPGP_DB.players["alice-realm"])
-- Clearing an idle DB removes the saved checkpoint and queued old actions.
a.env.SEPGP.sendQueue = { a.env.SEPGP_DB.actions["legacy-name"] }
a.env.SlashCmdList.SEPGP("cleardb")
assert(not a.env.SEPGP_DB.syncCheckpoint and not next(a.env.SEPGP_DB.actions))
assert(not next(a.env.SEPGP_DB.players) and #a.env.SEPGP.sendQueue == 0)
assert(a.messages[#a.messages]:find("sync checkpoint cleared", 1, true))
assert(a.env.SEPGP.RequestSync()); Drain()
Check(a, 10) -- A fresh sync can restore history and establish a new checkpoint.
-- Clearing during confirmation aborts the session and ignores queued packets.
a, b, c = New()
Action(a, "award", 50)
drop = function(packet) return packet.payload.kind == "ACK" and packet.sender == "C-Realm" end
assert(a.env.SEPGP.RequestSync()); Drain()
assert(b.env.SEPGP_DB.actions.award)
b.env.SlashCmdList.SEPGP("cleardb")
Drain()
assert(not next(b.env.SEPGP_DB.actions) and not next(b.env.SEPGP_DB.players))
assert(not b.env.SEPGP_DB.syncCheckpoint and not a.env.SEPGP_DB.syncCheckpoint)
local verify
for _, packet in ipairs(traffic) do if packet.payload.kind == "VERIFY" then verify = packet end end
assert(verify)
b.env.SEPGP:OnHistoryCommReceived(verify.prefix, verify.message, verify.channel, verify.sender)
assert(not b.env.SEPGP_DB.syncCheckpoint and not next(b.env.SEPGP_DB.actions))
drop = nil
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 50) end
-- Live loot awards preserve item links (including pipes and long item names)
-- on every officer without requiring a full sync or replaying duplicate GP.
a, b, c = New()
local itemLink = "|cffa335ee|Hitem:123:0:0:0|h[" .. string.rep("Long item name ", 25) .. "]|h|r"
local loot = a.env.SEPGP.AddGP("Ducky Dru", 75, itemLink)
assert(loot and loot.reason == itemLink)
Drain()
for _, client in ipairs({ a, b, c }) do
    assert(client.env.SEPGP_DB.actions[loot.id].reason == itemLink)
    assert(client.env.SEPGP.GetPlayer("Ducky Dru").GP == 175)
end
assert(a.env.SEPGP.SendAction(loot, "OFFICER") == 0); Drain()
assert(b.env.SEPGP.GetPlayer("Ducky Dru").GP == 175)
b.env.SEPGP_DB.actions[loot.id].reason = nil
assert(a.env.SEPGP.SendAction(loot, "OFFICER") == 0); Drain()
assert(b.env.SEPGP_DB.actions[loot.id].reason == itemLink)
for _, client in ipairs({ a, b, c }) do client.env.SEPGP.GetPlayer("Ducky Dru").GP = 50 end
local freeLoot = a.env.SEPGP.AddGP("Ducky Dru", 0, itemLink)
Drain()
for _, client in ipairs({ a, b, c }) do
    assert(client.env.SEPGP_DB.actions[freeLoot.id].reason == itemLink)
    assert(client.env.SEPGP.GetPlayer("Ducky Dru").GP == 50)
end
-- A new officer restores history across decay batches and later adjustments.
a, b, c = New()
for index = 1, 45 do
    assert(a.env.SEPGP.ApplyAction({ id = "seed" .. index, timestamp = 10, type = "EP",
        player = "player" .. index, amount = 123 + index, actor = "A-Realm" }))
end
now = now + 1
assert(a.env.SEPGP.Decay(17.5, "Weekly decay") == 45)
assert(a.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, now) end
roster[#roster + 1] = { name = "D-Realm", rank = 1, online = true }
d = Client("D-Realm")
now = now + 1
assert(a.env.SEPGP.AddEP("player1", -10, "Correction"))
Drain()
assert(d.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c, d }) do
    Check(client, now)
    assert(#client.env.SEPGP.GetSortedActions() == 91)
end
assert(d.env.SEPGP.GetPlayer("player1").EP == a.env.SEPGP.GetPlayer("player1").EP)
-- Importing history replaces an already downloaded standing, rather than
-- awarding the same points again on top of that standing.
roster[#roster + 1] = { name = "E-Realm", rank = 1, online = true }
local e = Client("E-Realm")
for name, player in pairs(a.env.SEPGP_DB.players) do
    e.env.SEPGP_DB.players[name] = { EP = player.EP, GP = player.GP }
end
assert(a.env.SEPGP.RequestSync()); Drain()
Check(e, now)
for name, player in pairs(a.env.SEPGP_DB.players) do
    assert(e.env.SEPGP_DB.players[name].EP == player.EP and e.env.SEPGP_DB.players[name].GP == player.GP)
end
-- Matching history IDs must still repair totals left by an earlier bad replay.
e.env.SEPGP_DB.players.player1.EP = 9999
a.env.SEPGP_DB.players.player2.GP = 9999
traffic = {}
assert(a.env.SEPGP.RequestSync()); Drain()
assert(#DataIDs() == 0)
assert(e.env.SEPGP.GetPlayer("player1").EP == a.env.SEPGP.GetPlayer("player1").EP)
assert(a.env.SEPGP.GetPlayer("player2").GP == e.env.SEPGP.GetPlayer("player2").GP)
-- Invalid decay records previously caused DATA to be silently ignored, leaving
-- every client waiting. Abort with the offending ID and allow a repaired retry.
a, b, c = New()
Action(a, "bad-decay", 10, "DECAY", 20)
a.env.SEPGP_DB.actions["bad-decay"].amount = 120
assert(b.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do
    assert(not client.env.SEPGP_DB.syncCheckpoint)
    assert(client.messages[#client.messages]:find("Invalid history action bad-decay (DECAY)", 1, true))
end
a.env.SEPGP_DB.actions["bad-decay"].amount = 20
assert(b.env.SEPGP.RequestSync()); Drain()
for _, client in ipairs({ a, b, c }) do Check(client, 10) end
-- The small handshake succeeds on transports where larger AceComm messages
-- are lost. Inventory and DATA must use ordinary, bounded addon packets too.
clients, queue, traffic, drop = {}, {}, {}, nil
roster = { { name = "Ducky Dru", rank = 0, online = true },
    { name = "Chartsigner one", rank = 1, online = true } }
a, b = Client("Ducky Dru"), Client("Chartsigner one")
transportLimit = 255
transportPrintableOnly = true
reverseFragments, duplicateFragments = true, true
for index = 1, 105 do Action(a, index .. "-ABCDEFGH", index) end
for index = 1, 88 do Action(b, index .. "-ABCDEFGH", index) end
Action(a, "106-DECAYABC", 106, "DECAY", 20)
assert(a.env.SEPGP.RequestSync()); Drain()
Check(a, 106); Check(b, 106)
assert(#b.env.SEPGP.GetSortedActions() == 106)
assert(b.env.SEPGP.GetPlayer("alice").EP == a.env.SEPGP.GetPlayer("alice").EP)
for _, packet in ipairs(traffic) do
    assert(#packet.message + #packet.prefix <= 255)
    assert(not packet.message:find("[^\032-\126]"))
end
assert(table.concat(a.messages, "\n"):find("Received inventory from Chartsigner one", 1, true))
assert(table.concat(b.messages, "\n"):find("Sending inventory of 88 actions to Ducky Dru", 1, true))
traffic = {}
assert(b.env.SEPGP.RequestSync()); Drain()
Check(a, 106); Check(b, 106)
assert(#DataIDs() == 0)
transportLimit = nil
transportPrintableOnly = false
reverseFragments, duplicateFragments = false, false
output("History checkpoint sync tests passed")
