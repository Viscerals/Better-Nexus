local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(8,20);T.Load()
local calls=0;local old=Nexus.LoadoutEvidence.Init
Nexus.LoadoutEvidence.Init=function(...)calls=calls+1;return old(...)end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
-- Force finite one-slice clock fallback for deterministic mid-admission timing.
debugprofilestop=nil
T.Until(H,function()return Nexus.BuildCatalog.RootState().state=='ROOT_ADMISSION_PENDING'end,1000)
assert(calls==1)
local evidence=Nexus.LoadoutEvidence
local replacement={};for k,v in pairs(evidence)do replacement[k]=v end
Nexus.LoadoutEvidence=replacement
H.Advance(3)
assert(not Nexus.StartupStatus().coreReady,'changed evidence owner cannot reuse its old admission')
assert(Nexus.StartupStatus().state=='failed','owner mismatch remains a terminal source refusal')
assert(calls==1,'must not disguise drift by silently reinitializing against a new owner')
assert(#H.sent==0,'no send on invalid startup')
print('PASS owner drift refused and missing-clock fallback stays bounded')
