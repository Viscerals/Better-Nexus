-- The explicit keep-current / preserve-legacy recovery changes ONE case: a
-- selected current root next to a distinct, non-empty legacy global. Every other
-- legacy-global case behaves exactly as before: absent, selected alias,
-- distinct empty, selected legacy, future format, invalid current, malformed
-- marker, non-plain current. A retained receipt of any decision is not
-- authority to discard. The command surface, and a static check that no other
-- owner reads the preservation store. Real TOC boot; synthetic data only.
-- (Control BN-CONTROL-LEGACY-RECOVERY-20261001-008.)
local S=dofile('tests/prototype/legacy_recovery_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local STORE=S.STORE
local REAUTH='LEGACY_DISPOSITION_REAUTH_REQUIRED'
local WAITING_NONE='No older-data decision is waiting'

local function NothingWaiting(H,label)
 local before=F.Serialize(NexusDB);local global=WishlistRealizerDB
 check(S.Plain(S.Say(H,'legacy')):find(WAITING_NONE,1,true),label..': /nexus legacy: nothing is waiting')
 check(S.Plain(S.Say(H,'legacy keep 000000000000')):find(WAITING_NONE,1,true),label..': /nexus legacy keep: nothing is waiting')
 check(F.Serialize(NexusDB)==before and WishlistRealizerDB==global and NexusDB[STORE]==nil,label..': nothing was written')
end

-- 1. Absent legacy global.
do
 local H=S.Start(S.Current(),nil)
 local s=Nexus.StartupStatus()
 check(s.coreReady and s.state~='failed' and WishlistRealizerDB==nil,'absent: start-up is ready, no legacy global')
 NothingWaiting(H,'absent')
end

-- 2. Selected alias: the legacy global IS the current root; one verified nil write.
do
 local db=S.Current()
 local H=S.Start(db,db)
 check(Nexus.StartupStatus().coreReady and NexusDB==db and WishlistRealizerDB==nil,'selected alias: ready, the alias is released, the root is the same table')
 check(NexusDB[STORE]==nil,'selected alias: nothing is preserved')
 NothingWaiting(H,'selected alias')
end

-- 3. Distinct empty legacy global: preserved without a write, grants nothing.
do
 local empty={}
 local H=S.Start(S.Current(),empty)
 check(Nexus.StartupStatus().coreReady and WishlistRealizerDB==empty and next(empty)==nil,'distinct empty: ready, the empty table is left as it was')
 check(NexusDB[STORE]==nil,'distinct empty: nothing is preserved')
 NothingWaiting(H,'distinct empty')
end

-- 4. Selected legacy: no current data; the legacy becomes the root (one nil write).
do
 local legacy=F.Database({version=2})
 local H=F.Boot(nil,function() WishlistRealizerDB=legacy end)
 check(Nexus.StartupStatus().coreReady and NexusDB==legacy and WishlistRealizerDB==nil,'selected legacy: adopted as the root, alias released')
 NothingWaiting(H,'selected legacy')
end

-- 5. Future format: a future receipt version stops start-up as before.
do
 local db=F.Database({version=2});db.nexusStoreMigrations={wishlistRealizerDB={version=2,completed=true}}
 local legacy=S.Legacy()
 local H=S.Start(db,legacy)
 local s=Nexus.StartupStatus()
 check(s.state=='failed' and s.reason=='FUTURE_SCHEMA','future format: stopped as FUTURE_SCHEMA: '..tostring(s.reason))
 check(WishlistRealizerDB==legacy and F.Serialize(legacy)==F.Serialize(S.Legacy()),'future format: the legacy global is untouched')
 NothingWaiting(H,'future format')
end

-- 6. Invalid current (malformed receipt) with a foreign legacy global.
do
 local db=F.Database({version=2});db.nexusStoreMigrations={wishlistRealizerDB={version=1,completed='yes'}}
 local legacy=S.Legacy()
 local H=S.Start(db,legacy)
 local s=Nexus.StartupStatus()
 check(s.state=='failed' and s.reason=='STORE_INVALID' and s.failure.row==5,'invalid: stopped as STORE_INVALID row 5')
 check(WishlistRealizerDB==legacy,'invalid: the legacy global is untouched')
 NothingWaiting(H,'invalid')
end

-- 7. Non-plain current root.
do
 local db=setmetatable(F.Database({version=2}),{})
 local legacy=S.Legacy()
 local H=S.Start(db,legacy)
 local s=Nexus.StartupStatus()
 check(s.state=='failed' and s.reason=='STORE_INVALID' and s.failure.row==1,'non-plain current: stopped as STORE_INVALID row 1')
 NothingWaiting(H,'non-plain current')
end

-- 8. A retained receipt of any decision is not authority to discard: the same
-- refusal returns, and only the explicit confirmation changes anything.
for _,decision in ipairs({'noLegacy','adoptedLegacy','keptCurrent','ignoredEmptyLegacy','completed','absent'}) do
 local db=S.Current()
 db.nexusStoreMigrations.wishlistRealizerDB={version=1,completed=true,decision=decision~='absent' and decision or nil}
 local legacy=S.Legacy()
 local H=S.Start(db,legacy)
 local s=Nexus.StartupStatus()
 check(s.reason==REAUTH and s.failure.legacyClass=='FOREIGN_BLOCK','stale receipt '..decision..': still refused')
 check(WishlistRealizerDB==legacy and F.Serialize(legacy)==F.Serialize(S.Legacy()),'stale receipt '..decision..': the legacy is untouched')
 local receipt=F.Serialize(NexusDB.nexusStoreMigrations)
 local code=S.Code(H)
 S.Say(H,'legacy keep '..code)
 check(WishlistRealizerDB==nil and NexusDB[STORE]~=nil,'stale receipt '..decision..': the explicit recovery works')
 check(F.Serialize(NexusDB.nexusStoreMigrations)==receipt,'stale receipt '..decision..': the receipt is not rewritten or repurposed')
end
-- A first-time profile (no receipt yet): the receipt is written as before the
-- disposition fails, and is still not authority.
do
 local db=S.Current();db.nexusStoreMigrations=nil
 local H=S.Start(db,S.Legacy())
 check(Nexus.StartupStatus().reason==REAUTH,'no receipt yet: refused')
 check(F.Serialize(NexusDB.nexusStoreMigrations)==F.Serialize({wishlistRealizerDB={version=1,completed=true,decision='keptCurrent'}}),
  'no receipt yet: the selection receipt is published as before the disposition fails')
 local code=S.Code(H);local receipt=F.Serialize(NexusDB.nexusStoreMigrations)
 S.Say(H,'legacy keep '..code)
 check(F.Serialize(NexusDB.nexusStoreMigrations)==receipt,'no receipt yet: the recovery does not rewrite it')
end

-- 9. The refusal points at the command; the old failure lines remain.
do
 local H=S.Start(S.Current(),S.Legacy())
 local said=S.Plain(S.Say(H,'status'))
 check(said:find('Startup stopped: '..REAUTH,1,true) and said:find('Startup failure: stage=STORE_LEGACY_DISPOSITION_PENDING; legacy=FOREIGN_BLOCK; saved format=supported 2',1,true),
  'refusal: the original lines are unchanged: '..said)
 check(said:find('/nexus legacy',1,true) and said:find('Nothing is deleted unless you confirm',1,true),'refusal: status points at /nexus legacy: '..said)
 -- After the recovery the hint says to reload, and no longer asks for a decision.
 S.Say(H,'legacy keep '..S.Code(H))
 local after=S.Plain(S.Say(H,'status'))
 check(after:find('Older data is preserved. Type /reload',1,true) and not after:find('needs your decision',1,true),
  'refusal: after the recovery the status says to reload: '..after)
 -- Other failures do not carry the hint.
 local db=F.Database({version=2});db.nexusStoreMigrations={wishlistRealizerDB={version=1,completed='yes'}}
 local H2=S.Start(db,nil)
 check(not S.Plain(S.Say(H2,'status')):find('/nexus legacy',1,true),'refusal: other failures carry no hint')
end

-- 10. Command surface.
do
 local legacy=S.Legacy()
 local H=S.Start(S.Current(),legacy)
 local before=F.Serialize(NexusDB)
 local usage=S.Plain(S.Say(H,'legacy foo'))
 check(usage:find('Use /nexus legacy',1,true),'commands: unknown option prints usage: '..usage)
 local code=S.Code(H)
 local bare=S.Plain(S.Say(H,'legacy keep'))
 check(bare:find('/nexus legacy keep '..code,1,true),'commands: keep without a code names the exact command')
 check(S.Plain(S.Say(H,'LEGACY   ')):find(code,1,true),'commands: case and trailing spaces are accepted')
 check(F.Serialize(NexusDB)==before and WishlistRealizerDB==legacy,'commands: none of these wrote anything')
 local out=S.Plain(S.Say(H,'LEGACY KEEP '..code:upper()))
 check(WishlistRealizerDB==nil and out:find('preserved',1,true),'commands: an upper-case confirmation works: '..out)
 check(not out:find(code:upper(),1,true),'commands: the answer does not echo the typed text')
end

-- 11. Static: only core/Store.lua knows the preservation store. Sync, Wishlist,
-- assignments, Community and the catalog never read it.
do
 local readers,total={},0
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local path=line:gsub('\\','/')
   local handle=io.open(path,'rb')
   if handle then
    local text=handle:read('*a');handle:close();total=total+1
    if text:find(STORE,1,true) then readers[#readers+1]=path end
   end
  end
 end
 check(total>40,'static: the TOC files were scanned: '..total)
 check(#readers==1 and readers[1]=='core/Store.lua','static: only core/Store.lua names the preservation store: '..table.concat(readers,','))
end

print('PASS legacy_recovery_unchanged: absent, alias, distinct empty, selected legacy, future, invalid, non-plain unchanged; stale receipts are not authority; command surface; no other reader checks='..checks)
