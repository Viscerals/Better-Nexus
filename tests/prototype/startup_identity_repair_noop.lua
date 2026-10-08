-- Start-up identity repair: needsFullBuild nil and false mean the same thing
-- ("no full build needed"; Sync stores received builds with nil). A record
-- whose identity is current except for that nil must not be rewritten at
-- start-up, because a repair is a whole catalog mutation pass
-- (BN-FULL-REVIEW-PRIVATE-BUILD-003; reporter file 9 replay: all 72 repairs
-- were nil -> false only). Control: needsFullBuild true, which does differ,
-- is still repaired. Real catalog, controller and start-up; module reloads with
-- round-tripped literal data (not a client reload).
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Settle(H,seconds) for _=1,seconds*20 do H.Advance(.05,.05) end end
local function FindUp(name)
 local seen,queue={},{}
 for _,v in pairs(Nexus) do if type(v)=='function' then queue[#queue+1]=v elseif type(v)=='table' then for _,w in pairs(v) do if type(w)=='function' then queue[#queue+1]=w end end end end
 while #queue>0 do
  local f=table.remove(queue,1)
  if not seen[f] then seen[f]=true
   for i=1,255 do local n,v=debug.getupvalue(f,i);if not n then break end
    if n==name and type(v)=='function' then return v end
    if type(v)=='function' then queue[#queue+1]=v
    elseif type(v)=='table' and not seen[v] then seen[v]=true
     for _,w in pairs(v) do if type(w)=='function' then queue[#queue+1]=w end end end
   end
  end
 end
end
local function Raw(id)
 local b=NexusDB.authorityBundle;local m=b and b.communityBuilds
 return m and m[id]
end
local function Put(C,H,record)
 local ok,why,ticket=C.Put(record)
 if ok==nil and why=='ROOT_MUTATION_PENDING' then
  for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
  ok=ticket.committed
 end
 return ok,why
end

-- 1. Seed: one received-style record with current identity and nil.
local H=F.Boot(F.Database());Settle(H,20)
local C=Nexus.BuildCatalog
local repaired=assert(FindUp('RepairedIdentity'),'fixture: the start-up repair rule is found')
local base={id='saved-identity_nil',title='Identity nil',author='IdentityPeer',class='MAGE',
 echoes={},postedAt=1700000100,lastModified=1700000100,isMine=false,ownerVerified=false,
 fingerprint='stale',fingerprintHash='stale',echoCount=0,loadoutAvailable=true}
for i,e in ipairs(F.PLAN) do base.echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks} end
local current=repaired(base)
check(type(current)=='table' and current.fingerprint~='stale','fixture: the rule computes a current identity (not vacuous)')
current.needsFullBuild=nil
check(Put(C,H,current),'fixture: the nil record is stored')
check(Raw(current.id) and Raw(current.id).needsFullBuild==nil and Raw(current.id).fingerprint==current.fingerprint,'fixture: stored with nil and the current identity')

-- 2. Reload: the nil record is not rewritten.
H=F.Reload();Settle(H,60)
local row=Raw('saved-identity_nil')
check(row~=nil,'the record survives the reload')
check(row.needsFullBuild==nil,'nil needsFullBuild is not rewritten to false at start-up (be19854: false)')
check(repaired(row)==nil,'the rule finds nothing to repair')

-- 3. Control: a stale identity field is still repaired at start-up.
C=Nexus.BuildCatalog
local stale=repaired(base);stale.id='saved-identity_stale';stale.title='Identity stale'
stale.needsFullBuild=true
check(Put(C,H,stale),'fixture: the stale record is stored')
check(Raw(stale.id).needsFullBuild==true,'fixture: stored with needsFullBuild true')
H=F.Reload();Settle(H,60)
check(Raw('saved-identity_stale').needsFullBuild==false,'needsFullBuild true is still repaired to false at start-up')
check(Raw('saved-identity_nil').needsFullBuild==nil,'the nil record stays unchanged beside a real repair')
print('PASS start-up identity repair skips nil/false-only differences; '..checks..' checks')
