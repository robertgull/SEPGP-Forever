SEPGP = SEPGP or {}

-- Realm-qualified names remain the stored identity and whisper address.
function SEPGP.DisplayName(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^[^-]+") or name
end

function SEPGP.CanEditOfficerSettings()
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer
        and C_GuildInfo.IsGuildOfficer() and true or false
end

-- Personal display preferences are saved separately for each character.
function SEPGP.GetPersonalSettings()
    if type(SEPGP_PREFS) ~= "table" then SEPGP_PREFS = {} end
    if type(SEPGP_PREFS.gpTooltip) ~= "boolean" then SEPGP_PREFS.gpTooltip = true end
    return SEPGP_PREFS
end

function SEPGP.SetGPTooltipEnabled(enabled)
    SEPGP.GetPersonalSettings().gpTooltip = enabled and true or false
end
