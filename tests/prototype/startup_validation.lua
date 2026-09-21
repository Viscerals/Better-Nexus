local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
-- Preserve the established over-wide unknown key rejection. There is no
-- real player fixture here and no cleanup/recovery helper in the package.
NexusDB={settings={unknown={[string.rep('x',184)]='preserve-me'}},chars={}}
local original=H.Clone(NexusDB)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(5)
assert(not Nexus.StartupStatus().coreReady,'invalid Store input must not unlock local controls')
assert(Nexus.StartupStatus().state=='failed','failed Store is not reported ready')
assert(not Nexus.StartupStatus().syncReady and not Nexus.StartupStatus().dpsReady,'invalid input cannot release shared owners')
assert(NexusDB.settings.unknown[string.rep('x',184)]=='preserve-me','invalid data must not be deleted')
assert(NexusDB.authorityBundle==nil,'invalid source must not be published')
assert(#H.sent==0 and #H.actions==0,'invalid Store must not cause game/network actions')
SlashCmdList.NEXUS('status')
assert(table.concat(H.chat,'\n'):find('Startup stopped:',1,true),'status reports refusal rather than endless preparing')
print('PASS invalid startup preserves data and all readiness gates')
