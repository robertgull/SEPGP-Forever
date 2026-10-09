-- Run from the repository root: lua tests/raidep.lua
local output = print
print = function() end
SlashCmdList = {}
local officer, inRaid = true, true
local roster = { "Officer-Realm", "Alice-Realm", "Bob-OtherRealm" }
local timers, attempts, broadcasts, announcements = {}, {}, {}, {}
local throttle = false
local refreshes = 0
C_GuildInfo = { IsGuildOfficer = function() return officer end }
IsInRaid = function() return inRaid end
GetNormalizedRealmName = function() return "Realm" end
GetNumGroupMembers = function() return #roster end
GetUnitName = function(unit)
    if unit == "player" then return "Officer-Realm" end
    return roster[tonumber(unit:match("raid(%d+)"))]
end
time = function() return 1 end
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
C_ChatInfo = { SendAddonMessage = function(_, message, channel)
    assert(channel == "OFFICER")
    attempts[#attempts + 1] = message
    if throttle then throttle = false; return 3 end
    broadcasts[#broadcasts + 1] = message
    return 0
end }
SendChatMessage = function(message, channel)
    assert(channel == "RAID")
    announcements[#announcements + 1] = message
end
strsplit = function(delimiter, value)
    local parts = {}
    for part in (value .. delimiter):gmatch("(.-)" .. delimiter) do parts[#parts + 1] = part end
    return unpack(parts)
end
dofile("SEPGP-Forever/EPGP.lua")
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/UI.lua")
dofile("SEPGP-Forever/PlayerNames.lua")
dofile("SEPGP-Forever/raidep.lua")
SEPGP.UI = { standingsFrame = { IsShown = function() return true end } }
SEPGP.RefreshStandingsWindow = function() refreshes = refreshes + 1 end
SEPGP_DB.players = {
    alice = { EP = 10, GP = 120 },
    ["bob-otherrealm"] = { EP = 50, GP = 200 },
    standby = { EP = 25, GP = 100 },
}
local function drain()
    local count = 0
    while #timers > 0 do
        count = count + 1
        assert(count < 1000)
        table.remove(timers, 1)()
    end
end
throttle = true
SlashCmdList.SEPGP("  RaIdEp 100 Boss kill  ")
assert(SEPGP_DB.players.alice.EP == 110 and SEPGP_DB.players.alice.GP == 120)
assert(not SEPGP_DB.players["alice-realm"])
assert(SEPGP_DB.players.bob.EP == 150)
assert(SEPGP_DB.players.officer.EP == 100)
assert(SEPGP_DB.players.standby.EP == 25)
assert(SEPGP_DB.revision == 3 and refreshes == 1 and #announcements == 1)
for _, action in pairs(SEPGP_DB.actions) do
    assert(action.type == "EP" and action.amount == 100 and action.reason == "Boss kill")
    assert(action.before and action.after and action.actor == "Officer-Realm")
end
drain()
assert(#broadcasts == 3 and #attempts == 4 and attempts[1] == attempts[2])
-- Invalid input and permissions must not modify or broadcast anything.
for _, command in ipairs({ "raidep", "raidep -1", "raidep 0", "raidep 1.5", "raidep 10oops", "raidep nope" }) do
    SlashCmdList.SEPGP(command)
    assert(SEPGP_DB.revision == 3)
end
assert(SEPGP.AwardRaidEP(0 / 0) == nil)
assert(SEPGP.AwardRaidEP(math.huge) == nil)
officer = false
assert(SEPGP.AwardRaidEP(10) == nil)
officer, inRaid = true, false
assert(SEPGP.AwardRaidEP(10) == nil)
inRaid = true
assert(SEPGP_DB.revision == 3 and #announcements == 1)
-- Incomplete roster aborts before granting anyone EP.
roster = { "Officer-Realm", "" }
assert(SEPGP.AwardRaidEP(10) == nil and SEPGP_DB.revision == 3)
-- Duplicate names count once, and short local names reuse the same record.
roster = { "Alice", "Alice-Realm" }
assert(SEPGP.AwardRaidEP(10) == 1)
assert(SEPGP_DB.players.alice.EP == 120)
drain()
-- A full raid is queued reliably, without checking online/alive status.
roster = {}
for i = 1, 40 do roster[i] = "Raider" .. i .. "-Realm" end
local beforeBroadcasts = #broadcasts
assert(SEPGP.AwardRaidEP(25, "Attendance") == 40)
drain()
assert(#broadcasts == beforeBroadcasts + 40)
for i = 1, 40 do assert(SEPGP_DB.players["raider" .. i].EP == 25) end
-- Another officer can apply the existing wire actions idempotently.
SEPGP_DB = { players = {}, actions = {}, revision = 0, localCounter = 0 }
for i = beforeBroadcasts + 1, #broadcasts do
    SEPGP.HandleAddonMessage("SEPGPF", broadcasts[i], "OFFICER", "Officer-Realm")
    SEPGP.HandleAddonMessage("SEPGPF", broadcasts[i], "OFFICER", "Officer-Realm")
end
assert(SEPGP_DB.revision == 40)
for i = 1, 40 do assert(SEPGP_DB.players["raider" .. i].EP == 25) end
output("Raid EP tests passed")
