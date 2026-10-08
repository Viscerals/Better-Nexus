-- Orb count refusal, part 2 of 2: honest fallbacks. The truthful over-cap text of
-- orb_count_refusal_truthful belongs to one case only: the CURRENT normal locked
-- read was refused for its count, rolled ownership is trusted, and the Orb read
-- refuses at stage trust_locked. Everywhere else the Orb read keeps its existing
-- refusal, the shared wait, at its existing stage, and a stale, mismatched or
-- failing diagnostic sample never decides the text and never opens a gate.
-- All checks are GUARD checks: they hold at b704660 and must keep holding after
-- the over-cap text is repaired. Cases:
--  F1 rolled ownership not confirmed for this run, with the locked view over
--     the cap (trust_both) and at the cap (trust_owned);
--  F2 unreadable and malformed locked returns (getter raises, nil, a number,
--     an invalid ID, conflicting count names, a scalar leaf, a cycle, too deep)
--     right after a real window read of the over-cap view, whose readiness
--     observation and, for a non-table value, locked capture are then stale;
--  F3 frozen diagnostic accessors that keep answering with the over-cap sample
--     (a stale serial) while the current locked read is refused for another
--     reason;
--  F4 diagnostic accessors that claim over_cap with a missing or malformed
--     serial (mismatched) while the current locked read is refused for another
--     reason;
--  F5 diagnostic accessors that throw: the read neither raises nor opens; with
--     another refusal reason it keeps the shared wait, and over the cap it
--     answers one of the two honest texts;
--  F6 a now-valid locked view after an over-cap read, also with a frozen
--     over-cap sample: the stale sample neither blocks nor explains anything.
-- The only fault injection replaces the passive diagnostic accessors
-- (GameAdapter.OwnershipTrustView, GameAdapter.LockedShapeView,
-- OrbRuntime.ReadinessView) inside F3-F6 and restores them; F2 replaces the
-- fake game getter for its raising case only. The read under test is always the
-- real OrbAdapter.Read and the real Orb window. Real TOC boot and modules; the
-- fake services of orbs_support.lua; artificial IDs and names. No Orb run is
-- started; nothing is spent, selected or locked.
local H,T=dofile('tests/prototype/locked_shape_support.lua')
local R=dofile('tests/prototype/orb_count_refusal_support.lua')
local A,O,M=H.A,H.O,H.M
local printable=R.printable
local C=R.Checker('orb_count_refusal_fallbacks',T.realPcall)
local X=R.Fixture(H,T)

H.now=math.floor(H.now)+100
local okPlan,whyPlan=X.Assign()
C.setup(okPlan and true or false,'fixture: slot 1 resolves its Wishlist through its association',whyPlan)
X.Trusted()
C.setup(A.AssignedWishlist().state=='ready','fixture: the assignment is ready',A.AssignedWishlist().state)
local ACTIONS={'orb-spend','take','banish','freeze','reroll','lock','unlock'}
local function kinds()
 local n=0
 for _,k in ipairs(ACTIONS) do n=n+H.Count(k) end
 return n
end
local ACTIONS0=kinds()
local REAL={trust=A.OwnershipTrustView,shape=A.LockedShapeView,readiness=M.ReadinessView}
local function restoreAccessors()
 A.OwnershipTrustView,A.LockedShapeView,M.ReadinessView=REAL.trust,REAL.shape,REAL.readiness
end
local function noMarker(v) return not printable(v):find('ZQ_',1,true) end
-- The real sample of the last locked read (never an injected accessor).
local function realSample() local ok,v=T.realPcall(REAL.trust);return ok and type(v)=='table' and v or {} end

-- Locked returns refused for a reason other than the count, all within the cap.
local OTHER={
 {'unreadable','unreadable','raise'},
 {'absent','absent',function() return nil end},
 {'not a table','not_table',function() return 5 end},
 {'invalid ID','invalid_value',function() return X.Invalid() end},
 {'conflicting count names','conflicting_alias',function() return {{spellId=410007,stack=1,count=2}} end},
 {'scalar leaf','scalar_leaf',function() return {{spellId=410007},{note='ZQ_NOTE_MARKER'}} end},
 {'cycle','cycle',function() local t={{spellId=410007}};t[2]=t;return t end},
 {'too deep','depth',function() local d={spellId=410007};for _=1,9 do d={d} end;return d end},
}
local GETTER_MARKER='ZQ_GETTER_MARKER 410001'
-- Put one OTHER case in place; returns the function that undoes it.
local function apply(case)
 local svc=ProjectEbonhold.PerkService
 local real=svc.GetLockedPerks
 if case[3]=='raise' then
  svc.GetLockedPerks=function() error(GETTER_MARKER,0) end
 else
  H.locked=case[3]()
 end
 return function() svc.GetLockedPerks=real end
end
-- One real Orb read and one real window read of the current state.
local function readBoth()
 local ok,snap,why,stage=X.Read()
 local sample=realSample()
 local s,shown=X.Window()
 return {ok=ok,snap=snap,why=why,stage=stage,sample=sample,window=s,shown=shown}
end
local function keepsWait(tag,got,stage)
 C.guard(got.ok and got.snap==nil and got.stage==stage and got.why==R.FALLBACK,
  tag..': the Orb read keeps the shared wait at stage '..stage,printable(got.stage)..' / '..printable(got.why))
 local s=got.window
 C.guard(type(s)=='table' and s.error==R.FALLBACK and s.progress==nil,tag..': and so does the Orb window, with no progress',
  type(s)=='table' and s.error or (got.shown and got.shown.error))
 C.guard(noMarker(got.why) and noMarker(type(s)=='table' and s.error),tag..': no getter, data or accessor text reaches the refusal')
end

-- F1. Rolled ownership not confirmed for this run.
C.scenario('F1 rolled ownership not confirmed',function()
 X.Trusted()
 H.holdGrantedResponse=true;A.RunBoundaryReset()
 C.setup(A.Owned().synced==false,'F1: fixture: after a run boundary the same rolled mirror is not confirmed')
 for _,case in ipairs({{'locked view over the cap',X.Over,'trust_both','over_cap'},{'locked view at the cap',X.AtCap,'trust_owned','none'}}) do
  H.now=H.now+1
  H.locked=case[2]()
  local got=readBoth()
  C.setup(got.sample.lockedRejection==case[4],'F1 '..case[1]..': fixture: the locked sample is '..case[4],got.sample.lockedRejection)
  keepsWait('F1 '..case[1],got,case[3])
 end
 X.Trusted()
 C.setup(A.Owned().synced==true,'F1: fixture: rolled ownership is trusted again')
end)

-- F2. Another refusal reason right after a real window read of the over-cap view.
C.scenario('F2 unreadable and malformed locked returns after an over-cap read',function()
 for _,case in ipairs(OTHER) do
  local tag='F2 '..case[1]
  X.Trusted()
  H.now=H.now+5
  H.locked=X.Over()
  local s0=X.Window()
  local r0=T.readiness() or {}
  C.setup(type(s0)=='table' and r0.stage=='trust_locked' and r0.lockedRejection=='over_cap' and T.int(r0.lockedSerial),
   tag..': fixture: an earlier window read saw the over-cap view',printable(r0.stage)..'/'..printable(r0.lockedRejection))
  H.now=H.now+1
  local undo=apply(case)
  local ok,snap,why,stage=X.Read()
  local sample=realSample()
  local stale=T.readiness() or {}
  local shape=T.shape() or {}
  local s,shown=X.Window()
  undo()
  C.setup(sample.lockedRejection==case[2] and T.int(sample.lockedSerial) and T.int(r0.lockedSerial)
   and sample.lockedSerial>r0.lockedSerial,tag..': fixture: the current locked read is refused as '..case[2],
   printable(sample.lockedRejection))
  C.setup(stale.lockedRejection=='over_cap' and stale.lockedSerial==r0.lockedSerial,
   tag..': fixture: the readiness observation still holds the earlier over-cap read (stale)',printable(stale.lockedSerial))
  if not T.TABLE_REJECTIONS[case[2]] then
   C.setup(shape.observed==true and shape.first=='over_cap' and shape.current==false,
    tag..': fixture: the locked capture is still the earlier over-cap read, no longer current',
    printable(shape.first)..'/'..printable(shape.current))
  end
  keepsWait(tag,{ok=ok,snap=snap,why=why,stage=stage,window=s,shown=shown},'trust_locked')
 end
 X.Trusted()
end)

-- F3. Frozen (stale) diagnostic accessors keep answering with the over-cap read.
C.scenario('F3 a frozen over-cap sample with a stale serial',function()
 X.Trusted()
 H.now=H.now+5
 H.locked=X.Over()
 X.Window()
 local frozen={trust=T.trust(),shape=T.shape(),readiness=T.readiness()}
 C.setup(type(frozen.trust)=='table' and frozen.trust.lockedRejection=='over_cap'
  and type(frozen.shape)=='table' and frozen.shape.first=='over_cap' and frozen.shape.current==true
  and type(frozen.readiness)=='table' and frozen.readiness.lockedRejection=='over_cap',
  'F3: fixture: the accessors hold the over-cap read')
 A.OwnershipTrustView=function() return H.Clone(frozen.trust) end
 A.LockedShapeView=function() return H.Clone(frozen.shape) end
 M.ReadinessView=function() return H.Clone(frozen.readiness) end
 for _,i in ipairs({1,2,4}) do
  local case=OTHER[i]
  local tag='F3 '..case[1]
  H.now=H.now+1
  local undo=apply(case)
  local got=readBoth()
  undo()
  C.setup(got.sample.lockedRejection==case[2] and T.int(got.sample.lockedSerial)
   and got.sample.lockedSerial~=frozen.trust.lockedSerial,tag..': fixture: the real current read is refused as '..case[2]
   ..', with a newer serial than the frozen one',printable(got.sample.lockedRejection))
  keepsWait(tag,got,'trust_locked')
 end
 restoreAccessors()
 X.Trusted()
end)

-- F4. Accessors that claim over_cap with a missing or malformed serial.
C.scenario('F4 an over-cap claim with a mismatched serial',function()
 X.Trusted()
 for _,bad in ipairs({{'missing',nil},{'zero',0},{'negative',-1},{'fraction',2.5},{'text','7'},
  {'not a number',0/0},{'infinite',math.huge}}) do
  local tag='F4 serial '..bad[1]
  A.OwnershipTrustView=function()
   local v=REAL.trust()
   v.lockedObserved,v.lockedSynced,v.lockedRejection,v.lockedCopies,v.lockedSerial=true,false,'over_cap',7,bad[2]
   return v
  end
  A.LockedShapeView=function()
   local v=REAL.shape()
   v.observed,v.first,v.copies,v.status,v.current,v.laterReads,v.serial=true,'over_cap',7,'captured',true,0,bad[2]
   return v
  end
  for _,i in ipairs({2,4}) do
   local case=OTHER[i]
   H.now=H.now+1
   local undo=apply(case)
   local got=readBoth()
   undo()
   C.setup(got.sample.lockedRejection==case[2],tag..' / '..case[1]..': fixture: the real current read is refused as '..case[2],
    printable(got.sample.lockedRejection))
   keepsWait(tag..' / '..case[1],got,'trust_locked')
  end
  restoreAccessors()
 end
 X.Trusted()
end)

-- F5. Diagnostic accessors that throw.
C.scenario('F5 diagnostic accessors that throw',function()
 X.Trusted()
 local function throwing()
  A.OwnershipTrustView=function() error('ZQ_TRUST_THROW_MARKER',0) end
  A.LockedShapeView=function() error('ZQ_SHAPE_THROW_MARKER',0) end
  M.ReadinessView=function() error('ZQ_READINESS_THROW_MARKER',0) end
 end
 for _,i in ipairs({2,4}) do
  local case=OTHER[i]
  local tag='F5 '..case[1]
  H.now=H.now+1
  local undo=apply(case)
  throwing()
  local got=readBoth()
  restoreAccessors()
  undo()
  C.setup(got.sample.lockedRejection==case[2],tag..': fixture: the real current read is refused as '..case[2],
   printable(got.sample.lockedRejection))
  keepsWait(tag,got,'trust_locked')
 end
 -- Over the cap: still refused at trust_locked, no raise, one of the two honest texts.
 H.now=H.now+1
 H.locked=X.Over()
 throwing()
 local got=readBoth()
 restoreAccessors()
 C.setup(got.sample.lockedRejection=='over_cap','F5 over the cap: fixture: the real current read is over the cap')
 C.guard(got.ok and got.snap==nil and got.stage=='trust_locked' and R.TrustRefusal(got.why),
  'F5 over the cap: the read neither raises nor opens; it answers the shared wait or the truthful count refusal',
  printable(got.stage)..' / '..printable(got.why))
 local s=got.window
 C.guard(type(s)=='table' and s.progress==nil and s.error==got.why,'F5 over the cap: the window shows the same refusal, with no progress',
  type(s)=='table' and s.error or (got.shown and got.shown.error))
 C.guard(noMarker(got.why) and noMarker(type(s)=='table' and s.error),'F5 over the cap: no accessor error text reaches the refusal')
 X.Trusted()
end)

-- F6. A stale over-cap sample neither blocks nor explains a now-valid read.
C.scenario('F6 a now-valid locked view after an over-cap read',function()
 X.Trusted()
 H.now=H.now+5
 H.locked=X.Over()
 X.Window()
 local frozen={trust=T.trust(),shape=T.shape(),readiness=T.readiness()}
 for _,inject in ipairs({false,true}) do
  local tag='F6 '..(inject and 'with a frozen over-cap sample' or 'after the over-cap read')
  if inject then
   A.OwnershipTrustView=function() return H.Clone(frozen.trust) end
   A.LockedShapeView=function() return H.Clone(frozen.shape) end
   M.ReadinessView=function() return H.Clone(frozen.readiness) end
  end
  H.now=H.now+1
  H.locked=X.AtCap()
  local got=readBoth()
  restoreAccessors()
  C.setup(got.sample.lockedRejection=='none' and got.sample.lockedCopies==6,tag..': fixture: the real current read is trusted (6 copies)',
   printable(got.sample.lockedRejection))
  C.guard(got.ok and type(got.snap)=='table' and got.why==nil and got.stage==nil,tag..': the Orb read passes its trust gate',
   printable(got.stage)..' / '..printable(got.why))
  local s=got.window
  C.guard(type(s)=='table' and s.progress~=nil and s.error==nil,tag..': and the Orb window shows progress',
   type(s)=='table' and s.error or (got.shown and got.shown.error))
 end
 X.Trusted()
end)

restoreAccessors()
C.guard(kinds()==ACTIONS0,'no Orb was spent and nothing was taken, banished, frozen, rerolled, locked or unlocked',kinds()-ACTIONS0)
C.guard(not A.Orbs.IsOwned(),'no Orb action owner exists')
C.finish('(outside the current over-cap read the Orb read keeps its honest refusal; stale or failing diagnostics decide nothing)')
