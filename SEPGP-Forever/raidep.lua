-- Manual EP awards to a snapshot of the current raid, using the action queue.
SEPGP = SEPGP or {}

local function RaidPlayerName(name)
    local short, realm = name:match("^([^-]+)%-(.+)$")
    local localRealm = GetNormalizedRealmName()
    if not short then short, realm = name, localRealm end
    local full = SEPGP.NormalizeName(short .. "-" .. realm)
    -- Keep existing same-realm records instead of creating a second account.
    if SEPGP.GetPlayer(full) then return full end
    if realm:lower() == localRealm:lower() and SEPGP.GetPlayer(short) then
        return SEPGP.NormalizeName(short)
    end
    return full
end

function SEPGP.AwardRaidEP(amount, reason)
    if type(amount) ~= "number" or amount <= 0 or amount >= math.huge or amount % 1 ~= 0 then
        print("Usage: /sep raidep <positive whole amount> [reason]")
        return nil
    end
    if not C_GuildInfo.IsGuildOfficer() then
        print("SEPGP: Raid EP awards are only available to guild officers.")
        return nil
    end
    if not IsInRaid() then
        print("SEPGP: You must be in a raid to award raid EP.")
        return nil
    end
    if reason ~= nil and type(reason) ~= "string" then return nil end
    reason = reason and reason:match("^%s*(.-)%s*$") or ""
    if reason == "" then reason = "Raid EP award" end

    local recipients, seen = {}, {}
    for index = 1, GetNumGroupMembers() do
        local name = GetUnitName("raid" .. index, true)
        if not name or name == "" then
            print("SEPGP: The raid roster is not ready. Try the award again.")
            return nil
        end
        local player = RaidPlayerName(name)
        if not seen[player] then
            seen[player] = true
            recipients[#recipients + 1] = player
        end
    end
    if #recipients == 0 then return nil end

    local count = 0
    for _, player in ipairs(recipients) do
        local action = SEPGP.CreateAction("EP", player, amount, reason)
        if SEPGP.ApplyAction(action) then
            SEPGP.QueueAction(action)
            count = count + 1
        end
    end
    if SEPGP.UI and SEPGP.UI.standingsFrame and SEPGP.UI.standingsFrame:IsShown() then
        SEPGP.RefreshStandingsWindow()
    end
    if count > 0 then
        local message = string.format("SEPGP: Awarded %g EP to %d raid members.", amount, count)
        print(message .. " Reason: " .. reason)
        SendChatMessage(message, "RAID")
    end
    return count
end

local previousSlash = SlashCmdList.SEPGP
SlashCmdList.SEPGP = function(msg)
    local command, args = (msg or ""):match("^%s*(%S+)%s*(.-)%s*$")
    if command and command:lower() == "raidep" then
        local amount, reason = args:match("^(%S+)%s*(.-)$")
        SEPGP.AwardRaidEP(amount and amount:match("^%d+$") and tonumber(amount) or nil, reason)
        return
    end
    previousSlash(msg)
    if not msg or msg == "" then print("/sep raidep <amount> [reason] - award EP to the current raid") end
end
