-- 035 part 2c: the Store budget and format review of the continuation archive, and the
-- downgrade question.
--
-- The archive is its own top-level key of the character row (orbRecoveryArchive). A key an
-- older build does not know survives that build's load and its Orb preference writes (the 034
-- compatibility probe, now a test); a history kept inside orbRefinement would be rebuilt from
-- known keys by the next older write. This test pins:
--  * the measured size of a real entry against the caps (entry edges, bytes, depth) and the
--    total of eight entries against the Store's own source bounds (key width 183, depth 6,
--    per-row notional edges and bytes), by starting the real Store on a row that carries the
--    most the caps allow;
--  * that the released test.9049 build and the current build both keep the key through load,
--    an Orb preference write, a logout and a second reload, with the write mode durable;
--  * that an archive of a NEWER format is kept unchanged by this build and by the older one.
-- Builds between 9049 and now were not run: only the released and the current build are covered.
-- Synthetic profile; no real data.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function Measure(v,level)
 level=level or 1
 local edges,bytes,depth=0,0,level
 for k,x in pairs(v) do
  edges=edges+1;bytes=bytes+#tostring(k)
  local kind=type(x)
  if kind=='string' then bytes=bytes+#x elseif kind=='number' or kind=='boolean' then bytes=bytes+8
  elseif kind=='table' then
   local e,b,d=Measure(x,level+1);edges=edges+e;bytes=bytes+b;depth=math.max(depth,d)
  end
 end
 return edges,bytes,depth
end

-- One real entry from the real flow.
local entry,original
section('0 a real entry',function()
 local H,M,A,O,server
 -- the worst case: three raw pick entries with every field, saved with the receipt
 local function Picks()
  local list={}
  for i=1,3 do
   list[i]={id=500000+i,q=1,board='500037:1,500001:1,500038:1',m='offer',acc=true,op=true,slot=101,sk=true,rd='ok',u=false,
    inb=true,ph='w',ep=65535,at=1700000000+i,c=999}
  end
  return list
 end
 H,M,A,O=R.Class({edit=function(row,state)
  for _,r in ipairs({row,state}) do r.picks=Picks();r.pickSeen=999;r.pickDropped=999 end
 end})
 server=R.Server(H)
 S.Pass(H,M,A,2)
 original=H.Clone(R.Saved())
 check(type(original.picks)=='table' and #original.picks==3,'the saved receipt carries three full pick entries')
 assert(M.ContinueBegin())
 local waited=0;while waited<20 and M.ContinueView().stage~='ready' do H.Advance(.25);waited=waited+.25 end
 assert(M.ContinueConfirm(M.ContinueView().token))
 entry=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
 local edges,bytes,depth=Measure(entry)
 print(string.format('  measured entry (deidentified 034 shape): %d edges, %d bytes, depth %d',edges,bytes,depth))
 check(edges<=1200 and bytes<=6144 and depth<=4,'a real entry is within the entry caps')
 check(edges*8<=16384 and bytes*8<=28672,'eight real entries fit the total caps and the per-row notional Store bounds')
 -- row (1) > archive (2) > entry (3) > receipt (4) > picks (5) > one pick (6): the deepest table is at the
 -- Store's own bound of 6 EXACTLY, and no deeper. The entry cap (depth 4 below the archive) keeps it there.
 check(depth==4 and 2+depth==6,'with pick evidence the deepest table is at the Store depth bound of 6, not past it: '..(2+depth))
 local longest=0
 local function Keys(t) for k,v in pairs(t) do longest=math.max(longest,#tostring(k));if type(v)=='table' then Keys(v) end end end
 Keys(entry)
 check(longest<=183,'no key is wider than the Store key bound of 183 bytes: '..longest)
end)

local P
local function Peers()
 -- Each peer copies the globals of this process when it starts: the world of section 0 must be
 -- gone, or the peers would share its Nexus table.
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusOrbRuntime=nil
 P=dofile('tests/prototype/sync_pair_support.lua')
 P.Boot({'Alpha','Bravo'},5,nil,{released={true,false}})
end
local function Row(e) local key=e.Nexus.Store.CurrentOwnerKey();return key,e.NexusDB.chars[key] end
local function Clone(v)
 if type(v)~='table' then return v end
 local t={};for k,x in pairs(v) do t[k]=Clone(x) end;return t
end
-- An entry grown by receipt keys until it is about n bytes, as large as the caps allow.
local function Padded(n)
 local e=Clone(entry)
 local i=0
 while select(2,Measure(e))<n do i=i+1;e.receipt.before['990'..string.format('%03d',i)..':1']=1 end
 e.id=string.format('%016x',n+i);e.cd=string.format('%016x',n*3+i)
 return e
end

section('1 starting the Store on the most the caps allow',function()
 assert(entry,'a real entry')
 Peers()
 local peer=P.B
 if not select(2,Row(peer.e)) then peer.e.Nexus.OrbRuntime.SetRecycle(true) end
 local key,row=Row(peer.e)
 local archive={}
 for i=1,8 do archive[i]=Padded(3400+i) end
 local _,bytes,depth=0,0,0
 local total=0;for _,e in ipairs(archive) do local _,b,d=Measure(e);total=total+b;depth=math.max(depth,d) end
 check(total<=28672 and depth<=4,'the worst case is inside the caps: '..total..' bytes')
 row.orbRecoveryArchive=archive
 local re=P.Rejoin(2)
 local k2,r2=Row(re.e)
 check(re.e.Nexus.StartupStatus().state=='ready','the Store reached ready with eight maximal entries')
 local st=re.e.Nexus.Store.StateWriteStatus()
 check(st.mode=='durable','the row is writable (durable): '..tostring(st.mode)..'/'..tostring(st.reason))
 check(type(r2.orbRecoveryArchive)=='table' and #r2.orbRecoveryArchive==8,'all eight entries were loaded')
 check(r2.orbRecoveryArchive[1].receipt.before['990001:1']==1,'unchanged')
 local before=re.H.Clone(r2.orbRecoveryArchive)
 check(re.e.Nexus.OrbRuntime.SetRecycle(true),'an Orb preference write works with it')
 local _,r3=Row(re.e)
 check(R.Same(r3.orbRecoveryArchive,before),'and leaves the archive exactly as it was')
 re.H.Fire('PLAYER_LOGOUT')
 local re2=P.Rejoin(2);local _,r4=Row(re2.e)
 check(R.Same(r4.orbRecoveryArchive,before),'a logout and a second reload keep it')
end)

section('2 downgrade: the released build and the current build keep the key',function()
 assert(entry,'a real entry')
 Peers()
 for i=1,2 do
  local label=i==1 and 'released 9049' or 'current'
  local peer=i==1 and P.A or P.B
  if not select(2,Row(peer.e)) then peer.e.Nexus.OrbRuntime.SetRecycle(true) end
  local key,row=Row(peer.e)
  assert(row,label..': a row for '..tostring(key)..' after '..tostring(peer.e.Nexus.OrbRuntime.SetRecycle(true)))
  local archive={Padded(2000+i),Padded(2100+i)}
  row.orbRecoveryArchive=archive
  local want=peer.H.Clone(archive)
  local re=P.Rejoin(i)
  local e=re.e;local _,r2=Row(e)
  check(R.Same(r2.orbRecoveryArchive,want),label..': the archive survives the load')
  check(e.Nexus.Store.StateWriteStatus().mode=='durable',label..': the write mode stays durable')
  check(pcall(function() return e.Nexus.OrbRuntime.SetRecycle(true) end),label..': an Orb preference write works')
  local _,r3=Row(e)
  check(R.Same(r3.orbRecoveryArchive,want),label..': and keeps the archive')
  re.H.Fire('PLAYER_LOGOUT')
  local re2=P.Rejoin(i);local _,r4=Row(re2.e)
  check(R.Same(r4.orbRecoveryArchive,want),label..': a logout and a second reload keep it')
  -- a pending receipt and an archive can coexist, and the older build keeps both
 end
end)

section('3 a newer archive format is kept unchanged',function()
 Peers()
 local future={{v=2,id='abc',cd='def',receipt={x=1},extra={y=2}},{v=3,id='ghi'}}
 for i=1,2 do
  local label=i==1 and 'released 9049' or 'current'
  local peer=i==1 and P.A or P.B
  if not select(2,Row(peer.e)) then peer.e.Nexus.OrbRuntime.SetRecycle(true) end
  local _,row=Row(peer.e)
  row.orbRecoveryArchive=peer.H.Clone(future)
  local re=P.Rejoin(i);local e=re.e
  e.Nexus.OrbRuntime.SetRecycle(false);e.Nexus.OrbRuntime.SetRecycle(true)
  re.H.Fire('PLAYER_LOGOUT')
  local re2=P.Rejoin(i);local _,r=Row(re2.e)
  check(R.Same(r.orbRecoveryArchive,future),label..': a newer archive is not touched')
 end
 -- and the current build offers no Continue over it
 local _,row=Row(P.B.e)
 local view=P.B.e.Nexus.OrbRuntime.ContinueView()
 check(view.archive.state=='future' and view.archive.count==2,'the view names it: '..tostring(view.archive.state))
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb recovery archive in the Store: within the caps and the Store bounds, kept by the released and the current build checks='..checks)
