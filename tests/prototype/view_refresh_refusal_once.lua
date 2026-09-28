-- REG-ERRFLOOD: a legacy-repair refusal that repeats on every view refresh
-- (here: a saved repair schema newer than this build, which stays read-only)
-- is recorded in the error log ONCE per session. The log keeps 20 entries;
-- recording the same refusal on every refresh pushed every earlier error,
-- such as an Orb or start-up error, out of the support report.
--
-- Real TOC boot; synthetic profile.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
-- A repair state written by a newer build: this build must not touch it.
NexusDB.legacyQualificationRepair={schemaVersion=999}
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local E,V=Nexus.Errors,Nexus.ViewRefresh
check(E.Limit()==20,'fixture: the error log keeps 20 entries: '..tostring(E.Limit()))

local REPAIR='ViewRefresh.LegacyQualificationRepair'
local function Count(source)
 local n=0
 for _,entry in ipairs(E.History()) do if entry.source==source then n=n+1 end end
 return n
end
local function Refreshes(n)
 for _=1,n do V.Request();for _=1,40 do H.Advance(.05,.05) end end
end

-- An earlier, unrelated error the support report must keep.
E.Record('OrbRuntime.Test','an earlier Orb error')
Refreshes(30)
check(Count(REPAIR)==1,'thirty refreshes record the same refusal once: '..Count(REPAIR))
check(Count('OrbRuntime.Test')==1,'and the earlier Orb error is still in the log')
local latestRepair
for _,entry in ipairs(E.History()) do if entry.source==REPAIR then latestRepair=entry end end
check(latestRepair and latestRepair.message:find('future legacy repair schema',1,true)~=nil,
 'the one entry states the refusal: '..tostring(latestRepair and latestRepair.message))
check(NexusDB.legacyQualificationRepair.schemaVersion==999,'the newer repair state is left untouched')

-- A DIFFERENT refusal is a new fact and is recorded once as well.
local repair=Nexus.LegacyQualificationRepair
local realRequest=repair.Request
repair.Request=function() return false,'a different refusal' end
Refreshes(10)
repair.Request=realRequest
check(Count(REPAIR)==2,'a different refusal is recorded once too: '..Count(REPAIR))
check(Count('OrbRuntime.Test')==1,'and the Orb error is still there')

print('PASS view_refresh_refusal_once checks='..checks)
