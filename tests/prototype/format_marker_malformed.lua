-- Only an ABSENT settings marker is an unversioned save. A PRESENT marker that
-- is not a finite whole number of 0 or more is malformed: the data stays
-- unchanged and read-only through boot and reload. It is never coerced to 0,
-- stamped 2, lowered, accepted by the legacy converter or bypassed for Orb.
-- Real TOC boot, Store, LegacyDataMigration and Orb runtime; synthetic data.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Writer()return Nexus.MainInternals.StoreAuthorityOwner end
local function Same(a,b)return (a~=a and b~=b) or a==b end
local function Receipt()
 return {pending={id='synthetic-pending',spellId=200010,at=11},exposure=1}
end
local function Build(marker)
 return F.Database({mutate=function(db)
  db.settingsVersion=marker
  db.chars[F.OWNER]={loadoutWishlists={},orbRefinement=Receipt(),canonicalUnknown={keep=true}}
 end})
end
local function Durable()
 return F.Serialize({chars=NexusDB.chars,settings=NexusDB.settings,ledger=NexusDB.accountCharacters,
  top=NexusDB.genUnknownTopLevel,archive=NexusDB.nexusNativeRecoveryArchiveF5})
end
local function Marker()return rawget(NexusDB,'settingsVersion')end

local cases={
 {6.5,'number','6.5'},{-1,'number','-1'},{0/0,'number','NaN'},{math.huge,'number','inf'},{-math.huge,'number','-inf'},
 {'5','string','"5"'},{'abc','string','"abc"'},{'',"string",'""'},{true,'boolean','true'},{false,'boolean','false'},
 {{version=5},'table',nil},
}
for _,case in ipairs(cases)do
 local marker,kind,text=case[1],case[2],case[3]
 local label='marker '..kind..' '..tostring(text or 'table')
 local db=Build(marker)
 local before=F.Serialize({chars=db.chars,settings=db.settings,ledger=db.accountCharacters,
  top=db.genUnknownTopLevel,archive=db.nexusNativeRecoveryArchiveF5})
 local markerBefore=F.Serialize(marker)
 local H=F.Boot(db,F.OrbService)
 local status=Nexus.Store.StateWriteStatus()
 check(status.mode=='unavailable' and status.reason=='saved-format' and status.format=='malformed',label..': read-only as malformed: '..tostring(status.format))
 check(status.markerType==kind and status.markerText==text,label..': names type and bounded value: '..tostring(status.markerText))
 check(Nexus.Store.Settings()~=NexusDB.settings,label..': settings reads use the temporary copy')
 check(next(Nexus.Store.State().orbRefinement or {})==nil,label..': reads do not expose a durable row as writable')
 assert(Writer().UpdateStateV1(function(row)row.malformedProbe=true end))
 check(NexusDB.chars[F.OWNER].malformedProbe==nil,label..': a write goes only to the temporary row')
 local allowed,why=Nexus.LegacyDataMigration.AccountWritesAllowed(NexusDB)
 check(allowed==false and tostring(why):find('malformed',1,true),label..': the converter refuses too: '..tostring(why))
 local ok,refusal=Nexus.OrbRuntime.Start(1)
 check(not ok and tostring(refusal):find('not a valid format number ('..kind,1,true),label..': Orb Start refuses factually: '..tostring(refusal))
 local spends=0;for _,a in ipairs(H.actions)do if a[1]=='orb-spend' then spends=spends+1 end end
 check(spends==0,label..': nothing is sent')
 check(F.Serialize(Marker())==markerBefore and type(Marker())==kind,label..': marker unchanged after boot')
 check(Durable()==before,label..': characters, receipt, settings, ledger, unknown fields and archive unchanged after boot')
 F.Reload(F.OrbService)
 check(F.Serialize(Marker())==markerBefore and type(Marker())==kind,label..': marker unchanged after reload')
 check(Durable()==before,label..': everything unchanged after reload')
 check(Nexus.Store.StateWriteStatus().format=='malformed',label..': still malformed after reload')
end

-- Positive controls: absent and 0 are unversioned (stamped 2 as before); 2 stays
-- 2; 5 is an accepted historical format; 6 stays future, not malformed.
for _,case in ipairs({{nil,2,'durable'},{0,2,'durable'},{2,2,'durable'},{5,5,'durable'},{6,6,'future'}})do
 local marker,after,expect=case[1],case[2],case[3]
 local label='control '..tostring(marker)
 local db=Build(marker)
 F.Boot(db)
 local status=Nexus.Store.StateWriteStatus()
 if expect=='durable' then
  check(status.mode=='durable',label..': durable: '..tostring(status.mode)..' '..tostring(status.format))
 else
  check(status.format=='future' and status.savedFormat==6,label..': future, not malformed')
 end
 check(Same(Marker(),after),label..': marker is '..tostring(after)..': '..tostring(Marker()))
 check(NexusDB.chars[F.OWNER].orbRefinement.pending.id=='synthetic-pending',label..': the pending receipt is kept')
end
print('PASS format_marker_malformed: 11 malformed markers read-only and unchanged through boot and reload; absent/0/2/5/6 controls checks='..checks)
