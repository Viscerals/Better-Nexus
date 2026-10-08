-- Locked-shape capture, part 1 of 4 (tests-first): the normal LockedOwned() read
-- keeps an anonymous structural capture of a REFUSED locked table, and every
-- existing answer stays exactly as it is.
-- At 5a8299c a refused read keeps only its first rejection code, its copy total
-- and its raw type class (source reading). GameAdapter.LockedShapeView does not
-- exist, so nothing tells seven separate entries from one entry with stacks=7,
-- a repeated ID from distinct IDs, or a counted wrapper from its children.
-- Contract: TEST_CONTRACT.md of the locked-shape tests-first phase, sections 1-4.
-- Guards (already true at 5a8299c): the LockedOwned() answer, the ownership
-- sample, the locked projection counters, revisions, dirty flags, the current
-- generation facts and saved data; the Orb trust gate and EchoWeaver's locked
-- wait; the Echo snapshot's locked acceptance and generation. Capture
-- expectations (new): the header and rows of each refused fixture; accepted
-- reads and the Echo snapshot path leave the capture alone. A repeated ID is a
-- repeated anonymous class, never a duplicate; valid repeated-ID
-- representations stay valid and count every copy.
-- Real TOC boot and modules, the fake services of orbs_support.lua, artificial
-- IDs. No Orb run, spend, lock or action. Every check is evaluated; the test
-- prints a summary and fails at the end if any check failed.
local H,T=dofile('tests/prototype/locked_shape_support.lua')
local A,O=H.A,H.O
local expect,guard,printable=T.expect,T.guard,T.printable

-- Whole seconds from here on, so that every age is exact.
H.now=math.floor(H.now)+100
local BASE_GRANTED=H.Clone(H.granted)
local TRUST='Waiting for current rolled and locked Echo data from the server.'
-- The text of an over-cap refusal is pinned by orb_count_refusal_truthful; the
-- gate guards here accept either honest text (orb_count_refusal_support).
local COUNT_REFUSAL=dofile('tests/prototype/orb_count_refusal_support.lua')
local WAIT_LOCKED='waiting for locked Echo state'
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
local function six()
 return {E(410001,{quality=1}),E(410002,{quality=2}),E(410003,{quality=0}),E(410004,{quality=3}),
  E(410005,{quality=0}),E(410006,{quality=3})}
end
local function facts(t,keys)
 if type(t)~='table' then return printable(t) end
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=k..'='..printable(t[k]) end
 return table.concat(out,' ')
end
local function counted(r) return T.int(r.n) and r.n>0 end

-- Refused fixtures. The rows are hand-derived from the parser rules of 5a8299c:
-- pre-order, p=parent row, k=key class, c=ID class by first appearance,
-- n=copies added, im/cm=alias bits read, e=defect bits (TEST_CONTRACT.md, section 4).
local PARALLEL
local REFUSED={
 {name='seven distinct entries',first='over_cap',copies=7,ids=7,
  bySpell={[410001]=1,[410002]=1,[410003]=1,[410004]=1,[410005]=1,[410006]=1,[410007]=1},
  build=function() local t=six();t[7]=E(410007,{quality=2});return t end,
  rows={ROOT,'1.i.1.1.1.0.0','1.i.2.1.1.0.0','1.i.3.1.1.0.0','1.i.4.1.1.0.0','1.i.5.1.1.0.0','1.i.6.1.1.0.0',
   '1.i.7.1.1.0.16'}},
 {name='six entries and a separate same-ID entry',first='over_cap',copies=7,ids=6,
  bySpell={[410001]=2,[410002]=1,[410003]=1,[410004]=1,[410005]=1,[410006]=1},
  build=function() local t=six();t[7]=E(410001,{quality=1});return t end,
  rows={ROOT,'1.i.1.1.1.0.0','1.i.2.1.1.0.0','1.i.3.1.1.0.0','1.i.4.1.1.0.0','1.i.5.1.1.0.0','1.i.6.1.1.0.0',
   '1.i.1.1.1.0.16'}},
 -- A record is over the cap when it holds more copies than its own stated
 -- maxStack (the native record shape), or when more records are occupied
 -- than the live capacity (T.CAPACITY); stackOver names the rows of the first.
 {name='one entry with stacks=7',first='over_cap',copies=7,ids=1,bySpell={[410007]=7},
  build=function() return {E(410007,{quality=2,stacks=7,maxStack=1})} end,
  rows={ROOT,'1.i.1.7.1.2.16'},stackOver={[2]=true}},
 {name='a counted wrapper over same-ID members',first='over_cap',copies=8,ids=1,bySpell={[410003]=8},
  build=function() return {{entryId=410003,count=4,maxStack=3,members={E(410003),E(410003),E(410003),E(410003)}}} end,
  rows={ROOT,'1.i.1.4.32.4.16','2.s.0.0.0.0.0','3.i.1.1.1.0.0','3.i.1.1.1.0.0','3.i.1.1.1.0.0','3.i.1.1.1.0.0'},
  stackOver={[2]=true}},
 {name='a counted record with a different-ID detail',first='over_cap',copies=7,ids=2,bySpell={[410004]=5,[410005]=2},
  build=function() return {E(410004,{stacks=5,maxStack=2,detail=E(410005,{stacks=2})})} end,
  rows={ROOT,'1.i.1.5.1.2.16','2.s.2.2.1.2.0'},stackOver={[2]=true}},
 {name='two separate same-ID entries and a leaf',first='scalar_leaf',copies=2,ids=1,bySpell={[410001]=2},
  build=function() return {E(410001,{quality=1}),E(410001,{quality=1}),{note='ZQ_NOTE_MARKER 410002'}} end,
  rows={ROOT,'1.i.1.1.1.0.0','1.i.1.1.1.0.0','1.i.0.0.0.0.32'}},
 {name='one entry with stacks=2 and a leaf',first='scalar_leaf',copies=2,ids=1,bySpell={[410001]=2},
  build=function() return {E(410001,{quality=1,stacks=2}),{note='ZQ_NOTE_MARKER 410002'}} end,
  rows={ROOT,'1.i.1.2.1.2.0','1.i.0.0.0.0.32'}},
 {name='parallel indexed and named views',first='over_cap',copies=8,ids=4,
  bySpell={[410001]=2,[410002]=2,[410003]=2,[410004]=2},
  build=function()
   return {ZQ_VIEW_LIST={E(410001),E(410002),E(410003),E(410004)},
    ZQ_VIEW_NAMED={ZQ_NAME_A=E(410001),ZQ_NAME_B=E(410002),ZQ_NAME_C=E(410003),ZQ_NAME_D=E(410004)}}
  end,
  check=function(tag,v) PARALLEL(tag,v) end},
 {name='an ID-less wrapper with a count',first='scalar_leaf',copies=2,ids=2,bySpell={[410001]=1,[410002]=1},
  build=function() return {{count=3,entries={E(410001),E(410002)}},{note='ZQ_NOTE_MARKER'}} end,
  rows={ROOT,'1.i.0.0.0.4.0','2.s.0.0.0.0.0','3.i.1.1.1.0.0','3.i.2.1.1.0.0','1.i.0.0.0.0.32'}},
 {name='alias forms, an invalid alias and two disagreeing ones',first='invalid_value',copies=4,ids=3,
  bySpell={[410001]=2,[410002]=1,[410003]=1},
  build=function()
   return {{perkID=410001,qty=2},{echoId=410002},{spell=410003,amount=1},
    {spellID=410004,perkId='ZQ_BAD_MARKER 410004',entryId=410004},{spellId=410005,id=410006},
    E(410007,{stack=1,count=2})}
  end,
  rows={ROOT,'1.i.1.2.16.16.0','1.i.2.1.128.0.0','1.i.3.1.512.8.0','1.i.x.0.10.0.4','1.i.x.0.5.0.8','1.i.4.0.1.5.8'}},
}
-- Hash order decides which view is read first, so this one is checked by
-- order-free rules.
PARALLEL=function(tag,v)
 local rows=T.rowList(v)
 expect(#rows==11,tag..': eleven rows: the root, two containers and eight entries',#rows)
 expect(T.rowText(rows[1] or {})==ROOT,tag..': row 1 is the root',T.rowText(rows[1] or {}))
 local containers={}
 for i=2,#rows do if rows[i].p==1 then containers[#containers+1]=i end end
 local okContainers=#containers==2
 for _,i in ipairs(containers) do okContainers=okContainers and rows[i].k=='s' and rows[i].c==0 and rows[i].n==0 end
 expect(okContainers,tag..': two string-keyed, uncounted containers under the root',#containers)
 local list,okEntries={},true
 for i=2,#rows do
  if counted(rows[i]) then
   list[#list+1]=i
   okEntries=okEntries and rows[i].n==1 and rows[i].im==T.ID_BIT.spellId and rows[i].cm==0
  end
 end
 expect(#list==8 and okEntries,tag..': eight counted entries of one copy each, by the spellId alias',#list)
 local kinds={}
 for _,i in ipairs(list) do
  local r=rows[i]
  kinds[r.p]=kinds[r.p] or {}
  kinds[r.p][r.k]=(kinds[r.p][r.k] or 0)+1
 end
 local a,b=kinds[containers[1] or -1] or {},kinds[containers[2] or -2] or {}
 local split=(a.i==4 and a.s==nil and b.s==4 and b.i==nil) or (b.i==4 and b.s==nil and a.s==4 and a.i==nil)
 expect(split,tag..': one container holds four indexed entries, the other four named ones')
 local parentsOf,classes,okPairs={},0,true
 for _,i in ipairs(list) do
  local r=rows[i]
  if parentsOf[r.c]==nil then parentsOf[r.c]={};classes=classes+1 end
  local l=parentsOf[r.c];l[#l+1]=r.p
 end
 for c,l in pairs(parentsOf) do okPairs=okPairs and T.int(c) and c>=1 and #l==2 and l[1]~=l[2] end
 expect(classes==4 and okPairs,tag..': four ID classes, each repeated once across the two containers',classes)
 local okCap=true
 for index,i in ipairs(list) do okCap=okCap and T.has(rows[i].e,T.DEFECT.over_cap)==(index>6) end
 expect(#list==8 and okCap,tag..': only the seventh and eighth counted entries in read order cross the cap')
end

-- Valid controls: repeated IDs are legitimate copies, each counted.
local VALID={
 {name='six entries',copies=6,bySpell={[410001]=1,[410002]=1,[410003]=1,[410004]=1,[410005]=1,[410006]=1},build=six},
 {name='two separate same-ID entries',copies=2,bySpell={[410001]=2},
  build=function() return {E(410001,{quality=1}),E(410001,{quality=1})} end},
 {name='one entry with stacks=2',copies=2,bySpell={[410001]=2},build=function() return {E(410001,{quality=1,stacks=2})} end},
 {name='a record with a same-ID detail',copies=2,bySpell={[410002]=2},
  build=function() return {E(410002,{quality=2,info=E(410002)})} end},
}

-- C0. Since load every locked read was accepted: nothing is captured.
T.scenario('C0 before any refused locked read',function()
 trusted()
 local v,why=T.shape()
 expect(v~=nil,'C0: GameAdapter.LockedShapeView() exists and answers a table',why)
 T.checkShape('C0',v)
 expect(v~=nil and v.observed==false,'C0: no refused locked read since load, so observed=false',v and v.observed)
end)

-- C1. Each refused fixture: the existing answer, sample and counters are as
-- before (guards), and the read is captured (expectations).
local captured={}
T.scenario('C1 refused locked reads',function()
 for _,f in ipairs(REFUSED) do
  local tag='C1 '..f.name
  trusted()
  H.now=H.now+7
  A.ConsumeDirty()
  local t0=T.trust() or {}
  local rev0,db0=T.serialize({A.PresentationRevisions()}),T.serialize(NexusDB)
  local l,d,err=T.read(f.build())
  guard(l~=nil,tag..': LockedOwned() answers',err)
  l=l or {}
  guard(l.synced==false,tag..': the read is refused (synced=false)',l.synced)
  guard(T.sig(l.bySpell)==T.sig(f.bySpell),tag..': the recognized copies per Echo are as before: '..T.sig(f.bySpell),T.sig(l.bySpell))
  guard(T.sum(l.byFamily)==f.copies,tag..': byFamily holds the same '..f.copies..' copies',T.sum(l.byFamily))
  guard(d.calls==1 and d.spells==f.ids and d.copies==f.copies,
   tag..': the locked projection counters advance as before (1 call, '..f.ids..' Echoes, '..f.copies..' copies)',
   d.calls..'/'..d.spells..'/'..d.copies)
  local t=T.trust() or {}
  guard(t.lockedObserved==true and t.lockedSynced==false and t.lockedCopies==f.copies and t.lockedRejection==f.first
   and t.lockedRawType=='table' and t.lockedAt==H.now,tag..': the ownership sample is that read ('..f.first..', '..f.copies..' copies)',
   facts(t,{'lockedSynced','lockedCopies','lockedRejection','lockedRawType','lockedAt'}))
  guard(t.ownedGeneration==t0.ownedGeneration and t.ownedConfirmed==t0.ownedConfirmed and t.ownedArmed==t0.ownedArmed
   and t.ownedRetries==t0.ownedRetries,tag..': the current generation facts are unchanged',
   facts(t,{'ownedGeneration','ownedConfirmed','ownedArmed','ownedRetries'}))
  guard(T.serialize({A.PresentationRevisions()})==rev0,tag..': no presentation revision moved')
  local dirtyBoard,dirtySlots,dirtyData=A.ConsumeDirty()
  guard(not dirtyBoard and not dirtySlots and not dirtyData,tag..': nothing was marked dirty',
   printable(dirtyBoard)..'/'..printable(dirtySlots)..'/'..printable(dirtyData))
  guard(T.serialize(NexusDB)==db0,tag..': saved data is unchanged')
  local v,why=T.shape()
  T.checkShape(tag,v)
  local w=v or {}
  expect(v~=nil and w.observed==true,tag..': LockedShapeView() shows the refused read as captured',why or w.observed)
  expect(w.serial==d.serial and w.current==true and w.laterReads==0,tag..': with the serial of that read, current, no later read',
   facts(w,{'serial','current','laterReads'})..' (read '..printable(d.serial)..')')
  expect(w.at==H.now and w.age==0,tag..': at the time of that read',facts(w,{'at','age'}))
  expect(w.first==f.first and w.copies==f.copies and w.ids==f.ids,
   tag..': with its first rejection, its copies and its distinct IDs ('..f.first..', '..f.copies..', '..f.ids..')',
   facts(w,{'first','copies','ids'}))
  expect(w.sampledGeneration==t.ownedGeneration and w.currentGeneration==t.ownedGeneration,
   tag..': the sampled generation is the current one',facts(w,{'sampledGeneration','currentGeneration'}))
  expect(w.status=='captured',tag..': complete (status=captured)',w.status)
  if f.rows then T.expectRows(tag,v,f.rows) else f.check(tag,v) end
  T.expectConsistent(tag,v,f.stackOver)
  captured[f.name]=v and H.Clone(v) or nil
 end
end)

-- C2. Valid repeated-ID representations stay valid, count every copy and leave
-- the last capture as it was (no longer current).
T.scenario('C2 valid repeated-ID representations',function()
 for _,f in ipairs(VALID) do
  local tag='C2 '..f.name
  H.now=H.now+3
  local before=T.shape()
  local rec0=T.record(before)
  local later0=type(before)=='table' and before.laterReads or nil
  local l,d,err=T.read(f.build())
  guard(l~=nil and l.synced==true,tag..': the read is trusted',err or (l and l.synced))
  guard(l~=nil and T.sig(l.bySpell)==T.sig(f.bySpell),tag..': every copy counts, nothing is de-duplicated: '..T.sig(f.bySpell),
   l and T.sig(l.bySpell))
  guard(d.calls==1 and d.copies==f.copies,tag..': the locked projection counters advance as before',d.calls..'/'..d.copies)
  local t=T.trust() or {}
  guard(t.lockedSynced==true and t.lockedRejection=='none' and t.lockedCopies==f.copies,tag..': the ownership sample is the trusted read',
   facts(t,{'lockedSynced','lockedRejection','lockedCopies'}))
  local v=T.shape()
  expect(type(before)=='table' and before.observed==true and type(v)=='table' and T.record(v)==rec0,
   tag..': an accepted read leaves the last refused capture exactly as it was')
  expect(type(v)=='table' and v.current==false and T.int(later0) and v.laterReads==later0+1,
   tag..': and marks it no longer current, with one more later read',facts(v,{'current','laterReads'}))
 end
end)

-- C3. The captures tell the representations apart, as structure only.
local function rowsOf(name) return T.rowList(captured[name]) end
local function nearestCountedAncestor(rows,i)
 local j,steps=rows[i] and rows[i].p,0
 while T.int(j) and j>=1 and steps<70 do
  if rows[j] and counted(rows[j]) then return j end
  j=rows[j] and rows[j].p;steps=steps+1
 end
 return nil
end
T.scenario('C3 representations',function()
 local seven,sixPlus,stack7='seven distinct entries','six entries and a separate same-ID entry','one entry with stacks=7'
 local function joined(name) return table.concat(T.rowTexts(captured[name]),'|') end
 local a,b,c=joined(seven),joined(sixPlus),joined(stack7)
 expect(a~='' and b~='' and c~='' and a~=b and a~=c and b~=c,
  'C3: the three over-cap fixtures (same first rejection, same 7 copies, same gate) give three different captures')
 local rows=rowsOf(seven)
 local n,classes,seen=0,0,{}
 for _,r in ipairs(rows) do
  if counted(r) then n=n+1;if r.n==1 and not seen[r.c] then seen[r.c]=true;classes=classes+1 end end
 end
 expect(n==7 and classes==7,'C3 '..seven..': seven counted rows of one copy, seven classes',n..'/'..classes)
 rows=rowsOf(sixPlus)
 local first,repeated={},{}
 for i,r in ipairs(rows) do
  if counted(r) then
   if first[r.c] then repeated[#repeated+1]={first[r.c],i} else first[r.c]=i end
  end
 end
 local pair=repeated[1]
 expect(#repeated==1 and rows[pair[1]].p==rows[pair[2]].p and rows[pair[1]].n==1 and rows[pair[2]].n==1,
  'C3 '..sixPlus..': one ID class repeats, on two separate one-copy rows of the same container',#repeated)
 rows=rowsOf(stack7)
 local big=0
 for _,r in ipairs(rows) do if counted(r) and r.n==7 and T.has(r.cm,T.COUNT_BIT.stacks) then big=big+1 end end
 expect(#rows==2 and big==1,'C3 '..stack7..': one counted row of seven copies by the stacks alias',#rows..'/'..big)
 -- Nested counting: the same class below a counted ancestor whose count equals
 -- the sum below it (an aggregate-shaped wrapper), against a different class
 -- whose count does not (a detail-shaped record). Neither is a native meaning.
 local function nested(name)
  local list=rowsOf(name)
  local out={}
  for i=1,#list do
   if counted(list[i]) then
    local anc=nearestCountedAncestor(list,i)
    if anc then
     out[anc]=out[anc] or {same=true,sum=0,n=list[anc].n}
     out[anc].same=out[anc].same and list[i].c==list[anc].c
     out[anc].sum=out[anc].sum+list[i].n
    end
   end
  end
  return out
 end
 local w=nested('a counted wrapper over same-ID members')[2]
 expect(w~=nil and w.same and w.sum==4 and w.n==4,'C3 counted wrapper: four same-class members below a counted row of four (entryId, count)',
  w and (tostring(w.same)..' '..w.sum..'/'..w.n))
 local d=nested('a counted record with a different-ID detail')[2]
 expect(d~=nil and d.same==false and d.sum==2 and d.n==5,'C3 detail record: a different class below a counted row, counts 5 and 2',
  d and (tostring(d.same)..' '..d.sum..'/'..d.n))
 local copiesRows,stackRows=rowsOf('two separate same-ID entries and a leaf'),rowsOf('one entry with stacks=2 and a leaf')
 local twoRows,oneRow=0,0
 for _,r in ipairs(copiesRows) do if counted(r) and r.n==1 and r.c==1 and r.cm==0 then twoRows=twoRows+1 end end
 for _,r in ipairs(stackRows) do if counted(r) and r.n==2 and r.cm==T.COUNT_BIT.stacks then oneRow=oneRow+1 end end
 expect(twoRows==2 and oneRow==1,'C3: two separate same-ID copies (two rows, default count) differ from one stacks=2 entry (one row)',
  twoRows..'/'..oneRow)
 rows=rowsOf('an ID-less wrapper with a count')
 local wrapper=rows[2] or {}
 local nestedCounted=0
 for i=1,#rows do if counted(rows[i]) and nearestCountedAncestor(rows,i) then nestedCounted=nestedCounted+1 end end
 expect(wrapper.n==0 and wrapper.c==0 and wrapper.cm==T.COUNT_BIT.count and nestedCounted==0,
  'C3 ID-less wrapper: its count alias is shown but it adds no copy, and no counted row sits below a counted one',
  T.rowText(wrapper)..' / '..nestedCounted)
 rows=rowsOf('alias forms, an invalid alias and two disagreeing ones')
 local inv,conflictId,conflictCount=rows[5] or {},rows[6] or {},rows[7] or {}
 expect(inv.c=='x' and inv.n==0 and inv.im==T.ID_BIT.spellID+T.ID_BIT.perkId and not T.has(inv.im,T.ID_BIT.entryId)
  and T.has(inv.e,T.DEFECT.invalid_value),
  'C3 aliases: the invalid row shows the aliases read up to the invalid one (spellID, perkId) and never the unread entryId',T.rowText(inv))
 expect(conflictId.c=='x' and conflictId.im==T.ID_BIT.spellId+T.ID_BIT.id and T.has(conflictId.e,T.DEFECT.conflicting_alias)
  and T.int(conflictCount.c) and conflictCount.c>=1 and conflictCount.cm==T.COUNT_BIT.stack+T.COUNT_BIT.count
  and conflictCount.n==0 and T.has(conflictCount.e,T.DEFECT.conflicting_alias),
  'C3 aliases: disagreeing ID aliases give class x; disagreeing count aliases keep the ID class but add no copy',
  T.rowText(conflictId)..' / '..T.rowText(conflictCount))
end)

-- C4. The gates read the same answers as before.
T.scenario('C4 gates',function()
 trusted()
 local refused=REFUSED[2]
 H.locked=refused.build()
 local ok,snap,why,stage=pcall(A.Orbs.Read)
 guard(ok and snap==nil and COUNT_REFUSAL.TrustRefusal(why) and stage=='trust_locked','C4: the Orb read refuses at its trust gate for the refused view',
  ok and (printable(why)..' / '..printable(stage)) or snap)
 H.locked=six()
 local okV,snapV,whyV,stageV=pcall(A.Orbs.Read)
 guard(okV and whyV~=TRUST and stageV~='trust_locked' and stageV~='trust_both' and stageV~='trust_owned',
  'C4: and passes it for six valid entries',okV and (printable(whyV)..' / '..printable(stageV)) or snapV)
 H.playerLevel=80
 local owned=A.Owned()
 local cat=A.Catalog()
 local plan={requestedCounts={[410002]=1,[410007]=1,[200001]=1},lockedRequestedCounts={[410007]=1,[200001]=1},
  explicitRoles=true,wishedFamilies={},targets={}}
 local function decide(locked)
  return Nexus.EchoWeaver.DecideNexus({plan=plan,owned=owned,locked=locked,level=80,horizon=40,ordinaryBoardAllowed=true,
   board={cards={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}},
   charges={banish=5,reroll=5,freeze=5,trustworthy=true},catalog=cat})
 end
 local lockedRefused=T.read(refused.build())
 local lockedValid=T.read({E(410007,{quality=2}),E(200001,{quality=1})})
 H.playerLevel=40
 guard(type(owned)=='table' and owned.synced==true,'C4: fixture: rolled ownership is trusted at the level cap',owned and owned.synced)
 local okD1,d1=pcall(decide,lockedRefused)
 guard(okD1 and type(d1)=='table' and d1.type=='wait' and d1.reason==WAIT_LOCKED,'C4: EchoWeaver keeps its locked wait for the refused view',
  okD1 and type(d1)=='table' and (printable(d1.type)..'/'..printable(d1.reason)) or d1)
 local okD2,d2=pcall(decide,lockedValid)
 guard(okD2 and type(d2)=='table' and d2.reason~=WAIT_LOCKED,'C4: and passes its locked gate for a valid view',
  okD2 and type(d2)=='table' and (printable(d2.type)..'/'..printable(d2.reason)) or d2)
 trusted()
end)

-- C5. The Echo snapshot (LockedFingerprint) parses the same source without a
-- collector: it neither captures nor replaces the capture, and its own field
-- acceptance and generation move exactly as before.
T.scenario('C5 the Echo snapshot path',function()
 trusted()
 local function reconcile(tree)
  H.locked=tree;H.now=H.now+1
  local before=T.lockedStats().calls or 0
  A.EchoActiveSlotGeneration()
  local st=A.EchoReconcileStats()
  return st.generations.locked,st.rejected.locked,(T.lockedStats().calls or 0)-before
 end
 local g0,r0,n0=reconcile(six())
 guard(r0==nil and n0==0,'C5: fixture: the snapshot accepts six valid entries, with no normal locked read',printable(r0)..'/'..n0)
 H.now=H.now+1
 local _,d=T.read(REFUSED[2].build())
 local v0=T.shape()
 local rec0=T.record(v0)
 expect(type(v0)=='table' and v0.observed==true and v0.serial==d.serial,'C5: fixture: the normal read is captured',facts(v0,{'observed','serial'}))
 local g1,r1,n1=reconcile(REFUSED[2].build())
 guard(r1=='locked:read' and g1==g0+1 and n1==0,'C5: the snapshot rejects the refused source as before and moves its generation once',
  printable(r1)..' '..printable(g0)..'->'..printable(g1))
 local g2,r2,n2=reconcile(REFUSED[1].build())
 guard(r2=='locked:read' and g2==g1+1 and n2==0,'C5: another refused source moves it once more',printable(r2)..' '..printable(g2))
 local g3,r3,n3=reconcile(REFUSED[1].build())
 guard(r3=='locked:read' and g3==g2 and n3==0,'C5: an identical refused source does not move it',printable(r3)..' '..printable(g3))
 local v1=T.shape()
 expect(type(v1)=='table' and T.record(v1)==rec0 and v1.current==true and v1.laterReads==0,
  'C5: the snapshot reads neither replace the capture nor count as later locked reads',facts(v1,{'serial','current','laterReads'}))
 local g4,r4,n4=reconcile(six())
 guard(r4==nil and g4==g3+1 and n4==0,'C5: an accepted source moves it once and is not rejected',printable(r4)..' '..printable(g4))
 local v2=T.shape()
 expect(type(v2)=='table' and T.record(v2)==rec0,'C5: the capture is still the normal read')
 trusted()
end)

T.finish('locked_shape_capture')
