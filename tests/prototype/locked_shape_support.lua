-- Shared helpers of the locked-shape tests (locked_shape_capture,
-- locked_shape_bounds, locked_shape_report, locked_shape_correlation). Not a
-- test itself: the name ends in _support, so tools/ci_check.py does not list it.
-- Contract: TEST_CONTRACT.md of the locked-shape tests-first phase.
-- It boots the real TOC through orbs_support.lua (fake services, artificial IDs
-- and names) and keeps the bookkeeping the four tests share. A check is either
--  * T.expect: a capture expectation (new behaviour), or
--  * T.guard: behaviour that already holds at 5a8299c and must keep holding.
-- Every check is evaluated. T.finish prints one summary line with both counts and
-- every failed guard, and raises at the end if any check failed.
local H=dofile('tests/prototype/orbs_support.lua')
local A=H.A
local T={}
-- The builtins as loaded, kept before a test replaces a global to count or probe.
local realPcall,realPairs,realNext=pcall,pairs,next
T.realPcall,T.realPairs,T.realNext=realPcall,realPairs,realNext

local failures,guardFailures={},{}
local tally={capture=0,guard=0,raised=0}
local function printable(v)
 local ok,s=realPcall(tostring,v)
 return ok and type(s)=='string' and s or '<unprintable '..type(v)..'>'
end
T.printable=printable
local function check(kind,ok,label,detail)
 tally[kind]=tally[kind]+1
 if ok then return true end
 local line=label..(detail~=nil and (' ['..printable(detail)..']') or '')
 if kind=='guard' then
  guardFailures[#guardFailures+1]=line
  failures[#failures+1]='GUARD '..line
  print('FAIL GUARD '..line)
 else
  failures[#failures+1]=line
  print('FAIL '..line)
 end
 return false
end
function T.expect(ok,label,detail) return check('capture',ok and true or false,label,detail) end
function T.guard(ok,label,detail) return check('guard',ok and true or false,label,detail) end
function T.scenario(name,fn)
 local ok,err=realPcall(fn)
 if not ok then
  tally.raised=tally.raised+1
  local line=name..': raised '..printable(err)
  failures[#failures+1]='RAISED '..line
  print('FAIL RAISED '..line)
 end
end
function T.finish(name)
 local guardFailed,raised=#guardFailures,tally.raised
 local captureFailed=#failures-guardFailed-raised
 print(string.format('SUMMARY %s: capture expectations held %d of %d; guards held %d of %d; scenarios raised %d',
  name,tally.capture-captureFailed,tally.capture,tally.guard-guardFailed,tally.guard,raised))
 for _,line in ipairs(guardFailures) do print('SUMMARY guard failed: '..line) end
 if #failures>0 then
  error(name..': '..#failures..' check(s) failed ('..captureFailed..' capture, '..guardFailed..' guard, '
   ..raised..' raised); first: '..failures[1],0)
 end
 print('PASS '..name..' checks='..(tally.capture+tally.guard))
end

-- Fixed codes and bits (TEST_CONTRACT.md, sections 3, 4 and 6).
local function set(list) local s={};for _,v in ipairs(list) do s[v]=true end;return s end
T.set=set
T.MAX_ROWS=64
T.ROW_KEYS={'p','k','c','n','im','cm','e'}
local ROW_KEY=set(T.ROW_KEYS)
T.ID_BIT={spellId=1,spellID=2,id=4,perkId=8,perkID=16,entryId=32,entryID=64,echoId=128,echoID=256,spell=512,perk=1024}
T.COUNT_BIT={stack=1,stacks=2,count=4,amount=8,qty=16}
T.DEFECT={depth=1,cycle=2,invalid_value=4,conflicting_alias=8,over_cap=16,scalar_leaf=32}
T.TABLE_REJECTIONS=set({'invalid_value','conflicting_alias','cycle','depth','over_cap','scalar_leaf'})
T.STATUSES=set({'captured','truncated','failed','mismatch'})
T.KEY_CLASSES=set({'i','s','o','-'})
T.CAPTURE_KEYS={'serial','at','age','current','laterReads','sampledGeneration','first','copies','ids','status','rows','row'}
T.BLOCK_CAPTURE_KEYS={'serial','age','current','later.reads','sampled.generation','first','copies','ids','status','rows','r1'}
T.NULL=set({'unknown','unavailable','?'})
T.UNSEEN=set({'not_observed','unknown','unavailable','?'})
T.LEGEND_WORDS={'spellId','spellID','id','perkId','perkID','entryId','entryID','echoId','echoID','spell','perk',
 'stack','stacks','count','amount','qty','depth','cycle','invalid_value','conflicting_alias','over_cap','scalar_leaf'}
-- Privacy: the artificial names and IDs of orbs_support.lua.
T.NAMES={'Disposable A','Disposable B','Desired A','Desired B','Protected low','Excess high',
 'Unsafe fallback','Synthetic Echo','Orb test','ZQ plan','ZQ build','PrototypeTester','Ebonhold'}
T.IDS={}
for id=410001,410008 do T.IDS[#T.IDS+1]=id end
for id=200001,200090 do T.IDS[#T.IDS+1]=id end
T.IDS[#T.IDS+1]=499999
T.ID_SET=set(T.IDS)

function T.int(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge and v==math.floor(v) end
function T.count(v,max) return T.int(v) and v>=0 and v<=(max or 2^53) end
function T.has(mask,bit) return T.count(mask) and math.floor(mask/bit)%2==1 or false end
function T.fmt(v) if T.count(v,9999999) then return string.format('%d',v) end return nil end
function T.ageValue(s)
 local n=type(s)=='string' and s:match('^(%d+)s?$')
 return n and tonumber(n) or nil
end

-- Accessors, looked up when called. A missing, failing or non-table answer is nil.
function T.call(fn,...)
 if type(fn)~='function' then return nil,'not available' end
 local ok,v=realPcall(fn,...)
 if not ok then return nil,printable(v) end
 if type(v)~='table' then return nil,'not a table' end
 return v
end
function T.view(owner,name)
 local ok,fn=realPcall(function() local m=Nexus[owner];return type(m)=='table' and m[name] or nil end)
 if not ok then return nil,printable(fn) end
 if type(fn)~='function' then return nil,owner..'.'..name..' is not available' end
 return T.call(fn)
end
function T.shape() return T.view('GameAdapter','LockedShapeView') end
function T.trust() return T.view('GameAdapter','OwnershipTrustView') end
function T.readiness() return T.view('OrbRuntime','ReadinessView') end

-- One normal LockedOwned() of `tree`, with the steps of the locked projection
-- counters; `serial` is the counter after the read (TEST_CONTRACT.md, section 3).
function T.lockedStats()
 local ok,st=realPcall(A.EchoReconcileStats)
 local p=ok and type(st)=='table' and type(st.projections)=='table' and st.projections.locked
 return type(p)=='table' and p or {}
end
function T.read(tree)
 H.locked=tree
 local before=T.lockedStats()
 local ok,l=realPcall(A.LockedOwned)
 local after=T.lockedStats()
 local d={calls=(after.calls or 0)-(before.calls or 0),spells=(after.spells or 0)-(before.spells or 0),
  copies=(after.copies or 0)-(before.copies or 0),serial=after.calls}
 if not ok or type(l)~='table' then return nil,d,printable(l) end
 return l,d
end
function T.sig(map)
 if type(map)~='table' then return '<'..type(map)..'>' end
 local keys={}
 for k in realPairs(map) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..tostring(map[k]) end
 return table.concat(out,',')
end
function T.sum(map)
 local n=0
 if type(map)=='table' then for _,c in realPairs(map) do n=n+(tonumber(c) or 0) end end
 return n
end
-- Every table of a fixture (values and keys), through the raw iterator only.
function T.tables(root,into)
 into=into or {}
 local stack={root}
 while #stack>0 do
  local t=table.remove(stack)
  if type(t)=='table' and not into[t] then
   into[t]=true
   for k,v in realNext,t do
    if type(k)=='table' then stack[#stack+1]=k end
    if type(v)=='table' then stack[#stack+1]=v end
   end
  end
 end
 return into
end

-- Rows: "p.k.c.n.im.cm.e", the row token form of the report.
local function part(x)
 if T.int(x) and math.abs(x)<2^53 then return string.format('%d',x) end
 if type(x)=='string' then return x end
 return '<'..type(x)..'>'
end
function T.rowText(r)
 if type(r)~='table' then return '<'..type(r)..'>' end
 local out={}
 for i,k in ipairs(T.ROW_KEYS) do
  local ok,x=realPcall(function() return r[k] end)
  out[i]=ok and part(x) or '<raised>'
 end
 return table.concat(out,'.')
end
function T.rowList(v)
 local out={}
 local list=type(v)=='table' and v.row or nil
 if type(list)~='table' then return out end
 for i=1,T.MAX_ROWS+6 do
  local r=list[i]
  if r==nil then break end
  out[i]=type(r)=='table' and r or {}
 end
 return out
end
function T.rowTexts(v)
 local out={}
 for i,r in ipairs(T.rowList(v)) do out[i]=T.rowText(r) end
 return out
end
function T.validRow(r,i)
 if type(r)~='table' then return false end
 for k in realPairs(r) do if not ROW_KEY[k] then return false end end
 return (T.count(r.p,T.MAX_ROWS-1) and r.p<i and (r.p==0)==(i==1)
  and T.KEY_CLASSES[r.k]==true and (r.k=='-')==(i==1)
  and (T.count(r.c,T.MAX_ROWS) or r.c=='x') and T.count(r.n)
  and T.count(r.im,2047) and T.count(r.cm,31) and T.count(r.e,63)) and true or false
end
-- The capture's record (not the derived current/laterReads/age).
function T.record(v)
 if type(v)~='table' then return '<'..type(v)..'>' end
 return T.serialize({observed=v.observed,serial=v.serial,at=v.at,sampledGeneration=v.sampledGeneration,first=v.first,
  copies=v.copies,ids=v.ids,status=v.status,rows=v.rows,row=v.row})
end

-- The form of a LockedShapeView() answer (TEST_CONTRACT.md, sections 3 and 4).
local HEADER_COUNTS={'serial','age','laterReads','sampledGeneration','currentGeneration','copies','ids'}
function T.checkShape(tag,v)
 local isTable=type(v)=='table'
 v=isTable and v or {}
 local n,bad=0,{}
 for k,x in realPairs(v) do
  n=n+1
  local kind=type(x)
  if type(k)~='string' then bad[#bad+1]='a '..type(k)..' key'
  elseif k=='row' then
   if kind~='table' then bad[#bad+1]='row is a '..kind end
  elseif kind=='number' then
   if not (x==x and x>-math.huge and x<math.huge) then bad[#bad+1]=k..' is not finite' end
  elseif kind=='string' then
   if #x>24 or x:find('[^%w_]') then bad[#bad+1]=k..' is not a short code' end
  elseif kind~='boolean' then bad[#bad+1]=k..' is a '..kind end
 end
 T.expect(isTable and #bad==0 and n<=24,tag..': the view holds only booleans, finite numbers, short codes and the row list (at most 24 keys)',
  table.concat(bad,',')..' ('..n..' keys)')
 T.expect(type(v.observed)=='boolean',tag..': observed is a boolean',v.observed)
 if v.observed~=true then
  local invented={}
  for _,k in ipairs(T.CAPTURE_KEYS) do if v[k]~=nil then invented[#invented+1]=k end end
  T.expect(#invented==0,tag..': nothing is invented while nothing is captured',table.concat(invented,','))
  return
 end
 local wrong={}
 for _,k in ipairs(HEADER_COUNTS) do if not T.count(v[k]) then wrong[#wrong+1]=k..'='..printable(v[k]) end end
 if not (T.int(v.serial) and v.serial>=1) then wrong[#wrong+1]='serial below 1' end
 if not (type(v.at)=='number' and v.at==v.at) then wrong[#wrong+1]='at='..printable(v.at) end
 if type(v.current)~='boolean' then wrong[#wrong+1]='current='..printable(v.current) end
 if not T.TABLE_REJECTIONS[v.first] then wrong[#wrong+1]='first='..printable(v.first) end
 if not T.STATUSES[v.status] then wrong[#wrong+1]='status='..printable(v.status) end
 if not T.count(v.rows,T.MAX_ROWS) then wrong[#wrong+1]='rows='..printable(v.rows) end
 if type(v.current)=='boolean' and T.int(v.laterReads) and v.current~=(v.laterReads==0) then
  wrong[#wrong+1]='current disagrees with laterReads'
 end
 T.expect(#wrong==0,tag..': the header has its documented types and codes',table.concat(wrong,'; '))
 local list=type(v.row)=='table' and v.row or {}
 T.expect(type(v.row)=='table' and #list==v.rows,tag..': the row list holds exactly rows entries',printable(#list)..' vs '..printable(v.rows))
 local badRows={}
 for i=1,math.min(#list,T.MAX_ROWS+6) do
  if not T.validRow(list[i],i) then badRows[#badRows+1]=i..':'..T.rowText(list[i]) end
 end
 T.expect(#list<=T.MAX_ROWS and #badRows==0,tag..': every row has exactly the seven fixed fields within range',table.concat(badRows,' '))
 local ids={}
 local function scan(x) if type(x)=='number' and T.ID_SET[x] then ids[#ids+1]=x end end
 for _,x in realPairs(v) do scan(x) end
 for i=1,math.min(#list,T.MAX_ROWS+6) do
  local r=list[i]
  if type(r)=='table' then for _,x in realPairs(r) do scan(x) end end
 end
 T.expect(#ids==0,tag..': the view carries no Echo ID',table.concat(ids,','))
end
function T.expectRows(tag,v,want)
 local got=T.rowTexts(v)
 T.expect(#got==#want,tag..': '..#want..' rows',#got)
 for i,w in ipairs(want) do T.expect(got[i]==w,tag..': row '..i..' is '..w,got[i]) end
end
-- The consistency of a complete capture (TEST_CONTRACT.md, section 4).
function T.expectConsistent(tag,v)
 local total,classes,distinct,bad=0,{},0,{}
 for i,r in ipairs(T.rowList(v)) do
  local n=T.count(r.n) and r.n or 0
  if n>0 then
   total=total+n
   if r.c~=nil and not classes[r.c] then classes[r.c]=true;distinct=distinct+1 end
  end
  if T.has(r.e,T.DEFECT.over_cap)~=(n>0 and total>6) then bad[#bad+1]=i end
 end
 local isTable=type(v)=='table'
 T.expect(isTable and total==v.copies,tag..': the copies of the rows add up to the copy total',total)
 T.expect(isTable and distinct==v.ids,tag..': the counted rows carry exactly ids distinct classes',distinct)
 T.expect(isTable and #bad==0,tag..': a counted row carries over_cap exactly when the running total passes six',table.concat(bad,','))
end

function T.serialize(v,seen)
 local kind=type(v)
 if kind=='string' then return string.format('%q',v) end
 if kind=='number' or kind=='boolean' or kind=='nil' then return tostring(v) end
 if kind~='table' then return '<'..kind..'>' end
 seen=seen or {}
 if seen[v] then return '<cycle>' end
 seen[v]=true
 local keys={}
 for k in realPairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b)
  local ta,tb=type(a),type(b)
  if ta~=tb then return ta<tb end
  if ta=='number' or ta=='string' then return a<b end
  return tostring(a)<tostring(b)
 end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=T.serialize(k,seen)..'='..T.serialize(rawget(v,k),seen) end
 seen[v]=nil
 return '{'..table.concat(out,',')..'}'
end

-- The adapter's own read-only counters and revisions.
T.COUNTER_NAMES={'reconciliations','scans','cacheHits','failures','lastReason','ownedCalls','lockedCalls','lockedSpells',
 'lockedCopies','wishlistCalls','slotsCalls','boardCalls','catalogChecks','catalogFastHits','catalogRebuilds','catalogFailures',
 'syncRetries','syncRequestedAt','rev1','rev2','rev3','rev4','rev5','rev6','rev7','rev8','rev9','rev10','rev11'}
function T.counters()
 local st=A.EchoReconcileStats();local cs=A.CatalogStatus();local sync=A.OwnedSyncInfo()
 local p=st.projections or {}
 local function f(name,field) return p[name] and p[name][field] end
 local c={reconciliations=st.reconciliations,scans=st.scans,cacheHits=st.cacheHits,failures=st.failures,
  lastReason=st.lastReason,ownedCalls=f('owned','calls'),lockedCalls=f('locked','calls'),lockedSpells=f('locked','spells'),
  lockedCopies=f('locked','copies'),wishlistCalls=f('wishlist','calls'),slotsCalls=f('slots','calls'),
  boardCalls=f('board','calls'),catalogChecks=cs.checks,catalogFastHits=cs.fastHits,catalogRebuilds=cs.rebuilds,
  catalogFailures=cs.failures,syncRetries=sync.retries,syncRequestedAt=sync.requestedAt}
 local rev={A.PresentationRevisions()}
 for i=1,11 do c['rev'..i]=rev[i] end
 return c
end
function T.sameCounters(tag,a,b)
 local moved={}
 for _,k in ipairs(T.COUNTER_NAMES) do
  if a[k]~=b[k] then moved[#moved+1]=k..' '..printable(a[k])..'->'..printable(b[k]) end
 end
 T.guard(#moved==0,tag..': no counter or revision moved (Echo reconciliation, projections, catalog, sync, presentation)',
  table.concat(moved,', '))
end
function T.callList(calls)
 local out={}
 for k,n in realPairs(calls or {}) do out[#out+1]=k..' x'..n end
 table.sort(out)
 return table.concat(out,', ')
end

-- The report (TEST_CONTRACT.md, section 6).
function T.prepared(options)
 local report,why=Nexus.SupportReport.Prepare(options or {})
 if type(report)~='table' or type(report.chunks)~='table' then
  error('the real builder did not prepare a report: '..printable(why),0)
 end
 return table.concat(report.chunks,'')
end
function T.lines(text,prefix)
 local out={}
 for line in (tostring(text or '')..'\n'):gmatch('([^\n]*)\n') do
  if line:match('^%s*'..prefix) then out[#out+1]=line end
 end
 return out
end
function T.tokens(list)
 local t,conflicts={},{}
 for _,line in ipairs(list) do
  for k,v in line:gmatch('([%a][%w_%.]*)=([%w_%.%-%?]*)') do
   if t[k]~=nil and t[k]~=v then conflicts[#conflicts+1]=k end
   t[k]=v
  end
 end
 return t,conflicts
end
function T.shapeBlock(text)
 local all=T.lines(text,'Locked shape')
 local facts,legend={},{}
 for _,line in ipairs(all) do
  if line:match('^%s*Locked shape legend') then legend[#legend+1]=line else facts[#facts+1]=line end
 end
 local t,conflicts=T.tokens(facts)
 return t,all,legend,conflicts
end
function T.leaks(list,markers,maxLines,maxBytes)
 local text=table.concat(list,'\n')
 local found={}
 for _,n in ipairs(T.NAMES) do if text:find(n,1,true) then found[#found+1]='name '..n end end
 for _,id in ipairs(T.IDS) do if text:find('%f[%d]'..id..'%f[%D]') then found[#found+1]='id '..id end end
 for _,r in ipairs({'table: ','function: ','userdata: ','thread: ','builtin'}) do
  if text:find(r,1,true) then found[#found+1]='reference '..r end
 end
 for _,m in ipairs(markers or {}) do if text:find(m,1,true) then found[#found+1]='text '..m:sub(1,40) end end
 for _,line in ipairs(list) do if line:find('%c') then found[#found+1]='control character' end end
 if maxLines and #list>maxLines then found[#found+1]=#list..' lines' end
 if maxBytes and #text>maxBytes then found[#found+1]=#text..' bytes' end
 return found
end
local YESNO=set({'yes','no'})
local function oneOf(s) return function(x) return s[x]==true or T.NULL[x]==true end end
local function blockCount(x) return (x:match('^%d+$')~=nil and #x<=7) or T.NULL[x]==true end
local BLOCK_VALID={
 observed=oneOf(YESNO),serial=blockCount,
 age=function(x) return (x:match('^%d+s?$')~=nil and #x<=8) or T.NULL[x]==true end,
 current=oneOf(YESNO),['later.reads']=blockCount,['sampled.generation']=blockCount,['current.generation']=blockCount,
 first=oneOf(T.TABLE_REJECTIONS),copies=blockCount,ids=blockCount,status=oneOf(T.STATUSES),rows=blockCount,omitted=blockCount,
}
function T.rowToken(x)
 if x=='unknown' or x=='unavailable' then return true end
 return x:match('^[%d%?]+%.[iso%-%?]%.[%dx%?]+%.[%d%?]+%.[%d%?]+%.[%d%?]+%.[%d%?]+$')~=nil
end
-- The block of one prepared report: present, bounded, private, documented values.
function T.checkBlock(tag,text,markers)
 local t,all,legend,conflicts=T.shapeBlock(text)
 T.expect(#all>0,tag..': the prepared report carries a Locked shape block (lines beginning "Locked shape")')
 T.expect(#conflicts==0,tag..': each block key has one value',table.concat(conflicts,','))
 local found=T.leaks(all,markers,80,4096)
 T.expect(#all>0 and #found==0,tag..': the block is bounded (80 lines, 4096 bytes) and carries no name, Echo ID, key text, value, error text, reference or control character',
  table.concat(found,','))
 local claims={}
 local lower=table.concat(all,'\n'):lower()
 if lower:find('%f[%a]duplicat') then claims[#claims+1]='duplicate' end
 for _,w in ipairs({'removed','revoked','deleted','lost'}) do
  if lower:find('%f[%a]'..w..'%f[%A]') then claims[#claims+1]=w end
 end
 for k in realPairs(t) do if k:lower():find('cause',1,true) then claims[#claims+1]=k end end
 table.sort(claims)
 T.expect(#claims==0,tag..': the block shows structure only: no duplicate or removal claim and no cause',table.concat(claims,','))
 local bad={}
 for k,x in realPairs(t) do
  if BLOCK_VALID[k] then
   if not BLOCK_VALID[k](x) then bad[#bad+1]=k..'='..x end
  elseif k:match('^r%d+$') and not T.rowToken(x) then
   bad[#bad+1]=k..'='..x
  end
 end
 table.sort(bad)
 T.expect(#bad==0,tag..': every documented key has a documented value',table.concat(bad,' '))
 if t.observed=='yes' then
  local legendText=table.concat(legend,' ')
  local missing={}
  for _,w in ipairs(T.LEGEND_WORDS) do
   if not legendText:find('%f[%w_]'..w..'%f[^%w_]') then missing[#missing+1]=w end
  end
  T.expect(#legend>=1 and #legend<=3 and #missing==0,tag..': one legend (one to three lines) names every alias and defect code of the bits',
   #legend..' line(s); missing '..table.concat(missing,','))
 end
 return t,all,legend
end
-- The block shows exactly what the accessor held when the report was collected.
local function yn(x) if x==true then return 'yes' elseif x==false then return 'no' end return nil end
function T.matchView(tag,t,v)
 v=type(v)=='table' and v or {}
 t=type(t)=='table' and t or {}
 local want={observed=yn(v.observed),serial=T.fmt(v.serial),current=yn(v.current),['later.reads']=T.fmt(v.laterReads),
  ['sampled.generation']=T.fmt(v.sampledGeneration),['current.generation']=T.fmt(v.currentGeneration),first=v.first,
  copies=T.fmt(v.copies),ids=T.fmt(v.ids),status=v.status,rows=T.fmt(v.rows)}
 local wrong={}
 for _,k in ipairs({'observed','serial','current','later.reads','sampled.generation','current.generation','first',
  'copies','ids','status','rows'}) do
  if want[k]==nil or t[k]~=want[k] then wrong[#wrong+1]=k..'='..printable(t[k])..' (view '..printable(want[k])..')' end
 end
 if v.age==nil or T.ageValue(t.age)~=v.age then wrong[#wrong+1]='age='..printable(t.age)..' (view '..printable(v.age)..')' end
 T.expect(#wrong==0,tag..': the block shows the header the accessor holds',table.concat(wrong,'; '))
 local rows,wrongRows=T.rowTexts(v),{}
 for i,r in ipairs(rows) do
  if t['r'..i]~=r then wrongRows[#wrongRows+1]='r'..i..'='..printable(t['r'..i])..' (view '..r..')' end
 end
 if t['r'..(#rows+1)]~=nil then wrongRows[#wrongRows+1]='an extra r'..(#rows+1) end
 T.expect(#rows>0 and #wrongRows==0,tag..': and every row the accessor holds, in order',table.concat(wrongRows,'; '))
end

-- A pristine adapter instance in a sandbox whose Nexus is its own table: no
-- normal read has run in it ("before the first read", or "after a reload").
function T.pristineAdapter()
 local own=setmetatable({},{__index=function(t,k) local v={};rawset(t,k,v);return v end})
 local chunk,err=loadfile('core/GameAdapter.lua')
 if not chunk then return nil,err end
 setfenv(chunk,setmetatable({Nexus=own},{__index=_G}))
 local ok,e=realPcall(chunk,'Nexus',{})
 if not ok then return nil,printable(e) end
 local m=rawget(own,'GameAdapter')
 if type(m)~='table' then return nil,'the sandbox has no GameAdapter table' end
 return m
end

return H,T
