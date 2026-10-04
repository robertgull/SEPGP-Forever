-- Run from the repository root: lua tests/settingssync.lua
SEPGP, SEPGP_DB, SEPGP_PREFS = { PREFIX = "SEPGP" }, { players = { Alice = { EP = 100, GP = 200 } } }, { gpTooltip = false }
local officer, guild, now = false, true, 100
local roster = { { "Me-Realm", 2 }, { "Officer-Realm", 1 }, { "Member-Realm", 2 }, { "Leader-Realm", 0 }, { "Other-Realm", 1 } }
C_GuildInfo = {
    IsGuildOfficer = function() return officer end,
    GuildControlGetRankFlags = function(rank) return { [12] = rank == 2 } end,
    GuildRoster = function() end,
}
GetRealmName = function() return "Realm" end
GetUnitName = function() return "Me-Realm" end
IsInGuild = function() return guild end
GetTime = function() return now end
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(index) return roster[index][1], "", roster[index][2] end
local timers, frames, sent, registrations = {}, {}, {}, {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
CreateFrame = function()
    local frame = { RegisterEvent = function() end, SetScript = function(self, _, callback) self.callback = callback end }
    frames[#frames + 1] = frame
    return frame
end
local output, messages = print, {}
print = function(message) messages[#messages + 1] = message end
dofile("SEPGP-Forever/libs/LibStub/LibStub.lua")
local comm = LibStub:NewLibrary("AceComm-3.0", 999)
function comm:Embed(target)
    target.RegisterComm = function(_, prefix, callback) registrations[prefix] = callback end
    target.SendCommMessage = function(_, prefix, message, channel, targetName)
        sent[#sent + 1] = { prefix = prefix, payload = SEPGP.DecodePayload(message), channel = channel, target = targetName }
    end
end
dofile("SEPGP-Forever/libs/AceSerializer-3.0/AceSerializer-3.0.lua")
dofile("SEPGP-Forever/libs/LibDeflate-1.0.2-release/LibDeflate.lua")
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/GP.lua")
dofile("SEPGP-Forever/BidSettings.lua")
dofile("SEPGP-Forever/comms.lua")
dofile("SEPGP-Forever/SettingsSync.lua")
local events = frames[#frames]
events.callback(events, "ADDON_LOADED", "SEPGP-Forever")
assert(registrations.SEP_SETTINGS == "OnSettingsCommReceived")
local refreshed = 0
SEPGP.RefreshSettings = function() refreshed = refreshed + 1 end
local function Data(base, request)
    return { version = 1, kind = "SETTINGS", request = request,
        gp = { Base = base, Multiplier = 3, Mod = 0.5 }, bids = SEPGP.Bids.Copy(SEPGP.Bids.GetSettings()) }
end
local function Receive(payload, sender, channel, prefix)
    SEPGP:OnSettingsCommReceived(prefix or "SEP_SETTINGS", SEPGP.EncodePayload(payload), channel or "GUILD", sender or "Officer-Realm")
end
assert(not SEPGP.SendSettings() and #sent == 0)
assert(SEPGP.RequestSettings())
local request = sent[#sent].payload.request
assert(sent[#sent].prefix == "SEP_SETTINGS" and sent[#sent].channel == "GUILD")
assert(not SEPGP.RequestSettings()) -- One outstanding request.
Receive(Data(10, request), "Member-Realm", "WHISPER")
Receive(Data(10, request), "Officer-OtherRealm", "WHISPER")
Receive(Data(10, "wrong"), nil, "WHISPER")
assert(SEPGP.GP.GetFormulaSettings().Base == 8 and refreshed == 0)
local invalid = Data(10, request)
invalid.bids[2].discount = 101
Receive(invalid, nil, "WHISPER")
invalid = Data(10, request)
invalid.gp.Multiplier = 0
Receive(invalid, nil, "WHISPER")
assert(SEPGP.GP.GetFormulaSettings().Base == 8)
local valid = Data(10, request)
valid.bids[1].label, valid.bids[1].discount, valid.bids[2].active = "Main Spec", 25, false
Receive(valid, "Officer", "WHISPER") -- Same-realm short names match.
assert(SEPGP.GP.GetFormulaSettings().Base == 10 and refreshed == 1)
assert(SEPGP.Bids.GetSettings()[1].label == "Main Spec" and not SEPGP.Bids.GetSettings()[2].active)
Receive(Data(99, request), "Other-Realm", "WHISPER") -- First valid reply wins.
assert(SEPGP.GP.GetFormulaSettings().Base == 10)
Receive(Data(12), "Member-Realm")
Receive(Data(12), "Outsider-Realm")
Receive(Data(12), nil, "RAID")
Receive(Data(12), nil, nil, "SEPGP")
assert(SEPGP.GP.GetFormulaSettings().Base == 10)
Receive(Data(12), "Leader-Realm")
assert(SEPGP.GP.GetFormulaSettings().Base == 12 and not SEPGP_PREFS.gpTooltip)
assert(SEPGP_DB.players.Alice.EP == 100 and SEPGP_DB.players.Alice.GP == 200)
officer = true
assert(SEPGP.SendSettings())
local broadcast = sent[#sent]
assert(broadcast.channel == "GUILD" and broadcast.payload.gp.Base == 12)
assert(not broadcast.payload.players and not broadcast.payload.gpTooltip)
local count = #sent
Receive({ version = 1, kind = "REQUEST", request = "abc" }, "Member-Realm")
assert(#sent == count + 1 and sent[#sent].channel == "WHISPER" and sent[#sent].target == "Member-Realm")
assert(sent[#sent].payload.request == "abc")
Receive({ version = 1, kind = "REQUEST", request = "abc" }, "Member-Realm")
assert(#sent == count + 1) -- Duplicate requests are throttled.
Receive({ version = 1, kind = "REQUEST", request = "abc" }, "Outsider-Realm")
Receive({ version = 1, kind = "REQUEST", request = "abc" }, "Other-Realm", "WHISPER")
assert(#sent == count + 1)
Receive(Data(15), "Other-Realm") -- Broadcasts update other officers too.
assert(SEPGP.GP.GetFormulaSettings().Base == 15)
officer = false
now = now + 3
Receive({ version = 1, kind = "REQUEST", request = "abc" }, "Member-Realm")
assert(#sent == count + 1)
-- Login waits for the roster; members request once, officers do not request.
timers = {}
local savedRoster = roster
roster = {}
events.callback(events, "PLAYER_LOGIN")
assert(#timers == 1 and timers[1][1] == 3)
timers[1][2]()
assert(#sent == count + 1 and #timers == 2)
roster = savedRoster
timers[2][2]()
assert(#sent == count + 2 and sent[#sent].payload.kind == "REQUEST")
Receive(Data(16, sent[#sent].payload.request), nil, "WHISPER")
timers = {}
officer = true
events.callback(events, "PLAYER_LOGIN")
timers[1][2]()
assert(#sent == count + 2)
officer = false
assert(SEPGP.RequestSettings())
timers[#timers][2]() -- Timeout permits retry and reports no officer response.
assert(messages[#messages]:find("No online officer", 1, true))
assert(SEPGP.RequestSettings())
timers[#timers][2]()
guild = false
Receive(Data(99))
assert(SEPGP.GP.GetFormulaSettings().Base == 16)
assert(not SEPGP.RequestSettings())
officer = true
assert(not SEPGP.SendSettings())
output("Settings sync tests passed")
