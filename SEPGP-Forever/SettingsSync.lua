-- Dedicated AceComm channel keeps settings separate from EP/GP history traffic.
local PREFIX = "SEP_SETTINGS"
local pending, sequence = nil, 0
local lastReply = {}

local function NameKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not name:find("-", 1, true) then
        name = name .. "-" .. (GetRealmName() or "")
    end
    return name:lower():gsub("%s+", "")
end

local function GuildMember(name)
    local key = NameKey(name)
    if not key or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
    for index = 1, GetNumGuildMembers() do
        local member, _, rank = GetGuildRosterInfo(index)
        if NameKey(member) == key then return rank end
    end
end

local function OfficerSender(sender)
    local rank = GuildMember(sender)
    if rank == nil then return false end
    if rank == 0 then return true end -- Guild master.
    if NameKey(sender) == NameKey(GetUnitName("player", true)) then
        return SEPGP.CanEditOfficerSettings()
    end
    -- Edit Officer Note is the guild permission identifying officers.
    if not C_GuildInfo or not C_GuildInfo.GuildControlGetRankFlags then return false end
    local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rank + 1)
    return ok and type(flags) == "table" and flags[12] == true
end
-- Shared roster identity/permission checks for officer history synchronization.
SEPGP.GuildNameKey = NameKey
SEPGP.IsGuildOfficerName = OfficerSender

local function Send(payload, channel, target)
    local encoded = SEPGP.EncodePayload(payload)
    if not encoded then return false end
    SEPGP:SendCommMessage(PREFIX, encoded, channel, target, "NORMAL")
    return true
end

local function Snapshot(request)
    local gp = SEPGP.GP.GetFormulaSettings()
    return { version = 1, kind = "SETTINGS", request = request,
        gp = { Base = gp.Base, Multiplier = gp.Multiplier, Mod = gp.Mod },
        bids = SEPGP.Bids.Copy(SEPGP.Bids.GetSettings()) }
end

function SEPGP.SendSettings()
    if not SEPGP.CanEditOfficerSettings() then
        print("SEPGP: Sending settings is officer only.")
        return false
    end
    if not IsInGuild() then print("SEPGP: You must be in a guild to send settings."); return false end
    local sent = Send(Snapshot(), "GUILD")
    print(sent and "SEPGP: Settings sent to the guild." or "SEPGP: Failed to send settings.")
    return sent
end

function SEPGP.RequestSettings(quiet)
    if not IsInGuild() then
        if not quiet then print("SEPGP: You must be in a guild to update settings.") end
        return false
    end
    if pending then
        if not quiet then print("SEPGP: A settings request is already in progress.") end
        return false
    end
    sequence = sequence + 1
    local request = tostring(GetTime()) .. ":" .. tostring(sequence)
    pending = request
    if not Send({ version = 1, kind = "REQUEST", request = request }, "GUILD") then
        pending = nil
        if not quiet then print("SEPGP: Failed to request settings.") end
        return false
    end
    if not quiet then print("SEPGP: Settings requested from online officers.") end
    C_Timer.After(10, function()
        if pending ~= request then return end
        pending = nil
        if not quiet then print("SEPGP: No online officer responded. Try settings update again later.") end
    end)
    return true
end

function SEPGP:OnSettingsCommReceived(prefix, message, channel, sender)
    if prefix ~= PREFIX or not IsInGuild()
        or (channel ~= "GUILD" and channel ~= "WHISPER") then return end
    if NameKey(sender) == NameKey(GetUnitName("player", true)) then return end
    local payload = SEPGP.DecodePayload(message)
    if type(payload) ~= "table" or payload.version ~= 1 then return end
    if payload.kind == "REQUEST" then
        if channel ~= "GUILD" or not SEPGP.CanEditOfficerSettings()
            or GuildMember(sender) == nil or type(payload.request) ~= "string"
            or #payload.request > 80 then return end
        local key, now = NameKey(sender), GetTime()
        if lastReply[key] and now - lastReply[key] < 2 then return end
        lastReply[key] = now
        Send(Snapshot(payload.request), "WHISPER", sender)
        return
    end
    if payload.kind ~= "SETTINGS" or not OfficerSender(sender) then return end
    if channel == "WHISPER" then
        if not pending or payload.request ~= pending then return end
    elseif payload.request ~= nil then return end
    -- Validate every value before replacing either section. Personal preferences
    -- and standings never travel in settings packets.
    local gp = payload.gp
    if type(gp) ~= "table" or not SEPGP.GP.IsValidFormulaValue("Base", gp.Base)
        or not SEPGP.GP.IsValidFormulaValue("Multiplier", gp.Multiplier)
        or not SEPGP.GP.IsValidFormulaValue("Mod", gp.Mod)
        or not SEPGP.Bids.Validate(payload.bids) then return end
    SEPGP.GP.GetFormulaSettings()
    SEPGP_DB.settings.gp = { Base = gp.Base, Multiplier = gp.Multiplier, Mod = gp.Mod }
    SEPGP_DB.settings.bids = SEPGP.Bids.Copy(payload.bids)
    pending = nil -- First valid officer response wins this request.
    if SEPGP.RefreshSettings then SEPGP.RefreshSettings() end
    print("SEPGP: Settings updated from " .. SEPGP.DisplayName(sender) .. ".")
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
local function LoginUpdate(attempt)
    if not IsInGuild() then
        if attempt < 6 then C_Timer.After(5, function() LoginUpdate(attempt + 1) end) end
        return
    end
    -- The guild roster and permissions may not yet be available at PLAYER_LOGIN.
    if GuildMember(GetUnitName("player", true)) ~= nil then
        if not SEPGP.CanEditOfficerSettings() then SEPGP.RequestSettings(true) end
        return
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    if attempt < 6 then C_Timer.After(5, function() LoginUpdate(attempt + 1) end) end
end
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == "SEPGP-Forever" then
        SEPGP:RegisterComm(PREFIX, "OnSettingsCommReceived")
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(3, function() LoginUpdate(1) end)
    end
end)
