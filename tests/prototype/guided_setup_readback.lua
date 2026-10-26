-- Guided setup evidence (issue #131): receipts from real outcome sites bound
-- to owner, assignment epoch, world session, destination and Wishlist key,
-- then a fresh read back. Observed-existing; verified then failing/missing
-- read back (unknown) and a later write (stale); refused; a different
-- Wishlist; early, other-destination and forged receipts; owner, session,
-- Wishlist and target changes; delayed role choice; import draft vs saved
-- Create; partial and unconfirmed saves.
-- EXPECT: added behaviour; at 2b287ef8 each scenario reaches its healthy
-- SETUP through the real chooser, editor and adapter, then the EXPECT fails
-- because Nexus.GuidedSetup is absent. GUARD: existing writer and Store
-- behaviour. Fault routers replace one adapter or host field and are
-- restored. Synthetic host services; no native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('guided_setup_readback')
local H,A,G,writes
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity',
 'UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist','ClearFirstRunWishlist','SetFirstRunWishlistIdentity','ConfirmWishlistRoles'}
local NAMES={'ProjectEbonholdEchoJournal','EchoJournalMicroButton','NexusEditorFrame','NexusWishlistNameInput',
 'NexusActiveWishlistSelector','NexusWishlistOnlyPicker','NexusLoadoutAssociationPanel','NexusGuidedSetup',
 'NexusQuickStart','NexusQuickStartEscape','NexusPanel','NexusWishlistRolePicker','NexusWishlistRoleConfirm',
 'NexusWishlistRoleUseOwned','NexusWishlistRoleCancel','NexusWishlistSaveOnlyButton','NexusWishlistAssignNowButton'}

local function Boot(o)
 o=o or {}
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 for _,n in ipairs(NAMES) do _G[n]=nil end
 H=dofile('tests/prototype/harness.lua');H.playerLevel=80
 if o.evidence then
  local rows={}
  for i=1,85 do rows[i]={spellId=200000+i,quality=i%4,stacks=1} end
  H.locked={};for i=80,85 do H.locked[#H.locked+1]={spellId=200000+i,stack=1} end
  H.perks.serverBuildSlots={[1]={name='Saved Build A',verified=true,echoes={{spellId=200086,quality=2,stacks=1}}},
   [2]={name='Saved Build B',verified=true,echoes={{spellId=200087,quality=3,stacks=1}}},
   [101]={name='Evidence Plan',verified=false,echoes=rows}}
  H.perks.serverActiveSlot=1
 else
  wipe(H.db)
  H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5)
  H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
  H.service.GetServerMaxSlots=function() return 6 end
  H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
   [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
  H.perks.serverActiveSlot=2
 end
 H.Boot();A=Nexus.GameAdapter;H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do local real=A[k]
  if type(real)=='function' then writes[k]=0;A[k]=function(...) writes[k]=writes[k]+1;return real(...) end end end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent);journal:Hide()
 CreateFrame('Button','EchoJournalMicroButton',UIParent):SetScript('OnClick',function() journal:Show() end)
end
local function Writes() local n=0;for k,c in pairs(writes) do if k~='ConfirmWishlistRoles' then n=n+c end end;return n end
local function Stored(slot) local s=Nexus.Store.State();return s.loadoutWishlists and s.loadoutWishlists[slot] end
local function Cand(slot) for _,c in ipairs(A.GetWishlistCandidates() or {}) do if tonumber(c.slot)==slot then return c end end end
local function Row(name)
 local p=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(p and p.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
end
-- The real Echo Journal chooser and one explicit row click.
local function Choose(name)
 Nexus.JournalTab.OpenBuilds(true)
 local r=Row(name);if r then r.nameButton:Click() end
 return r~=nil
end
local function Core(tag) G=Nexus.GuidedSetup;return C.expect(G~=nil,tag..': the guided setup core is loaded') end
local function Coach(slot,dest)
 G.Replay();G.SetPath('existing')
 local a=G.ChooseWishlist(Cand(slot));local b=G.ChooseTarget(dest)
 return a and b
end
local function St() return G.AssignStatus().state end
local function Create()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame and V.Plain(f:GetText() or '')=='Create & assign' then
   H.popup=nil;f:Click();local p=H.popup
   if p and p.which=='WISHLISTREALIZER_CREATE_WISHLIST' then H.popup=nil;StaticPopupDialogs[p.which].OnAccept(p.frame,p.data);return true end
  end
 end
 return false
end
local CODE
local function Import(name)
 CODE=CODE or Nexus.Codec.EncodeEBH1({{spellId=201175,quality=0,stacks=1,locked=false}},'MAGE','Starter')
 Nexus.WishlistEditor.ImportEBH1String(CODE,name)
 return _G.NexusEditorFrame~=nil and NexusEditorFrame:IsShown()
end

C.scenario('R1 an existing assignment is observed, never verified',function()
 Boot()
 C.setup(Choose('W-Free') and Stored(2) and Stored(2).name=='W-Free','R1: fixture: Fire PvE already follows W-Free')
 if not Core('R1') then return end
 Coach(107,2)
 C.expect(St()=='observed' and G.TargetFacts().already==true,'R1: observed-existing',St())
 local sm=G.Summary()
 C.expect(sm.complete==false and sm.trueNow==true,'R1: true now, not completed by the guide')
end)

C.scenario('R2 verified only after the write and read back; failing or missing read back is unknown; later write is stale',function()
 Boot()
 C.setup(Cand(107)~=nil and A.SelectedSavedBuild()==2,'R2: fixture: W-Free listed; Fire PvE selected')
 if not Core('R2') then return end
 C.expect(Coach(107,2) and St()=='ready','R2: nothing is claimed before an action',St())
 C.expect(G.ArmAssign()==true and St()=='pending','R2: an armed request with no result is pending',St())
 C.setup(Choose('W-Free'),'R2: fixture: the chooser lists W-Free')
 C.guard(Writes()==1 and Stored(2) and Stored(2).name=='W-Free','R2: one explicit write to Saved Build 2')
 C.expect(St()=='verified','R2: verified from its receipt and the read back',St())
 local real=A.GetLoadoutWishlistState
 A.GetLoadoutWishlistState=function() error('synthetic readback failure') end
 C.expect(St()=='unknown','R2: a failing read back is unknown',St())
 A.GetLoadoutWishlistState=nil
 C.expect(St()=='unknown','R2: a missing getter is unknown',St())
 G.State().index=G.INDEX.assign
 C.expect(not G.CanNext(),'R2: unknown cannot continue')
 A.GetLoadoutWishlistState=real
 C.expect(St()=='verified' and G.CanNext(),'R2: the real read back verifies again')
 C.setup(A.ClearLoadoutWishlist(2)==true,'R2: fixture: another route unassigns Saved Build 2')
 C.expect(St()=='stale' and not G.CanNext(),'R2: a later write makes it stale',St())
end)

C.scenario('R3 refused and R4 a different Wishlist are not completed',function()
 Boot()
 if not Core('R3') then return end
 Coach(107,2);G.ArmAssign()
 local real=A.SetLoadoutWishlist
 A.SetLoadoutWishlist=function() writes.SetLoadoutWishlist=writes.SetLoadoutWishlist+1;return false,'store unavailable' end
 local listed=Choose('W-Free')
 A.SetLoadoutWishlist=real
 C.setup(listed,'R3: fixture: the chooser lists W-Free')
 C.guard(Stored(2)==nil and writes.SetLoadoutWishlist==1,'R3: the refused write changed nothing')
 C.expect(St()=='refused' and G.AssignStatus().reason=='store unavailable','R3: refused, with its reason',St())
 Coach(107,2);G.ArmAssign()
 C.setup(Choose('W-Six') and Stored(2) and Stored(2).name=='W-Six','R4: fixture: W-Six was chosen instead')
 C.expect(St()=='other','R4: another Wishlist is not this request',St())
end)

C.scenario('R5 early, other-destination and forged receipts never verify',function()
 Boot()
 if not Core('R5') then return end
 Coach(107,2)
 local key=G.State().wishlist and G.State().wishlist.key
 G.Note('assign',{destination=2,ok=true,key=key,origin='synthetic'})
 G.ArmAssign()
 C.expect(St()=='pending','R5: a receipt before the request does not count',St())
 G.Note('assign',{destination=1,ok=true,key=key,origin='synthetic'})
 C.expect(St()=='pending','R5: a receipt for another Saved Build does not count',St())
 G.Note('assign',{destination=2,ok=true,key=key,origin='synthetic'})
 C.expect(St()=='unknown' and Stored(2)==nil,'R5: a receipt without a matching write is not verified',St())
 C.guard(Writes()==0,'R5: nothing was written')
end)

C.scenario('R6 owner, session, Wishlist and target changes invalidate evidence',function()
 Boot()
 if not Core('R6') then return end
 Coach(107,2);G.ArmAssign()
 C.setup(Choose('W-Free'),'R6: fixture: real assignment')
 C.expect(St()=='verified','R6: verified first',St())
 local store,key=Nexus.Store,Nexus.Store.CurrentOwnerKey
 store.CurrentOwnerKey=function() return 'someone-else@elsewhere' end
 G.Recheck()
 local cleared=G.State().wishlist==nil and St()=='none'
 store.CurrentOwnerKey=key;G.Recheck()
 C.expect(cleared and St()=='none' and G.State().notice~=nil,'R6: an owner change clears evidence and it is not restored')
 Coach(107,2)
 C.expect(St()=='observed','R6: after replay the assignment is only observed',St())
 Nexus.Panel.ObserveDestinationCharacter(nil,'PLAYER_ENTERING_WORLD')
 C.expect(G.Recheck()=='session' and G.State().wishlist==nil,'R6: a new world session clears it')
 Coach(107,2);G.ArmAssign();G.ChooseWishlist(Cand(106))
 C.expect(G.State().request==nil and St()~='verified','R6: changing the Wishlist drops the request',St())
 Coach(106,1);G.ArmAssign();G.ChooseTarget(2)
 C.expect(G.State().request==nil and St()~='verified','R6: changing the target drops the request',St())
end)

C.scenario('R7 delayed locked-role choice: pending until its own receipt and read back',function()
 Boot({evidence=true})
 Nexus.Store.Settings().useCurrentLocksForUntagged=false
 C.setup(Cand(101)~=nil and Cand(101).lockEvidenceStatus=='unavailable','R7: fixture: an 85-copy plan without lock evidence')
 if not Core('R7') then return end
 C.expect(Coach(101,1) and G.ArmAssign()==true,'R7: request armed for Saved Build A')
 C.setup(Choose('Evidence Plan') and _G.NexusWishlistRolePicker and NexusWishlistRolePicker:IsShown(),'R7: fixture: the role choice opens')
 C.expect(St()=='pending' and Writes()==0,'R7: while the role choice is open nothing is complete',St())
 NexusWishlistRoleUseOwned:Click();NexusWishlistRoleConfirm:Click()
 C.guard(Stored(1) and Stored(1).name=='Evidence Plan','R7: the role picker assigned Saved Build A')
 C.expect(St()=='verified','R7: verified after the delayed receipt and read back',St())
end)

C.scenario('R8 import is a draft; a real Create is saved and verified; partial and unconfirmed saves are not done',function()
 Boot()
 if not Core('R8') then return end
 G.Replay();G.SetPath('new');G.AwaitSave()
 C.setup(Import('Starter'),'R8: fixture: the import opened a draft')
 C.expect(G.State().draft~=nil and G.State().wishlist==nil and G.Summary().wishlist=='draft','R8: an import is a draft, not a saved Wishlist')
 C.setup(Create(),'R8: fixture: Create & assign was confirmed')
 C.guard(Stored(2) and Stored(2).name=='Starter','R8: the Create assigned Saved Build 2 as before')
 local w=G.State().wishlist
 C.expect(w~=nil and w.source=='saved' and w.name=='Starter','R8: the completed save is adopted')
 C.expect(G.ChooseTarget(2) and St()=='verified' and G.AssignStatus().origin=='save','R8: the save receipt verifies by read back',St())
 Boot()
 if not Core('R8b') then return end
 G.Replay();G.AwaitSave()
 local real=A.SetLoadoutWishlistIdentity
 A.SetLoadoutWishlistIdentity=function() return false,'store unavailable' end
 C.setup(Import('Partial plan') and Create(),'R8b: fixture: Create confirmed')
 A.SetLoadoutWishlistIdentity=real
 C.expect(G.State().wishlist==nil and G.Summary().wishlist=='partial','R8b: an uploaded-but-unassigned save is partial',G.Summary().wishlist)
 Boot()
 if not Core('R8c') then return end
 G.Replay();G.AwaitSave()
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function() error('synthetic host failure') end
 C.setup(Import('Erring plan') and Create(),'R8c: fixture: Create confirmed')
 H.service.UploadServerBuildSlot=upload
 C.expect(G.State().wishlist==nil and G.Summary().wishlist=='uncertain','R8c: an unconfirmed upload is not done',G.Summary().wishlist)
end)

-- R9-R15 (operation origin): an outcome is a guide request's own only when its
-- real operation began under that request. Real coach Show and chooser action,
-- real Journal rows, the real role picker and the real Auto-ON confirmation; a
-- request is re-armed while an older operation still waits. EXPECT: an older
-- or originless operation never verifies the newer request (it fails on the
-- base source after healthy SETUP). GUARD: the real write still happens once,
-- and an unchanged request still verifies. No new helper is required.
do
 local CONSENT='NEXUS_ASSIGN_WISHLIST_AUTO_ON'
 -- The real coach: Show, then its own chooser action, which arms a request.
 local function Route(tag)
  local before=G.State().request
  local shown=Nexus.GuidedSetupUI.Show()==true
  Nexus.GuidedSetupUI.RouteChooser()
  local now=G.State().request
  return C.setup(shown and now~=nil and now~=before,tag..': fixture: the real coach Show and chooser action armed a new request'),now
 end
 local function Waiting() return _G.NexusWishlistRolePicker~=nil and NexusWishlistRolePicker:IsShown() end
 local function Confirm()
  if not (_G.NexusWishlistRoleUseOwned and _G.NexusWishlistRoleConfirm) then return false end
  NexusWishlistRoleUseOwned:Click();NexusWishlistRoleConfirm:Click();return true
 end
 local function Cancel()
  if not _G.NexusWishlistRoleCancel then return false end
  NexusWishlistRoleCancel:Click();return true
 end
 local function Evidence(tag)
  Boot({evidence=true})
  Nexus.Store.Settings().useCurrentLocksForUntagged=false
  C.setup(Cand(101)~=nil and Cand(101).lockEvidenceStatus=='unavailable',tag..': fixture: an 85-copy plan without lock evidence')
  return Core(tag) and C.setup(Coach(101,1),tag..': fixture: Evidence Plan and Saved Build A chosen in the coach')
 end
 local function AutoOn(tag)
  SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
  return C.setup(Nexus.RecomputeStats().autoEnabled==true,tag..': fixture: Auto is ON before the choice')
 end
 -- One real chooser row while Auto is ON: its confirmation shown, nothing written.
 local function Ask(tag,name)
  H.popup=nil
  local listed=Choose(name)
  local p=H.popup
  local ok=C.setup(listed and p~=nil and p.which==CONSENT and Writes()==0,
   tag..': fixture: the real chooser asks first while Auto is ON; nothing written',Writes())
  return ok and p or nil
 end
 local function Agree(p) StaticPopupDialogs[p.which].OnAccept(p.frame,p.data) end

 C.scenario('R9 an old delayed role choice confirmed after the coach re-armed is not verified for the new request',function()
  if not Evidence('R9') then return end
  if not Route('R9 request one') then return end
  if not C.setup(Choose('Evidence Plan') and Waiting(),'R9: fixture: the request-one role choice waits') then return end
  if not (Route('R9 request two') and C.setup(Waiting(),'R9: fixture: the old role choice still waits under request two')) then return end
  C.guard(Writes()==0,'R9: nothing was written before the role choice',Writes())
  if not Confirm() then return end
  C.guard(writes.SetLoadoutWishlist==1 and Stored(1) and Stored(1).name=='Evidence Plan','R9: the old role choice really assigned Saved Build A once')
  C.expect(St()~='verified','R9: the request-one role result is NOT verified for request two',St())
  C.expect(G.Summary().complete==false,'R9: core setup is not reported complete from that older operation',St())
 end)

 C.scenario('R10 the same delayed role choice under its own unchanged request is verified',function()
  if not Evidence('R10') then return end
  local armed,req=Route('R10')
  if not (armed and C.setup(Choose('Evidence Plan') and Waiting(),'R10: fixture: the role choice waits')) then return end
  C.guard(St()=='pending' and Writes()==0,'R10: while it waits nothing is complete or written',St())
  if not Confirm() then return end
  C.guard(writes.SetLoadoutWishlist==1 and Stored(1) and Stored(1).name=='Evidence Plan','R10: the role choice assigned Saved Build A once')
  C.guard(G.State().request==req and St()=='verified','R10: the unchanged request is verified by its own delayed result and read back',St())
 end)

 C.scenario('R11 an old Auto-ON confirmation accepted after the coach re-armed is not verified for the new request',function()
  Boot()
  if not (Core('R11') and AutoOn('R11') and C.setup(Coach(107,2),'R11: fixture: W-Free and Fire PvE chosen in the coach')) then return end
  if not Route('R11 request one') then return end
  local p=Ask('R11','W-Free')
  if not (p and Route('R11 request two')) then return end
  Agree(p)
  C.guard(writes.SetLoadoutWishlist==1 and Stored(2) and Stored(2).name=='W-Free','R11: the old confirmation, accepted, really assigned Fire PvE once')
  C.expect(St()~='verified','R11: the request-one confirmation is NOT verified for request two',St())
  C.expect(G.Summary().complete==false,'R11: core setup is not reported complete from that older operation',St())
 end)

 C.scenario('R12 the same Auto-ON confirmation under its own unchanged request is verified',function()
  Boot()
  if not (Core('R12') and AutoOn('R12') and C.setup(Coach(107,2),'R12: fixture: W-Free and Fire PvE chosen in the coach')) then return end
  if not Route('R12') then return end
  local p=Ask('R12','W-Free')
  if not p then return end
  C.guard(St()=='pending','R12: a waiting confirmation is pending, not complete',St())
  Agree(p)
  C.guard(writes.SetLoadoutWishlist==1 and Stored(2) and Stored(2).name=='W-Free','R12: the accepted confirmation assigned Fire PvE once')
  C.guard(St()=='verified','R12: the unchanged request is verified by its own confirmed result and read back',St())
 end)

 C.scenario('R13 a matching immediate choice is verified; a later write reported without the origin the guide issued is not',function()
  Boot()
  if not (Core('R13') and C.setup(Coach(107,2),'R13: fixture: W-Free and Fire PvE chosen in the coach')) then return end
  if not (Route('R13') and C.setup(Choose('W-Free'),'R13: fixture: the chooser lists W-Free')) then return end
  C.guard(Writes()==1 and St()=='verified','R13: the matching immediate choice is verified by its own receipt and read back',St())
  local key=G.State().wishlist.key
  for i,case in ipairs({{'missing'},{'unissued',{}},{'text','journal'}}) do
   if not Route('R13 '..case[1]) then return end
   C.setup(A.SetLoadoutWishlist(2,107)==true and writes.SetLoadoutWishlist==i+1,'R13: fixture: another route writes Fire PvE again ('..case[1]..')')
   G.Note('assign',{destination=2,ok=true,key=key,origin='journal',guide=case[2]})
   C.expect(St()~='verified','R13: a result reported with a '..case[1]..' operation origin is NOT verified',St())
  end
 end)

 C.scenario('R14 a role choice started before any request is not verified for a request armed later',function()
  if not Evidence('R14') then return end
  if not C.setup(G.State().request==nil and Choose('Evidence Plan') and Waiting(),'R14: fixture: a role choice started with no request armed') then return end
  if not (Route('R14') and C.setup(Waiting(),'R14: fixture: the role choice still waits after the coach armed its request')) then return end
  if not Confirm() then return end
  C.guard(writes.SetLoadoutWishlist==1 and Stored(1) and Stored(1).name=='Evidence Plan','R14: the role choice really assigned Saved Build A once')
  C.expect(St()~='verified','R14: a result of an operation started with no request is NOT verified',St())
 end)

 C.scenario('R15 a role choice Cancel reports only for the request it began under',function()
  if not Evidence('R15') then return end
  if not (Route('R15 own') and C.setup(Choose('Evidence Plan') and Waiting(),'R15: fixture: the role choice waits under its own request')) then return end
  if not Cancel() then return end
  C.guard(St()=='cancelled' and Writes()==0,'R15: its own Cancel is its own request outcome; nothing written',St())
  if not C.setup(Coach(101,1),'R15: fixture: the coach choices are made again') then return end
  if not (Route('R15 request one') and C.setup(Choose('Evidence Plan') and Waiting(),'R15: fixture: the request-one role choice waits')) then return end
  if not (Route('R15 request two') and Cancel()) then return end
  C.guard(Writes()==0,'R15: Cancel wrote nothing',Writes())
  C.expect(St()~='cancelled','R15: the request-one Cancel is NOT reported as request two cancelled',St())
 end)
end

C.finish('(receipts bound to context and read back; unknown, refused, partial, stale and observed are not completion)')
