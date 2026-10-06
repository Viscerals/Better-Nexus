-- Locked-shape capture, part 4 of 4 (tests-first): honest correlation. The
-- capture keeps the serial, time and generation of its own read; later reads
-- make it "not current" without rewriting it; the Orb observation carries the
-- serial of the locked read it saw, so a report can tell whether the capture is
-- that read.
-- At 5a8299c there is no capture, OwnershipTrustView has no lockedSerial and the
-- Orb observation can be tied to the locked sample only by age (source reading).
-- Contract: TEST_CONTRACT.md of the locked-shape tests-first phase, sections 1-3, 5 and 6.
-- Sequences: refused then accepted; refused then a new refused shape; refused,
-- then unreadable, absent and not_table; a run boundary; rolled reads and
-- collection; one normal Orb window read, then a newer refused read; a reload.
-- The Orb trust gate and the ordinary-board gate are guards.
-- Real TOC boot and modules, Orb runtime and window; the fake services of
-- orbs_support.lua; artificial IDs and names (markers ZQ_). No Orb run is started
-- and nothing is spent, selected or locked. Every check is evaluated; the test
-- prints a summary and fails at the end if any check failed.
local H,T=dofile('tests/prototype/locked_shape_support.lua')
local A,O=H.A,H.O
local expect,guard,printable=T.expect,T.guard,T.printable

H.now=math.floor(H.now)+100
local BASE_GRANTED=H.Clone(H.granted)
local TRUST='Waiting for current rolled and locked Echo data from the server.'
local PLAN='ZQ plan alpha'
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
local function sixPlus() local t=six();t[7]=E(410001,{quality=1});return t end
local function seven() local t=six();t[7]=E(410007,{quality=2});return t end
local function stack7() return {E(410007,{quality=2,stacks=7})} end
local function facts(t,keys)
 if type(t)~='table' then return printable(t) end
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=k..'='..printable(t[k]) end
 return table.concat(out,' ')
end
-- One normal Orb window read: open, refresh, close.
local function observe()
 local ok,s=T.realPcall(function()
  Nexus.OrbPanel.Show();local snap=NexusOrbPanel.snapshot;NexusOrbPanel:Hide();return snap
 end)
 return ok and s or nil
end

-- An active populated Saved Build whose Wishlist resolves through its
-- association, so that the Orb window read reaches its trust gate.
H.perks.serverBuildSlots={[1]={name='ZQ build one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
local okPlan,whyPlan=A.SetLoadoutWishlistIdentity(1,PLAN,{{spellId=410002,quality=2,stacks=1}})
guard(okPlan and true or false,'fixture: slot 1 resolves its Wishlist through its association',whyPlan)

local Q={}

-- Q1. A refused read is the current capture; the ownership sample carries the
-- same serial.
T.scenario('Q1 a refused read is the current capture',function()
 trusted()
 H.now=H.now+10
 local l,d,err=T.read(stack7())
 local t=T.trust() or {}
 guard(l~=nil and l.synced==false and t.lockedRejection=='over_cap','Q1: fixture: the normal read is refused (over_cap)',
  err or t.lockedRejection)
 local w=T.shape() or {}
 expect(w.observed==true and w.serial==d.serial and w.current==true and w.laterReads==0 and w.age==0,
  'Q1: it is captured as the current read, age 0',facts(w,{'observed','serial','current','laterReads','age'}))
 expect(t.lockedSerial==d.serial,'Q1: OwnershipTrustView() carries the serial of its locked sample',t.lockedSerial)
 local text=T.prepared()
 local s=T.checkBlock('Q1',text,{'ZQ_'})
 expect(s.serial==T.fmt(d.serial) and s.current=='yes' and s['later.reads']=='0' and T.ageValue(s.age)==0,
  'Q1: the report shows the serial, current=yes, later.reads=0 and age 0',facts(s,{'serial','current','later.reads','age'}))
 local o=T.tokens(T.lines(text,'Ownership sample'))
 if o['locked.serial']~=nil then
  expect(o['locked.serial']==T.fmt(d.serial),'Q1: an ownership locked.serial, when shown, is the sample serial',o['locked.serial'])
 end
 Q.s1,Q.t1=d.serial,H.now
end)

-- Q2. A later accepted read keeps the capture as it was, but no longer current.
T.scenario('Q2 a later accepted read',function()
 H.now=H.now+30
 local l,d,err=T.read(six())
 local t=T.trust() or {}
 guard(l~=nil and l.synced==true and t.lockedSynced==true and t.lockedRejection=='none','Q2: fixture: the later read is trusted',
  err or t.lockedRejection)
 local w=T.shape() or {}
 expect(w.serial==Q.s1 and w.at==Q.t1 and w.current==false and w.laterReads==1 and w.age==30 and w.copies==7 and w.ids==1,
  'Q2: the capture keeps its read, time and facts: current=no, one later read, age 30',
  facts(w,{'serial','at','current','laterReads','age','copies','ids'}))
 expect(t.lockedSerial==d.serial and Q.s1~=nil and d.serial==Q.s1+1,'Q2: the ownership sample is the later read, one serial on',
  printable(t.lockedSerial))
 local text=T.prepared()
 local s=T.checkBlock('Q2',text,{'ZQ_'})
 expect(s.serial==T.fmt(Q.s1) and s.current=='no' and s['later.reads']=='1' and T.ageValue(s.age)==30,
  'Q2: the report keeps the old capture apart: current=no, later.reads=1, age 30',facts(s,{'serial','current','later.reads','age'}))
 local o=T.tokens(T.lines(text,'Ownership sample'))
 guard(o['locked.synced']=='yes' and o['locked.rejection']=='none' and T.ageValue(o['locked.age'])==0,
  'Q2: the ownership block shows the later, trusted read with its own age',facts(o,{'locked.synced','locked.rejection','locked.age'}))
end)

-- Q3. A later refused read with another shape replaces the capture.
T.scenario('Q3 a later refused read replaces the capture',function()
 H.now=H.now+10
 local _,d=T.read(seven())
 local w=T.shape() or {}
 expect(w.serial==d.serial and w.current==true and w.at==H.now and w.rows==8 and w.ids==7 and w.copies==7 and w.first=='over_cap',
  'Q3: the newer refused read, with another shape, replaces the capture',facts(w,{'serial','current','rows','ids','copies','first'}))
 Q.s3,Q.t3=d.serial,H.now
end)

-- Q4. Refusals of a non-table value keep the capture and only count as later
-- reads; no getter error text reaches the report.
T.scenario('Q4 non-table refusals keep the capture',function()
 local svc=ProjectEbonhold.PerkService
 local real=svc.GetLockedPerks
 H.now=H.now+5
 svc.GetLockedPerks=function() error('ZQ_GETTER_MARKER Disposable A 410001',0) end
 local okU,lu=T.realPcall(A.LockedOwned)
 svc.GetLockedPerks=real
 local t=T.trust() or {}
 guard(okU and type(lu)=='table' and lu.synced==false and t.lockedRejection=='unreadable',
  'Q4: fixture: the getter raised, so the read is refused as unreadable',t.lockedRejection)
 local w=T.shape() or {}
 expect(w.serial==Q.s3 and w.at==Q.t3 and w.current==false and w.laterReads==1 and w.rows==8,
  'Q4 unreadable: the capture is kept, no longer current',facts(w,{'serial','current','laterReads','rows'}))
 local la=T.read(nil)
 t=T.trust() or {}
 guard(la~=nil and la.synced==false and t.lockedRejection=='absent','Q4: fixture: an absent locked value is refused as absent',
  t.lockedRejection)
 local ln=T.read(5)
 t=T.trust() or {}
 guard(ln~=nil and ln.synced==false and t.lockedRejection=='not_table','Q4: fixture: a number is refused as not_table',t.lockedRejection)
 w=T.shape() or {}
 expect(w.serial==Q.s3 and w.at==Q.t3 and w.laterReads==3 and w.rows==8 and w.first=='over_cap',
  'Q4: absent and not_table reads keep it too, as three later reads',facts(w,{'serial','laterReads','rows','first'}))
 local s,all=T.checkBlock('Q4',T.prepared(),{'ZQ_'})
 expect(#all>0 and s.current=='no' and s['later.reads']=='3' and s.serial==T.fmt(Q.s3),
  'Q4: the report shows the kept capture with three later reads',facts(s,{'current','later.reads','serial'}))
 H.locked={}
end)

-- Q5. A run boundary moves the current generation, not the sampled one. The
-- generation is context only: it is no locked validity rule.
T.scenario('Q5 sampled and current generation',function()
 trusted()
 local g=(T.trust() or {}).ownedGeneration
 H.now=H.now+5
 local _,d=T.read(sixPlus())
 H.holdGrantedResponse=true
 A.RunBoundaryReset()
 local t=T.trust() or {}
 guard(T.int(g) and t.ownedGeneration==g+1 and t.ownedConfirmed==false,
  'Q5: fixture: a run boundary moved the current generation, unconfirmed',printable(g)..' -> '..facts(t,{'ownedGeneration','ownedConfirmed'}))
 local w=T.shape() or {}
 expect(T.int(g) and w.serial==d.serial and w.sampledGeneration==g and w.currentGeneration==g+1 and w.current==true,
  'Q5: the capture keeps its sampled generation apart from the current one; the boundary is no locked read',
  facts(w,{'serial','sampledGeneration','currentGeneration','current'}))
 local text=T.prepared()
 local s=T.checkBlock('Q5',text,{'ZQ_'})
 expect(T.int(g) and s['sampled.generation']==T.fmt(g) and s['current.generation']==T.fmt(g+1),
  'Q5: the report shows both generations',facts(s,{'sampled.generation','current.generation'}))
 local o=T.tokens(T.lines(text,'Ownership sample'))
 guard(T.int(g) and o['current.generation']==T.fmt(g+1) and o['current.confirmed']=='no',
  'Q5: the ownership block shows the new, unconfirmed generation',facts(o,{'current.generation','current.confirmed'}))
 H.now=H.now+1
 local lv=T.read(six())
 guard(lv~=nil and lv.synced==true,'Q5: a valid locked view after the boundary is trusted as before',lv and lv.synced)
 local w2=T.shape() or {}
 expect(w2.serial==d.serial and w2.current==false and T.int(g) and w2.sampledGeneration==g,
  'Q5: and the capture stays the earlier read, with its own generation',facts(w2,{'serial','current','sampledGeneration'}))
 trusted()
end)

-- Q6. A normal rolled read, the views and the report do not refresh the capture.
T.scenario('Q6 rolled reads and collection do not refresh the capture',function()
 trusted()
 H.now=H.now+5
 local _,d=T.read(sixPlus())
 local rec=T.record(T.shape())
 H.now=H.now+20
 A.Owned();T.trust();T.readiness();T.prepared();Nexus.SupportReport.Summary()
 local w=T.shape()
 expect(type(w)=='table' and w.serial==d.serial and T.record(w)==rec and w.current==true and w.laterReads==0 and w.age==20,
  'Q6: they leave the capture as it was, still current; only its age grows',facts(w,{'serial','current','laterReads','age'}))
end)

-- Q7. One normal Orb window read refused at the trust gate: the observation
-- carries the serial of its locked read, which is the capture. A newer refused
-- read then replaces the capture, which no longer explains that Orb refusal.
T.scenario('Q7 the Orb window read and the capture',function()
 trusted()
 H.now=H.now+5
 H.locked=sixPlus()
 local snap=observe()
 guard(type(snap)=='table' and snap.error==TRUST and snap.progress==nil,'Q7: fixture: the window read waits at the trust gate',
  snap and snap.error)
 local r=T.readiness() or {}
 guard(r.observed==true and r.stage=='trust_locked' and r.lockedRejection=='over_cap',
  'Q7: fixture: the observation records the trust_locked stage',facts(r,{'observed','stage','lockedRejection'}))
 local t=T.trust() or {}
 local w=T.shape() or {}
 expect(T.int(r.lockedSerial) and r.lockedSerial==t.lockedSerial,'Q7: the Orb observation carries the serial of the last locked read',
  printable(r.lockedSerial)..' vs '..printable(t.lockedSerial))
 expect(w.observed==true and T.int(r.lockedSerial) and w.serial==r.lockedSerial and w.current==true,'Q7: the capture is that read',
  facts(w,{'serial','current'}))
 local text=T.prepared()
 local rt=T.tokens(T.lines(text,'Orb readiness'))
 local st=T.checkBlock('Q7',text,{'ZQ_'})
 expect(rt['locked.serial']~=nil and rt['locked.serial']==T.fmt(r.lockedSerial) and st.serial==rt['locked.serial'],
  'Q7: the report ties them: the readiness locked.serial equals the shape serial',
  printable(rt['locked.serial'])..' / '..printable(st.serial))
 local at0=r.at
 H.now=H.now+10
 local _,d2=T.read(stack7())
 local r2=T.readiness() or {}
 local w2=T.shape() or {}
 guard(r2.at==at0 and r2.stage=='trust_locked' and r2.age==10,'Q7: the Orb observation is kept as it was, 10 s old',
  facts(r2,{'at','stage','age'}))
 expect(w2.serial==d2.serial and w2.age==0 and T.int(r2.lockedSerial) and r2.lockedSerial==r.lockedSerial
  and w2.serial~=r2.lockedSerial,'Q7: a newer refused read replaces the capture, which is then not the read of that Orb refusal',
  facts(w2,{'serial','age'})..' readiness '..printable(r2.lockedSerial))
 local text2=T.prepared()
 local rt2=T.tokens(T.lines(text2,'Orb readiness'))
 local st2=T.checkBlock('Q7 later',text2,{'ZQ_'})
 expect(rt2['locked.serial']~=nil and st2.serial~=nil and rt2['locked.serial']~=st2.serial,
  'Q7 later: the report shows two different serials',printable(rt2['locked.serial'])..' / '..printable(st2.serial))
 expect(T.ageValue(rt2.age)==10 and T.ageValue(st2.age)==0,'Q7 later: each with its own age',
  printable(rt2.age)..' / '..printable(st2.age))
 trusted()
end)

-- Q8. The gates read the same answers with a capture present.
T.scenario('Q8 gates',function()
 trusted()
 local allowed0=T.serialize({A.OrdinaryBoardAllowed()})
 H.now=H.now+5
 H.locked=sixPlus()
 local ok,snap,why,stage=T.realPcall(A.Orbs.Read)
 guard(ok and snap==nil and why==TRUST and stage=='trust_locked','Q8: the Orb read waits at its trust gate',
  ok and (printable(why)..' / '..printable(stage)) or snap)
 local w=T.shape() or {}
 expect(w.observed==true and w.current==true and w.first=='over_cap' and w.copies==7,
  "Q8: the Orb read's own normal locked read is the capture",facts(w,{'observed','current','first','copies'}))
 T.prepared()
 guard(T.serialize({A.OrdinaryBoardAllowed()})==allowed0,'Q8: the ordinary-board gate is unchanged by the capture and the report',
  allowed0)
 trusted()
end)

-- Q9. A reload (a freshly loaded adapter) has observed nothing.
T.scenario('Q9 a reload has observed nothing',function()
 H.now=H.now+5
 T.read(sixPlus())
 local live=T.shape() or {}
 local pristine,perr=T.pristineAdapter()
 guard(type(pristine)=='table','Q9: fixture: a pristine adapter instance loads in its own sandbox',perr)
 pristine=type(pristine)=='table' and pristine or {}
 local pv,pwhy=T.call(pristine.LockedShapeView)
 local pt=T.call(pristine.OwnershipTrustView) or {}
 expect(live.observed==true and pv~=nil and pv.observed==false,
  'Q9: while the live adapter holds a capture, a freshly loaded one has observed none',
  printable(live.observed)..' / '..printable(pwhy or (pv and pv.observed)))
 guard(pt.lockedObserved==false and pt.lockedSerial==nil,'Q9: nor a locked sample or serial',facts(pt,{'lockedObserved','lockedSerial'}))
 trusted()
end)

T.finish('locked_shape_correlation')
