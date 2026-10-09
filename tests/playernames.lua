local output = print
print = function() end
SEPGP, SEPGP_DB, SlashCmdList = {}, {}, {}
C_GuildInfo = { IsGuildOfficer = function() return true end }
GetUnitName = function() return "Officer-Realm" end
time = function() return 100 end
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
C_Timer = { After = function() end }
C_ChatInfo = { SendAddonMessage = function() return 0 end }
dofile("SEPGP-Forever/EPGP.lua")
dofile("SEPGP-Forever/SettingsData.lua")
dofile("SEPGP-Forever/UI.lua")
SEPGP_DB.players = { ["ducky dru-classicbetapvp"] = { EP = 500, GP = 200 } }
SEPGP_DB.syncCheckpoint = { timestamp = 10 }
dofile("SEPGP-Forever/PlayerNames.lua")
assert(SEPGP_DB.players["ducky dru"].EP == 500)
assert(not SEPGP_DB.players["ducky dru-classicbetapvp"] and not SEPGP_DB.syncCheckpoint)
SlashCmdList.SEPGP("addep ducky dru 100")
assert(SEPGP.GetPlayer("Ducky Dru").EP == 600)
assert(SEPGP.GetPlayer("Ducky Dru-ClassicBetaPvP").EP == 600)
SlashCmdList.SEPGP("addgp ducky dru 50")
assert(SEPGP.GetPlayer("Ducky Dru").GP == 250)
for _, action in pairs(SEPGP_DB.actions) do assert(action.player == "ducky dru") end
-- Signed command amounts subtract points and retain the adjustment in history.
SlashCmdList.SEPGP("addep ducky dru -100")
assert(SEPGP.GetPlayer("Ducky Dru").EP == 500)
SlashCmdList.SEPGP("addgp ducky dru -50")
assert(SEPGP.GetPlayer("Ducky Dru").GP == 200)
local negativeEP, negativeGP = false, false
for _, action in pairs(SEPGP_DB.actions) do
    if action.type == "EP" and action.amount == -100 then
        assert(action.before.EP == 600 and action.after.EP == 500)
        negativeEP = true
    elseif action.type == "GP" and action.amount == -50 then
        assert(action.before.GP == 250 and action.after.GP == 200)
        negativeGP = true
    end
end
assert(negativeEP and negativeGP)
-- Restore the totals used by the migration checks below.
SlashCmdList.SEPGP("addep ducky dru 100")
SlashCmdList.SEPGP("addgp ducky dru 50")
-- Legacy actions still apply to the same account without creating an alias.
assert(SEPGP.ApplyAction({ id = "legacy", timestamp = 110, type = "EP", player = "ducky dru-classicbetapvp", amount = 25 }))
assert(SEPGP.GetPlayer("ducky dru").EP == 625)
assert(not SEPGP_DB.players["ducky dru-classicbetapvp"])
-- Existing split accounts combine their awards once, with a backup of originals.
SEPGP_DB.players = { ["ducky dru-realm"] = { EP = 500, GP = 200 }, ["ducky dru"] = { EP = 100, GP = 100 } }
SEPGP_DB.actions = {
    old = { id = "old", timestamp = 10, type = "EP", player = "ducky dru-realm", amount = 500, before = { EP = 0, GP = 100 } },
    gp = { id = "gp", timestamp = 20, type = "GP", player = "ducky dru-realm", amount = 100 },
    recent = { id = "recent", timestamp = 30, type = "EP", player = "ducky dru", amount = 100, before = { EP = 0, GP = 100 } },
}
SEPGP.MigratePlayerNames()
assert(SEPGP.GetPlayer("ducky dru").EP == 600 and SEPGP.GetPlayer("ducky dru").GP == 200)
assert(SEPGP_DB.nameMigrationBackup["ducky dru-realm"].EP == 500)
assert(SEPGP_DB.nameMigrationBackup["ducky dru"].EP == 100)
SEPGP.MigratePlayerNames()
assert(SEPGP.GetPlayer("ducky dru").EP == 600) -- Idempotent across reloads.
-- Imported standings with no history keep their totals during a simple rename.
SEPGP_DB.players = { ["imported pal-realm"] = { EP = 750, GP = 300 } }
assert(SEPGP.GetPlayer("Imported Pal").EP == 750)
assert(SEPGP.EnsurePlayer("Imported Pal-Realm").GP == 300)
assert(not SEPGP_DB.players["imported pal-realm"])
assert(SEPGP.NormalizeName("  Ducky Dru-ClassicBetaPvP ") == "ducky dru")
output("Player name migration/command tests passed")
