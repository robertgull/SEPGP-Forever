-- One access policy and help list for every slash-command module.
local commands = {
    { name = "help", usage = "/sep help" },
    { name = "show", usage = "/sep show" },
    { name = "show history", usage = "/sep show history", officer = true },
    { name = "standings", usage = "/sep standings" },
    { name = "update", usage = "/sep update" },
    { name = "get", usage = "/sep get <player>" },
    { name = "me", usage = "/sep me" },
    { name = "settings update", usage = "/sep settings update" },
    { name = "settings send", usage = "/sep settings send", officer = true },
    { name = "sync", usage = "/sep sync", officer = true },
    { name = "history", usage = "/sep history", officer = true },
    { name = "addep", usage = "/sep addep <player> <amount>", officer = true },
    { name = "addgp", usage = "/sep addgp <player> <amount>", officer = true },
    { name = "decay", usage = "/sep decay <percent>", officer = true },
    { name = "raidep", usage = "/sep raidep <amount> [reason]", officer = true },
    { name = "dfb", usage = "/sep dfb", officer = true },
    { name = "testid", usage = "/sep testid", officer = true },
    { name = "cleardb", usage = "/sep cleardb - clear local data", officer = true },
}
local officerCommands = {}
for _, command in ipairs(commands) do
    if command.officer then officerCommands[command.name] = true end
end

function SEPGP.PrintCommandHelp()
    print("SEPGP Forever")
    for _, command in ipairs(commands) do
        print(command.usage .. (command.officer and " (officer only)" or ""))
    end
end

local previousSlash = SlashCmdList.SEPGP
SlashCmdList.SEPGP = function(message)
    message = (message or ""):match("^%s*(.-)%s*$")
    local command = (message:match("^(%S+)") or ""):lower()
    if command == "" or command == "help" then SEPGP.PrintCommandHelp(); return end
    if command == "show" and message:lower():match("^show%s+history%s*$") then
        if not SEPGP.CanEditOfficerSettings() then
            print("SEPGP: /sep show history is officer only.")
        else SEPGP.ToggleHistoryWindow() end
        return
    end
    if command == "settings" then
        local action = (message:match("^%S+%s+(%S+)") or ""):lower()
        if action == "send" and not SEPGP.CanEditOfficerSettings() then
            print("SEPGP: /sep settings send is officer only.")
        elseif action == "send" then SEPGP.SendSettings()
        elseif action == "update" then SEPGP.RequestSettings()
        else print("SEPGP: /sep settings send (officer only) or /sep settings update") end
        return
    end
    if officerCommands[command] and not SEPGP.CanEditOfficerSettings() then
        print("SEPGP: /sep " .. command .. " is officer only.")
        return
    end
    previousSlash(message)
end
