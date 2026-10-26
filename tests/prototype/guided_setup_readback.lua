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

C.finish('(receipts bound to context and read back; unknown, refused, partial, stale and observed are not completion)')
