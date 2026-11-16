-- M3 review repair B1 (independent review, combined-03): an explicit Save
-- changes the player confirmed keeps its intent while it waits for the
-- service's 3 s spacing guard. On the exact combined-03 preimage (2594d591)
-- the spaced retry dropped the bound confirmation, so the retry ran as a
-- legacy save: a Wishlist opened for another Saved Build was assigned there,
-- and the opened first-run plan created a new slot-1 handoff.
-- Stale-retry repair (R6-R8): the Save changes of the plan its Saved Build
-- holds ("Saving also updates its assignment") stays that save. When that
-- assignment is changed after the confirmation (Assign or Unassign while the
-- save waits, or before the accept), nothing is uploaded, nothing stays
-- queued and the result says why. On the B1-fixed cut afaa7e21 the retry
-- (and the accept) re-read the assignment and uploaded it as a save without
-- an assignment (wishlist_editor_binding L11, ux_save_assignment_result A10).
-- Categories (view_regression_support): EXPECT is the repaired behaviour; the
-- R1/R2 EXPECTs fail on combined-03 by design, the R6-R8 EXPECTs on afaa7e21
-- (where R1/R2 already hold); GUARD holds on both cuts and must keep holding;
-- SETUP is the fixture. Oracles: the host upload call (H.actions 'upload'), the
-- assignment writers counted at the adapter boundary, the Store and the
-- controller's own result. Real TOC boot, adapter, controller, editor controls
-- and StaticPopup handlers; the editor's own OnUpdate pumps the retry.
-- Synthetic host services only; no native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_save_retry_intent')
local H,A,writes,spends
-- Revision 6 (updated-client compatibility, full-CI finding): GameAdapter.
-- UploadWishlist replaces an existing server Wishlist (slot > 0) only when
-- the current slot list shows that destination in full; a missing one is
-- refused ("stale_slot") and starts no spacing. Slot 103 is not in this
-- fixture's list, so the spacing setup names it as a known synthetic Wishlist
-- mirror (above the declared slots, unverified, the spacer's own Echoes) for
-- that one real upload and then puts the list back exactly as it was. The
-- spacing window is the production one, opened by that real upload; nothing
-- is stubbed and no timestamp is set.
local function KnownSlotUpload(upload,slot,name,echoes)
 local created=H.perks.serverBuildSlots==nil
 if created then H.perks.serverBuildSlots={} end
 local slots=H.perks.serverBuildSlots
 local prior=slots[slot]
 local rows={}
 for i,e in ipairs(echoes) do rows[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=false} end
 slots[slot]={name=name,verified=false,echoes=rows}
 local ok,why=upload(slot,name,echoes)
 slots[slot]=prior
 if created then H.perks.serverBuildSlots=nil end
 return ok,why
end
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E3={{spellId=201176,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function World()
 return {[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Arena',verified=true,echoes=E3},[6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
end
local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusWishlistEditorLoadoutMenu=nil;NexusWishlistSaveOnlyButton=nil;NexusLoadoutAssociationPanel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5);H.AddEcho(201176,'Echo Arena',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=H.Clone(o.slots)
 H.perks.serverActiveSlot=o.active
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() spends=spends+1;return false end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then
   writes[k]=0
   A[k]=function(...) writes[k]=writes[k]+1;return real(...) end
  end
 end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
-- Writer counts start again after fixture assignments.
local function Zero() for k in pairs(writes) do writes[k]=0 end end
local function Ctrl()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 error('editor controller not found')
end
local function EditorButton(text)
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame and V.Plain(f:GetText() or '')==text then return f end
 end
 return nil
end
-- The editor's primary save control (created before the alternative beside it).
local APPLY_LABELS={['Create & assign']=true,['Create unassigned']=true,['Save & assign']=true,['Save changes']=true,
 ['Create Wishlist']=true,['Save Wishlist']=true,['Saved']=true,['Saving...']=true}
local function ApplyButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame and APPLY_LABELS[V.Plain(f:GetText() or '')] then return f end
 end
 return nil
end
local function Label(f) return f and V.Plain(f:GetText() or '') or nil end
local function EditorLabels()
 local t={}
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame then t[#t+1]=V.Plain(f:GetText() or '') end
 end
 table.sort(t);return table.concat(t,'|')
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
local function Click(button)
 if not button then return nil end
 local before=H.popup
 button:Click()
 if H.popup~=nil and H.popup~=before then return H.popup end
 return nil
end
local function Accept(p)
 if not p then return nil end
 if H.popup==p then H.popup=nil end
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
local function Uploads(slot)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' and (slot==nil or a[2]==slot) then n=n+1 end end
 return n
end
local function Others() local n=0;for _,a in ipairs(H.actions) do if a[1]~='upload' then n=n+1 end end;return n end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Pending() return Nexus.WishlistEditor.IsApplyPending()==true end
local function Stored(where)
 local s=Nexus.Store.State()
 if where=='first' then return s.firstRunWishlist end
 return s.loadoutWishlists and s.loadoutWishlists[where]
end
local function Facts()
 local s=Nexus.Store.State() or {};local links=type(s.loadoutWishlists)=='table' and s.loadoutWishlists or {}
 local out={}
 for slot=1,6 do local r=links[slot]
  out[#out+1]=slot..'='..(type(r)=='table' and (tostring(r.name)..'/'..tostring(r.assignmentId)) or tostring(r)) end
 local f=s.firstRunWishlist
 out[#out+1]='first='..(type(f)=='table' and (tostring(f.name)..'/'..tostring(f.assignmentId)) or tostring(f))
 return table.concat(out,' ')
end
local function NameText()
 local box=NexusWishlistNameInput
 if not box then return nil end
 if box._NexusRawText then return box:_NexusRawText() end
 return box:GetText()
end
local function Result() local c=Ctrl();return c.SaveResult and c.SaveResult(NameText()) or nil end
local function Describe(r)
 if type(r)~='table' then return tostring(r) end
 return tostring(r.kind)..'/'..tostring(r.reason)..'/'..tostring(r.intent)
end
local function Copies(rec,id)
 if type(rec)~='table' then return nil end
 local n=0;for _,e in ipairs(rec.echoes or {}) do if e.spellId==id then n=n+(e.stacks or 1) end end;return n
end
-- An earlier upload opens the service's spacing window (as ux_save_intents I12).
local function StartSpacing(tag)
 C.setup(KnownSlotUpload(A.UploadWishlist,103,'Spacer',H.Clone(EF))==true,tag..': fixture: an earlier upload starts the 3 s spacing window')
end
-- Saved Build 6 holds W-Six; W-Free is open for Saved Build 6 with one more copy.
local function OpenForOtherBuild(tag)
 Boot({active=6,slots=World()})
 local ok=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6))
 C.setup(ok,tag..': fixture: Saved Build 6 is assigned W-Six')
 H.Notify();A.Poll();H.Advance(1)
 Zero()
 for _,cand in ipairs(A.GetWishlistCandidates()) do if cand.slot==107 then Nexus.WishlistEditor.OpenForWishlist(cand,6) end end
 local ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Free' and ctx.loadoutSlot==6,tag..': fixture: W-Free is open for Saved Build 6',ctx.name)
 selected(201174).plus:Click()
 Nexus.WishlistEditor.Refresh()
 local changes=EditorButton('Save changes')
 C.setup(Label(ApplyButton())=='Save & assign' and changes~=nil and changes~=ApplyButton(),
  tag..': fixture: Save & assign with Save changes beside it',EditorLabels())
 return changes
end
-- The real Save changes click and accept while the spacing window is open.
local function SpacedSaveChanges(tag,button)
 StartSpacing(tag)
 local p=Click(button)
 C.setup(p~=nil and p.which=='WISHLISTREALIZER_UPDATE_WISHLIST' and type(p.data)=='table'
  and type(p.data.confirmation)=='table' and p.data.confirmation.explicit==true and p.data.intent=='saveChanges',
  tag..': fixture: the explicit Save changes confirmation')
 Accept(p)
 C.setup(Pending() and Uploads(107)==0,tag..': fixture: the accepted save waits for the spacing guard; nothing is sent yet',
  'pending='..tostring(Pending())..' uploads='..Uploads(107))
 return p
end

C.scenario('R1 a spaced Save changes of a Wishlist opened for another Saved Build assigns nothing on its retry',function()
 local changes=OpenForOtherBuild('R1')
 local facts,w,others,auto=Facts(),Writes(),Others(),Auto()
 local p=SpacedSaveChanges('R1',changes)
 C.setup(p~=nil and p.data.keepsAssignment==true,'R1: fixture: the confirmation keeps Saved Build 6\'s Wishlist')
 C.guard(Writes()==w and Facts()==facts,'R1: nothing is assigned while the save waits',Facts())
 H.Advance(5)
 print('OBSERVED','R1 uploads='..Uploads(107)..' writes='..Writes()..' association='..tostring(writes.UpdateWishlistAssociationAfterSave)..' facts='..Facts())
 C.guard(Uploads(107)==1 and not Pending(),'R1: the retry uploads W-Free exactly once and nothing stays queued',Uploads(107))
 C.expect(writes.UpdateWishlistAssociationAfterSave==0 and Writes()==w,
  'R1: the retry runs no assignment writer',tostring(writes.UpdateWishlistAssociationAfterSave))
 C.expect(Stored(6)~=nil and Stored(6).name=='W-Six' and Facts()==facts,'R1: Saved Build 6 keeps W-Six',Facts())
 local r=Result()
 C.expect(r~=nil and r.kind=='unassigned' and r.reason=='saveOnly' and r.intent=='saveChanges',
  'R1: the result says saved without an assignment, as chosen (Save changes)',Describe(r))
 -- The used confirmation answered again sends and assigns nothing more.
 StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
 C.guard(Uploads(107)==1 and writes.UpdateWishlistAssociationAfterSave<=1,'R1: a repeated answer sends nothing again',Uploads(107))
 C.guard(Others()==others and spends==0 and Auto()==auto,'R1: no other game action, spend or Auto change')
end)

C.scenario('R2 a spaced explicit Save changes of the opened first-run plan creates no slot-1 handoff on its retry',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 C.setup(A.SetFirstRunWishlist(107)==true and Stored('first')~=nil and Stored(1)==nil,
  'R2: fixture: W-Free is the first-run plan and slot 1 holds no assignment',Facts())
 Zero()
 SlashCmdList.NEXUS('editor')
 local ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Free' and ctx.destination=='first','R2: fixture: the editor opens the first-run plan',ctx.name)
 selected(201174).plus:Click()
 Nexus.WishlistEditor.Refresh()
 C.setup(Label(ApplyButton())=='Save changes','R2: fixture: the Save changes control',EditorLabels())
 local auto=Auto()
 SpacedSaveChanges('R2',ApplyButton())
 C.guard(Stored(1)==nil,'R2: nothing is written while the save waits',Facts())
 H.Advance(5)
 print('OBSERVED','R2 uploads='..Uploads(107)..' facts='..Facts())
 C.guard(Uploads(107)==1 and not Pending() and Copies(Stored('first'),201174)==2,
  'R2: the retry uploads once and updates the first-run plan',Facts())
 C.expect(Stored(1)==nil,'R2: the retry creates no new slot-1 handoff (no new destination)',Facts())
 C.guard(Auto()==auto and spends==0,'R2: no Auto change and no spend')
end)

C.scenario('R3 legacy: a caller that names no intent keeps the writers\' handoff rule through the spacing wait',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 C.setup(A.SetFirstRunWishlist(107)==true and Stored(1)==nil,'R3: fixture: the same first-run plan; slot 1 holds no assignment')
 SlashCmdList.NEXUS('editor')
 selected(201174).plus:Click()
 StartSpacing('R3')
 local c=Ctrl()
 local data=c.PrepareApply(nil)
 C.setup(type(data)=='table' and type(data.confirmation)=='table' and data.confirmation.explicit==nil,
  'R3: fixture: the default-intent confirmation is not explicit')
 local ok,why=c.AcceptApply(data)
 C.setup(ok==false and why=='spacing' and c.IsApplyPending(),'R3: fixture: the legacy save waits for the spacing guard',tostring(why))
 H.Advance(5)
 C.guard(Uploads(107)==1 and Stored(1)~=nil and Stored('first')~=nil and Stored(1).assignmentId==Stored('first').assignmentId,
  'R3: the legacy retry keeps the earlier rule (slot 1 receives the proven handoff)',Facts())
end)

C.scenario('R4 an assignment made elsewhere while a Save changes waits is kept',function()
 local changes=OpenForOtherBuild('R4')
 SpacedSaveChanges('R4',changes)
 local ok=A.SetLoadoutWishlistIdentity(6,'Other plan',H.Clone(E3))
 C.setup(ok,'R4: fixture: Saved Build 6 is assigned Other plan elsewhere while the save waits')
 local w=Writes()
 H.Advance(5)
 print('OBSERVED','R4 uploads='..Uploads(107)..' facts='..Facts())
 C.guard(Stored(6)~=nil and Stored(6).name=='Other plan' and writes.UpdateWishlistAssociationAfterSave==0
  and Writes()==w and not Pending(),'R4: the newer choice is kept; the waiting save writes no assignment',Facts())
end)

C.scenario('R5 a draft changed while a Save changes waits is not sent',function()
 local changes=OpenForOtherBuild('R5')
 local facts,w=Facts(),Writes()
 SpacedSaveChanges('R5',changes)
 selected(201174).plus:Click()
 H.Advance(5)
 local r=Result()
 C.guard(Uploads(107)==0 and not Pending() and Writes()==w and Facts()==facts,
  'R5: the changed draft is not sent and nothing is assigned',Facts())
 C.guard(r~=nil and r.kind=='notSaved' and r.reason=='retry_draft_changed','R5: the result says the draft changed',Describe(r))
end)

-- Chat notices printed while fn runs (colour codes removed).
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
-- W-Six is open for Saved Build 6, which holds it, with one more copy: its
-- Save changes is the bound plan's own save (it updates that assignment).
local function OpenBoundPlan(tag)
 Boot({active=6,slots=World()})
 local ok=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6))
 C.setup(ok,tag..': fixture: Saved Build 6 is assigned W-Six')
 H.Notify();A.Poll();H.Advance(1)
 Zero()
 for _,cand in ipairs(A.GetWishlistCandidates()) do if cand.slot==106 then Nexus.WishlistEditor.OpenForWishlist(cand,6) end end
 local ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Six' and ctx.loadoutSlot==6,tag..': fixture: W-Six is open for Saved Build 6, which holds it',ctx.name)
 selected(201173).plus:Click()
 Nexus.WishlistEditor.Refresh()
 C.setup(Label(ApplyButton())=='Save changes' and EditorButton('Save & assign')==nil,
  tag..': fixture: the bound plan offers Save changes only',EditorLabels())
 return ApplyButton()
end
-- The confirmation of that Save changes: explicit, and not one that keeps
-- another plan's assignment (its words say it updates the assignment).
local function BoundConfirmation(tag,p)
 C.setup(p~=nil and p.which=='WISHLISTREALIZER_UPDATE_WISHLIST' and type(p.data)=='table'
  and type(p.data.confirmation)=='table' and p.data.confirmation.explicit==true and p.data.intent=='saveChanges'
  and p.data.keepsAssignment==nil,tag..': fixture: the explicit Save changes confirmation of the bound plan')
end
-- That Save changes clicked and accepted inside the spacing window.
local function SpacedBoundSave(tag,button)
 StartSpacing(tag)
 local p=Click(button)
 BoundConfirmation(tag,p)
 Accept(p)
 C.setup(Pending() and Uploads(106)==0,tag..': fixture: the accepted save waits for the spacing guard; nothing is sent yet',
  'pending='..tostring(Pending())..' uploads='..Uploads(106))
 return p
end
-- After the change: no host upload, nothing queued, no writer, the newer
-- choice kept, a not-saved result and notice naming why.
local function RefusedBeforeUpload(tag,said,facts,w,others,auto)
 print('OBSERVED',tag..' uploads='..Uploads(106)..' writes='..Writes()..' facts='..Facts()..' said='..said)
 C.expect(Uploads(106)==0,tag..': the save of W-Six is not uploaded',Uploads(106))
 C.guard(not Pending(),tag..': nothing stays queued')
 C.guard(Facts()==facts and Writes()==w and writes.UpdateWishlistAssociationAfterSave==0,
  tag..': no writer runs; the newer choice for Saved Build 6 is kept',Facts())
 local r=Result()
 C.expect(r~=nil and r.kind=='notSaved' and r.reason=='assignment_changed' and r.intent=='saveChanges',
  tag..': the result says not saved because the assignment changed',Describe(r))
 C.expect(said:find('Not saved:',1,true)~=nil and said:find('that choice is kept',1,true)~=nil
  and not said:find('as you chose',1,true),tag..': the notice says why; it does not say saved as chosen',said)
 C.guard(Others()==others and spends==0 and Auto()==auto,tag..': no other game action, spend or Auto change')
end

C.scenario('R6 a spaced Save changes of the bound plan is refused before any upload when its Saved Build is given another plan meanwhile',function()
 local save=OpenBoundPlan('R6')
 local others,auto=Others(),Auto()
 SpacedBoundSave('R6',save)
 C.setup(A.SetLoadoutWishlist(6,107)==true and Stored(6)~=nil and Stored(6).name=='W-Free',
  'R6: fixture: Saved Build 6 is given W-Free after the wait began',Facts())
 local facts,w=Facts(),Writes()
 local said=Heard(function() H.Advance(5) end)
 RefusedBeforeUpload('R6',said,facts,w,others,auto)
end)

C.scenario('R7 a spaced Save changes of the bound plan is refused before any upload when its Saved Build is unassigned meanwhile',function()
 local save=OpenBoundPlan('R7')
 local others,auto=Others(),Auto()
 SpacedBoundSave('R7',save)
 C.setup(A.ClearLoadoutWishlist(6)==true and Stored(6)==nil,'R7: fixture: Saved Build 6 is unassigned after the wait began',Facts())
 local facts,w=Facts(),Writes()
 local said=Heard(function() H.Advance(5) end)
 RefusedBeforeUpload('R7',said,facts,w,others,auto)
end)

C.scenario('R8 a confirmed Save changes of the bound plan is refused before any upload when its Saved Build is reassigned before the accept',function()
 local save=OpenBoundPlan('R8')
 H.Advance(4)
 local others,auto=Others(),Auto()
 local p=Click(save)
 BoundConfirmation('R8',p)
 C.setup(A.SetLoadoutWishlist(6,107)==true and Stored(6)~=nil and Stored(6).name=='W-Free',
  'R8: fixture: Saved Build 6 is given W-Free before the accept',Facts())
 local facts,w=Facts(),Writes()
 local said=Heard(function() Accept(p) end)
 RefusedBeforeUpload('R8',said,facts,w,others,auto)
end)

C.finish('(B1: an explicit Save changes keeps its intent, destination and no-assignment effect through the spacing retry; legacy callers unchanged; the bound plan\'s Save changes is refused before upload when its assignment changes meanwhile)')
