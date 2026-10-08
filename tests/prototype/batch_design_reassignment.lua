-- Group 5 (S1-C2): an initial locked-target design is not substituted after
-- Unassign and a selector reassignment of identical rolled contents.
-- Two saves of the same 79 rolled copies keep two permanent designs: D1
-- (targets 200080-200085, the content-key bucket, which a later save never
-- replaces) and D2 (200086-200091, the authored record). The native mirror
-- holds ordinary rows only, so its content cannot tell D1 from D2. After the
-- authored D2 is assigned and then Unassigned (D2 kept in the removal
-- history), assigning the plain mirror again silently takes D1's targets
-- from the content-key bucket (GameAdapter.AssignedWishlist fallback).
-- EXPECT (fails at 8c), through the actual adapter assignment and through the
-- actual Journal picker: the reassigned mirror does not carry D1's stale
-- targets, and no retained design is chosen without an explicit selection:
-- the assignment is refused, or not ready, or carries neither design.
-- GUARD (holds at 8c): the authored D2 assignment carries exactly D2 before
-- Unassign; Unassign succeeds and keeps D2 (with its identity) in the removal
-- history, still offered after the reassignment; the D1 bucket content is
-- unchanged; with ONE retained design the same Unassign/reassign still uses
-- it (legacy sidecar path); no lock, unlock, choice or spend call.
-- SETUP: real TOC boot per scenario, real Store, real Wishlist controller
-- saves (their fake uploads are setup), synthetic server slots; the Journal
-- picker is the real one, with a positive control that it assigns an
-- unambiguous plan in this fixture.
-- N (the journal_picker_layers shape): the same two designs saved as two
-- plans of different names, D1 'Named one' kept on Saved Build 1 (and in the
-- bucket), D2 'Named two' Unassigned from Saved Build 2. The explicit
-- first-run selection of the plain 'Named two' mirror resolves (GUARD, as at
-- 8c) with exactly D2, never D1 (EXPECT). R: the same row, renamed to
-- 'Named one' after the picker opened (contents unchanged), borrows no
-- retained design. F: the A shape chosen in the first-run context stays
-- unresolved like A (no first-run exception).
-- E (standards review r1, STD-R1-04): the A state opened in the actual
-- Wishlist Editor (the remedy the unavailable note names). EXPECT (fails at
-- 3bc6d88): the draft is filled with no locked target from the content-key
-- bucket, and the editor says why. GUARD (holds at 3bc6d88): the editor opens
-- the plan with its 79 rolled copies; the assignment, the D1 bucket and D2 in
-- the removal history are unchanged and the assignment still reads
-- unavailable; opening makes no game write. A save would then keep only the
-- targets the player sets (not exercised here).
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_design_reassignment')
local printable=B.printable

-- `names` (optional): one plan name per save; save i is then made in its own
-- Saved Build i and mirrored at server slot 100+i. Without it every save is
-- the first-run plan 'Same rolled contents', mirrored at slot 101 by the last.
local function Setup(label,firsts,names)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 for i=86,91 do H.AddEcho(200000+i,'Synthetic extra '..i,i%4,1) end
 H.Boot()
 local A=Nexus.GameAdapter
 local function State() return Nexus.Store.State() end
 local function Save(first,name)
  local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,
   accountRoot=function() return {} end,notify=function() end})
  c.Initialize(A);c.BeginNewWishlist()
  local rows={}
  for i=1,79 do rows[#rows+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
  for i=first,first+5 do rows[#rows+1]={spellId=200000+i,quality=i%4,stacks=1,locked=true} end
  C.setup(c.LoadPendingEchoes(rows),label..': the real controller admits the plan with targets from '..(200000+first))
  local draft=c.PrepareApply(name)
  C.setup(draft~=nil and c.AcceptApply(draft)==true,label..': the real controller saves it')
  H.now=H.now+4;H.Advance(.2,.05)
  return draft or {}
 end
 local drafts={}
 for i,first in ipairs(firsts) do
  if names then
   H.perks.serverBuildSlots[i]={name=i==1 and 'Saved synthetic' or 'Saved synthetic '..i,verified=true,
    echoes={{spellId=200010,quality=2,stacks=1}}}
   H.perks.serverActiveSlot=i;H.Notify();A.Poll()
  end
  drafts[i]=Save(first,names and names[i] or 'Same rolled contents')
 end
 local key=A.WishlistKey(drafts[1].echoes or {})
 for i=2,#drafts do C.setup(A.WishlistKey(drafts[i].echoes or {})==key,label..': the saves have the same rolled-content key') end
 H.perks.serverBuildSlots[1]={name='Saved synthetic',verified=true,echoes={{spellId=200010,quality=2,stacks=1}}}
 H.perks.serverActiveSlot=1
 for i,draft in ipairs(names and drafts or {drafts[#drafts]}) do
  H.perks.serverBuildSlots[100+i]={name=draft.name,verified=false,echoes=H.Clone(draft.echoes)}
 end
 H.Notify();A.Poll()
 local buckets=State().lockDesignTargetsBySlot or {}
 local bucket=buckets[key]
 C.setup(type(bucket)=='table' and bucket[200080]~=nil,label..': the first save created the D1 content-key bucket')
 return {H=H,A=A,State=State,key=key,bucketDump=B.Dump(bucket)}
end
local function Has(result,first)
 local n=0
 for _,e in ipairs(type(result)=='table' and result.entries or {}) do
  if e.locked and e.spellId>=200000+first and e.spellId<=200000+first+5 then n=n+1 end
 end
 return n
end
local function Authored(f,first)
 for _,c in ipairs(f.A.GetWishlistCandidates()) do
  if c.designTargets and c.key==f.key and c.designTargets[200000+first] then return c end
 end
end
local function Live(f)
 for _,c in ipairs(f.A.GetWishlistCandidates()) do if c.slot==101 then return c end end
end
local function Offered(f,assignmentId)
 for _,plan in ipairs(f.A.ForgottenWishlistPlans()) do
  if assignmentId~=nil and plan.assignmentId==assignmentId then return true end
 end
 return false
end
local function Association(f) local s=f.State();return s.loadoutWishlists and s.loadoutWishlists[1] or nil end
-- The authored D2 is assigned, then Unassigned. Returns D2's identity.
local function AssignThenUnassign(label,f)
 local authored=Authored(f,86)
 C.setup(authored~=nil,label..': the authored D2 candidate is offered')
 if not authored then return nil end
 C.setup(f.A.SetLoadoutWishlist(1,101,authored),label..': the authored D2 is assigned')
 local before=f.A.AssignedWishlist()
 C.guard(before.state=='ready' and Has(before,86)==6 and Has(before,80)==0,
  label..': before Unassign the assignment carries exactly D2',Has(before,86)..'/'..Has(before,80))
 local identity=(Association(f) or {}).assignmentId
 C.guard(f.A.ClearLoadoutWishlist(1)==true,label..': Unassign succeeds')
 C.guard(Offered(f,identity),label..': D2 with its identity is kept in the removal history')
 return identity
end
local function After(label,f,refused,identity)
 local after=f.A.AssignedWishlist()
 local d1,d2=Has(after,80),Has(after,86)
 print('OBSERVED',label,'refused='..printable(refused),'state='..printable(after.state),'D1 targets='..d1,'D2 targets='..d2)
 C.expect(d1==0,label..': the reassigned mirror does not carry the stale initial design D1',d1)
 C.expect(refused or after.state~='ready' or (d1==0 and d2==0),
  label..': no retained design is chosen without an explicit selection',printable(after.state)..' D1='..d1..' D2='..d2)
 C.guard(Offered(f,identity),label..': D2 is still offered in the removal history')
 C.guard(B.Dump((f.State().lockDesignTargetsBySlot or {})[f.key])==f.bucketDump,
  label..': the D1 content-key bucket is unchanged')
 local mutations=0
 for _,a in ipairs(f.H.actions) do
  if a[1]=='lock' or a[1]=='unlock' or a[1]=='take' or a[1]=='reroll' or a[1]=='orb-spend' then mutations=mutations+1 end
 end
 C.guard(mutations==0,label..': no lock, unlock, choice or spend call',mutations)
end

C.scenario('A two designs, actual adapter reassignment',function()
 local f=Setup('A',{80,86})
 local identity=AssignThenUnassign('A',f)
 local live=Live(f)
 C.setup(live~=nil and live.designTargets==nil,'A: the plain server mirror stays selectable')
 local ok,why=f.A.SetLoadoutWishlist(1,101,live)
 print('OBSERVED','A reassignment',printable(ok),printable(why))
 After('A',f,ok~=true,identity)
end)

C.scenario('J two designs, actual Journal picker reassignment',function()
 local f=Setup('J',{80,86})
 -- An unrelated, unambiguous server Wishlist for the positive picker control.
 f.H.perks.serverBuildSlots[102]={name='Synthetic other plan',verified=false,echoes={{spellId=200020,quality=0,stacks=1}}}
 f.H.Notify();f.A.Poll()
 local identity=AssignThenUnassign('J',f)
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Show();Nexus.JournalTab.RefreshAssociations()
 C.setup(NexusActiveWishlistSelector~=nil,'J: the Journal assignment selector exists')
 if not NexusActiveWishlistSelector then return end
 local function Open()
  if NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown() then return NexusWishlistOnlyPicker end
  NexusActiveWishlistSelector:Click()
  return NexusWishlistOnlyPicker
 end
 local function Row(picker,name)
  for _,r in ipairs(picker and picker.children or {}) do
   if r.nameButton and r:IsVisible() and r.nameButton.text:GetText():find(name,1,true) then return r end
  end
 end
 local picker=Open()
 C.setup(picker and picker:IsShown(),'J: the actual picker opens')
 local row=Row(picker,'Same rolled contents')
 C.setup(row~=nil,'J: the picker offers the plain mirror row')
 if not row then return end
 local lines=B.CapturePrint(function() row.nameButton:Click() end)
 local assigned=Association(f)
 print('OBSERVED','J picker assigned='..printable(assigned and assigned.slot),table.concat(lines,' | '))
 After('J',f,assigned==nil,identity)
 picker=Open()
 local other=Row(picker,'Synthetic other plan')
 C.setup(other~=nil,'J: the picker offers the unrelated plan')
 if other then
  other.nameButton:Click()
  local now=Association(f)
  C.setup(now~=nil and now.slot==102,'J: positive control, the actual picker assigns an unambiguous plan in this fixture',
   now and now.slot)
 end
end)

C.scenario('L one retained design keeps the legacy sidecar path',function()
 local f=Setup('L',{80})
 local authored=Authored(f,80)
 C.setup(authored~=nil and f.A.SetLoadoutWishlist(1,101,authored),'L: the only design D1 is assigned')
 C.setup(f.A.ClearLoadoutWishlist(1)==true,'L: Unassign succeeds')
 local live=Live(f)
 C.setup(live~=nil and live.designTargets==nil,'L: the plain server mirror stays selectable')
 local ok=f.A.SetLoadoutWishlist(1,101,live)
 local after=f.A.AssignedWishlist()
 C.guard(ok==true and after.state=='ready' and Has(after,80)==6,
  'L: with a single retained design the reassigned mirror still uses it',printable(ok)..' '..printable(after.state)..' '..Has(after,80))
end)

-- N and R: 'Named two' (D2) is Unassigned from Saved Build 2, then the
-- first-run context. Returns the fixture, D2's identity, Saved Build 1's
-- record and the plain 'Named two' picker candidate.
local function NamedFirstRun(label)
 local f=Setup(label,{80,86},{'Named one','Named two'})
 local kept=Association(f)
 C.setup(kept~=nil and kept.name=='Named one',label..': Saved Build 1 holds Named one (D1)')
 f.H.perks.serverActiveSlot=2;f.H.Notify();f.A.Poll()
 local identity=((f.State().loadoutWishlists or {})[2] or {}).assignmentId
 C.setup(identity~=nil and f.A.ClearLoadoutWishlist(2)==true and Offered(f,identity),
  label..': Named two (D2) is Unassigned from Saved Build 2 and kept in the removal history')
 f.H.perks.serverActiveSlot=0;f.H.Notify();f.A.Poll()
 local live
 for _,c in ipairs(f.A.GetWishlistCandidates()) do if c.slot==102 then live=c end end
 C.setup(live~=nil and live.designTargets==nil and live.name=='Named two',label..': the plain Named two mirror is offered')
 return f,identity,B.Dump(kept),live
end
local function Kept(label,f,identity,kept)
 C.guard(Offered(f,identity),label..': D2 is still offered in the removal history')
 C.guard(B.Dump((f.State().lockDesignTargetsBySlot or {})[f.key])==f.bucketDump,
  label..': the D1 content-key bucket is unchanged')
 C.guard(B.Dump(Association(f))==kept,label..': Saved Build 1 keeps Named one exactly')
 local writes=0
 for _,kind in ipairs({'lock','unlock','take','reroll','orb-spend'}) do writes=writes+B.Count(f.H,kind) end
 C.guard(writes==0,label..': no lock, unlock, choice or spend call',writes)
end

C.scenario('N two named plans, explicit first-run selection after Unassign',function()
 local f,identity,kept,live=NamedFirstRun('N')
 if not live then return end
 local ok,why=f.A.SetFirstRunWishlist(102,live)
 local after=f.A.AssignedWishlist()
 local d1,d2=Has(after,80),Has(after,86)
 print('OBSERVED','N first-run selection',printable(ok),printable(why),'state='..printable(after.state),'D1 targets='..d1,'D2 targets='..d2)
 C.guard(ok==true and after.state=='ready' and after.activeSlot==0 and after.name=='Named two',
  'N: the explicit first-run selection of the only plan of that name resolves',printable(after.state))
 C.expect(d2==6 and d1==0,'N: it carries that plan\'s own design D2, never the bucket\'s D1',d2..'/'..d1)
 Kept('N',f,identity,kept)
end)

C.scenario('R a row renamed after the picker opened borrows no design',function()
 local f,identity,kept,live=NamedFirstRun('R')
 if not live then return end
 -- Same slot, same contents, now the other plan's name (and the only row of it).
 f.H.perks.serverBuildSlots[101]=nil
 f.H.perks.serverBuildSlots[102].name='Named one'
 f.H.Notify();f.A.Poll()
 local ok,why=f.A.SetFirstRunWishlist(102,live)
 local after=f.A.AssignedWishlist()
 local d1,d2=Has(after,80),Has(after,86)
 print('OBSERVED','R renamed selection',printable(ok),printable(why),'state='..printable(after.state),'D1 targets='..d1,'D2 targets='..d2)
 C.expect(d1==0 and d2==0 and (ok~=true or after.state~='ready'),
  'R: the renamed row borrows no retained design (refused or not ready)',printable(after.state)..' D1='..d1..' D2='..d2)
 Kept('R',f,identity,kept)
end)

C.scenario('F two designs, first-run selection of the plain mirror after Unassign',function()
 local f=Setup('F',{80,86})
 local identity=AssignThenUnassign('F',f)
 f.H.perks.serverActiveSlot=0;f.H.Notify();f.A.Poll()
 local live=Live(f)
 C.setup(live~=nil and live.designTargets==nil,'F: the plain server mirror stays selectable')
 local ok,why=f.A.SetFirstRunWishlist(101,live)
 print('OBSERVED','F first-run selection',printable(ok),printable(why))
 After('F',f,ok~=true,identity)
end)

C.scenario('E the editor opens the ambiguous plain plan',function()
 local f=Setup('E',{80,86})
 local identity=AssignThenUnassign('E',f)
 local live=Live(f)
 C.setup(live~=nil and live.designTargets==nil,'E: the plain server mirror stays selectable')
 C.setup(f.A.SetLoadoutWishlist(1,101,live)==true and f.A.AssignedWishlist().state=='unavailable',
  'E: the plain mirror is assigned and reads unavailable (two retained designs)')
 local record=B.Dump(Association(f))
 local actions=#f.H.actions
 local lines,ok,err=B.CapturePrint(function() Nexus.WishlistEditor.Show() end)
 C.setup(ok,'E: the actual editor opens',err)
 local draft=Nexus.WishlistEditor.DebugDraftState()
 local said=B.Plain(table.concat(lines,' | '))
 print('OBSERVED','E editor draft pending='..printable(draft.pending),'pendingLock='..printable(draft.pendingLock),
  'fulfilled='..printable(draft.fulfilled))
 C.guard(draft.pending==79,'E: the editor opens the plan with its 79 rolled copies',draft.pending)
 C.expect(draft.pendingLock==0 and draft.fulfilled==0,'E: no locked target is filled in from the content-key bucket',
  printable(draft.pendingLock)..'/'..printable(draft.fulfilled))
 C.expect(said:find('no locked targets were filled in',1,true)~=nil,'E: the editor says why no targets were filled in',said)
 C.guard(B.Dump(Association(f))==record and f.A.AssignedWishlist().state=='unavailable',
  'E: opening the editor changes no assignment; it still reads unavailable')
 C.guard(Offered(f,identity),'E: D2 is still offered in the removal history')
 C.guard(B.Dump((f.State().lockDesignTargetsBySlot or {})[f.key])==f.bucketDump,'E: the D1 content-key bucket is unchanged')
 C.guard(#f.H.actions==actions,'E: opening the editor makes no game write',#f.H.actions-actions)
end)

C.finish('(equal rolled content never substitutes a stale or guessed design)')
