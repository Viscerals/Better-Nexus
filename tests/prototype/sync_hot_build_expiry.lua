-- A build this client broadcasts is remembered as "hot" (its evidence pinned
-- for the responder window) and forgotten after HOT_WINDOW seconds, never
-- for the rest of the session. The pin outlives the build's own transport
-- queue (bulk packets expire after PENDING_MAX_AGE), so nothing a queued
-- answer could still need is released early. Two isolated production
-- runtimes; synthetic; not native evidence.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local A,B=P.Boot({'Alpha','Beta'},0)
local N=A.e.Nexus
-- The hot-build count and the window length. Current Sync publishes both in
-- Sync.Stats (hotBuilds, hotWindow). The code this test was red against kept
-- them in private locals; they are reached there through the upvalues of
-- Sync's own functions (test-only reflection, never a product path), so the
-- behavioural checks below run against either.
local function FindUpvalue(name,wanted)
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
       if type(inner)=='function' then
        local found=Visit(inner,depth+1);if found~=nil then return found end
       end
      end
     end
    end
   end
  end
  return nil
 end
 for _,fn in pairs(N.Sync) do
  local found=Visit(fn,1);if found~=nil then return found end
 end
 return nil
end
local hotTable,hotWindow
local function HotCount()
 local stats=N.Sync.Stats()
 if stats.hotBuilds~=nil then return stats.hotBuilds end
 hotTable=hotTable or FindUpvalue('hotBuilds','table')
 assert(hotTable,'fixture: the hot-build table is reachable')
 local n=0;for _ in pairs(hotTable) do n=n+1 end;return n
end
local function HotWindow()
 local stats=N.Sync.Stats()
 if stats.hotWindow~=nil then return stats.hotWindow end
 hotWindow=hotWindow or FindUpvalue('HOT_WINDOW','number')
 return hotWindow
end
local id=P.Post(A,'Hot build')
P.Until(function() return P.Full(A,id)~=nil end)
check(HotCount()==0,'fixture: no hot build before a full broadcast')
local ok,why=N.Sync.BroadcastBuild(N.BuildCatalog.Get(id))
local posted=A.H.now
check(ok==true,'the complete own build is broadcast: '..tostring(why))
check(HotCount()==1,'the broadcast build is remembered as hot')
local window=HotWindow()
check(type(window)=='number' and window>=60 and window<=600,'the hot window is a bounded number of seconds: '..tostring(window))
local function AdvanceTo(at) while A.H.now<at do P.Step() end end
P.Until(function() return P.Full(B,id)~=nil end)
check(P.Full(B,id)~=nil,'the peer received the broadcast build')
check(A.H.now<posted+window-5,'fixture: the transfer finished inside the window')
AdvanceTo(posted+window-5)
check(HotCount()==1,'inside the window the build stays hot')
AdvanceTo(posted+window+5)
check(HotCount()==0,'after the window the build is forgotten')
-- A later broadcast of the changed build is remembered again and forgotten
-- after its own window.
local build=N.BuildCatalog.Get(id)
build.lastModified=(build.lastModified or 0)+10
local okPut,putWhy,ticket=N.BuildCatalog.Put(build,{source='local'})
if okPut==nil and type(ticket)=='table' then P.Until(function() return ticket.state~='pending' end) end
check(N.Sync.BroadcastBuild(N.BuildCatalog.Get(id))==true,'a later broadcast of the changed build is accepted: '..tostring(putWhy))
posted=A.H.now
check(HotCount()==1,'the later broadcast is remembered')
AdvanceTo(posted+window+5)
check(HotCount()==0,'and forgotten after its own window')
print('PASS sync_hot_build_expiry checks='..checks)
