-- Reporter failure on test.9035 after test.9033: saved format 5, start-up
-- failed with STORE_INVALID. Reproduced mechanism: while a build kept format 5
-- read-only (test.9033 treated it as newer), the Store built no Store-data
-- wrapper, and the catalog committed its bundle with the empty placeholder.
-- A build that accepts format 5 then took the bundle path and refused the empty
-- wrapper. Here the same placeholder comes from the current code: one start-up
-- while the marker is 6 (read-only), then the marker is 5 again. Real TOC boot.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local OTHER='otherchar@ebonhold'
local function Receipt()return {pending={id='synthetic-pending',spellId=200010,at=11},exposure=1}end

-- Stage 1: a start-up that keeps the data read-only writes the placeholder.
local db=F.Database({version=6,mutate=function(d)
 d.chars[OTHER]={orbRefinement=Receipt(),loadoutWishlists={},otherUnknown={keep=true}}
end})
F.Boot(db)
check(Nexus.Store.StateWriteStatus().format=='future','fixture: stage 1 keeps the data read-only')
local sd=NexusDB.authorityBundle and NexusDB.authorityBundle.storeData
check(type(sd)=='table' and next(sd)==nil,'fixture: the bundle holds the empty Store-data placeholder')
NexusDB.settingsVersion=5
local saved=F.Serialize(NexusDB)
local function Fresh()return assert(loadstring('return '..saved))()end
local original=Fresh()

-- Stage 2: the accepting build starts, as a first admission, preserving everything.
F.Boot(Fresh())
local s=Nexus.StartupStatus()
check(s.state~='failed' and s.coreReady,'the accepted format starts: '..tostring(s.reason)..' '..tostring(s.failure and s.failure.cause))
check(Nexus.Store.StateWriteStatus().mode=='durable','writes are durable')
check(NexusDB.settingsVersion==5,'the saved marker stays 5')
local function Same(a,b,path)
 if type(a)~='table' then check(a==b,'unchanged '..path) return end
 check(type(b)=='table','kept '..path)
 for k,v in pairs(a)do Same(v,b[k],path..'.'..tostring(k)) end
end
for _,key in ipairs({'settings','accountCharacters','genUnknownTopLevel','nexusNativeRecoveryArchiveF5'})do
 Same(original[key],NexusDB[key],key)
end
Same(original.chars[F.NAME],NexusDB.chars[F.NAME],'plain-name row')
Same(original.chars[OTHER],NexusDB.chars[OTHER],'other character row')
check(NexusDB.chars[OTHER].orbRefinement.pending.id=='synthetic-pending' and NexusDB.chars[OTHER].orbRefinement.exposure==1,'the pending receipt and its exposure are kept')
check(Nexus.Store.State().loadoutWishlists[1].name=='Gen plan','the owned plain-name row is readable (carried on first write)')
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.afterFix=true end))
check(NexusDB.chars[F.OWNER].savedFormatCarry.from==F.NAME and NexusDB.chars[F.OWNER].afterFix,'the first write carries the owned row durably')

-- Reload: still starts; the carry is not repeated.
local carried=F.Serialize(NexusDB.chars[F.OWNER].savedFormatCarry)
F.Reload()
check(Nexus.StartupStatus().coreReady,'reload starts')
check(F.Serialize(NexusDB.chars[F.OWNER].savedFormatCarry)==carried,'the carry is not repeated')

-- No bypass: a non-empty invalid wrapper for format 5 still fails, with its cause.
local bad=Fresh();bad.authorityBundle.storeData={schemaVersion=2}
F.Boot(bad)
local b=Nexus.StartupStatus()
check(b.state=='failed' and b.reason=='STORE_INVALID' and b.failure and b.failure.cause=='STORE_DATA_SCHEMA',
 'a non-empty invalid Store-data wrapper stays refused: '..tostring(b.failure and b.failure.cause))
-- An unverified format 5 with the placeholder stays read-only, not started as accepted.
local unverified=Fresh();unverified.settings.syncMode='auto'
F.Boot(unverified)
local u=Nexus.Store.StateWriteStatus()
check(u.mode=='unavailable' and u.format=='unverified','an unverified format with the placeholder stays read-only')
print('PASS format5_bundle_placeholder: placeholder from a read-only start-up is admitted as a first admission for an accepted format; originals kept; no bypass checks='..checks)
