-- Locked-shape capture, part 2 of 4 (tests-first): bounded capture of deep,
-- shared, cyclic, large and hostile sources; a failing collector; one
-- traversal; no retained raw table.
-- At 5a8299c nothing is captured (source reading: GameAdapter.LockedShapeView
-- does not exist). The parser semantics these fixtures exercise already hold
-- there and are guards: the answers, the counters, one pairs() call per walked
-- table, nothing kept after the read.
-- Contract: TEST_CONTRACT.md of the locked-shape tests-first phase, sections 1-4, 6 and 7.
-- Counting: the global pairs, next and ipairs are wrapped (the adapter resolves
-- them when it calls them) and count calls on the fixture's own tables only.
-- Collector probe (section 2): the global pcall and xpcall are wrapped from the
-- moment the locked getter returns until the read's first A.Catalog lookup
-- (FamilyOf, after the parse). The parser calls neither, so every protected call
-- in that window is diagnostic. Each is reported as failed, without running it
-- ("before") or after running it ("after"). Retention: a weak table must empty
-- after two full collections.
-- Real TOC boot and modules, the fake services of orbs_support.lua, artificial
-- IDs and names; injected markers start with ZQ_. No Orb run, spend or action.
-- Every check is evaluated; the test prints a summary and fails at the end if
-- any check failed.
local H,T=dofile('tests/prototype/locked_shape_support.lua')
local A,O=H.A,H.O
local expect,guard,printable=T.expect,T.guard,T.printable

H.now=math.floor(H.now)+100
local BASE_GRANTED=H.Clone(H.granted)
local ROOT='0.-.0.0.0.0.0'
local function trusted()
 H.holdGrantedResponse=nil;O.known=true;H.playerLevel=40
 H.granted=H.Clone(BASE_GRANTED);A.Owned()
 H.locked={};A.LockedOwned()
end
local function E(id,fields)
 local e={spellId=id}
 for k,v in pairs(fields or {}) do e[k]=v end
 return e
end
local function facts(t,keys)
 if type(t)~='table' then return printable(t) end
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=k..'='..printable(t[k]) end
 return table.concat(out,' ')
end
local function six()
 return {E(410001,{quality=1}),E(410002,{quality=2}),E(410003,{quality=0}),E(410004,{quality=3}),
  E(410005,{quality=0}),E(410006,{quality=3})}
end
local function sixPlus() local t=six();t[7]=E(410001,{quality=1});return t end
local SIX_COPIES={[410001]=1,[410002]=1,[410003]=1,[410004]=1,[410005]=1,[410006]=1}

-- Traversal counting: calls on the current fixture's tables only.
local realPairs,realNext,realIpairs=pairs,next,ipairs
local RAW=setmetatable({},{__mode='k'})
local TRAVERSAL={on=false,pairs=0,next=0,ipairs=0}
pairs=function(t,...)
 if TRAVERSAL.on and RAW[t] then TRAVERSAL.pairs=TRAVERSAL.pairs+1 end
 return realPairs(t,...)
end
next=function(t,...)
 if TRAVERSAL.on and RAW[t] then TRAVERSAL.next=TRAVERSAL.next+1 end
 return realNext(t,...)
end
ipairs=function(t,...)
 if TRAVERSAL.on and RAW[t] then TRAVERSAL.ipairs=TRAVERSAL.ipairs+1 end
 return realIpairs(t,...)
end
local function register(tree)
 RAW=setmetatable({},{__mode='k'})
 T.tables(tree,RAW)
 TRAVERSAL.pairs,TRAVERSAL.next,TRAVERSAL.ipairs=0,0,0
end
-- One normal read of `tree`, counting how the raw value was iterated.
local function counted(tree)
 register(tree)
 TRAVERSAL.on=true
 local l,d,err=T.read(tree)
 TRAVERSAL.on=false
 return l,d,err,{pairs=TRAVERSAL.pairs,next=TRAVERSAL.next,ipairs=TRAVERSAL.ipairs}
end
-- One fixture: the existing answer (guards), then the capture (expectations).
local function run(tag,f)
 trusted()
 H.now=H.now+3
 local l,d,err,trav=counted(f.build())
 guard(l~=nil,tag..': LockedOwned() answers',err)
 l=l or {}
 guard(l.synced==false,tag..': the read is refused (synced=false)',l.synced)
 guard(T.sig(l.bySpell)==T.sig(f.bySpell),tag..': the recognized copies per Echo are as before',T.sig(l.bySpell))
 guard(d.calls==1 and d.spells==f.ids and d.copies==f.copies,
  tag..': the locked projection counters advance as before (1 call, '..f.ids..' Echoes, '..f.copies..' copies)',
  d.calls..'/'..d.spells..'/'..d.copies)
 local t=T.trust() or {}
 guard(t.lockedSynced==false and t.lockedCopies==f.copies and t.lockedRejection==f.first,
  tag..': the ownership sample is that read ('..f.first..', '..f.copies..' copies)',facts(t,{'lockedSynced','lockedCopies','lockedRejection'}))
 guard(trav.pairs==f.walked and trav.next==0 and trav.ipairs==0,
  tag..': one traversal: pairs() once on each of the '..f.walked..' walked tables, nothing else',facts(trav,{'pairs','next','ipairs'}))
 local v,why=T.shape()
 T.checkShape(tag,v)
 local w=v or {}
 expect(v~=nil and w.observed==true and w.serial==d.serial and w.current==true,tag..': the refused read is captured as the current one',
  why or facts(w,{'observed','serial','current'}))
 expect(w.first==f.first and w.copies==f.copies and w.ids==f.ids,
  tag..': with the first rejection and the exact copies and distinct IDs ('..f.first..', '..f.copies..', '..f.ids..')',
  facts(w,{'first','copies','ids'}))
 expect(w.status==f.status and w.rows==f.rowCount,tag..': status='..f.status..' with '..f.rowCount..' rows',facts(w,{'status','rows'}))
 if f.rows then T.expectRows(tag,v,f.rows) end
 if f.status=='captured' then T.expectConsistent(tag,v) end
 return v,l,d
end

-- Expected rows (TEST_CONTRACT.md, section 4).
local function flatRows(n)
 local rows={ROOT}
 for i=1,n do rows[#rows+1]='1.i.'..i..'.1.1.0.'..(i>=7 and 16 or 0) end
 return rows
end
local function nestedRows()
 local rows={ROOT}
 for j=1,32 do
  rows[#rows+1]='1.i.0.0.0.0.0'
  if #rows<64 then rows[#rows+1]=(2*j)..'.s.'..j..'.1.1.0.'..(j>=7 and 16 or 0) end
 end
 return rows
end
local DEPTH_ROWS={ROOT}
for i=2,9 do DEPTH_ROWS[i]=(i-1)..'.i.0.0.0.0.0' end
DEPTH_ROWS[10]='9.i.0.0.0.0.1'
local function chain(levels)
 local d=E(410001)
 for _=1,levels do d={d} end
 return d
end
local function plainId(i) return 200000+i end
local function cycledId(i) return 200000+((i-1)%90)+1 end
local function entries(n,idOf)
 local t={}
 for i=1,n do t[i]=E(idOf(i)) end
 return t
end
local function copiesOf(n,idOf)
 local m={}
 for i=1,n do local id=idOf(i);m[id]=(m[id] or 0)+1 end
 return m
end
local SHAPES={
 {name='an entry nine tables deep',first='depth',copies=0,ids=0,bySpell={},walked=9,status='captured',rowCount=10,
  build=function() return chain(9) end,rows=DEPTH_ROWS},
 {name='an entry forty tables deep',first='depth',copies=0,ids=0,bySpell={},walked=9,status='captured',rowCount=10,
  build=function() return chain(40) end,rows=DEPTH_ROWS},
 {name='the same entry table twice',first='cycle',copies=6,ids=6,bySpell=SIX_COPIES,walked=7,status='captured',rowCount=8,
  build=function() local t=six();t[7]=t[1];return t end,
  rows={ROOT,'1.i.1.1.1.0.0','1.i.2.1.1.0.0','1.i.3.1.1.0.0','1.i.4.1.1.0.0','1.i.5.1.1.0.0','1.i.6.1.1.0.0','1.i.0.0.0.0.2'}},
 {name='a table that holds itself',first='cycle',copies=1,ids=1,bySpell={[410001]=1},walked=2,status='captured',rowCount=3,
  build=function() local t={E(410001)};t[2]=t;return t end,rows={ROOT,'1.i.1.1.1.0.0','1.i.0.0.0.0.2'}},
 {name='two entries that hold each other',first='cycle',copies=2,ids=2,bySpell={[410001]=1,[410002]=1},walked=3,
  status='captured',rowCount=4,
  build=function() local a,b=E(410001),E(410002);a.ZQ_NEXT=b;b.ZQ_NEXT=a;return {a} end,
  rows={ROOT,'1.i.1.1.1.0.0','2.s.2.1.1.0.0','3.s.0.0.0.0.2'}},
 {name='exactly 64 tables',first='over_cap',copies=63,ids=63,bySpell=copiesOf(63,plainId),walked=64,status='captured',
  rowCount=64,build=function() return entries(63,plainId) end,rows=flatRows(63)},
 {name='65 tables',first='over_cap',copies=64,ids=64,bySpell=copiesOf(64,plainId),walked=65,status='truncated',rowCount=64,
  build=function() return entries(64,plainId) end,rows=flatRows(63)},
 {name='101 tables',first='over_cap',copies=100,ids=90,bySpell=copiesOf(100,cycledId),walked=101,status='truncated',
  rowCount=64,build=function() return entries(100,cycledId) end,rows=flatRows(63)},
 {name='40 nested wrappers',first='over_cap',copies=40,ids=40,bySpell=copiesOf(40,plainId),walked=81,status='truncated',
  rowCount=64,build=function() local t={};for i=1,40 do t[i]={ZQ_ITEM=E(200000+i)} end;return t end,rows=nestedRows()},
 {name='one entry with 5000 dynamic keys',first='over_cap',copies=7,ids=1,bySpell={[410001]=7},walked=2,status='captured',
  rowCount=2,
  build=function()
   local e=E(410001,{stacks=7})
   for i=1,5000 do e['ZQ_DYN_'..i..' Disposable A']='ZQ_VAL_'..i..' 410002' end
   return {e}
  end,
  rows={ROOT,'1.i.1.7.1.2.16'}},
}

-- B1. Deep, shared, cyclic, large and wide sources: the parser's answers are
-- unchanged and the capture stays within 64 rows, saying when it is truncated.
T.scenario('B1 bounded capture',function()
 for _,f in ipairs(SHAPES) do run('B1 '..f.name,f) end
end)

-- B2. The report of a truncated capture declares it and stays bounded.
T.scenario('B2 truncation in the report',function()
 trusted()
 H.now=H.now+3
 counted(entries(100,cycledId))
 local t,all=T.checkBlock('B2',T.prepared(),{'ZQ_'})
 expect(t.status=='truncated' and t.rows=='64' and t.copies=='100' and t.ids=='90',
  'B2: the block shows status=truncated, 64 rows and the exact copies and distinct IDs',facts(t,{'status','rows','copies','ids'}))
 local shown=0
 for i=1,64 do if t['r'..i]~=nil then shown=shown+1 end end
 local omitted=t.omitted and tonumber(t.omitted) or 0
 expect(#all>0 and shown+omitted==64 and t.r65==nil,'B2: every kept row is shown or declared omitted, and nothing beyond them',
  shown..' shown, omitted '..printable(t.omitted))
end)

-- B3. Hostile keys, metatables, names and values: the parser reads them as
-- before; the capture keeps only classes and numbers, and is complete because
-- the collector runs no metamethod and converts no key or value.
local function raiseMarker() error('ZQ_META_MARKER Disposable A 410001',0) end
local EVIL={__index=raiseMarker,__newindex=raiseMarker,__tostring=raiseMarker,__concat=raiseMarker,__len=raiseMarker,
 __eq=raiseMarker,__lt=raiseMarker,__le=raiseMarker,__call=raiseMarker,__unm=raiseMarker,__add=raiseMarker}
local function hostile()
 local root={}
 root[setmetatable({},EVIL)]=E(410001)
 root[true]=E(410002)
 root[1.5]=E(410003)
 root[-2]=E(410004)
 root[0]=E(410005)
 root[math.huge]=E(410006)
 root['ZQ_KEY_MARKER Disposable B 200002']=setmetatable({spellId=410008,stacks=2,name='Disposable A',
  note='ZQ_VALUE_MARKER 410001'},EVIL)
 root[3]=E('410007')
 return root
end
local HOSTILE={name='hostile',first='over_cap',copies=9,ids=8,walked=9,status='captured',rowCount=9,build=hostile,
 bySpell={[410001]=1,[410002]=1,[410003]=1,[410004]=1,[410005]=1,[410006]=1,[410007]=1,[410008]=2}}
T.scenario('B3 hostile source',function()
 local v=run('B3 hostile source',HOSTILE)
 local rows=T.rowList(v)
 expect(#rows==9 and T.rowText(rows[1] or {})==ROOT,'B3: nine rows, the root first',#rows)
 local kinds,classes,distinct,ok={},{},0,#rows==9
 for i=2,#rows do
  local r=rows[i]
  ok=ok and r.p==1 and r.im==T.ID_BIT.spellId
  if r.k=='s' then ok=ok and r.n==2 and r.cm==T.COUNT_BIT.stacks else ok=ok and r.n==1 and r.cm==0 end
  kinds[r.k or '?']=(kinds[r.k or '?'] or 0)+1
  if r.c~=nil and not classes[r.c] then classes[r.c]=true;distinct=distinct+1 end
 end
 expect(ok,'B3: every entry is a counted child of the root by its spellId alias; the named one counts its stacks')
 expect(kinds.o==6 and kinds.s==1 and kinds.i==1,
  'B3: key classes: six other (table, boolean, fraction, negative, zero, infinite), one string, one whole number',
  'o='..printable(kinds.o)..' s='..printable(kinds.s)..' i='..printable(kinds.i))
 expect(distinct==8,'B3: eight distinct anonymous ID classes',distinct)
 T.checkBlock('B3',T.prepared(),{'ZQ_'})
end)

-- B4. A failing collector. Every protected call during the parse reports a
-- failure; the read answers, counts, samples and traverses exactly as the
-- reference read does, records no error, and the capture says failed.
T.scenario('B4 a failing collector changes nothing the read answers',function()
 trusted()
 H.now=H.now+5
 local ref,_,refErr,refTrav=counted(sixPlus())
 local refTrust=T.trust() or {}
 local refView=T.shape()
 local refRows=T.rowTexts(refView)
 guard(ref~=nil and ref.synced==false and refTrav.pairs==8,'B4: fixture: the reference read is refused, with one traversal',
  refErr or refTrav.pairs)
 expect(type(refView)=='table' and refView.status=='captured' and #refRows==8,'B4: fixture: the reference read is captured completely',
  facts(refView,{'status','rows'}))
 local FAULT='ZQ_COLLECTOR_FAULT Disposable A 410001'
 local realPcall,realXpcall=pcall,xpcall
 local svc=ProjectEbonhold.PerkService
 local realGetter,realCatalog=svc.GetLockedPerks,A.Catalog
 local errors,incidents=Nexus.Errors,Nexus.SupportIncidents
 local realRecord=type(errors)=='table' and errors.Record or nil
 local realIncident=type(incidents)=='table' and incidents.Record or nil
 local P={armed=false,enabled=false,mode='before',injected=0,records=0,tree=nil}
 pcall=function(f,...)
  if P.armed and f~=GetTime then
   P.injected=P.injected+1
   if P.mode=='after' then realPcall(f,...) end
   return false,FAULT
  end
  return realPcall(f,...)
 end
 xpcall=function(f,handler,...)
  if P.armed and f~=GetTime then
   P.injected=P.injected+1
   if P.mode=='after' then realXpcall(f,handler,...) end
   return false,FAULT
  end
  return realXpcall(f,handler,...)
 end
 svc.GetLockedPerks=function() P.armed=P.enabled;return P.tree end
 A.Catalog=function(...) P.armed=false;return realCatalog(...) end
 if realRecord then errors.Record=function(...) P.records=P.records+1;return realRecord(...) end end
 if realIncident then incidents.Record=function(...) P.records=P.records+1;return realIncident(...) end end
 local function probe(build,mode)
  P.tree=build();P.mode=mode;P.injected=0;P.records=0;P.armed=false;P.enabled=true
  register(P.tree)
  TRAVERSAL.on=true
  local before=T.lockedStats()
  local ok,l=T.realPcall(A.LockedOwned)
  TRAVERSAL.on=false;P.enabled=false;P.armed=false
  local after=T.lockedStats()
  return {ok=ok,l=ok and type(l)=='table' and l or nil,err=(not ok) and printable(l) or nil,
   d={calls=(after.calls or 0)-(before.calls or 0),spells=(after.spells or 0)-(before.spells or 0),
    copies=(after.copies or 0)-(before.copies or 0),serial=after.calls},
   trav={pairs=TRAVERSAL.pairs,next=TRAVERSAL.next,ipairs=TRAVERSAL.ipairs},injected=P.injected,records=P.records}
 end
 local results={}
 local okRun,errRun=T.realPcall(function()
  for _,mode in ipairs({'before','after'}) do
   H.now=H.now+5
   local r=probe(sixPlus,mode)
   r.mode,r.kind,r.view,r.trust=mode,'refused',T.shape(),T.trust()
   results[#results+1]=r
   H.now=H.now+5
   local s=probe(six,mode)
   s.mode,s.kind,s.view,s.previous=mode,'valid',T.shape(),r.view
   results[#results+1]=s
  end
 end)
 pcall,xpcall=realPcall,realXpcall
 svc.GetLockedPerks,A.Catalog=realGetter,realCatalog
 if realRecord then errors.Record=realRecord end
 if realIncident then incidents.Record=realIncident end
 guard(okRun,'B4: the probe ran',errRun)
 guard(#results==4,'B4: four probed reads (refused and valid, failing before and after the call)',#results)
 for _,r in ipairs(results) do
  local tag='B4 '..r.kind..' read, calls failing '..r.mode
  local l=r.l or {}
  guard(r.ok and r.l~=nil,tag..': LockedOwned() still answers and raises nothing',r.err)
  guard(r.trav.pairs==(r.kind=='refused' and 8 or 7) and r.trav.next==0 and r.trav.ipairs==0,
   tag..': still exactly one traversal',facts(r.trav,{'pairs','next','ipairs'}))
  guard(r.records==0,tag..': nothing is recorded in the error or incident history',r.records)
  guard(r.d.calls==1,tag..': one locked projection call',r.d.calls)
  if r.kind=='refused' then
   guard(l.synced==false and T.sig(l.bySpell)==T.sig(ref and ref.bySpell) and T.sum(l.byFamily)==7
    and r.d.spells==6 and r.d.copies==7,tag..': the same refused answer and counter steps as the reference read',T.sig(l.bySpell))
   local t=r.trust or {}
   guard(t.lockedSynced==false and t.lockedCopies==refTrust.lockedCopies and t.lockedRejection==refTrust.lockedRejection,
    tag..': the same locked sample as the reference read',facts(t,{'lockedSynced','lockedCopies','lockedRejection'}))
   expect(r.injected>=1,tag..': the collector runs under protection during the parse (global pcall/xpcall), so the probe reached it',
    r.injected)
   T.checkShape(tag,r.view)
   local w=r.view or {}
   expect(w.observed==true and w.serial==r.d.serial and w.current==true,tag..': the read is still recorded, as the current one',
    facts(w,{'observed','serial','current'}))
   expect(w.status=='failed',tag..': with status=failed',w.status)
   expect(w.first=='over_cap' and w.copies==7 and w.ids==6,tag..': and the exact header of that read',facts(w,{'first','copies','ids'}))
   local rows,wrong=T.rowTexts(r.view),{}
   for i,row in ipairs(rows) do if row~=refRows[i] then wrong[#wrong+1]=i end end
   expect(type(r.view)=='table' and #rows<=#refRows and #wrong==0,tag..': any rows it kept are a prefix of the complete capture',
    table.concat(wrong,','))
  else
   guard(l.synced==true and T.sig(l.bySpell)==T.sig(SIX_COPIES),tag..': six valid entries stay trusted, with every copy',
    T.sig(l.bySpell))
   expect(type(r.view)=='table' and type(r.previous)=='table' and T.record(r.view)==T.record(r.previous)
    and r.view.current==false,tag..': the accepted read leaves the failed capture as it was, no longer current')
  end
 end
 local t=T.checkBlock('B4 report',T.prepared(),{'ZQ_',FAULT})
 expect(t.status=='failed','B4 report: the block shows status=failed, never captured',t.status)
end)

-- B5. Collection never traverses the locked source: the getter still returns
-- it, so any read during collection would.
T.scenario('B5 collection never traverses the locked source',function()
 trusted()
 H.now=H.now+3
 counted(hostile())
 TRAVERSAL.pairs,TRAVERSAL.next,TRAVERSAL.ipairs=0,0,0
 TRAVERSAL.on=true
 local ok,err=T.realPcall(function()
  T.shape();T.trust();T.readiness();T.prepared()
  Nexus.SupportReport.Summary();Nexus.SupportReport.OrbLines()
 end)
 TRAVERSAL.on=false
 guard(ok,'B5: the collection window completed',err)
 guard(TRAVERSAL.pairs==0 and TRAVERSAL.next==0 and TRAVERSAL.ipairs==0,'B5: the views and the report never iterate the locked source',
  facts(TRAVERSAL,{'pairs','next','ipairs'}))
end)

-- B6. No raw table is retained by the read, the views or the report. The source
-- is built, read and dropped inside a function, so no stack slot of this one
-- holds it; one of its tables is kept on purpose as the control.
local function lifecycle(build)
 local weak=setmetatable({},{__mode='k'})
 local tree=build()
 T.tables(tree,weak)
 local keep
 for _,v in realNext,tree do if type(v)=='table' then keep=v;break end end
 H.locked=tree
 local okRead=T.realPcall(A.LockedOwned)
 T.realPcall(T.shape);T.realPcall(T.trust);T.realPcall(T.prepared)
 H.locked={}
 return weak,{keep},okRead
end
T.scenario('B6 no raw table is retained',function()
 trusted()
 for _,c in ipairs({{'a refused hostile source',hostile},{'a refused six plus same-ID source',sixPlus},
  {'an accepted six-entry source',six}}) do
  local tag='B6 '..c[1]
  H.now=H.now+3
  local weak,keep,okRead=lifecycle(c[2])
  collectgarbage('collect');collectgarbage('collect')
  local survivors,kept=0,false
  for t in realNext,weak do
   survivors=survivors+1
   if t==keep[1] then kept=true end
  end
  guard(okRead,tag..': fixture: the read ran')
  guard(kept,tag..': control: the one table the test still holds survives the collection')
  guard(survivors==1,tag..': no other table of the source is referenced after the read, the views and the report',survivors)
 end
 trusted()
end)

T.finish('locked_shape_bounds')
