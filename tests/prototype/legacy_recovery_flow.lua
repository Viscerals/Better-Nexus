-- Explicit keep-current / preserve-legacy start-up recovery (control
-- BN-CONTROL-LEGACY-RECOVERY-20261001-008).
-- A current profile (committed authority bundle, retained "noLegacy" receipt)
-- next to a distinct, non-empty legacy WishlistRealizerDB is refused at
-- STORE_LEGACY_DISPOSITION_PENDING with legacy class FOREIGN_BLOCK. This test
-- pins the refusal, then the explicit recovery: read-only offer, a code bound
-- to the exact legacy value, full-value preservation in a separate
-- non-authoritative store, unchanged current authority, and a serialize and
-- reload round trip. Offline literal round trip only; this is NOT a native host
-- save and reload. Real TOC boot, Store coordinator, lifecycle, commands.
-- Synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local STORE='nexusLegacyPreservationV1'

local base
do
 F.Boot(F.Database({version=2}))
 check(Nexus.StartupStatus().coreReady,'fixture: the base profile starts')
 base=F.Serialize(NexusDB)
end
local function Current()
 local db=assert(loadstring('return '..base))()
 -- The receipt a reporter's profile retains: completed, decision noLegacy.
 db.nexusStoreMigrations={wishlistRealizerDB={version=1,completed=true,decision='noLegacy'}}
 return db
end
local function Legacy()
 return {settingsVersion=1,
  chars={LegacyAlt={loadoutWishlists={[1]={slot=1,name='Old plan',echoes={{spellId=300001,quality=2,stacks=1}}}},note='legacy'}},
  customLegacy={keep=true,list={1,2,3}},[7]='numeric key',flag=false}
end
local LEGACY_TEXT=F.Serialize(Legacy())
local function Start(db,legacy)
 return F.Boot(db,function() WishlistRealizerDB=legacy end)
end
local function Say(H,command)
 local first=#H.chat+1
 SlashCmdList.NEXUS(command)
 return table.concat(H.chat,'\n',first)
end
local function Plain(text) return (tostring(text):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
local function Without(db,...)
 local copy=assert(loadstring('return '..F.Serialize(db)))()
 for _,key in ipairs({...}) do copy[key]=nil end
 return F.Serialize(copy)
end

-- 1. Initial refusal (unchanged behavior). Legacy and receipt stay untouched.
local db=Current()
local legacy=Legacy()
local H=Start(db,legacy)
local s=Nexus.StartupStatus()
check(s.state=='failed' and not s.coreReady,'refusal: start-up is stopped')
check(s.reason=='LEGACY_DISPOSITION_REAUTH_REQUIRED','refusal: the original reason is kept: '..tostring(s.reason))
check(s.failure.stage=='STORE_LEGACY_DISPOSITION_PENDING' and s.failure.legacyClass=='FOREIGN_BLOCK'
 and s.failure.formatClass=='supported' and s.failure.formatVersion==2,'refusal: stage, class and format are reported')
check(WishlistRealizerDB==legacy and F.Serialize(legacy)==LEGACY_TEXT,'refusal: the legacy table is untouched')
check(F.Serialize(NexusDB.nexusStoreMigrations)==F.Serialize({wishlistRealizerDB={version=1,completed=true,decision='noLegacy'}}),
 'refusal: the retained noLegacy receipt is not rewritten')
check(NexusDB[STORE]==nil,'refusal: nothing is preserved or written without confirmation')
check(Nexus.Store.StateWriteStatus().mode~='durable','refusal: dependents have no durable write eligibility')
local failedSaved=F.Serialize(NexusDB)

-- 2. Read-only offer.
local said=Plain(Say(H,'legacy'))
local code=said:match('/nexus legacy keep (%x+)')
check(code and #code==12 and code==code:lower(),'offer: a 12-character code is shown: '..said)
check(said:find('current',1,true) and said:find('unchanged',1,true),'offer: says the current setup stays unchanged: '..said)
check(said:find('Nothing is deleted, imported or merged',1,true),'offer: says nothing is deleted, imported or merged: '..said)
check(F.Serialize(NexusDB)==failedSaved and F.Serialize(legacy)==LEGACY_TEXT and WishlistRealizerDB==legacy,
 'offer: reading the offer writes nothing')
check(Plain(Say(H,'legacy')):find(code,1,true),'offer: the code is stable across reads')
check(F.Serialize(NexusDB)==failedSaved,'offer: repeated reads write nothing')

-- 3. Missing and wrong code change nothing.
local out=Plain(Say(H,'legacy keep'))
check(out:find('/nexus legacy keep '..code,1,true),'confirm: no code names the exact command: '..out)
out=Plain(Say(H,'legacy keep 000000000000'))
check(out:find('CODE_MISMATCH',1,true),'confirm: a wrong code is refused: '..out)
check(F.Serialize(NexusDB)==failedSaved and WishlistRealizerDB==legacy,'confirm: a refused code changes nothing')

-- 4. Explicit recovery.
local bundle=rawget(NexusDB,'authorityBundle')
local beforeAuthority=Without(NexusDB,STORE)
out=Plain(Say(H,'legacy keep '..code))
check(out:find('preserved',1,true) and out:find('/reload',1,true),'recovery: success names the reload step: '..out)
check(WishlistRealizerDB==nil,'recovery: the legacy global is released after it is preserved')
local store=NexusDB[STORE]
check(type(store)=='table' and store.version==1 and type(store.entries)=='table','recovery: the preservation store exists')
local keys={};for k in pairs(store.entries)do keys[#keys+1]=k end
check(#keys==1 and keys[1]:sub(1,12)==code and #keys[1]==16,'recovery: one entry, keyed by the full 16-character digest')
local entry=store.entries[keys[1]]
check(F.Serialize(entry.value)==LEGACY_TEXT,'recovery: the preserved value equals the legacy value in full')
check(entry.value~=legacy,'recovery: the preserved value is a detached copy')
check(entry.source=='WishlistRealizerDB' and entry.version==1 and entry.digest==keys[1],'recovery: entry fields')
check(rawget(NexusDB,'authorityBundle')==bundle,'recovery: the current authority bundle is the same table')
check(Without(NexusDB,STORE)==beforeAuthority,'recovery: the current profile is unchanged except the preservation store')
check(F.Serialize(NexusDB.nexusStoreMigrations)==F.Serialize({wishlistRealizerDB={version=1,completed=true,decision='noLegacy'}}),
 'recovery: the old receipt is not rewritten or repurposed')
-- Same session, repeated confirmation and offer.
out=Plain(Say(H,'legacy keep '..code))
check(out:find('already preserved',1,true),'repeat: a second confirmation reports it is already preserved: '..out)
check(#(function() local n={};for k in pairs(NexusDB[STORE].entries)do n[#n+1]=k end return n end)()==1,'repeat: no second entry')
check(Plain(Say(H,'legacy')):find('already preserved',1,true),'repeat: the offer says it is already preserved')

-- 5. Save and reload round trip (offline literal round trip, not a native reload).
local saved=F.Serialize(NexusDB)
local roundTrip=assert(loadstring('return '..saved))()
check(F.Serialize(roundTrip)==saved,'round trip: the saved text reloads to the same value')
local H2=F.Boot(roundTrip)
s=Nexus.StartupStatus()
check(s.coreReady and s.state~='failed','reload: the profile starts with the current setup: '..tostring(s.state)..'/'..tostring(s.reason))
check(WishlistRealizerDB==nil,'reload: no legacy global')
local afterEntry=NexusDB[STORE] and NexusDB[STORE].entries[keys[1]]
check(afterEntry and F.Serialize(afterEntry.value)==LEGACY_TEXT,'reload: the preserved value is still complete')
H2.Advance(30,.05)
check(F.Serialize(NexusDB[STORE].entries[keys[1]].value)==LEGACY_TEXT,'reload: maintenance and play leave the preserved value unchanged')
check(F.Serialize(NexusDB.nexusStoreMigrations)==F.Serialize({wishlistRealizerDB={version=1,completed=true,decision='noLegacy'}}),
 'reload: the old receipt is still not rewritten')
check(Plain(Say(H2,'legacy')):find('No older-data decision is waiting',1,true),'reload: the command reports nothing is waiting')
-- A second start-up from the same saved text (repeated start-up).
local H3=F.Boot((assert(loadstring('return '..F.Serialize(NexusDB)))()))
check(Nexus.StartupStatus().coreReady and WishlistRealizerDB==nil,'repeat start-up: ready again, still no legacy global')
check(F.Serialize(NexusDB[STORE].entries[keys[1]].value)==LEGACY_TEXT,'repeat start-up: the preserved value is unchanged')

-- 6. Interrupted before save: the file still holds the refusal state. The
-- same refusal returns and the same recovery works again.
local H4=Start((assert(loadstring('return '..failedSaved))()),Legacy())
check(Nexus.StartupStatus().reason=='LEGACY_DISPOSITION_REAUTH_REQUIRED','interrupted before save: the same refusal returns')
local again=Plain(Say(H4,'legacy')):match('/nexus legacy keep (%x+)')
check(again==code,'interrupted before save: the offer code is the same for the same data: '..tostring(again))
out=Plain(Say(H4,'legacy keep '..again))
check(WishlistRealizerDB==nil and NexusDB[STORE] and out:find('preserved',1,true),'interrupted before save: recovery works again')

-- 7. A restored copy of the same legacy after an earlier recovery: the entry is
-- reused, never overwritten, and no second entry is made.
local H5=Start((assert(loadstring('return '..saved))()),Legacy())
check(Nexus.StartupStatus().reason=='LEGACY_DISPOSITION_REAUTH_REQUIRED','restored legacy: refused again')
local entryBefore=F.Serialize(NexusDB[STORE].entries[keys[1]])
local restored=Plain(Say(H5,'legacy')):match('/nexus legacy keep (%x+)')
check(restored==code,'restored legacy: the same code')
out=Plain(Say(H5,'legacy keep '..restored))
check(WishlistRealizerDB==nil,'restored legacy: released after the existing entry is verified: '..out)
local n=0;for _ in pairs(NexusDB[STORE].entries)do n=n+1 end
check(n==1 and F.Serialize(NexusDB[STORE].entries[keys[1]])==entryBefore,'restored legacy: one entry, not overwritten')

print('PASS legacy_recovery_flow: refusal, read-only offer, bound code, full-value preservation, unchanged authority, reload round trip, repeated start-up checks='..checks)
