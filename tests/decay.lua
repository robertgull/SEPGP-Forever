-- Run from the repository root: lua tests/decay.lua
local messages, timers = {}, {}
print = function() end
GetUnitName = function() return "Officer" end
time = function() return 1 end
SlashCmdList = {}
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
C_GuildInfo = { IsGuildOfficer = function() return true end }
C_ChatInfo = {
    SendAddonMessage = function(prefix, message, channel)
        assert(prefix == "SEPGPF" and channel == "OFFICER")
        messages[#messages + 1] = message
        return 0
    end,
}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
strsplit = function(delimiter, value)
    local parts = {}
    for part in (value .. delimiter):gmatch("(.-)" .. delimiter) do
        parts[#parts + 1] = part
    end
    return (unpack or table.unpack)(parts)
end
dofile("SEPGP-Forever/EPGP.lua")

local function reset()
    SEPGP_DB = { revision = 0, localCounter = 0, players = {}, actions = {} }
    SEPGP.sendQueue, SEPGP.isSending = {}, false
    messages, timers = {}, {}
end
local function close(actual, expected)
    assert(math.abs(actual - expected) < 0.000001)
end
local function seed()
    SEPGP_DB.players = {
        alice = { EP = 101, GP = 100 },
        bob = { EP = 500, GP = 250 },
    }
end

seed()
SlashCmdList.SEPGP("DeCaY 20")
close(SEPGP_DB.players.alice.EP, 80.8)
close(SEPGP_DB.players.alice.GP, 80)
close(SEPGP_DB.players.bob.EP, 400)
close(SEPGP_DB.players.bob.GP, 200)
assert(SEPGP_DB.revision == 2)
while #timers > 0 do table.remove(timers, 1)() end
assert(#messages == 2)
local sent = { messages[1], messages[2] }
for _, action in pairs(SEPGP_DB.actions) do
    assert(action.type == "DECAY" and action.amount == 20)
    assert(action.before and action.after)
    assert(not SEPGP.ApplyAction(action))
end
SEPGP.PrintHistory()
SEPGP.PrintStandings()
SlashCmdList.SEPGP("get alice")
SEPGP.AddEP("alice", 1)
SEPGP.AddGP("bob", 1)

-- Another officer receives the serialized actions, including duplicates.
reset()
seed()
for _, message in ipairs(sent) do
    SEPGP.HandleAddonMessage("SEPGPF", message, "OFFICER", "Officer")
    SEPGP.HandleAddonMessage("SEPGPF", message, "OFFICER", "Officer")
end
close(SEPGP_DB.players.alice.EP, 80.8)
close(SEPGP_DB.players.alice.GP, 80)
close(SEPGP_DB.players.bob.EP, 400)
assert(SEPGP_DB.revision == 2)

for _, command in ipairs({ "decay", "decay -1", "decay 101", "decay nope", "decay 20 extra" }) do
    SlashCmdList.SEPGP(command)
    assert(SEPGP_DB.revision == 2)
end
assert(SEPGP.Decay(-1) == nil)
assert(SEPGP.Decay(0 / 0) == nil)
assert(SEPGP.Decay(math.huge) == nil)
assert(SEPGP.ParseAction("ACTION|bad|DECAY|alice|101|Officer|1||||") == nil)

SlashCmdList.SEPGP("decay 0")
close(SEPGP_DB.players.alice.EP, 80.8)
SlashCmdList.SEPGP("decay 12.5")
close(SEPGP_DB.players.alice.EP, 70.7)
SlashCmdList.SEPGP("decay 100")
assert(SEPGP_DB.players.alice.EP == 0 and SEPGP_DB.players.alice.GP == 0)
assert(SEPGP.GetPR("alice") == 0)
reset()
assert(SEPGP.Decay(20) == 0 and SEPGP_DB.revision == 0)
io.write("Decay tests passed\n")