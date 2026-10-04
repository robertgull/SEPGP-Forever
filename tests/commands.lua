-- Run from the repository root: lua tests/commands.lua
local output = print
local messages, delegated = {}, {}
print = function(message) messages[#messages + 1] = message end
SEPGP = {}
local officer = false
C_GuildInfo = { IsGuildOfficer = function() return officer end }
dofile("SEPGP-Forever/SettingsData.lua")
local sends, updates = 0, 0
SEPGP.SendSettings = function() sends = sends + 1 end
SEPGP.RequestSettings = function() updates = updates + 1 end
SlashCmdList = { SEPGP = function(message) delegated[#delegated + 1] = message end }
dofile("SEPGP-Forever/Commands.lua")
SlashCmdList.SEPGP(" HeLp ")
local help = table.concat(messages, "\n")
for _, usage in ipairs({ "sync", "history", "addep <player> <amount>", "addgp <player> <amount>",
    "decay <percent>", "raidep <amount> [reason]", "dfb" }) do
    assert(help:find("/sep " .. usage .. " (officer only)", 1, true))
end
assert(help:find("/sep show\n", 1, true) and help:find("/sep update\n", 1, true))
assert(#delegated == 0 and not help:find("Unknown", 1, true))
assert(help:find("/sep settings send (officer only)", 1, true))
assert(help:find("/sep settings update\n", 1, true))
local helpLines = #messages
SlashCmdList.SEPGP(" ")
assert(#messages == helpLines * 2) -- Bare /sep shows the same help without duplicates.
for _, command in ipairs({ "SYNC", "history", "addep Alice 100", "addgp Alice 100", "decay 20",
    "raidep 100 Boss kill", "dfb", "testid", "cleardb" }) do
    SlashCmdList.SEPGP(" " .. command .. " ")
    assert(#delegated == 0 and messages[#messages]:find("officer only", 1, true))
end
for _, command in ipairs({ "show", "standings", "update", "get Alice", "me" }) do SlashCmdList.SEPGP(command) end
assert(#delegated == 5 and delegated[3] == "update")
SlashCmdList.SEPGP("settings send")
assert(sends == 0)
SlashCmdList.SEPGP("SETTINGS UPDATE")
assert(updates == 1)
officer = true
SlashCmdList.SEPGP("settings send")
assert(sends == 1)
for _, command in ipairs({ "sync", "history", "addep Alice 100", "addgp Alice 100", "decay 20", "raidep 100 Boss", "dfb" }) do
    local before = #delegated
    SlashCmdList.SEPGP(command)
    assert(#delegated == before + 1 and delegated[#delegated] == command)
end
C_GuildInfo = nil
local before = #delegated
SlashCmdList.SEPGP("addep Alice 100")
assert(#delegated == before)
output("Command permission/help tests passed")
