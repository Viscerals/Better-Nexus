local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(24,300)
local source=NexusDB;local legacy=H.Clone(source.communityBuilds)
T.Load()
local count=0;local init=Nexus.LoadoutEvidence.Init
Nexus.LoadoutEvidence.Init=function(...)count=count+1;return init(...)end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.startupTiming.readyAt~=nil end)
assert(count==1,'EXPECTED RED: evidence initialized '..count..' times for one startup source')
assert(Nexus.StartupStatus().coreReady,'validated local data ready')
assert(T.Equal(source.communityBuilds,legacy),'legacy input changed while migrating')
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end)
assert(count<=2,'reinitialization repeated during Community startup')
assert(T.Equal(source.communityBuilds,legacy),'legacy records must remain untouched')
local durable=source.authorityBundle
assert(type(durable)=='table' and T.Count(durable.communityBuilds)==24,'complete rows retained')
for i=1,24 do
 local row=durable.communityBuilds['synthetic-startup-'..i]
 assert(row and row.customUnknown.keep==i,'unknown row data preserved')

end
for i=1,300 do
 assert(durable.loadoutEvidence.entries['synthetic-preserved-'..i].keep==i,'opaque evidence lost')
end
local cursor=assert(Nexus.BuildCatalog.BeginRecordCursor());local rows=0
for i=1,30000 do
 local page,why=Nexus.BuildCatalog.RecordCursorNext(cursor)
 assert(type(page)=='table' and not why,'public cursor failed: '..tostring(why))
 if page.record then rows=rows+1;assert(type(page.record.echoes)=='table' and #page.record.echoes==79,'public row lost ordinary Echoes')end
 if page.done then break end
end
assert(rows==24,'public catalog omitted rows')
print('PASS evidence once-per-source; 24 complete rows and 300 opaque entries preserved; calls='..count)
