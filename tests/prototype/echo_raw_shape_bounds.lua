-- RawShape work and size bounds (review of 19ac830, D1).
--
-- A field the strict Echo snapshot check rejects is recorded as rejected plus
-- a reading of its raw source (core/GameAdapter.lua RawShape). That reading
-- is change evidence only. The reviewed version collected and sorted every key
-- of a table before its part limit applied, counted a string of any length as
-- one part (a 1 MiB string became a 1 MiB reading), and wrote "~" for a table
-- deeper than the limit or a cycle instead of the documented "unreadable".
--
-- Required: the work is bounded WHILE it is done -- keys are counted as they
-- are collected and nothing over the limit is sorted; a string is measured
-- before it is copied and the total size is checked before every append; a
-- source deeper than the limit, larger than the limits, or cyclic reads
-- "unreadable" as a whole; identical over-limit sources give identical
-- readings (no generation churn) and a source back within the limits is read
-- again; a rejected field still grants nothing.
-- Keys (review of 124cf37, sections 8-9): only primitive keys are read and they
-- are checked before any key is stored, compared or converted, so no source
-- metamethod runs and no over-length key reaches the sort.
local S=dofile('tests/prototype/progress_refresh_support.lua')
local C=S.Checker('echo_raw_shape_bounds')
local check=C.check

-- The documented limits (docs/PROGRESS_REFRESH_INVALIDATION.md).
local DEPTH,ENTRIES,BYTES,SCALAR=8,20000,262144,1024

local H=S.Boot({granted=S.GA,active=2,locked={},
 slots={[2]={name='Build Two',verified=true,echoes=S.SlotRows(S.GA)}},associations={}})
local A=Nexus.GameAdapter

local function Find(fn,name,seen)
 if type(fn)~='function' or seen[fn] then return nil end
 seen[fn]=true
 for i=1,200 do
  local n,v=debug.getupvalue(fn,i)
  if not n then break end
  if n==name then return v end
  if type(v)=='function' then local got=Find(v,name,seen);if got~=nil then return got end end
 end
end
local function Upvalue(name)
 for _,f in pairs(A) do local v=Find(f,name,{});if v~=nil then return v end end
end
local RawShape=Upvalue('RawShape')
check(type(RawShape)=='function','fixture: the adapter\'s RawShape is reachable')

-- Work observed during one reading: the largest table handed to table.sort,
-- and the Lua heap growth with the collector stopped (allocation, not leaks).
local function Measure(value)
 local sort,largest=table.sort,0
 table.sort=function(t,...) if #t>largest then largest=#t end;return sort(t,...) end
 collectgarbage('collect');collectgarbage('stop')
 local heap0=collectgarbage('count')
 local t0=os.clock()
 local ok,result=pcall(RawShape,value)
 local ms=(os.clock()-t0)*1000
 local grownKiB=collectgarbage('count')-heap0
 collectgarbage('restart');table.sort=sort
 assert(ok,result)
 return result,largest,grownKiB,ms
end
local function Wide(n) local t={};for i=1,n do t[i]=i end;return t end
local function Deep(levels) local root={};local c=root;for _=1,levels do c.child={};c=c.child end;c.leaf=1;return root end

-- 1. Wide: far more keys than the limit. Collection stops at the limit and
-- nothing over it is sorted.
do
 local input=Wide(100001)
 local result,sorted,grown,ms=Measure(input)
 print(string.format('RAW_SHAPE wide-100001 result=%s sorted=%d heapKiB=%.0f cpuMs=%.1f',result,sorted,grown,ms))
 check(result=='unreadable','wide: an over-limit table reads unreadable: '..tostring(result):sub(1,40))
 check(sorted<=ENTRIES,'wide: no table over the limit is sorted: '..sorted)
 check(grown<1024,'wide: collection stops at the limit (heap growth '..string.format('%.0f',grown)..' KiB)')
 local again=Measure(input)
 check(again==result,'wide: the same over-limit source gives the same reading')
 input[100002]=7
 check(Measure(input)=='unreadable','wide: an over-limit change is not tracked (documented); still unreadable')
end
-- Within the limit the same shape is read, and its cost is measured.
do
 local result,sorted,grown,ms=Measure(Wide(ENTRIES/2-1))
 print(string.format('RAW_SHAPE wide-within result=%dB sorted=%d heapKiB=%.0f cpuMs=%.1f',#result,sorted,grown,ms))
 check(result~='unreadable' and #result<=BYTES,'wide within the limits: read, '..#result..' bytes')
end

-- 2. One long string: measured before it is copied.
do
 local result,_,grown,ms=Measure({name=string.rep('x',1048576)})
 print(string.format('RAW_SHAPE long-string result=%s heapKiB=%.0f cpuMs=%.1f',tostring(result):sub(1,20),grown,ms))
 check(result=='unreadable','long string: a 1 MiB string reads unreadable')
 check(grown<256,'long string: it is not copied (heap growth '..string.format('%.0f',grown)..' KiB)')
 check(Measure({name=string.rep('x',SCALAR)})~='unreadable','a string at the scalar limit is read')
 check(Measure({name=string.rep('x',SCALAR+1)})=='unreadable','one byte over the scalar limit reads unreadable')
end

-- 3. Many small strings: the total is checked before every append.
do
 local over={};for i=1,400 do over[i]=string.rep('y',1000) end   -- about 400 KB of text
 local result,_,grown,ms=Measure(over)
 print(string.format('RAW_SHAPE many-strings result=%s heapKiB=%.0f cpuMs=%.1f',tostring(result):sub(1,20),grown,ms))
 check(result=='unreadable','many small strings over the total read unreadable')
 check(grown<BYTES/1024+256,'many small strings: no more than the total is built (heap growth '..string.format('%.0f',grown)..' KiB)')
 local under={};for i=1,200 do under[i]=string.rep('y',1000) end  -- about 200 KB
 local read=Measure(under)
 check(read~='unreadable' and #read<=BYTES,'many small strings within the total are read: '..#read..' bytes')
end

-- 4. Depth: deeper than the limit is unreadable as a whole (not a marker
-- inside an ordinary reading); at the limit it is read.
do
 check(Measure(Deep(DEPTH+2))=='unreadable','deeper than the limit reads unreadable')
 local atLimit=Measure(Deep(DEPTH-1))
 check(atLimit~='unreadable' and not atLimit:find('~',1,true),'within the depth limit it is read in full: '..atLimit:sub(1,60))
 local a,b=Deep(DEPTH+2),Deep(DEPTH+2);b.child.extra=1
 check(Measure(a)==Measure(b),'deep sources read the same unreadable (no claim to track deep change)')
end

-- 5. Cycles are unreadable; a table shared without a cycle is read.
do
 local loop={a=1};loop.self=loop
 check(Measure(loop)=='unreadable','a cyclic source reads unreadable')
 local shared={x=1}
 local twice=Measure({one=shared,two=shared})
 check(twice~='unreadable' and twice==Measure({one={x=1},two={x=1}}),'a shared, acyclic table is read like two copies')
end

-- 6. A realistic slot mirror is read in full, independent of key order.
do
 local function Slots(reverse)
  local s={}
  local order={}
  for slot=1,5 do order[#order+1]=slot end
  for slot=101,110 do order[#order+1]=slot end
  if reverse then local r={} for i=#order,1,-1 do r[#r+1]=order[i] end;order=r end
  for _,slot in ipairs(order) do
   local echoes={}
   for i=1,85 do echoes[i]={spellId=200000+i,quality=i%4,stacks=1,locked=i>79} end
   s[slot]={name='Saved Build '..slot,verified=slot<=5,echoes=echoes}
  end
  return s
 end
 local result,sorted,grown,ms=Measure(Slots(false))
 print(string.format('RAW_SHAPE slots-15x85 bytes=%d sorted=%d heapKiB=%.0f cpuMs=%.1f',#result,sorted,grown,ms))
 check(result~='unreadable' and #result<=BYTES,'a 15-row, 85-Echo slot mirror is read in full: '..#result..' bytes')
 check(Measure(Slots(true))==result,'and its reading does not depend on key insertion order')
end

-- 7. The real path: a rejected discovery field whose raw source is over the
-- limits. Its snapshot value stays small and unreadable; repeated identical
-- rejections move nothing; back within the limits it is read again and the
-- generation moves once; nothing is granted from it.
local function Snapshot() return Upvalue('echoSnapshot') end
local function Gen() return A.EchoReconcileStats().generations.discovery end
do
 local big={};for i=1,100001 do big[i]=true end;big[200001]=false
 H.discovered=big;H.Notify();H.Advance(1)
 local token=Snapshot().discovery
 check(A.EchoReconcileStats().rejected.discovery=='discovery:key','real path: the discovery field is rejected: '..tostring(A.EchoReconcileStats().rejected.discovery))
 check(#token<200 and token:find('|raw:unreadable',1,true)~=nil,'real path: its snapshot value is short and unreadable ('..#token..' bytes)')
 local g0=Gen();local owned0=A.Owned().total
 H.Notify();H.Advance(1);H.Advance(6)
 check(Gen()==g0,'real path: repeated identical over-limit rejections move no generation')
 big[100002]=true;H.Notify();H.Advance(1)
 check(Gen()==g0,'real path: an over-limit change moves nothing (documented: not tracked)')
 local small={[200001]=false,[200002]=true};H.discovered=small;H.Notify();H.Advance(1)
 check(Gen()==g0+1,'real path: back within the limits the source is read again: the generation moves once')
 check(Snapshot().discovery:find('|raw:{',1,true)~=nil,'real path: and the reading is the source itself')
 check(A.EchoReconcileStats().rejected.discovery=='discovery:key','real path: still rejected (strict check unchanged)')
 small[200001]=nil;H.Notify();H.Advance(1)
 check(A.EchoReconcileStats().rejected.discovery==nil and Gen()==g0+2,'real path: valid again: accepted, the generation moves once more')
 check(A.Owned().total==owned0,'real path: ownership is untouched throughout')
end
do -- a 1 MiB name inside a rejected slot mirror
 H.perks.serverBuildSlots[3]={name=string.rep('n',1048576),verified=1,echoes={}}
 H.Notify();H.Advance(1)
 local token=Snapshot().slots
 check(A.EchoReconcileStats().rejected.slots=='slots:verified','real path: the slot mirror is rejected')
 check(#token<200 and token:find('|raw:unreadable',1,true)~=nil,'real path: a 1 MiB name never enters the snapshot ('..#token..' bytes)')
 H.perks.serverBuildSlots[3]=nil;H.Notify();H.Advance(1)
 check(A.EchoReconcileStats().rejected.slots==nil,'real path: recovery: the slot mirror is accepted again')
end

-- 8. Keys (review of 124cf37). A raw source may be rejected precisely because
-- its keys are malformed, so keys are checked as they are collected, before
-- any key is stored, compared or converted. Only primitive keys are read: a
-- finite number, a string within the scalar limit, a boolean. Any other key
-- (table, function, userdata, thread), an infinite number or an over-length
-- string makes the whole field unreadable, and no source metamethod runs. The
-- reviewed comparator called tostring on table keys (running their
-- __tostring) and sorted 1 MiB string keys before refusing them.
local calls=0
local Hooked={}
for _,name in ipairs({'__tostring','__lt','__le','__eq','__concat','__len','__index',
 '__newindex','__call','__unm','__add','__sub','__mul','__div','__mod','__pow'}) do
 Hooked[name]=function() calls=calls+1;if name=='__tostring' then return 'k' end;return false end
end
local function KeyTable(label) return setmetatable({label=label},Hooked) end
-- How many strings longer than the scalar limit were handed to table.sort.
local function LongSorted(value)
 local sort,long=table.sort,0
 table.sort=function(t,...)
  for i=1,#t do if type(t[i])=='string' and #t[i]>SCALAR then long=long+1 end end
  return sort(t,...)
 end
 local ok,result=pcall(RawShape,value)
 table.sort=sort
 assert(ok,result)
 return result,long
end
do
 calls=0
 local result,sorted=Measure({[KeyTable('a')]=1,[KeyTable('b')]=2})
 check(result=='unreadable','keys: two table keys read unreadable: '..tostring(result):sub(1,40))
 check(calls==0,'keys: no metamethod of a table key runs (calls '..calls..')')
 check(sorted==0,'keys: nothing is sorted ('..sorted..')')
 calls=0
 check(Measure({[KeyTable('only')]=1})=='unreadable' and calls==0,'keys: a single table key reads unreadable')
 check(Measure({x={[KeyTable('nested')]=1}})=='unreadable' and calls==0,'keys: a table key at any depth reads unreadable')
 check(Measure({[print]=1})=='unreadable','keys: a function key reads unreadable')
 check(Measure({[coroutine.create(function() end)]=1})=='unreadable','keys: a thread key reads unreadable')
 if newproxy then
  local u=newproxy(true)
  getmetatable(u).__tostring=function() calls=calls+1;return 'u' end
  getmetatable(u).__lt=function() calls=calls+1;return false end
  calls=0
  check(Measure({[u]=1,[newproxy(u)]=2})=='unreadable' and calls==0,'keys: userdata keys read unreadable, no metamethod runs (calls '..calls..')')
 else
  print('RAW_SHAPE keys: newproxy unavailable here; userdata key case not constructible')
 end
 check(Measure({[math.huge]=1})=='unreadable','keys: an infinite number key reads unreadable')
 check(Measure({[-math.huge]=1})=='unreadable','keys: a negative infinite number key reads unreadable')
 check(not pcall(function() local t={};t[0/0]=1 end),'keys: a NaN key cannot be constructed (Lua refuses it), so none can reach a reading')
 check(Measure({[1e300]=1,[-0.5]=2,[3]=3})~='unreadable','keys: finite number keys, large or fractional, are read')
 -- Over-length string keys with a long common prefix never reach the sort.
 local prefix=string.rep('x',1048576)
 local long,reached=LongSorted({[prefix..'a']=1,[prefix..'b']=2})
 check(long=='unreadable','keys: 1 MiB string keys read unreadable')
 check(reached==0,'keys: and are refused before any sort ('..reached..' reached it)')
 -- Keys at the scalar limit, sharing a 1023-byte prefix, are read in value order.
 local near=string.rep('p',SCALAR-1)
 local function AtLimit(order) local t={};for _,s in ipairs(order) do t[near..s]=s end;return t end
 local ascending=Measure(AtLimit({'a','b','c'}))
 check(ascending~='unreadable','keys: keys at the scalar limit with a long common prefix are read')
 local ia,ib,ic=ascending:find(near..'a',1,true),ascending:find(near..'b',1,true),ascending:find(near..'c',1,true)
 check(ia and ib and ic and ia<ib and ib<ic,'keys: and ordered by value')
 check(Measure(AtLimit({'c','a','b'}))==ascending,'keys: whatever the insertion order')
 check(Measure({[near..'zz']=1})=='unreadable','keys: a key one byte over the scalar limit reads unreadable')
 -- Mixed primitive keys: booleans (false before true), then numbers, then
 -- strings, each ascending; independent of insertion order.
 local mixed=Measure({[true]=1,[false]=2,[2]=3,[-1.5]=4,b=5,a=6})
 check(mixed=='{F=2;T=1;-1.5=4;2=3;1:a=6;1:b=5;}','keys: canonical primitive key order: '..tostring(mixed))
 local reverse={};reverse.a=6;reverse.b=5;reverse[-1.5]=4;reverse[2]=3;reverse[false]=2;reverse[true]=1
 check(Measure(reverse)==mixed,'keys: independent of insertion order')
 check(calls==0,'keys: no metamethod ran in any key case (calls '..calls..')')
end

-- 9. The real path with malformed keys: a rejected discovery map holding table
-- keys reads unreadable without running their metamethods; identical repeats
-- move nothing; with primitive keys again the source is read (generation
-- once), then accepted; ownership is untouched.
do
 calls=0
 H.discovered={[KeyTable('x')]=true,[KeyTable('y')]=true,[200001]=true};H.Notify();H.Advance(1)
 local token=Snapshot().discovery
 check(A.EchoReconcileStats().rejected.discovery=='discovery:key','real path keys: the discovery field is rejected: '..tostring(A.EchoReconcileStats().rejected.discovery))
 check(#token<200 and token:find('|raw:unreadable',1,true)~=nil,'real path keys: its snapshot value is unreadable ('..#token..' bytes)')
 check(calls==0,'real path keys: no key metamethod ran (calls '..calls..')')
 local g0=Gen();local owned0=A.Owned().total
 H.Notify();H.Advance(1);H.Advance(6)
 check(Gen()==g0 and calls==0,'real path keys: identical repeats move nothing and run nothing (calls '..calls..')')
 H.discovered={[200001]=false};H.Notify();H.Advance(1)
 check(Gen()==g0+1 and Snapshot().discovery:find('|raw:{',1,true)~=nil,'real path keys: primitive keys again: read, the generation moves once')
 H.discovered={[200001]=true};H.Notify();H.Advance(1)
 check(A.EchoReconcileStats().rejected.discovery==nil and Gen()==g0+2,'real path keys: valid again: accepted, the generation moves once more')
 check(A.Owned().total==owned0 and calls==0,'real path keys: ownership untouched; no metamethod ran')
end

C.finish('wide, long-string, many-string, deep and cyclic sources and non-primitive, infinite or over-length keys are refused while read, with no source metamethod run and nothing over-length sorted; identical over-limit readings repeat; within the limits sources are read in canonical key order; a rejected field grants nothing')
