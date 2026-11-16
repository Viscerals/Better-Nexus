-- Priority user bug (reported on Valentinew, USER-REPRODUCED): clicking Create
-- more than once made several identical Wishlists. One logical Create -- one
-- create context, one draft, one name -- reaches the host at most once: a
-- fresh confirmation for the created draft, a repeat inside the service
-- spacing window, a click while the Create waits for that window, a host
-- callback that presses Create again during the save, a delayed server mirror
-- or refresh, and a Create that uploaded but was not assigned upload nothing
-- more. A cancel or an unsubmitted refusal consumes nothing; a changed plan and
-- an explicit New, Copy or Import are separate Creates; Save to the opened
-- Wishlist's own server slot is unchanged.
-- Categories (tests/prototype/view_regression_support.lua): EXPECT is the
-- reproduced defect and fails on the unpatched delivered1704 and current
-- product; GUARD already holds there and must keep holding; SETUP is the
-- fixture. The oracle is the host upload call (server slot 0 is Create) and
-- the assignment writers, never a result row, so delivered1704 (which has no
-- result row) runs the same checks.
-- Real TOC boot, adapter, controller, editor button and the editor's own
-- StaticPopup handlers; the host services are the synthetic harness, and a race
-- is modelled only at the host boundary (the upload call, an assignment
-- writer). Frontend realism: the harness does not model the 3.3.5 StaticPopup
-- and no native double-click is claimed; N1 runs the same clicks with the
-- harness popup and with a labelled MODEL of the client's dialog reuse.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('wishlist_create_once')
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
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function World()
 return {[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
end

local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 -- Named frames of an earlier boot in this process are not this boot's.
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusLoadoutAssociationPanel=nil;NexusWishlistRolePicker=nil;NexusWishlistRoleConfirm=nil
 NexusWishlistRoleUseOwned=nil;NexusWishlistRoleCancel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=H.Clone(o.slots)
 H.perks.serverActiveSlot=o.active
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() spends=spends+1;return false end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 -- Count every assignment writer call (the controller uses this adapter table).
 writes={}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then
   writes[k]=0
   A[k]=function(...) writes[k]=writes[k]+1;return real(...) end
  end
 end
 if o.editor~=false then SlashCmdList.NEXUS('editor') end
end

-- The editor's own controller (no public handle), for fixture checks only.
local function Ctrl()
 local show=Nexus.WishlistEditor and Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 return nil
end
-- Uploads to the create sentinel (server slot 0), optionally of one name.
local function Creates(name)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==0 and (name==nil or a[3]==name) then n=n+1 end end
 return n
end
local function LastCreate()
 local last
 for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==0 then last=a end end
 return last
end
local function UploadsTo(slot)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==slot then n=n+1 end end
 return n
end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
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
local function Name(text) NexusWishlistNameInput:SetText(text) end
local function ClickCatalog(id)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();return true end end
 error('visible catalog row absent: '..id)
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
-- The editor's Create/Save button, whatever it reads now: right after a save it
-- reads Saved and is still enabled, and a refresh turns it back into Create.
-- M3: its label names its effect (Create & assign, Create unassigned, Save &
-- assign, Save changes; legacy Create Wishlist / Save Wishlist). It is created
-- before the Save changes alternative beside it, so it is the first match.
local APPLY_LABELS={['Create Wishlist']=true,['Save Wishlist']=true,['Saved']=true,['Saving...']=true,
 ['Create & assign']=true,['Create unassigned']=true,['Save & assign']=true,['Save changes']=true}
local function ApplyButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame then
   local t=V.Plain(f:GetText() or '')
   if APPLY_LABELS[t] then return f end
  end
 end
 error('the editor Create/Save button is absent')
end
-- One click on that button; the confirmation this click opened, or nil.
local function Click()
 local before=H.popup
 ApplyButton():Click()
 if H.popup~=nil and H.popup~=before then return H.popup end
 return nil
end
-- The client runs a dialog's OnAccept and then hides it (the handler returns
-- nothing); the harness keeps H.popup, so it is cleared here as the client does.
local function Accept(p)
 if not p then return nil end
 if H.popup==p then H.popup=nil end
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
local function Cancel(p)
 if not p then return end
 if H.popup==p then H.popup=nil end
 StaticPopupDialogs[p.which].OnCancel(p.frame,p.data)
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
-- The server lists an upload in a designed slot (a Create uploads to 0).
local function MirrorAt(slot,last)
 local rows=H.Clone(H.perks.serverBuildSlots or {});rows[slot]={name=last[3],verified=false,echoes=H.Clone(last[4])}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(4)
end
-- A first Create of `name` for the draft the editor holds.
local function FirstCreate(tag,name,id)
 Name(name);ClickCatalog(id or 201175)
 local p=Click()
 C.setup(p~=nil and p.which=='WISHLISTREALIZER_CREATE_WISHLIST' and p.arg1==name,
  tag..': fixture: Create asks for confirmation of '..name,p and p.arg1)
 Accept(p)
 C.setup(Creates()==1,tag..': fixture: the first Create uploads once',Creates())
 return p
end

C.scenario('R1 a fresh confirmation for the unchanged created draft (the reported path)',function()
 Boot({active=2,slots=World()})
 local c=Ctrl()
 local target=c and c.CreateTargetContext and c.CreateTargetContext()
 C.setup(NexusEditorFrame and NexusEditorFrame:IsShown() and target and target.loadoutSlot==2,
  'R1: fixture: a new draft captured Saved Build 2 (Fire PvE)')
 FirstCreate('R1','Raid plan')
 C.setup(writes.SetLoadoutWishlistIdentity==1 and Stored(2) and Stored(2).name=='Raid plan',
  'R1: fixture: the Create is assigned to Saved Build 2 once',Facts())
 local facts=Facts()
 -- Later, outside the spacing window and after refreshes: the button reads
 -- Create & assign again and the editor still shows the same draft and name.
 for _=1,3 do Nexus.WishlistEditor.Refresh() end
 H.Advance(4)
 local again
 local said=Heard(function() again=Click();if again then Accept(again) end end)
 H.Advance(4)
 local third=Click();if third then Accept(third) end
 H.Advance(4)
 print('OBSERVED','R1 creates='..Creates()..' assignWrites='..writes.SetLoadoutWishlistIdentity
  ..' offered='..tostring(again~=nil)..'/'..tostring(third~=nil)..' said='..said)
 C.expect(Creates()==1,'R1: a second and a third click + accept on the created draft upload nothing',Creates())
 C.expect(writes.SetLoadoutWishlistIdentity==1 and Facts()==facts,'R1: and assign nothing again',Facts())
 C.expect(again==nil and third==nil,'R1: no further confirmation is offered for the created draft')
 C.expect(said:find('already created',1,true)~=nil,'R1: the click says the draft was already created',said)
 C.guard(Stored(2) and Stored(2).name=='Raid plan','R1: Saved Build 2 keeps the created Raid plan',Facts())
 C.guard(spends==0 and not Nexus.WishlistEditor.IsApplyPending(),'R1: no spend; nothing queued')
end)

C.scenario('R2 an immediate repeat inside the spacing window is not delayed into a second Wishlist',function()
 Boot({active=2,slots=World()})
 FirstCreate('R2','Quick plan')
 -- The next click lands at once, while the button still reads Saved.
 local again=Click();if again then Accept(again) end
 local pending=Nexus.WishlistEditor.IsApplyPending()
 H.Advance(5)
 print('OBSERVED','R2 creates='..Creates()..' queued='..tostring(pending)..' offered='..tostring(again~=nil))
 C.expect(not pending,'R2: the repeat is not queued behind the spacing guard')
 C.expect(Creates()==1,'R2: after the spacing window passes nothing more is uploaded',Creates())
 C.expect(again==nil,'R2: the repeat opens no confirmation')
 C.guard(Stored(2) and Stored(2).name=='Quick plan','R2: the one Create is assigned',Facts())
end)

C.scenario('R3 a host callback that presses Create again during the upload',function()
 Boot({active=2,slots=World()})
 Name('Reentrant plan');ClickCatalog(201175)
 local upload=H.service.UploadServerBuildSlot
 local depth,inner=0,{}
 H.service.UploadServerBuildSlot=function(...)
  depth=depth+1
  local ok=upload(...)
  if depth==1 then
   -- The adapter calls the host inside pcall: record that the callback ran.
   local p=Click()
   inner.clicked=true
   inner.offered=p~=nil
   if p then Accept(p) end
   -- The retry pump re-entered from the same callback.
   Nexus.WishlistEditor._PumpApplyRetry()
   inner.pumped=true
  end
  depth=depth-1
  return ok
 end
 local p=Click()
 C.setup(p~=nil,'R3: fixture: Create asks for confirmation')
 Accept(p)
 H.service.UploadServerBuildSlot=upload
 H.Advance(5)
 print('OBSERVED','R3 creates='..Creates()..' innerOffered='..tostring(inner.offered))
 C.setup(inner.clicked==true and inner.pumped==true,'R3: fixture: the callback pressed Create and pumped the retry')
 C.expect(Creates()==1,'R3: the Create pressed again inside the upload call uploads nothing',Creates())
 C.expect(not inner.offered,'R3: no confirmation is offered while the upload runs')
 C.guard(Stored(2) and Stored(2).name=='Reentrant plan','R3: the Create itself is saved and assigned',Facts())
end)

C.scenario('R3b a callback that presses Create again while the Create is being assigned',function()
 Boot({active=2,slots=World()})
 Name('Writer plan');ClickCatalog(201175)
 local real=A.SetLoadoutWishlistIdentity
 local inner={}
 A.SetLoadoutWishlistIdentity=function(...)
  if not inner.done then
   inner.done=true
   local p=Click()
   inner.offered=p~=nil
   if p then Accept(p) end
  end
  return real(...)
 end
 local p=Click()
 C.setup(p~=nil,'R3b: fixture: Create asks for confirmation')
 Accept(p)
 A.SetLoadoutWishlistIdentity=real
 H.Advance(5)
 print('OBSERVED','R3b creates='..Creates()..' innerOffered='..tostring(inner.offered))
 C.setup(inner.done==true,'R3b: fixture: the assignment writer ran')
 C.expect(not inner.offered,'R3b: no confirmation is offered while the Create is being assigned')
 C.guard(Creates()==1,'R3b: one upload',Creates())
 C.guard(Stored(2) and Stored(2).name=='Writer plan','R3b: the Create is assigned',Facts())
end)

C.scenario('R4 a Create that uploaded but was not assigned is never uploaded again',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 local c=Ctrl()
 C.setup(c and c.CreateTargetContext and c.CreateTargetContext()==nil and not c.IsEditing(),
  'R4: fixture: a new first-run draft')
 -- The first-run writer refuses after the real upload (forced at the adapter boundary).
 local writer=A.SetFirstLoadoutWishlistIdentity
 A.SetFirstLoadoutWishlistIdentity=function()
  writes.SetFirstLoadoutWishlistIdentity=writes.SetFirstLoadoutWishlistIdentity+1;return false
 end
 FirstCreate('R4','Starter',201174)
 A.SetFirstLoadoutWishlistIdentity=writer
 C.setup(not Stored('first') and writes.SetFirstLoadoutWishlistIdentity==1,
  'R4: fixture: the upload was accepted and its assignment refused',Facts())
 H.Advance(4)
 local again=Click();if again then Accept(again) end
 H.Advance(4)
 print('OBSERVED','R4 creates='..Creates()..' offered='..tostring(again~=nil)..' facts='..Facts())
 C.expect(Creates()==1,'R4: pressing Create again after the partial save uploads nothing',Creates())
 C.expect(again==nil,'R4: and offers no new confirmation')
 C.expect(not Stored('first') and writes.SetFirstLoadoutWishlistIdentity==1,
  'R4: nothing is assigned behind the player\'s back by a repeat',Facts())
end)

C.scenario('N1 double and triple clicks before accepting, and a repeated accept callback',function()
 for _,model in ipairs({false,true}) do
  local tag=model and 'N1 MODEL' or 'N1'
  Boot({active=2,slots=World()})
  if model then
   -- MODEL of the 3.3.5 StaticPopup reuse, not native evidence: showing a
   -- dialog that is already shown first cancels it with its old data.
   local show=StaticPopup_Show
   StaticPopup_Show=function(which,a,b,data)
    local open=H.popup
    if open and open.which==which then
     local d=StaticPopupDialogs[which]
     if d and d.OnCancel then d.OnCancel(open.frame,open.data,'override') end
    end
    return show(which,a,b,data)
   end
  end
  Name('Clicky plan');ClickCatalog(201175)
  local first=Click();local second=Click();local third=Click()
  C.setup(first~=nil and second~=nil and third~=nil,tag..': fixture: each click before accepting shows the confirmation')
  local shown=H.popup
  Accept(shown)
  C.guard(Creates()==1,tag..': accepting the one shown confirmation uploads once',Creates())
  -- The same confirmation accepted again (a repeated callback) and a superseded one.
  if shown then StaticPopupDialogs[shown.which].OnAccept(shown.frame,shown.data) end
  if first then StaticPopupDialogs[first.which].OnAccept(first.frame,first.data) end
  H.Advance(5)
  C.guard(Creates()==1,tag..': a repeated or superseded accept uploads nothing',Creates())
  C.guard(writes.SetLoadoutWishlistIdentity==1,tag..': one assignment',writes.SetLoadoutWishlistIdentity)
 end
end)

C.scenario('R6 a Create waiting for the spacing guard is sent exactly once',function()
 Boot({active=2,slots=World()})
 C.setup(KnownSlotUpload(A.UploadWishlist,103,'Spacer',H.Clone(EF))==true,'R6: fixture: an earlier upload starts the spacing window')
 Name('Spaced plan');ClickCatalog(201175)
 local p=Click()
 C.setup(p~=nil,'R6: fixture: Create asks for confirmation')
 Accept(p)
 C.setup(Nexus.WishlistEditor.IsApplyPending() and Creates()==0,'R6: fixture: the Create waits for the spacing guard')
 -- A click while it waits (before the button is redrawn as Saving...).
 local again=Click()
 H.Advance(4)
 C.setup(Creates()==1,'R6: fixture: the held Create is sent once the window passes',Creates())
 -- The confirmation that click opened is accepted after the held Create went out.
 if again then Accept(again) end
 H.Advance(5)
 print('OBSERVED','R6 creates='..Creates()..' offered='..tostring(again~=nil))
 C.expect(again==nil,'R6: a click while the Create waits opens no second confirmation')
 C.expect(Creates()==1,'R6: the held Create is sent exactly once',Creates())
 C.guard(not Nexus.WishlistEditor.IsApplyPending(),'R6: nothing stays queued')
 H.Advance(8)
 C.expect(Creates()==1 and writes.SetLoadoutWishlistIdentity==1,'R6: and nothing is sent or assigned later',Creates())
end)

C.scenario('R7 the server listing the new Wishlist later does not re-admit its draft',function()
 Boot({active=2,slots=World()})
 FirstCreate('R7','Mirror plan')
 for _=1,3 do Nexus.WishlistEditor.Refresh() end
 H.Advance(2)
 MirrorAt(108,LastCreate())
 C.setup(A.Slots() and A.Slots().bySlot[108] and A.Slots().bySlot[108].name=='Mirror plan',
  'R7: fixture: the server now lists Mirror plan')
 local again=Click();if again then Accept(again) end
 H.Advance(5)
 print('OBSERVED','R7 creates='..Creates()..' offered='..tostring(again~=nil))
 C.expect(Creates()==1,'R7: Create after the mirror refresh uploads nothing more',Creates())
 C.expect(again==nil,'R7: and offers no confirmation')
 C.guard(A.Slots().bySlot[108].name=='Mirror plan','R7: the listed Wishlist is untouched')
end)

C.scenario('R8 a cancel or an unsubmitted refusal consumes nothing',function()
 Boot({active=2,slots=World()})
 Name('Careful plan');ClickCatalog(201175)
 local p=Click()
 C.setup(p~=nil,'R8: fixture: Create asks for confirmation')
 Cancel(p)
 C.guard(Creates()==0 and Writes()==0 and not Nexus.WishlistEditor.IsApplyPending(),'R8: Cancel uploads, assigns and queues nothing')
 -- The host refuses the upload: nothing was sent.
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function() return false end
 p=Click()
 C.guard(p~=nil,'R8: after Cancel, Create is offered again')
 Accept(p)
 H.service.UploadServerBuildSlot=upload
 C.guard(Creates()==0 and Writes()==0,'R8: a refused upload sends and assigns nothing')
 p=Click()
 C.guard(p~=nil,'R8: after a cancel and a refused upload, Create is offered again')
 Accept(p)
 C.guard(Creates()==1 and Stored(2) and Stored(2).name=='Careful plan','R8: and the Create is saved once',Facts())
 -- A confirmation made stale by an edit uploads nothing, and the next Create does.
 Boot({active=2,slots=World()})
 Name('Edited plan');ClickCatalog(201175)
 p=Click()
 C.setup(p~=nil,'R8: fixture: Create asks for confirmation')
 ClickCatalog(201172)
 Accept(p)
 C.guard(Creates()==0,'R8: a confirmation for an edited draft uploads nothing',Creates())
 p=Click()
 C.guard(p~=nil,'R8: the edited draft is offered for Create')
 Accept(p)
 C.guard(Creates()==1,'R8: and is created once',Creates())
end)

C.scenario('R9 a changed plan and an explicit New, Copy or Import are separate Creates',function()
 Boot({active=2,slots=World()})
 FirstCreate('R9','Plan A')
 H.Advance(4)
 -- The plan changes: another logical Create.
 ClickCatalog(201172)
 local p=Click()
 C.guard(p~=nil,'R9: a changed plan is offered for Create')
 Accept(p);H.Advance(4)
 C.guard(Creates()==2,'R9: the changed plan is created',Creates())
 -- New Wishlist with the same Echo and the same name.
 Nexus.WishlistEditor.NewWishlist()
 Name('Plan A');ClickCatalog(201175)
 p=Click()
 C.guard(p~=nil,'R9: New Wishlist starts a draft that can be created')
 Accept(p);H.Advance(4)
 C.guard(Creates()==3,'R9: the New draft is created',Creates())
 -- Copy of a record.
 C.setup(Nexus.WishlistEditor.OpenForCandidate({title='Plan A',echoes=H.Clone(E2)})==true,
  'R9: fixture: Copy opens a draft')
 p=Click()
 C.guard(p~=nil,'R9: the Copy can be created')
 Accept(p);H.Advance(4)
 C.guard(Creates()==4,'R9: the Copy is created',Creates())
 -- Import of a code.
 local code=Nexus.Codec.EncodeEBH1({{spellId=201175,quality=0,stacks=1,locked=false}},'MAGE','Plan A')
 C.setup(type(code)=='string' and code:sub(1,6)~='EBH1::','R9: fixture: an import code')
 Nexus.WishlistEditor.ImportEBH1String(code,'Plan A')
 p=Click()
 C.guard(p~=nil,'R9: the Import can be created')
 Accept(p);H.Advance(4)
 C.guard(Creates()==5,'R9: the Import is created',Creates())
 -- Each of those, pressed again, is the same draft again.
 local again=Click();if again then Accept(again) end
 H.Advance(4)
 C.expect(Creates()==5,'R9: the imported draft pressed again uploads nothing',Creates())
end)

C.scenario('R11 Save to the opened Wishlist still saves each time',function()
 Boot({active=6,slots=World(),editor=false})
 local ok,why=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6))
 C.setup(ok,'R11: fixture: Saved Build 6 is assigned W-Six',why)
 H.Notify();A.Poll();H.Advance(1)
 for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==106 then Nexus.WishlistEditor.OpenForWishlist(c,6) end end
 local c=Ctrl()
 local ctx=c and c.EditingContext and c.EditingContext() or {}
 C.setup(ctx.name=='W-Six' and ctx.loadoutSlot==6,'R11: fixture: W-Six is open for Saved Build 6',ctx.name)
 local function SaveEdit()
  selected(201173).plus:Click()
  local p=Click()
  C.setup(p~=nil and p.which=='WISHLISTREALIZER_UPDATE_WISHLIST','R11: fixture: Save asks for confirmation')
  Accept(p)
 end
 SaveEdit();H.Advance(4);SaveEdit();H.Advance(4)
 C.guard(UploadsTo(106)==2 and Creates()==0,'R11: two Saves upload to W-Six\'s own server Wishlist',UploadsTo(106))
 -- An immediate second Save waits for the spacing guard and is still sent.
 SaveEdit();SaveEdit()
 C.guard(Nexus.WishlistEditor.IsApplyPending(),'R11: the next Save waits for the spacing guard')
 H.Advance(5)
 C.guard(UploadsTo(106)==4 and Creates()==0 and Stored(6) and Stored(6).name=='W-Six',
  'R11: the held Save is sent, as before; nothing is created',UploadsTo(106))
end)

C.finish('(one logical Create uploads once; production editor path; native popup not claimed)')
