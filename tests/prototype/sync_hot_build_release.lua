-- A broadcast build's hot pin (HOT_WINDOW, 120 s) and the queued transfer
-- of that build are two different owners. The transfer is serialized into
-- the queued packets before the pin exists and the transport owns those
-- strings for up to PENDING_MAX_AGE (300 s); the pin only reports the
-- build's evidence reference to the evidence reference provider for the
-- responder window. So a pin that expires while the packets are still
-- queued releases exactly its own references (the provider reports the key
-- no more, the pin's tables are collectable) and nothing else: the queued
-- transfer still reaches the peer complete and exact, and the build's own
-- durable catalog and evidence references stay valid. Two isolated
-- production runtimes; the wire is blocked by combat on the sender so the
-- queue outlives the window; synthetic; not native evidence.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local ID='hot-held'
local ECHOES={{spellId=200001,quality=1,stacks=3},{spellId=200002,quality=2,stacks=1},{spellId=200003,quality=0,stacks=2}}
local function Held()
 local echoes={};for i,e in ipairs(ECHOES) do echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks} end
 return {id=ID,title='Hot held build',author='Alpha',ownerKey='alpha@ebonhold',realm='ebonhold',ownerVerified=true,isMine=true,
  class='MAGE',postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,echoes=echoes,lockedEchoes={},lockedComplete=true}
end
local A,B=P.Boot({'Alpha','Beta'},0,function(i,db)
 if i==1 then db.communityBuilds=db.communityBuilds or {};db.communityBuilds[ID]=Held() end
end)
local N=A.e.Nexus
P.Until(function() return P.Full(A,ID)~=nil end)
P.Advance(10)
check(P.Full(B,ID)==nil,'fixture: the peer does not hold the build')
local window=N.Sync.Stats().hotWindow
check(window==120,'fixture: the hot window is 120 s: '..tostring(window))

-- Test-only reflection into Sync's private hot table and the evidence
-- owner's provider registry (never a product path).
local function FindUpvalue(root,name,wanted)
 local seen={}
 local function Visit(fn,depth)
  if type(fn)~='function' or seen[fn] or depth>4 then return nil end
  seen[fn]=true
  for i=1,60 do
   local n,v=debug.getupvalue(fn,i)
   if not n then break end
   if n==name and type(v)==wanted then return v end
  end
  for i=1,60 do
   local n,v=debug.getupvalue(fn,i)
   if not n then break end
   if type(v)=='function' then
    local found=Visit(v,depth+1);if found~=nil then return found end
   elseif type(v)=='table' and n~='_G' and n~='Nexus' then
    for _,member in pairs(v) do
     if type(member)=='function' then
      local found=Visit(member,depth+1);if found~=nil then return found end
     elseif type(member)=='table' then
      for _,inner in pairs(member) do
       if type(inner)=='function' then local found=Visit(inner,depth+1);if found~=nil then return found end end
      end
     end
    end
   end
  end
  return nil
 end
 for _,fn in pairs(root) do local found=Visit(fn,1);if found~=nil then return found end end
 return nil
end
local hotTable=assert(FindUpvalue(N.Sync,'hotBuilds','table'),'fixture: the hot-build table is reachable')
local providers=assert(FindUpvalue(N.LoadoutEvidence,'referenceProviders','table'),'fixture: the evidence provider registry is reachable')
local provider=assert(providers['sync.hot-builds'],'fixture: Sync registered its hot-build reference provider')
local function ProvidedKeys()
 local out={};for _,key in ipairs(provider() or {}) do out[key]=true end;return out
end
local function HotCount() local n=0;for _ in pairs(hotTable) do n=n+1 end;return n end

-- 1. The build is broadcast while the wire is blocked (combat): the whole
-- transfer is queued, serialized, and the build is pinned hot.
local evidenceKey=N.BuildCatalog.Get(ID).evidenceKey
check(type(evidenceKey)=='string','fixture: the admitted build is evidence-backed')
local hot0=HotCount()
A.H.combat=true
local sentBefore=#A.H.sent
-- The row handed to the broadcast is not kept by this test: the pin's own
-- build object must be collectable once the pin is gone.
local ok,why=N.Sync.BroadcastBuild(N.BuildCatalog.Get(ID))
check(ok==true,'the build is queued for broadcast while the wire is blocked: '..tostring(why))
local posted=A.H.now
check(HotCount()==hot0+1,'the broadcast build is pinned hot')
check(ProvidedKeys()[evidenceKey]==true,'while hot, the provider reports the build\'s evidence reference')
local weak=setmetatable({},{__mode='k'})
for _,hot in pairs(hotTable) do weak[hot]=true;if type(hot.build)=='table' then weak[hot.build]=true end end
local pinned=0;for _ in pairs(weak) do pinned=pinned+1 end
check(pinned>=2,'fixture: the pin and its build object are observed weakly: '..pinned)

-- 2. The window passes with the wire still blocked: nothing was sent, the
-- pin expired, the provider released its reference, the pin's tables are
-- collectable, and the durable references stay valid.
while A.H.now<posted+window+5 do P.Step() end
check(#A.H.sent==sentBefore,'nothing left the blocked wire during the window')
check(HotCount()==hot0,'the pin expired inside the window')
check(ProvidedKeys()[evidenceKey]==nil,'after expiry the provider no longer reports the reference')
collectgarbage('collect');collectgarbage('collect')
local alive=0;for _ in pairs(weak) do alive=alive+1 end
check(alive==0,'the pin and its build object are collected after expiry (nothing else held them): '..alive..' alive')
local references=N.LoadoutEvidence.ReferenceSnapshot()
check(references[evidenceKey]==true,'the build\'s own catalog reference keeps its evidence referenced')
check(P.Full(A,ID)~=nil and #N.BuildCatalog.Get(ID).echoes==#ECHOES,'the catalog row still resolves its exact evidence')
check(N.Sync.Stats().hotBuilds==hot0,'Sync reports the expired pin as gone')

-- 3. The wire opens: the queued transfer, serialized before the pin, reaches
-- the peer complete and exact.
local wlrbBefore=P.Count('WLRB')
A.H.combat=false
P.Until(function() return P.Full(B,ID)~=nil end,6000)
check(P.Count('WLRB')>wlrbBefore,'the build travelled after the pin expired: '..(P.Count('WLRB')-wlrbBefore)..' chunks')
local received=B.e.Nexus.BuildCatalog.Get(ID)
check(#received.echoes==#ECHOES,'every Echo arrived')
for i,e in ipairs(ECHOES) do
 local got=received.echoes[i]
 check(got.spellId==e.spellId and got.quality==e.quality and got.stacks==e.stacks,'Echo '..i..' is exact')
end
check(received.title=='Hot held build','the title is exact')
check((received.claimedOwnerKey or received.ownerKey)=='alpha@ebonhold','the owner claim is exact')
check(type(received.lockedEchoes)~='table' or #received.lockedEchoes==0,'a broadcast carries no locked roles and none were invented')
check(P.Full(A,ID)~=nil,'the sender still holds its build after the transfer')
print('PASS sync_hot_build_release checks='..checks)
