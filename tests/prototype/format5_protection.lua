-- Saved formats that are not verified stay protected; existing format-2 and
-- unversioned users are unchanged; a failed start-up and an interrupted first
-- write keep the originals. Real TOC boot, Store and Orb runtime; synthetic
-- data only; no Orb service call can happen on these paths.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Writer()return Nexus.MainInternals.StoreAuthorityOwner end
local function Protected(label,db,expect)
 local before=F.Serialize({chars=db.chars,settings=db.settings,ledger=db.accountCharacters,version=db.settingsVersion})
 local H=F.Boot(db,F.OrbService)
 local status=Nexus.Store.StateWriteStatus()
 check(status.mode=='unavailable' and status.reason=='saved-format' and status.format==expect.format
  and status.savedFormat==expect.saved and status.supportedFormat==2,label..': read-only with the real markers')
 check(status.field==expect.field,label..': names the failing field '..tostring(status.field))
 check(Nexus.Store.Settings()~=NexusDB.settings,label..': settings reads use the temporary copy')
 assert(Writer().UpdateStateV1(function(row)row.protectedProbe=true end))
 local ok,why=Nexus.OrbRuntime.Start(1)
 check(not ok and tostring(why):find(expect.text,1,true),label..': Start refuses with factual wording: '..tostring(why))
 check(not tostring(why):find('newer Nexus',1,true),label..': no claim about who wrote the data')
 local spends=0;for _,a in ipairs(H.actions)do if a[1]=='orb-spend' then spends=spends+1 end end
 check(spends==0,label..': nothing is sent')
 local after=F.Serialize({chars=NexusDB.chars,settings=NexusDB.settings,ledger=NexusDB.accountCharacters,version=NexusDB.settingsVersion})
 check(after==before,label..': characters, settings, ledger and marker are unchanged')
end
Protected('stamped 5 without the format-3 normalization',F.Database({mutate=function(db)db.settings.syncMode='auto'end}),
 {format='unverified',saved=5,field='settings.syncMode',text='Saved data format 5 did not pass'})
Protected('format-5 ledger with an unknown-realm row',F.Database({mutate=function(db)
 db.accountCharacters['prototypetester@unknown']={name=F.NAME}end}),
 {format='unverified',saved=5,field='accountCharacters',text='(field: accountCharacters)'})
Protected('format-3 retention value out of range',F.Database({version=3,mutate=function(db)
 db.settings.communityRetentionTopAverage=-1 end}),
 {format='unverified',saved=3,field='settings.communityRetentionTopAverage',text='format 3 data'})
Protected('format 6',F.Database({version=6}),{format='future',saved=6,text='Saved data format 6 is not supported. This build writes format 2 and reads formats 3 to 5 after a check.'})
Protected('format 99',F.Database({version=99}),{format='future',saved=99,text='Saved data format 99 is not supported'})

-- Existing format-2 and unversioned users: unchanged behavior. A plain-name
-- row is not carried there, even with a matching ledger row.
for _,version in ipairs({2,false})do
 local label=version and 'format 2' or 'unversioned'
 local db=F.Database({mutate=function(d)d.settingsVersion=version or nil end})
 local nameRow=F.Serialize(db.chars[F.NAME])
 F.Boot(db)
 check(NexusDB.settingsVersion==2,label..': marker is (still) 2')
 check(Nexus.Store.StateWriteStatus().mode=='durable' and Nexus.Store.StateWriteStatus().carriedFrom==nil,label..': durable, no carry')
 assert(Writer().UpdateStateV1(function(row)row.format2Probe=true end))
 check(NexusDB.chars[F.OWNER].format2Probe==true and NexusDB.chars[F.OWNER].savedFormatCarry==nil
  and NexusDB.chars[F.OWNER].loadoutWishlists[1]==nil,label..': a new canonical row as before')
 check(F.Serialize(NexusDB.chars[F.NAME])==nameRow,label..': the plain-name row is untouched')
end

-- A failed start-up (an aliased table in a row): stops before any carry and
-- changes neither the original rows nor any saved setting value.
do
 local db=F.Database()
 local shared={x=1};db.chars[F.NAME].aliasA=shared;db.chars[F.NAME].aliasB=shared
 local settings={};for k,v in pairs(db.settings)do settings[k]=F.Serialize(v)end;local rowTable=db.chars[F.NAME]
 F.Boot(db,F.OrbService)
 check(Nexus.StartupStatus().state=='failed' and not Nexus.StartupStatus().coreReady,'failed start-up is reported, not ready')
 check(NexusDB.chars[F.OWNER]==nil and NexusDB.chars[F.NAME]==rowTable and rowTable.aliasA==rowTable.aliasB,'failed start-up: no carry, original row kept as it was')
 -- Existing behavior for every format: missing default keys are added before
 -- the row checks; no saved value changes.
 for k,v in pairs(settings)do check(F.Serialize(NexusDB.settings[k])==v,'failed start-up: saved setting unchanged: '..k)end
 check(NexusDB.settingsVersion==5,'failed start-up: marker unchanged')
 local ok,why=Nexus.OrbRuntime.Start(1)
 check(not ok,'failed start-up: Start refuses: '..tostring(why))
end

-- An interrupted first write: the copy is complete, the original stays, and
-- the next start-up keeps both without copying again.
do
 local db=F.Database();local nameRow=F.Serialize(db.chars[F.NAME])
 F.Boot(db)
 local ok=pcall(Writer().UpdateStateV1,function(row)row.halfDone=true;error('synthetic interruption')end)
 check(not ok,'fixture: the first write is interrupted')
 local canonical=NexusDB.chars[F.OWNER]
 check(type(canonical)=='table' and canonical.loadoutWishlists[1].name=='Gen plan'
  and canonical.savedFormatCarry.from==F.NAME,'interrupted: the carried copy is complete')
 check(F.Serialize(NexusDB.chars[F.NAME])==nameRow,'interrupted: the original row is unchanged')
 local carried=F.Serialize(canonical)
 F.Reload()
 check(F.Serialize(NexusDB.chars[F.OWNER])==carried and F.Serialize(NexusDB.chars[F.NAME])==nameRow,'interrupted: reload keeps both, no second copy')
end
-- No coordinator (Store loaded alone): the rows were never admitted, so
-- nothing is copied and the status is not reported as durable.
do
 Nexus=nil;dofile('tests/prototype/harness.lua')
 local db=F.Database();local before=F.Serialize(db.chars)
 Nexus={};NexusDB=db;dofile('core/Identity.lua');dofile('core/Store.lua')
 local status=Nexus.Store.StateWriteStatus()
 check(status.mode=='loading' and status.reason=='lifecycle','no coordinator: not durable: '..tostring(status.mode))
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.aloneProbe=true end))
 check(F.Serialize(NexusDB.chars)==before,'no coordinator: no copy and no durable write')
end
-- Unverified values the format-3 normalization never leaves behind.
for _,bad in ipairs({1.5,0/0,'5',math.huge})do
 Protected('retention value '..tostring(bad),F.Database({mutate=function(db)db.settings.communityRetentionTopAverage=bad end}),
  {format='unverified',saved=5,field='settings.communityRetentionTopAverage',text='(field: settings.communityRetentionTopAverage)'})
end
Protected('format 4 without a ledger',F.Database({version=4,mutate=function(db)db.accountCharacters=nil end}),
 {format='unverified',saved=4,field='accountCharacters',text='format 4 data'})

-- Known formats 3 and 4 (format 3 has no ledger yet): durable, marker kept, no carry without a ledger.
for _,case in ipairs({{3,false},{4,true}})do
 local version,ledger=case[1],case[2]
 local db=F.Database({version=version,mutate=function(d)if not ledger then d.accountCharacters=nil end end})
 local nameRow=F.Serialize(db.chars[F.NAME]);local ledgerBefore=F.Serialize(db.accountCharacters)
 F.Boot(db)
 local status=Nexus.Store.StateWriteStatus()
 check(status.mode=='durable' and NexusDB.settingsVersion==version,'format '..version..': durable, marker kept')
 check((status.carriedFrom~=nil)==ledger,'format '..version..': carry only with an established ledger owner')
 assert(Writer().UpdateStateV1(function(row)row.knownProbe=version end))
 check(NexusDB.chars[F.OWNER].knownProbe==version and F.Serialize(NexusDB.chars[F.NAME])==nameRow,'format '..version..': write durable, original kept')
 check(F.Serialize(NexusDB.accountCharacters)==ledgerBefore,'format '..version..': no ledger row added')
end

-- A real boot before the row checks ran: no copy and no durable write.
do
 local db=F.Database();local before=F.Serialize(db.chars)
 local early
 F.Boot(db,nil,function()
  early={status=Nexus.Store.StateWriteStatus()}
  assert(Writer().UpdateStateV1(function(row)row.earlyProbe=true end))
  early.chars=F.Serialize(NexusDB.chars)
 end)
 check(early.status.mode~='durable','early boot: not reported durable: '..tostring(early.status.mode))
 check(early.chars==before,'early boot: no copy and no durable write before the row checks')
 check(Nexus.Store.StateWriteStatus().carriedFrom==F.NAME,'early boot: the copy becomes possible after admission')
end

-- A plain key with a realm suffix is never taken as this character's row.
do
 local db=F.Database({mutate=function(d)d.chars['PrototypeTester-OtherRealm']=d.chars[F.NAME];d.chars[F.NAME]=nil end})
 local suffixed=F.Serialize(db.chars['PrototypeTester-OtherRealm'])
 F.Boot(db)
 check(Nexus.Store.StateWriteStatus().carriedFrom==nil,'suffixed key: no carry')
 assert(Writer().UpdateStateV1(function(row)row.suffixProbe=true end))
 check(NexusDB.chars[F.OWNER].savedFormatCarry==nil and F.Serialize(NexusDB.chars['PrototypeTester-OtherRealm'])
  ==suffixed,'suffixed key: preserved, not carried')
end
print('PASS format5_protection: unverified and future formats read-only, format 2 unchanged, failed, interrupted and unadmitted paths keep originals checks='..checks)
