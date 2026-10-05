-- D1: one Echo field the strict snapshot check rejects must not freeze every
-- Echo generation.
--
-- GameAdapter.ReconcileEchoState fingerprints five client mirrors (slots,
-- granted, locked, discovery+disabled levers, active slot) with strict
-- validation. Before this change any rejected field made the whole capture
-- fail BEFORE any generation moved. The getters (Owned, Slots, LockedOwned)
-- are lenient and stayed fresh, but every reader keyed on the generations kept
-- the last accepted reading as current: the HUD progress, the Wishlist overlay
-- and the Journal association refresh froze until a reload, and the five-second
-- fallback repaired (a full step) every five seconds for as long as it lasted.
--
-- Required now: a rejected field is reported as rejected, with its reason; the
-- other fields still advance; the rejected field's own generation moves when
-- its source moves (into, within and out of rejection) and NOT on repeated
-- identical rejections; nothing is accepted from it (no ownership
-- confirmation, locked evidence stays fail-closed); roles are unchanged.
local S=dofile('tests/prototype/progress_refresh_support.lua')
local C=S.Checker('echo_snapshot_rejected_field')
local check=C.check
local A

local W=S.Rows(S.Ordinary(1,79))
local function Slots()
 return {[2]={name='Build Two',verified=true,echoes=S.SlotRows(S.GA)},
  [5]={name='Build Five',verified=true,echoes=S.SlotRows(S.GB)},
  [101]={name='Synthetic W',verified=false,echoes=S.Copy(W)}}
end
local BASE={granted=S.GA,active=2,locked={},
 associations={[2]=S.Association(101,'Synthetic W',W),[5]=S.Association(101,'Synthetic W',W)}}
local function Boot(before)
 local o=S.Copy(BASE);o.slots=Slots();o.before=before
 local H=S.Boot(o);A=Nexus.GameAdapter
 return H
end
local function Rejected() return A.EchoReconcileStats().rejected or {} end
local function At(h,owned) return h.owned==owned and h.total==79 end
-- Switch from loadout 2 (40/79) to loadout 5 (35/79): the client replaces the
-- granted mirror and the active slot; `extra` adds the variant's field.
local function Switch(H,extra,notify)
 H.perks.serverActiveSlot=5;H.granted=S.Granted(S.GB)
 if extra then extra(H) end
 if notify~=false then H.Notify() end
end

-- A lever whose member is not on W (the disabled-lever part of the snapshot).
local function WithLever(h) h.db[200090].requiredSpell=300001 end

local SHAPES={
 {id='discovery false marker',field='discovery',reason='discovery:key',
  apply=function(H) H.discovered[200001]=false end},
 {id='slot echo locked=0',field='slots',reason='slots:echo',
  apply=function(H) H.perks.serverBuildSlots[5].echoes[1].locked=0 end},
 {id='slot verified=1',field='slots',reason='slots:verified',
  apply=function(H) H.perks.serverBuildSlots[5].verified=1 end},
 {id='granted entry without spellId',field='granted',reason='granted:entry',
  apply=function(H) H.granted['Placeholder']={{quality=0}} end},
 {id='disabled lever answer not boolean',field='discovery',reason='disabled:value',before=WithLever,
  apply=function(H) H.service.IsTomeEchoDisabled=function() return nil end end},
}

-- 0. Control: a well-formed switch reaches the HUD at once.
do
 local H=Boot()
 check(At(S.Hud(),40),'control: baseline 40/79: '..S.Text(S.Hud()))
 Switch(H)
 check(S.Within(H,1,function() return At(S.Hud(),35) end)~=nil,'control: a well-formed notified switch shows 35/79 within 1 s: '..S.Text(S.Hud()))
 check(next(Rejected())==nil,'control: nothing is reported rejected')
end

-- 1. Each rejected shape arriving WITH the switch, notified.
for _,shape in ipairs(SHAPES) do
 local tag=shape.id
 local H=Boot(shape.before)
 Nexus.WishlistOverlay.Show();H.Advance(1.5)
 check(At(S.Hud(),40) and S.OverlayComplete()==40,tag..': baseline HUD 40/79, overlay 40 complete: '..S.Text(S.Hud())..' overlay '..S.OverlayComplete())
 local journal=S.CountJournalRefreshes()
 local g0=S.Copy(A.EchoReconcileStats().generations)
 Switch(H,shape.apply)
 local t=S.Within(H,1,function() return At(S.Hud(),35) end)
 journal.restore()
 local g1=A.EchoReconcileStats().generations
 check(Rejected()[shape.field]==shape.reason,tag..': the '..shape.field..' field is reported rejected ('
  ..tostring(shape.reason)..'), got '..tostring(Rejected()[shape.field]))
 check(t~=nil,tag..': the HUD shows 35/79 within 1 s: '..S.Text(S.Hud()))
 check(S.Hud().owned==S.GetterHave(W),tag..': the HUD equals the fresh ownership getter: HUD '
  ..tostring(S.Hud().owned)..' getter '..S.GetterHave(W))
 H.Advance(1.5)
 check(S.OverlayComplete()==35,tag..': the overlay follows: '..S.OverlayComplete()..' complete rows')
 check(journal.n>=1,tag..': the Journal association refresh runs for the active-slot change: '..journal.n)
 check(g1.activeSlot==g0.activeSlot+1,tag..': the active-slot generation advanced once: '
  ..tostring(g0.activeSlot)..' -> '..tostring(g1.activeSlot))
 check(g1.granted>g0.granted,tag..': the granted generation advanced')
end

-- 2. Silent: the same shape and switch with no client notification.
do
 local H=Boot()
 Switch(H,SHAPES[1].apply,false)
 check(S.Within(H,5.5,function() return At(S.Hud(),35) end)~=nil,
  'silent: the five-second fallback brings 35/79: '..S.Text(S.Hud()))
end

-- 3. Consumed: an Orb-style read (EchoActiveSlotGeneration, the call the Orb
-- read context makes) takes the notification before the poll.
do
 local H=Boot()
 Switch(H,SHAPES[1].apply)
 A.EchoActiveSlotGeneration()
 check(S.Within(H,5.5,function() return At(S.Hud(),35) end)~=nil,
  'consumed notification: 35/79 is still shown: '..S.Text(S.Hud()))
end

-- 4. Rejected since start-up, before the switch: the rejected field cannot
-- hold back the others, and a rejected granted mirror still moves with its source.
for _,shape in ipairs({SHAPES[1],SHAPES[4]}) do
 local tag=shape.id..' since start-up'
 local H=Boot(function(h)
  if shape.field=='granted' then h.granted['Placeholder']={{quality=0}} else h.discovered[200001]=false end
 end)
 check(At(S.Hud(),40),tag..': baseline 40/79 from the first (uncached) read: '..S.Text(S.Hud()))
 check(Rejected()[shape.field]==shape.reason,tag..': reported rejected from the start: '..tostring(Rejected()[shape.field]))
 H.perks.serverActiveSlot=5;H.granted=S.Granted(S.GB)
 if shape.field=='granted' then H.granted['Placeholder']={{quality=0}} end
 H.Notify()
 check(S.Within(H,1,function() return At(S.Hud(),35) end)~=nil,tag..': the switch shows 35/79 within 1 s: '..S.Text(S.Hud()))
 check(Rejected()[shape.field]==shape.reason,tag..': still reported rejected after the switch')
end

-- 5. Repeated identical rejections cost no repeated work, and an unchanged
-- mirror moves no generation.
do
 local H=Boot(function(h) h.discovered[200001]=false end)
 H.Advance(6)
 local w0=S.Work()
 H.Advance(60)
 local w1=S.Work()
 check(w1.repairs==w0.repairs,'60 s of the same rejected field: no fallback repair: +'..(w1.repairs-w0.repairs))
 check(w1.steps-w0.steps<=1,'and at most one full step: +'..(w1.steps-w0.steps))
 check(w1.static==w0.static,'and no static rebuild: +'..(w1.static-w0.static))
 check(w1.scans-w0.scans<=13,'scans stay at the fallback cadence: +'..(w1.scans-w0.scans))
 local same=true
 for field,value in pairs(w0.generations) do if w1.generations[field]~=value then same=false end end
 check(same,'no Echo generation moved on repeated identical snapshots')
 check(Rejected().discovery=='discovery:key','the field is still reported rejected')
end

-- 6. Ownership confirmation is never minted from a rejected granted mirror.
local function OwnedRevision() return select(4,A.PresentationRevisions()) end
for _,case in ipairs({{tag='rejected granted response',malformed=true},{tag='control: well-formed response',malformed=false}}) do
 local H=Boot()
 H.holdGrantedResponse=true
 A.RunBoundaryReset()
 local r0=OwnedRevision()
 local response=S.Granted(S.GB)
 if case.malformed then response['Placeholder']={{quality=0}} end
 H.granted=response;H.Notify()
 A.EchoActiveSlotGeneration() -- the reconciliation alone; no ownership getter is called
 local r1=OwnedRevision()
 if case.malformed then
  check(r1==r0,case.tag..': the snapshot confirms no ownership from it: owned revision '..r0..' -> '..r1)
  check(Rejected().granted=='granted:entry',case.tag..': and reports the granted field rejected: '..tostring(Rejected().granted))
 else
  check(r1==r0+1,case.tag..': a valid fresh response is confirmed by the snapshot: '..r0..' -> '..r1)
  check(Rejected().granted==nil,case.tag..': and is not reported rejected')
 end
end

-- 7. Recovery: the rejected field goes away, then another switch.
do
 local H=Boot()
 Switch(H,SHAPES[1].apply)
 H.Advance(1)
 H.discovered[200001]=nil;H.Notify();H.Advance(1)
 check(next(Rejected())==nil,'recovery: nothing is reported rejected once the field is valid')
 check(At(S.Hud(),35),'recovery: the HUD still shows 35/79: '..S.Text(S.Hud()))
 H.perks.serverActiveSlot=2;H.granted=S.Granted(S.GA);H.Notify()
 check(S.Within(H,1,function() return At(S.Hud(),40) end)~=nil,'recovery: switching back shows 40/79 within 1 s: '..S.Text(S.Hud()))
end

-- 8. Locked roles. X (200079) is a LOCKED-role target of a 78+1 Wishlist and
-- is not rolled. A rejected unrelated field must not hide a new lock; a
-- rejected locked mirror must not keep showing the last accepted lock.
do
 local X=200079
 local spec=S.Ordinary(1,78);spec[#spec+1]={X,1,true}
 local WL=S.Rows(spec)
 local function BootLocked(locked,before)
  local o={granted=S.GA,active=2,locked=locked,before=before,
   slots={[2]={name='Build Two',verified=true,echoes=S.SlotRows(S.GA)},
    [101]={name='Synthetic WL',verified=false,echoes=S.Copy(WL)}},
   associations={[2]=S.Association(101,'Synthetic WL',WL)}}
  local H=S.Boot(o);A=Nexus.GameAdapter
  return H
 end
 local function Locked(h) return h.lockedOwned==1 and h.lockedTotal==1 and not S.Has(h.toLock,'Echo 79') end
 do -- (a) an unrelated rejected field, then X is locked
  local H=BootLocked({},function(h) h.discovered[200001]=false end)
  local h=S.Hud()
  check(h.total==78 and S.Has(h.toLock,'Echo 79') and h.lockedOwned==0,'locked (a): before the lock X is TO LOCK, 40/78: '..S.Text(h))
  H.locked={{spellId=X,stacks=1}};H.Notify()
  check(S.Within(H,1,function() return Locked(S.Hud()) end)~=nil,'locked (a): the new lock is shown within 1 s despite the rejected discovery field')
  check(not S.Has(S.Hud().missing,'Echo 79'),'locked (a): X is not STILL NEEDED')
 end
 do -- (b) the locked mirror itself becomes unreadable, then valid again
  local H=BootLocked({{spellId=X,stacks=1}})
  check(Locked(S.Hud()),'locked (b): baseline shows X locked 1/1')
  H.locked={{spellId=X,stacks=1},{name='unrecognized entry'}};H.Notify()
  check(Nexus.GameAdapter.LockedOwned().synced==false,'locked (b): the locked getter is unsynced (fail-closed, unchanged)')
  check(S.Within(H,1,function() local h=S.Hud() return h.lockedOwned==0 and S.Has(h.toLock,'Echo 79') end)~=nil,
   'locked (b): the HUD no longer shows the last accepted lock; X is TO LOCK within 1 s: locked '
   ..tostring(S.Hud().lockedOwned)..'/'..tostring(S.Hud().lockedTotal))
  check(Rejected().locked=='locked:read','locked (b): the locked field is reported rejected: '..tostring(Rejected().locked))
  check(not S.Has(S.Hud().missing,'Echo 79'),'locked (b): an unreadable lock list never moves X to STILL NEEDED')
  H.locked={{spellId=X,stacks=1}};H.Notify()
  check(S.Within(H,1,function() return Locked(S.Hud()) end)~=nil,'locked (b): a valid list again shows X locked within 1 s')
  check(Rejected().locked==nil,'locked (b): and the field is no longer reported rejected')
 end
 do -- (c) roles unchanged: an ORDINARY entry for a locked Echo stays STILL NEEDED
  local spec2=S.Ordinary(1,79)
  local W2=S.Rows(spec2)
  local o={granted=S.GA,active=2,locked={{spellId=X,stacks=1}},before=function(h) h.discovered[200001]=false end,
   slots={[2]={name='Build Two',verified=true,echoes=S.SlotRows(S.GA)},[101]={name='Synthetic W',verified=false,echoes=S.Copy(W2)}},
   associations={[2]=S.Association(101,'Synthetic W',W2)}}
  local H=S.Boot(o)
  local h=S.Hud()
  check(h.total==79 and h.owned==40 and S.Has(h.missing,'Echo 79'),'roles: an ordinary entry for a locked Echo is still needed: '..S.Text(h))
 end
end

-- 9. The Orb read context's active-slot generation: present while only an
-- unrelated field is rejected, absent while the active slot itself is
-- rejected (an unknown slot has no generation), present again afterwards.
do
 local H=Boot()
 H.discovered[200001]=false;H.now=H.now+.01
 check(type(A.EchoActiveSlotGeneration())=='number' and Rejected().discovery=='discovery:key',
  'Orb read: a rejected discovery field leaves the active-slot generation available')
 local raw=H.service.GetServerActiveSlot
 H.service.GetServerActiveSlot=function() return 2.5 end
 H.now=H.now+.01
 check(A.EchoActiveSlotGeneration()==nil and Rejected().activeSlot=='echo:scalar',
  'Orb read: a rejected active slot carries no generation: '..tostring(Rejected().activeSlot))
 H.service.GetServerActiveSlot=raw;H.now=H.now+.01
 check(type(A.EchoActiveSlotGeneration())=='number' and Rejected().activeSlot==nil,
  'Orb read: a valid active slot carries a generation again')
end

C.finish('a rejected Echo field is reported, holds back no other field, moves with its source, confirms nothing, repeats no work; HUD, overlay and Journal follow; locked evidence stays fail-closed')
