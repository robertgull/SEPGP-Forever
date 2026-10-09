-- One realm: point records use character names, including embedded spaces.
function SEPGP.MigratePlayerNames()
    local groups, changed = {}, false
    for name, player in pairs(SEPGP_DB.players) do
        local key = SEPGP.NormalizeName(name)
        groups[key] = groups[key] or {}
        groups[key][#groups[key] + 1] = { name = name, player = player }
        if key ~= name then changed = true end
    end
    if not changed then return end
    local players = {}
    for key, records in pairs(groups) do
        if #records == 1 then players[key] = records[1].player
        else
            -- A command may already have created a second account for the same
            -- character. Keep the original records and reconcile their ledger.
            SEPGP_DB.nameMigrationBackup = SEPGP_DB.nameMigrationBackup or {}
            local actions, hasHistory = {}, {}
            for _, action in ipairs(SEPGP.GetSortedActions()) do
                if SEPGP.NormalizeName(action.player) == key then
                    actions[#actions + 1] = action
                    hasHistory[action.player:lower()] = true
                end
            end
            local baseline
            for _, record in ipairs(records) do
                if not SEPGP_DB.nameMigrationBackup[record.name] then
                    SEPGP_DB.nameMigrationBackup[record.name] = { EP = record.player.EP, GP = record.player.GP }
                end
                -- A record with no ledger is an imported standing, not a set of
                -- additional awards. Use it as a baseline rather than summing it.
                if not hasHistory[record.name:lower()] then
                    baseline = baseline or { EP = 0, GP = SEPGP.BASE_GP }
                    baseline.EP = math.max(baseline.EP, record.player.EP)
                    baseline.GP = math.max(baseline.GP, record.player.GP)
                end
            end
            local before = actions[1] and actions[1].before
            local player = baseline or { EP = before and before.EP or 0, GP = before and before.GP or SEPGP.BASE_GP }
            for _, action in ipairs(actions) do
                if action.type == "EP" then player.EP = math.max(0, player.EP + action.amount)
                elseif action.type == "GP" and action.amount ~= 0 then player.GP = math.max(SEPGP.BASE_GP, player.GP + action.amount)
                elseif action.type == "DECAY" and SEPGP.IsValidDecay(action.amount) then
                    local multiplier = 1 - action.amount / 100
                    player.EP, player.GP = player.EP * multiplier, player.GP * multiplier
                end
            end
            players[key] = player
        end
    end
    SEPGP_DB.players = players
    SEPGP_DB.syncCheckpoint = nil -- Confirm the canonical names at the next sync.
end

function SEPGP.GetPlayer(name)
    local key = SEPGP.NormalizeName(name)
    if not key then return nil end
    if not SEPGP_DB.players[key] then
        -- Also recognize legacy standings introduced after addon initialization.
        for stored in pairs(SEPGP_DB.players) do
            if SEPGP.NormalizeName(stored) == key then SEPGP.MigratePlayerNames(); break end
        end
    end
    return SEPGP_DB.players[key]
end
function SEPGP.EnsurePlayer(name)
    local player = SEPGP.GetPlayer(name)
    if player then return player end
    player = { EP = 0, GP = SEPGP.BASE_GP }
    SEPGP_DB.players[SEPGP.NormalizeName(name)] = player
    return player
end
SEPGP.MigratePlayerNames()
