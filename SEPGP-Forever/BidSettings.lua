-- Stable positions retain category priority; position 5 always means Pass.
SEPGP.Bids = {}
local Bids = SEPGP.Bids
local defaults = {
    { label = "BiS", discount = 0, active = true },
    { label = "Alternative", discount = 20, active = true },
    { label = "Upgrade", discount = 50, active = true },
    { label = "Off Spec", discount = 100, active = true },
    { label = "Pass", discount = 100, active = true },
}

function Bids.Key(label)
    return label:lower():gsub("%s+", "")
end

function Bids.Validate(values)
    if type(values) ~= "table" then return false, "Invalid bid buttons." end
    local names = {}
    for index = 1, 5 do
        local value = values[index]
        if type(value) ~= "table" or type(value.label) ~= "string"
            or not value.label:find("%S") or #value.label > 24
            or value.label:find("[|%c]") then
            return false, "Button names must contain 1-24 characters, without formatting or line breaks."
        end
        local key = Bids.Key(value.label)
        if names[key] then return false, "Button names must be distinct." end
        names[key] = true
        if type(value.discount) ~= "number" or value.discount ~= value.discount
            or value.discount < 0 or value.discount > 100
            or type(value.active) ~= "boolean" then
            return false, "Discounts must be between 0 and 100 percent."
        end
    end
    return true
end

function Bids.Copy(values)
    local copy = {}
    for index = 1, 5 do
        local value = values[index]
        copy[index] = { label = value.label:match("^%s*(.-)%s*$"),
            discount = index == 5 and 100 or value.discount, active = value.active }
    end
    return copy
end

function Bids.GetSettings()
    SEPGP_DB = SEPGP_DB or {}
    if type(SEPGP_DB.settings) ~= "table" then SEPGP_DB.settings = {} end
    if not Bids.Validate(SEPGP_DB.settings.bids) then
        SEPGP_DB.settings.bids = Bids.Copy(defaults)
    end
    return SEPGP_DB.settings.bids
end

function Bids.SetSettings(values)
    if not SEPGP.CanEditOfficerSettings() then
        return false, "Only guild officers can change bid buttons."
    end
    local ok, err = Bids.Validate(values)
    if not ok then return false, err end
    Bids.GetSettings()
    SEPGP_DB.settings.bids = Bids.Copy(values)
    return true
end

function Bids.ResetSettings() return Bids.SetSettings(defaults) end

function Bids.GetChoices(values)
    local choices = Bids.Copy(values or Bids.GetSettings())
    for _, choice in ipairs(choices) do choice.percent = 100 - choice.discount end
    return choices
end

function Bids.GetDefaultChoices() return Bids.GetChoices(defaults) end
