-- M3 review repair B2/NB3/NB1/NB4 (independent review, combined-03): every
-- assignment route the player starts while Auto is selected discloses Auto's
-- consequence BEFORE any role choice or assignment is written.
--   B2: the Echo Journal chooser's rows for a Wishlist without lock evidence
--       (80-85 copies; the current-lock default, a remembered role choice, and
--       the manual role picker) ask first. Cancel writes nothing and begins no
--       role choice; Assign writes exactly the target the chooser captured; a
--       stale answer or a changed selection refuses.
--   NB3: the editor's tracking candidates (several, or exactly one; normal and
--       role-pending) ask through the same confirmation; the Saved Build named
--       is revalidated on Assign.
--   NB1: the confirmation makes no timing promise.
--   NB4: with Auto selected and no confirmation UI, nothing is assigned and the
--       player is told why; one confirmation assigns at most once.
-- Auto OFF and the first-run target keep one-click behaviour (GUARD).
-- Categories (view_regression_support): EXPECT fails on the exact combined-03
-- preimage (2594d591) by design; GUARD already holds there and must keep
-- holding; SETUP is the fixture (pre-click, or a state both cuts reach).
-- Oracles: the confirmation the client shows (H.popup), call-through counts
-- of the role and assignment writers at the adapter boundary, the role entry
-- (WishlistEditor.ResolveAndAssignWishlist), the role picker frame, the saved
-- assignment/role fields and Auto's state. Real TOC boot, Journal chooser,
-- editor refresh and StaticPopup handlers; synthetic host services only.
-- Route note: the editor's candidate buttons are filled by the tracking block
-- and hidden again by the name-field block of the same refresh (recorded as
-- ROUTE UNREACHED by saved_build_wishlist_evidence_picker R2). The E scenarios
-- press each button's own installed handler: a handler-level regression, not a
-- claim that a player can reach those buttons today. No native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_assignment_consent_routes')
local H,A,writes,calls,resolves,spends
local CONSENT='NEXUS_ASSIGN_WISHLIST_AUTO_ON'
local BUILD_A,BUILD_B='Saved Build A','Saved Build B'
local EVIDENCE,PLAIN='Evidence Plan','Plain Plan'
local EVIDENCE_SLOT,PLAIN_SLOT=101,102
local TARGET_A="Saved Build '"..BUILD_A.."'"
local WRITERS={'ConfirmWishlistRoles','SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
-- Words that would promise a timing or an unconditional replacement.
local BANNED={'within seconds','seconds','right away','immediately','will replace','at once'}
-- Harness catalog: 200000+i has quality i%4.
local function EvidenceEchoes()
 local rows={}
 for i=1,85 do rows[#rows+1]={spellId=200000+i,quality=i%4,stacks=1} end
 return rows
end
local LOCKS={}
for i=80,85 do LOCKS[#LOCKS+1]={spellId=200000+i,stack=1} end
-- 'plain' or 'evidence' keeps one designed Wishlist; nil keeps both.
local function Rows(only)
 local rows={[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=1}}},
  [2]={name=BUILD_B,verified=true,echoes={{spellId=200087,quality=3,stacks=1}}}}
 if only~='plain' then rows[EVIDENCE_SLOT]={name=EVIDENCE,verified=false,echoes=EvidenceEchoes()} end
 if only~='evidence' then
  rows[PLAIN_SLOT]={name=PLAIN,verified=false,echoes={{spellId=200089,quality=1,stacks=1},{spellId=200090,quality=2,stacks=1}}}
 end
 return rows
end
-- A fresh boot of the real TOC at level 80: Saved Builds A (1) and B (2), the
-- Wishlists named in Rows, six current locks (200080-85).
local function Boot(o)
 o=o or {}
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusWishlistEditorLoadoutMenu=nil;NexusWishlistSaveOnlyButton=nil;NexusPanel=nil
 NexusLoadoutAssociationPanel=nil
 NexusWishlistRolePicker=nil;NexusWishlistRoleConfirm=nil;NexusWishlistRoleUseOwned=nil;NexusWishlistRoleCancel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 H.locked=H.Clone(LOCKS)
 H.perks.serverBuildSlots=Rows(o.only)
 H.perks.serverActiveSlot=o.active or 1
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() spends=spends+1;return false end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if o.manual then Nexus.Store.Settings().useCurrentLocksForUntagged=false end
 writes,calls={},{}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then
   writes[k]=0
   A[k]=function(...)
    writes[k]=writes[k]+1
    local call={fn=k,a1=(...),a2=select(2,...)}
    calls[#calls+1]=call
    local r1,r2,r3,r4,r5=real(...)
    call.ok=r1
    return r1,r2,r3,r4,r5
   end
  end
 end
 -- The role entry both the chooser and the editor call (looked up per call).
 local editor=Nexus.WishlistEditor
 local resolve=editor.ResolveAndAssignWishlist
 resolves=0
 editor.ResolveAndAssignWishlist=function(...) resolves=resolves+1;return resolve(...) end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
-- Writer counts start again after a fixture write.
local function Zero() for k in pairs(writes) do writes[k]=0 end;calls={};resolves=0 end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Roles() return writes.ConfirmWishlistRoles or 0 end
-- Accepted writer calls of `fn` for this first argument.
local function Wrote(fn,a1)
 local n=0
 for _,c in ipairs(calls) do if c.fn==fn and c.ok==true and (a1==nil or tonumber(c.a1)==a1) then n=n+1 end end
 return n
end
local function Desc()
 local out={}
 for _,c in ipairs(calls) do out[#out+1]=c.fn..'('..tostring(c.a1)..','..tostring(c.a2)..')->'..tostring(c.ok) end
 return #out>0 and table.concat(out,'; ') or 'none'
end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function TurnAutoOn() SlashCmdList.NEXUS('auto');H.Advance(.2,.1) end
local function Stored(where)
 local s=Nexus.Store.State() or {}
 if where=='first' then return s.firstRunWishlist end
 return type(s.loadoutWishlists)=='table' and s.loadoutWishlists[where] or nil
end
local function Ser(v,depth)
 depth=depth or 0
 if type(v)=='string' then return string.format('%q',v) end
 if type(v)~='table' then return tostring(v) end
 if depth>8 then return '{...}' end
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Ser(v[k],depth+1) end
 return '{'..table.concat(out,',')..'}'
end
-- Every saved assignment and role choice of this character, comparable.
local function Saved()
 local s=Nexus.Store.State() or {}
 return 'links='..Ser(s.loadoutWishlists)..' first='..Ser(s.firstRunWishlist)..' roles='..Ser(s.wishlistRoleChoices)
end
local function Settings()
 local s=Nexus.Store.Settings() or {}
 local keys={}
 for k,v in pairs(s) do if type(v)~='table' and type(v)~='function' then keys[#keys+1]=tostring(k)..'='..tostring(v) end end
 table.sort(keys)
 return table.concat(keys,';')
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
local function Asked(p)
 if not p then return nil end
 local d=StaticPopupDialogs[p.which] or {}
 local ok,s=pcall(string.format,tostring(d.text or ''),p.arg1,p.arg2)
 return V.Plain(ok and s or tostring(d.text or ''))
end
-- The client runs a dialog's OnAccept and hides it; the harness keeps H.popup.
local function Accept(p)
 if not p then return nil end
 if H.popup==p then H.popup=nil end
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
-- The same answer delivered a second time (a repeated callback).
local function AcceptAgain(p)
 if not p then return nil end
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
-- The client hides a dialog on Cancel; this one has nothing to undo.
local function Dismiss(p)
 if not p then return end
 local d=StaticPopupDialogs[p.which]
 if H.popup==p then H.popup=nil end
 if d and type(d.OnCancel)=='function' then d.OnCancel(p.frame,p.data) end
end
-- One press; the Auto-ON confirmation it opened, or nil.
local function Press(button)
 H.popup=nil
 if button then button:Click() end
 local p=H.popup
 if p and p.which==CONSENT then return p end
 return nil
end
local function RolePickerShown() return _G.NexusWishlistRolePicker~=nil and NexusWishlistRolePicker:IsShown()==true end
local function RolePickerMessage()
 local f=_G.NexusWishlistRolePicker
 return f and f.message and V.Plain(tostring(f.message:GetText() or '')) or ''
end
-- If the current-lock default left the role picker open with Confirm enabled,
-- the player presses Confirm (as saved_build_wishlist_evidence_picker does).
local function RepeatIfOpen()
 if RolePickerShown() and NexusWishlistRoleConfirm and NexusWishlistRoleConfirm:IsEnabled() then NexusWishlistRoleConfirm:Click() end
end
local function SetActive(slot) H.perks.serverActiveSlot=slot;H.Notify();A.Poll();H.Advance(1) end

-- The Echo Journal's Wishlist chooser, opened for the Saved Build it targets.
local function OpenPicker()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Show();Nexus.JournalTab.RefreshAssociations()
 local selector=_G.NexusActiveWishlistSelector
 if selector and selector:IsVisible() and not (_G.NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown()) then
  selector:Click()
 end
 return _G.NexusWishlistOnlyPicker~=nil and NexusWishlistOnlyPicker:IsShown()
end
local function PickerRow(name)
 local picker=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(picker and picker.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
 return nil
end
local function RowText(row) return row and V.Plain(tostring(row.nameButton.text:GetText() or '')) or '' end
-- The chooser open with this row listed; the row and its plain text.
local function ChooserRow(tag,name,needsRoles)
 C.setup(OpenPicker(),tag..': fixture: the Wishlist chooser is open')
 local row=PickerRow(name)
 local text=RowText(row)
 C.setup(row~=nil and (not needsRoles or text:find('use current locks',1,true)~=nil
  or text:find('choose locked targets',1,true)~=nil),tag..': fixture: the chooser lists '..name
  ..(needsRoles and ' as needing locked targets (no lock evidence, 85 copies)' or ''),text)
 return row and row.nameButton or nil
end

-- The editor's candidate buttons as the real refresh filled them.
local function EditorCandidates()
 Nexus.WishlistEditor.Show();Nexus.WishlistEditor.Refresh()
 local out={}
 for _,f in ipairs(NexusEditorFrame and NexusEditorFrame.children or {}) do
  local p=f.points and f.points[1]
  if f.kind=='Button' and f.width==115 and f.height==20 and p and p[5]==-112 then out[#out+1]=f end
 end
 return out
end
local function EditorCandidate(tag,name)
 local buttons=EditorCandidates()
 local found,named=nil,{}
 for _,b in ipairs(buttons) do
  local t=V.Plain(tostring(b:GetText() or ''))
  if t~='' then named[#named+1]=t end
  if t:find(name,1,true) then found=b end
 end
 C.setup(Nexus.GameAdapter.Wishlist()==nil and found~=nil and found:GetScript('OnClick')~=nil,
  tag..': fixture: no Wishlist is tracked and the editor refresh filled a candidate button for '..name,
  table.concat(named,' | '))
 return found,#named
end

C.scenario('C0 NB1: the Auto-ON confirmation makes no timing promise and keeps its consequence and safe path',function()
 Boot()
 local d=StaticPopupDialogs[CONSENT]
 local text=V.Plain(tostring(d and d.text or '')):lower()
 local hit
 for _,w in ipairs(BANNED) do if text:find(w,1,true) then hit=w end end
 print('OBSERVED','C0 text='..text)
 C.expect(d~=nil and hit==nil,'C0: the confirmation names no timing (no "within seconds", "right away", "immediately")',hit)
 C.guard(text:find('auto is on',1,true)~=nil and text:find('may replace',1,true)~=nil and text:find('level 80',1,true)~=nil
  and text:find('cancel changes nothing',1,true)~=nil and text:find('turn auto off, then assign',1,true)~=nil,
  'C0: it still names Auto, the conditional replacement, Cancel and the Auto-OFF path',text)
end)

C.scenario('C1 B2 current-lock default, Auto ON: the chooser asks before any role choice; Cancel writes nothing',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto(),'C1: fixture: Auto is ON')
 local button=ChooserRow('C1',EVIDENCE,true)
 local saved,settings=Saved(),Settings()
 Zero()
 local p=Press(button)
 local asked=Asked(p)
 print('OBSERVED','C1 confirmation='..tostring(asked)..' calls='..Desc()..' resolves='..resolves)
 C.expect(p~=nil and p.arg1==EVIDENCE and p.arg2==TARGET_A,'C1: the click asks first, naming the Wishlist and Saved Build A',
  p and (tostring(p.arg1)..' / '..tostring(p.arg2)) or 'no confirmation')
 C.expect(Writes()==0 and resolves==0 and not RolePickerShown() and Saved()==saved,
  'C1: nothing is written and no role choice begins before the answer',Desc())
 C.expect(asked~=nil and asked:find('Auto is ON',1,true)~=nil and asked:find('Cancel changes nothing',1,true)~=nil,
  'C1: the confirmation says Auto is ON and that Cancel changes nothing',asked)
 Dismiss(p)
 C.expect(p~=nil and Writes()==0 and resolves==0 and not RolePickerShown() and Saved()==saved,
  'C1: Cancel writes no role choice and no assignment',Desc())
 C.guard(Auto() and Settings()==settings and spends==0,'C1: Auto stays ON; no setting changes; nothing is spent')
end)

C.scenario('C2 B2 current-lock default, Auto ON: Assign confirms the roles and assigns exactly Saved Build A, once',function()
 Boot()
 TurnAutoOn()
 local button=ChooserRow('C2',EVIDENCE,true)
 Zero()
 local p=Press(button)
 C.expect(p~=nil and Writes()==0 and resolves==0,'C2: the click asks first; nothing is written yet',Desc())
 Accept(p)
 RepeatIfOpen()
 print('OBSERVED','C2 calls='..Desc())
 C.guard(Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Writes()==2 and Stored(1)~=nil and Stored(1).name==EVIDENCE
  and Stored(2)==nil and Stored('first')==nil and not RolePickerShown(),
  'C2: after the answer the roles are confirmed once and Saved Build A (only) holds the Wishlist',Desc())
 AcceptAgain(p)
 C.guard(Roles()==1 and Writes()==2,'C2: the same answer delivered again writes nothing more',Desc())
 C.guard(Auto() and spends==0,'C2: Auto stays ON; nothing is spent')
end)

C.scenario('C3 B2 a stale answer refuses: the character changed, or the Journal selection changed',function()
 Boot()
 TurnAutoOn()
 local button=ChooserRow('C3',EVIDENCE,true)
 local saved=Saved()
 Zero()
 local p=Press(button)
 local store=Nexus.Store
 local key=store.CurrentOwnerKey
 store.CurrentOwnerKey=function() return 'someone-else@elsewhere' end
 local said=Heard(function() Accept(p) end)
 store.CurrentOwnerKey=key
 C.expect(p~=nil and Writes()==0 and resolves==0 and Saved()==saved and said:find('Nothing was assigned',1,true)~=nil,
  'C3: an answer after the character data changed writes nothing and says why',said)
 -- The selection moves to Saved Build B before Assign: the role step refuses.
 Boot()
 TurnAutoOn()
 button=ChooserRow('C3b',EVIDENCE,true)
 saved=Saved()
 Zero()
 p=Press(button)
 SetActive(2)
 local w=Writes()
 Accept(p)
 print('OBSERVED','C3b calls='..Desc()..' picker='..tostring(RolePickerShown())..' message='..RolePickerMessage())
 C.expect(p~=nil and w==0 and Writes()==0 and Saved()==saved and Stored(1)==nil and Stored(2)==nil,
  'C3b: Assign after the selection changed writes no role choice and no assignment',Desc())
 C.expect(p~=nil and RolePickerShown() and RolePickerMessage():find('active loadout changed',1,true)~=nil,
  'C3b: the role picker keeps the existing refusal (the active loadout changed)',RolePickerMessage())
 C.guard(Auto(),'C3: Auto stays ON')
end)

C.scenario('C4 B2 manual role mode, Auto ON: no role picker before the answer; Cancel opens none',function()
 Boot({manual=true})
 TurnAutoOn()
 C.setup(Nexus.Store.Settings().useCurrentLocksForUntagged==false,'C4: fixture: manual role mode')
 local button=ChooserRow('C4',EVIDENCE,true)
 local saved=Saved()
 Zero()
 local p=Press(button)
 print('OBSERVED','C4 picker='..tostring(RolePickerShown())..' resolves='..resolves)
 C.expect(p~=nil and resolves==0 and not RolePickerShown(),'C4: the click asks first; the role picker is not opened yet')
 C.guard(Writes()==0 and Saved()==saved,'C4: nothing is written at the click',Desc())
 Dismiss(p)
 C.expect(p~=nil and resolves==0 and not RolePickerShown() and Writes()==0 and Saved()==saved,
  'C4: Cancel opens no role picker and writes nothing',Desc())
 C.guard(Auto(),'C4: Auto stays ON')
end)

C.scenario('C5 B2 manual role mode, Auto ON: Assign opens the role picker; its Confirm assigns exactly Saved Build A',function()
 Boot({manual=true})
 TurnAutoOn()
 local button=ChooserRow('C5',EVIDENCE,true)
 Zero()
 local p=Press(button)
 C.expect(p~=nil and resolves==0 and not RolePickerShown(),'C5: the click asks first')
 Accept(p)
 C.guard(RolePickerShown() and Writes()==0 and NexusWishlistRoleConfirm and not NexusWishlistRoleConfirm:IsEnabled(),
  'C5: after the answer the role picker is open, Confirm waits, nothing is written')
 NexusWishlistRoleUseOwned:Click()
 NexusWishlistRoleConfirm:Click()
 print('OBSERVED','C5 calls='..Desc())
 C.guard(Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Writes()==2 and Stored(1)~=nil and Stored(1).name==EVIDENCE
  and Stored(2)==nil and not RolePickerShown(),'C5: the role picker confirms once and assigns exactly Saved Build A',Desc())
 C.guard(Auto(),'C5: Auto stays ON')
end)

C.scenario('C6 B2 a remembered role choice (actionable), Auto ON: asks first; Assign writes exactly Saved Build A',function()
 Boot()
 TurnAutoOn()
 local button=ChooserRow('C6',EVIDENCE,true)
 -- A role choice for this Wishlist is remembered after the chooser listed it
 -- (as the editor's role picker does), so the click resolves it directly.
 local live
 for _,c in ipairs(A.GetWishlistCandidates()) do if tonumber(c.slot)==EVIDENCE_SLOT then live=c end end
 local typed={}
 for i=1,85 do typed[i]={spellId=200000+i,quality=i%4,stacks=1,locked=i>=80} end
 local remembered=live and A.ConfirmWishlistRoles(live,typed,'user-confirmed')
 C.setup(type(remembered)=='table','C6: fixture: a role choice for '..EVIDENCE..' is remembered')
 local probe={slot=EVIDENCE_SLOT,name=EVIDENCE,key=live and live.key,lockEvidenceStatus='unavailable',echoes={}}
 for i,e in ipairs(live and live.echoes or {}) do probe.echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks} end
 local _,status=A.ResolveWishlistEvidence(probe)
 C.setup(status=='actionable','C6: fixture: the listed row now resolves as actionable',status)
 local saved=Saved()
 Zero()
 local p=Press(button)
 print('OBSERVED','C6 calls='..Desc()..' resolves='..resolves)
 C.expect(p~=nil and Writes()==0 and resolves==0 and Saved()==saved,'C6: the click asks first; nothing is assigned yet',Desc())
 Accept(p)
 C.guard(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Roles()==0 and Stored(1)~=nil and Stored(1).name==EVIDENCE
  and Stored(2)==nil,'C6: after the answer exactly Saved Build A is assigned, from the remembered roles',Desc())
 C.guard(Auto(),'C6: Auto stays ON')
end)

C.scenario('C7 B2 guards: Auto OFF assigns at the click; the first-run target needs no confirmation',function()
 Boot()
 C.setup(not Auto(),'C7: fixture: Auto is OFF')
 local button=ChooserRow('C7',EVIDENCE,true)
 Zero()
 local p=Press(button)
 RepeatIfOpen()
 C.guard(p==nil and H.popup==nil and Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Stored(1)~=nil
  and Stored(1).name==EVIDENCE and not Auto(),'C7: with Auto OFF one click confirms the roles and assigns Saved Build A',Desc())
 Boot({active=0})
 TurnAutoOn()
 C.setup(Auto(),'C7b: fixture: Auto is ON and no Saved Build is active')
 button=ChooserRow('C7b',EVIDENCE,true)
 Zero()
 p=Press(button)
 RepeatIfOpen()
 C.guard(p==nil and H.popup==nil and Roles()==1 and Wrote('SetFirstRunWishlist')==1 and Stored('first')~=nil
  and Stored(1)==nil,'C7b: the first-run target is set without a confirmation (no Saved Build to replace)',Desc())
end)

C.scenario('E1 NB3 several candidates, Auto ON: a candidate asks first; Cancel writes nothing',function()
 Boot()
 TurnAutoOn()
 local button,count=EditorCandidate('E1',PLAIN)
 C.setup(count>=2,'E1: fixture: the several-candidates block',count)
 local saved,settings=Saved(),Settings()
 Zero()
 local p=Press(button)
 print('OBSERVED','E1 confirmation='..tostring(Asked(p))..' calls='..Desc())
 C.expect(p~=nil and p.arg1==PLAIN and p.arg2==TARGET_A and Writes()==0 and Saved()==saved,
  'E1: the candidate asks first, naming the Wishlist and Saved Build A; nothing is written',Desc())
 Dismiss(p)
 C.expect(p~=nil and Writes()==0 and Saved()==saved,'E1: Cancel writes nothing',Desc())
 C.guard(Auto() and Settings()==settings and spends==0,'E1: Auto stays ON; no setting changes; nothing is spent')
end)

C.scenario('E2 NB3 several candidates, Auto ON: Assign writes the named Saved Build once',function()
 Boot()
 TurnAutoOn()
 local button=EditorCandidate('E2',PLAIN)
 Zero()
 local p=Press(button)
 C.expect(p~=nil and Writes()==0,'E2: the candidate asks first',Desc())
 Accept(p)
 C.guard(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil and Stored(1).name==PLAIN and Stored(2)==nil,
  'E2: after the answer Saved Build A (only) holds the Wishlist',Desc())
 AcceptAgain(p)
 C.expect(p~=nil and Writes()==1,'E2: the same answer delivered again writes nothing more',Desc())
 C.guard(Auto(),'E2: Auto stays ON')
end)

C.scenario('E3 NB3 the active Saved Build changes before Assign: nothing is assigned',function()
 Boot()
 TurnAutoOn()
 local button=EditorCandidate('E3',PLAIN)
 local saved=Saved()
 Zero()
 local p=Press(button)
 SetActive(2)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','E3 calls='..Desc()..' said='..said)
 C.expect(p~=nil and Writes()==0 and Saved()==saved and Stored(1)==nil and Stored(2)==nil
  and said:find('active Saved Build changed',1,true)~=nil,'E3: the changed target refuses and says why',said)
 C.guard(Auto(),'E3: Auto stays ON')
end)

C.scenario('E4 NB3 a role-pending candidate, Auto ON: no role choice before the answer; Assign assigns Saved Build A',function()
 Boot()
 TurnAutoOn()
 local button=EditorCandidate('E4',EVIDENCE)
 local saved=Saved()
 Zero()
 local p=Press(button)
 print('OBSERVED','E4 calls='..Desc()..' resolves='..resolves)
 C.expect(p~=nil and Writes()==0 and resolves==0 and not RolePickerShown() and Saved()==saved,
  'E4: the role-pending candidate asks first; no role choice begins',Desc())
 Dismiss(p)
 C.expect(p~=nil and Writes()==0 and resolves==0 and Saved()==saved,'E4: Cancel writes nothing',Desc())
 Boot()
 TurnAutoOn()
 button=EditorCandidate('E4b',EVIDENCE)
 Zero()
 p=Press(button)
 C.expect(p~=nil and Writes()==0 and resolves==0,'E4b: the candidate asks first')
 Accept(p)
 RepeatIfOpen()
 C.guard(Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Writes()==2 and Stored(1)~=nil and Stored(1).name==EVIDENCE,
  'E4b: after the answer the roles are confirmed once and Saved Build A is assigned',Desc())
end)

C.scenario('E5 NB3 exactly one candidate (normal, then role-pending), Auto ON: asks first; Cancel and Assign',function()
 Boot({only='plain'})
 TurnAutoOn()
 local button,count=EditorCandidate('E5',PLAIN)
 C.setup(count==1,'E5: fixture: the one-candidate block',count)
 local saved=Saved()
 Zero()
 local p=Press(button)
 C.expect(p~=nil and p.arg1==PLAIN and Writes()==0 and Saved()==saved,'E5: the only candidate asks first',Desc())
 Dismiss(p)
 C.expect(p~=nil and Writes()==0 and Saved()==saved,'E5: Cancel writes nothing',Desc())
 Boot({only='plain'})
 TurnAutoOn()
 button=EditorCandidate('E5b',PLAIN)
 Zero()
 p=Press(button)
 Accept(p)
 C.expect(p~=nil and Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil and Stored(1).name==PLAIN,
  'E5b: Assign writes the named Saved Build once',Desc())
 Boot({only='evidence'})
 TurnAutoOn()
 button,count=EditorCandidate('E5c',EVIDENCE)
 C.setup(count==1,'E5c: fixture: the one role-pending candidate',count)
 saved=Saved()
 Zero()
 p=Press(button)
 C.expect(p~=nil and Writes()==0 and resolves==0 and not RolePickerShown() and Saved()==saved,
  'E5c: the only role-pending candidate asks first; no role choice begins',Desc())
 Dismiss(p)
 C.expect(p~=nil and Writes()==0 and resolves==0 and Saved()==saved,'E5c: Cancel writes nothing',Desc())
end)

C.scenario('E6 NB3 guards: Auto OFF assigns at the click; the first-run target needs no confirmation',function()
 Boot()
 C.setup(not Auto(),'E6: fixture: Auto is OFF')
 local button=EditorCandidate('E6',PLAIN)
 Zero()
 local p=Press(button)
 C.guard(p==nil and H.popup==nil and Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil
  and Stored(1).name==PLAIN and not Auto(),'E6: with Auto OFF the candidate assigns Saved Build A at the click',Desc())
 Boot({active=0})
 TurnAutoOn()
 button=EditorCandidate('E6b',PLAIN)
 Zero()
 p=Press(button)
 C.guard(p==nil and H.popup==nil and Wrote('SetFirstRunWishlist')==1 and Writes()==1 and Stored('first')~=nil,
  'E6b: the first-run target is set without a confirmation',Desc())
end)

C.scenario('N1 NB4 Auto ON without a confirmation UI: nothing is assigned and the player is told why',function()
 Boot()
 TurnAutoOn()
 local button=ChooserRow('N1',PLAIN,false)
 local saved=Saved()
 Zero()
 local show=StaticPopup_Show
 StaticPopup_Show=nil
 local said=Heard(function() button:Click() end)
 StaticPopup_Show=show
 print('OBSERVED','N1 chooser calls='..Desc()..' said='..said)
 C.expect(Writes()==0 and Saved()==saved and said:find('Nothing was assigned',1,true)~=nil
  and said:find('could not be shown',1,true)~=nil,'N1: the chooser assigns nothing and says why',said)
 Boot()
 TurnAutoOn()
 button=ChooserRow('N1b',EVIDENCE,true)
 saved=Saved()
 Zero()
 show=StaticPopup_Show
 StaticPopup_Show=nil
 said=Heard(function() button:Click() end)
 StaticPopup_Show=show
 C.expect(Writes()==0 and resolves==0 and Saved()==saved and said:find('could not be shown',1,true)~=nil,
  'N1b: a row needing locked targets begins no role choice and assigns nothing',Desc())
 Boot()
 TurnAutoOn()
 button=EditorCandidate('N1c',PLAIN)
 saved=Saved()
 Zero()
 show=StaticPopup_Show
 StaticPopup_Show=nil
 said=Heard(function() button:Click() end)
 StaticPopup_Show=show
 C.expect(Writes()==0 and Saved()==saved and said:find('could not be shown',1,true)~=nil,
  'N1c: an editor candidate assigns nothing and says why',said)
 C.guard(Auto(),'N1: Auto stays ON')
end)

C.scenario('N2 NB4 guard: Auto OFF without a confirmation UI still assigns at the click',function()
 Boot()
 C.setup(not Auto(),'N2: fixture: Auto is OFF')
 local button=ChooserRow('N2',PLAIN,false)
 Zero()
 local show=StaticPopup_Show
 StaticPopup_Show=nil
 button:Click()
 StaticPopup_Show=show
 C.guard(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil and Stored(1).name==PLAIN,
  'N2: with Auto OFF the chooser assigns Saved Build A at once, as before',Desc())
end)

C.scenario('N3 one confirmation assigns at most once (a repeated answer writes nothing more)',function()
 Boot()
 TurnAutoOn()
 local button=ChooserRow('N3',PLAIN,false)
 Zero()
 local p=Press(button)
 C.setup(p~=nil,'N3: fixture: the chooser asks first (Auto ON)')
 Accept(p)
 C.setup(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1,'N3: fixture: Assign wrote Saved Build A once',Desc())
 AcceptAgain(p)
 print('OBSERVED','N3 calls='..Desc())
 C.expect(Writes()==1,'N3: the same answer delivered again calls no writer',Desc())
end)

-- D7 (reviews D7-S1/S2, F-1/F-2): the editor's candidate question and every
-- role picker that waits after an assignment was started are bound to the
-- Saved Build that was named (its slot, name and contents), not to the slot
-- number, the active slot or the name alone. Saved over, renamed, gone, empty
-- or unreadable at the answer or at the role Confirm: no role choice is
-- confirmed, nothing is assigned, and the player is told to choose again.
-- EXPECT here fails on the pin 6950edb3 by design (the editor passed no
-- binding; the role picker compared the selected slot number only); GUARD
-- holds on both. Oracles as above, plus the chat line. No native claim.
local CHANGED='That Saved Build changed or could not be read'
local OTHER={{spellId=200088,quality=0,stacks=1},{spellId=200087,quality=3,stacks=1}}
local function Refused(said)
 return said:find(CHANGED,1,true)~=nil and said:find('Nothing was assigned',1,true)~=nil
  and said:find('choose again',1,true)~=nil
end
-- The game now reports other Saved Build rows (fresh tables, as a re-send).
local function ServerNow(change)
 local rows=H.Clone(H.perks.serverBuildSlots)
 change(rows)
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(1)
end

C.scenario('E7 D7 editor candidate: Saved Build A was replaced while the question waited: nothing is assigned; asking again assigns',function()
 Boot()
 TurnAutoOn()
 local button=EditorCandidate('E7',PLAIN)
 local saved=Saved()
 Zero()
 local p=Press(button)
 C.setup(p~=nil and p.arg2==TARGET_A,'E7: fixture: the candidate asks first, naming Saved Build A')
 if not p then return end
 -- Another build is saved over the active slot 1; slot 1 stays active.
 ServerNow(function(rows) rows[1]={name='Saved Build C',verified=true,echoes=H.Clone(OTHER)} end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','E7 calls='..Desc()..' said='..said)
 C.expect(Writes()==0 and resolves==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil,
  'E7: the answer for the replaced Saved Build calls no writer and stores nothing',Desc())
 C.expect(Refused(said),'E7: it says the Saved Build changed, that nothing was assigned and to choose again',said)
 C.guard(Auto() and spends==0,'E7: Auto stays ON; nothing is spent')
 -- A fresh question names what slot 1 holds now, and its answer assigns it.
 button=EditorCandidate('E7b',PLAIN)
 Zero()
 local again=Press(button)
 print('OBSERVED','E7b confirmation='..tostring(Asked(again)))
 C.expect(again~=nil and again~=p and again.arg1==PLAIN and again.arg2=="Saved Build 'Saved Build C'",
  'E7b: asking again names the Saved Build the slot holds now',again and tostring(again.arg2) or 'no confirmation')
 if not again then return end
 Accept(again)
 C.expect(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil and Stored(1).name==PLAIN and Stored(2)==nil,
  'E7b: the fresh answer assigns the Wishlist to slot 1, once',Desc())
end)

C.scenario('E8 D7 editor candidate: the same slot and name with other contents is not the Saved Build that was asked about',function()
 Boot()
 TurnAutoOn()
 local button=EditorCandidate('E8',PLAIN)
 local saved=Saved()
 Zero()
 local p=Press(button)
 C.setup(p~=nil,'E8: fixture: the candidate asks first')
 if not p then return end
 -- Saved over under the same name: its one Echo gained a stack.
 ServerNow(function(rows) rows[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=2}}} end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','E8 calls='..Desc()..' said='..said)
 C.expect(Writes()==0 and resolves==0 and Saved()==saved and Stored(1)==nil,
  'E8: an equal name and slot do not stand in for the Saved Build: nothing is written',Desc())
 C.expect(Refused(said),'E8: the player is told to choose again',said)
 C.guard(Auto(),'E8: Auto stays ON')
end)

C.scenario('E10 D7 editor candidate: Saved Build A gone, empty, unreadable or renamed at the answer: nothing is assigned',function()
 Boot()
 TurnAutoOn()
 local world=H.Clone(H.perks.serverBuildSlots)
 local function Restore() H.perks.serverBuildSlots=H.Clone(world);H.Notify();A.Poll();H.Advance(1) end
 local cases={
  {'gone',function() ServerNow(function(rows) rows[1]=nil end) end},
  {'empty',function() ServerNow(function(rows) rows[1]={name=BUILD_A,verified=true,echoes={}} end) end},
  -- No Saved Build data at all at the moment of the answer.
  {'unreadable',function() H.perks.serverBuildSlots=nil end},
  -- Last: on the pin this one assigns, which would end the cases after it.
  {'renamed',function() ServerNow(function(rows) rows[1].name='Saved Build A2' end) end},
 }
 for _,case in ipairs(cases) do
  local tag='E10 '..case[1]
  local button=EditorCandidate(tag,PLAIN)
  local saved=Saved()
  Zero()
  local p=Press(button)
  C.setup(p~=nil and p.arg2==TARGET_A,tag..': fixture: the candidate asks first, naming Saved Build A')
  if not p then return end
  case[2]()
  local said=Heard(function() Accept(p) end)
  print('OBSERVED',tag..' calls='..Desc()..' said='..said)
  C.expect(Writes()==0 and resolves==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil and Refused(said),
   tag..': no writer is called, nothing is stored and the player is told to choose again',said..' / '..Desc())
  Restore()
 end
 C.guard(Auto() and spends==0,'E10: Auto stays ON; nothing is spent')
end)

C.scenario('E11 D7 control, editor candidate: the same Saved Build A re-sent and another slot changed still assigns it',function()
 Boot()
 TurnAutoOn()
 local button=EditorCandidate('E11',PLAIN)
 Zero()
 local p=Press(button)
 C.setup(p~=nil,'E11: fixture: the candidate asks first')
 if not p then return end
 -- Saved Build A arrives again in fresh tables; Saved Build B is saved over.
 ServerNow(function(rows)
  rows[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=1}}}
  rows[2]={name='Saved Build B2',verified=true,echoes=H.Clone(OTHER)}
 end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','E11 calls='..Desc()..' said='..said)
 C.guard(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil and Stored(1).name==PLAIN and Stored(2)==nil
  and said:find(CHANGED,1,true)==nil,'E11: the unchanged named Saved Build A is assigned, once, and no change is reported',Desc())
 C.guard(Auto() and spends==0,'E11: Auto stays ON; nothing is spent')
end)

C.scenario('C8 D7 role picker after the Journal answer: Saved Build A saved over under its name, or renamed, before Confirm: no role, no assignment',function()
 Boot({manual=true})
 TurnAutoOn()
 local world=H.Clone(H.perks.serverBuildSlots)
 local function Restore() H.perks.serverBuildSlots=H.Clone(world);H.Notify();A.Poll();H.Advance(1) end
 local cases={
  {'same name, other contents',function(rows) rows[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=2}}} end},
  {'renamed',function(rows) rows[1].name='Saved Build A2' end},
 }
 for _,case in ipairs(cases) do
  local tag='C8 '..case[1]
  local button=ChooserRow(tag,EVIDENCE,true)
  local saved=Saved()
  Zero()
  local p=Press(button)
  C.setup(p~=nil,tag..': fixture: the click asks first')
  if not p then return end
  Accept(p)
  C.setup(RolePickerShown() and Writes()==0,tag..': fixture: after the answer the role picker waits; nothing is written',Desc())
  -- The Saved Build that was named changes while the role picker waits.
  ServerNow(case[2])
  C.setup(RolePickerShown(),tag..': fixture: the role picker is still open')
  NexusWishlistRoleUseOwned:Click()
  local said=Heard(function() NexusWishlistRoleConfirm:Click() end)
  print('OBSERVED',tag..' calls='..Desc()..' said='..said..' picker='..tostring(RolePickerShown()))
  C.expect(Roles()==0 and Writes()==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil,
   tag..': Confirm writes no role choice and no assignment',Desc())
  C.expect(Refused(said) and not RolePickerShown(),
   tag..': the role picker closes and the player is told to choose again',said)
  Restore()
 end
 C.guard(Auto() and spends==0,'C8: Auto stays ON; nothing is spent')
end)

C.scenario('C9 D7 control, role picker after the Journal answer: the same Saved Build A re-sent before Confirm is assigned',function()
 Boot({manual=true})
 TurnAutoOn()
 local button=ChooserRow('C9',EVIDENCE,true)
 Zero()
 local p=Press(button)
 C.setup(p~=nil,'C9: fixture: the click asks first')
 if not p then return end
 Accept(p)
 C.setup(RolePickerShown() and Writes()==0,'C9: fixture: after the answer the role picker waits',Desc())
 -- Saved Build A arrives again in fresh tables, unchanged.
 ServerNow(function(rows) rows[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=1}}} end)
 C.setup(RolePickerShown(),'C9: fixture: the role picker is still open')
 NexusWishlistRoleUseOwned:Click()
 local said=Heard(function() NexusWishlistRoleConfirm:Click() end)
 print('OBSERVED','C9 calls='..Desc()..' said='..said)
 C.guard(Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Writes()==2 and Stored(1)~=nil and Stored(1).name==EVIDENCE
  and Stored(2)==nil and not RolePickerShown() and said:find(CHANGED,1,true)==nil,
  'C9: the unchanged named Saved Build A gets its roles confirmed and the Wishlist assigned, once',Desc())
 C.guard(Auto(),'C9: Auto stays ON')
end)

C.scenario('E12 D7 role picker after an editor candidate answer: Saved Build A replaced before Confirm: no role, no assignment',function()
 Boot({manual=true})
 TurnAutoOn()
 local button=EditorCandidate('E12',EVIDENCE)
 local saved=Saved()
 Zero()
 local p=Press(button)
 C.setup(p~=nil and p.arg2==TARGET_A,'E12: fixture: the role-pending candidate asks first, naming Saved Build A')
 if not p then return end
 Accept(p)
 C.setup(RolePickerShown() and Writes()==0,'E12: fixture: after the answer the role picker waits; nothing is written',Desc())
 ServerNow(function(rows) rows[1]={name='Saved Build C',verified=true,echoes=H.Clone(OTHER)} end)
 C.setup(RolePickerShown(),'E12: fixture: the role picker is still open')
 NexusWishlistRoleUseOwned:Click()
 local said=Heard(function() NexusWishlistRoleConfirm:Click() end)
 print('OBSERVED','E12 calls='..Desc()..' said='..said..' picker='..tostring(RolePickerShown()))
 C.expect(Roles()==0 and Writes()==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil,
  'E12: Confirm writes no role choice and no assignment',Desc())
 C.expect(Refused(said) and not RolePickerShown(),'E12: the role picker closes and the player is told to choose again',said)
 C.guard(Auto() and spends==0,'E12: Auto stays ON; nothing is spent')
end)

-- D7-S3: a numbered target that cannot be identified when the assignment is
-- started (an empty or missing Saved Build slot) starts no role choice and no
-- role picker. A Saved Build saved into that slot afterwards receives nothing
-- without a fresh choice and, with Auto ON, its confirmation. EXPECT here
-- fails on the pin 143b3ab5 by design: there the default mode confirmed the
-- roles for the empty target, the role picker then waited unbound, and its
-- Confirm assigned to whatever the slot held by then, unasked. The populated
-- controls are C2, C5, C9, E4b and E11; the first-run controls are F1 and F2.
local EMPTY_REASON='empty or unavailable'
local function EmptyA(rows) rows[1]={name=BUILD_A,verified=true,echoes={}} end
local function MissingA(rows) rows[1]=nil end
local function PopulatedA(rows) rows[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=1}}} end
-- Whatever a waiting role picker would do if the player now confirmed it.
local function ConfirmIfWaiting()
 if not RolePickerShown() then return end
 if NexusWishlistRoleUseOwned then NexusWishlistRoleUseOwned:Click() end
 if NexusWishlistRoleConfirm and NexusWishlistRoleConfirm:IsEnabled() then NexusWishlistRoleConfirm:Click() end
end
-- One D7-S3 case. `button(tag)` finds the route's control for the Wishlist
-- without lock evidence; `manual` is the role mode; `unset` empties slot 1.
local function UnidentifiedTarget(tag,manual,unset,button)
 Boot({manual=manual})
 TurnAutoOn()
 ServerNow(unset)
 local control=button(tag)
 local saved=Saved()
 Zero()
 local p
 local said=Heard(function() p=Press(control) end)
 print('OBSERVED',tag..' calls='..Desc()..' said='..said..' picker='..tostring(RolePickerShown()))
 C.guard(p==nil and H.popup==nil,tag..': no Auto-ON question is asked for a slot that holds no Saved Build')
 C.expect(Roles()==0 and Writes()==0 and Saved()==saved,
  tag..': no role choice is confirmed and nothing is assigned for the unidentified target',Desc())
 C.expect(not RolePickerShown(),tag..': no role picker is opened to wait on it')
 C.expect(said:find(EMPTY_REASON,1,true)~=nil,tag..': the player is told the slot is empty or unavailable',said)
 -- A Saved Build is saved into slot 1 afterwards.
 ServerNow(PopulatedA)
 Zero()
 ConfirmIfWaiting()
 print('OBSERVED',tag..' after the slot was populated: calls='..Desc())
 C.expect(Roles()==0 and Writes()==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil,
  tag..': the Saved Build that appeared in the slot receives no role choice and no assignment',Desc())
 -- A fresh choice for it asks first (Auto ON), and only its answer assigns.
 control=button(tag..' again')
 Zero()
 local again=Press(control)
 C.expect(again~=nil and again.arg1==EVIDENCE and again.arg2==TARGET_A and Writes()==0,
  tag..': choosing again asks the Auto-ON question, naming Saved Build A',again and tostring(again.arg2) or 'no confirmation')
 if not again then return end
 Accept(again)
 ConfirmIfWaiting()
 C.expect(Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Stored(1)~=nil and Stored(1).name==EVIDENCE and Stored(2)==nil,
  tag..': only that answer confirms the roles and assigns Saved Build A',Desc())
 C.guard(Auto() and spends==0,tag..': Auto stays ON; nothing is spent')
end
local function JournalRow(tag) return ChooserRow(tag,EVIDENCE,true) end
local function EditorRow(tag) return (EditorCandidate(tag,EVIDENCE)) end

C.scenario('S3a D7-S3 Journal, current-lock default: an empty Saved Build slot starts no role choice; a build saved into it later gets nothing unasked',function()
 UnidentifiedTarget('S3a',false,EmptyA,JournalRow)
end)
C.scenario('S3b D7-S3 Journal, manual role mode: a missing Saved Build slot opens no role picker; a build saved into it later gets nothing unasked',function()
 UnidentifiedTarget('S3b',true,MissingA,JournalRow)
end)
C.scenario('S3c D7-S3 editor candidate, current-lock default: a missing Saved Build slot starts no role choice; a build saved into it later gets nothing unasked',function()
 UnidentifiedTarget('S3c',false,MissingA,EditorRow)
end)
C.scenario('S3d D7-S3 editor candidate, manual role mode: an empty Saved Build slot opens no role picker; a build saved into it later gets nothing unasked',function()
 UnidentifiedTarget('S3d',true,EmptyA,EditorRow)
end)

C.scenario('S3e D7-S3 Journal: a chooser left open over an empty slot assigns nothing to a Saved Build saved into it meanwhile',function()
 Boot()
 TurnAutoOn()
 ServerNow(EmptyA)
 local button=ChooserRow('S3e',PLAIN,false)
 local saved=Saved()
 -- A Saved Build is saved into slot 1 while the chooser stays open.
 ServerNow(PopulatedA)
 C.setup(NexusWishlistOnlyPicker:IsShown() and button~=nil and button:IsVisible(),
  'S3e: fixture: the chooser opened over the empty slot is still open')
 Zero()
 local p
 local said=Heard(function() p=Press(button) end)
 print('OBSERVED','S3e calls='..Desc()..' said='..said)
 C.expect(Writes()==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil,
  'S3e: the click assigns nothing to the Saved Build that was never shown or asked about',Desc())
 C.expect(p==nil and Refused(said) and not NexusWishlistOnlyPicker:IsShown(),
  'S3e: the stale chooser closes and the player is told to choose again',said)
 button=ChooserRow('S3e again',PLAIN,false)
 Zero()
 local again=Press(button)
 C.expect(again~=nil and again.arg1==PLAIN and again.arg2==TARGET_A and Writes()==0,
  'S3e: choosing again asks the Auto-ON question, naming Saved Build A',again and tostring(again.arg2) or 'no confirmation')
 if not again then return end
 Accept(again)
 C.expect(Wrote('SetLoadoutWishlist',1)==1 and Writes()==1 and Stored(1)~=nil and Stored(1).name==PLAIN,
  'S3e: only that answer assigns Saved Build A',Desc())
end)

C.scenario('F1 D7-S3 control, Journal first run, manual role mode: slot 0 still opens the role picker and sets the first-run target',function()
 Boot({active=0,manual=true})
 TurnAutoOn()
 local button=ChooserRow('F1',EVIDENCE,true)
 Zero()
 local p=Press(button)
 C.guard(p==nil and H.popup==nil and RolePickerShown() and Writes()==0,
  'F1: no confirmation; the role picker waits and nothing is written',Desc())
 ConfirmIfWaiting()
 print('OBSERVED','F1 calls='..Desc())
 C.guard(Roles()==1 and Wrote('SetFirstRunWishlist')==1 and Stored('first')~=nil and Stored(1)==nil and Stored(2)==nil
  and not RolePickerShown(),'F1: its Confirm sets the first-run target and no Saved Build',Desc())
end)

C.scenario('F2 D7-S3 control, editor candidate first run, current-lock default: slot 0 still confirms roles and sets the first-run target',function()
 Boot({active=0})
 TurnAutoOn()
 local button=EditorCandidate('F2',EVIDENCE)
 Zero()
 local p=Press(button)
 RepeatIfOpen()
 print('OBSERVED','F2 calls='..Desc())
 C.guard(p==nil and H.popup==nil and Roles()==1 and Wrote('SetFirstRunWishlist')==1 and Stored('first')~=nil
  and Stored(1)==nil and Stored(2)==nil,'F2: the first-run target is set without a confirmation',Desc())
end)

-- D7-S4: the Saved Build that was named is gone, empty or unreadable at the
-- role Confirm. Gone or empty: nothing is written, the picker closes and a
-- new choice is required. Unreadable: nothing is written while it is
-- unknown and the picker stays open with its existing message (retained,
-- bounded retry); a later Confirm must prove the original identity again
-- before any role or assignment, and a changed identity always closes the
-- picker for a new choice. All GUARD: the pin already behaves so.
C.scenario('S4 D7-S4 role Confirm over a gone, empty or unreadable Saved Build: no write while unknown; only the same identity is assigned',function()
 Boot({manual=true})
 TurnAutoOn()
 local world=H.Clone(H.perks.serverBuildSlots)
 local function Restore() H.perks.serverBuildSlots=H.Clone(world);H.Notify();A.Poll();H.Advance(1) end
 -- The chooser asked, the player answered, the role picker waits.
 local function Waiting(tag)
  local button=ChooserRow(tag,EVIDENCE,true)
  Zero()
  local p=Press(button)
  C.setup(p~=nil,tag..': fixture: the click asks first')
  if not p then return false end
  Accept(p)
  C.setup(RolePickerShown() and Writes()==0,tag..': fixture: after the answer the role picker waits',Desc())
  if not RolePickerShown() then return false end
  NexusWishlistRoleUseOwned:Click()
  return true
 end
 for _,case in ipairs({{'gone',MissingA},{'empty',EmptyA}}) do
  local tag='S4 '..case[1]
  if not Waiting(tag) then return end
  local saved=Saved()
  ServerNow(case[2])
  C.setup(RolePickerShown(),tag..': fixture: the role picker is still open')
  local said=Heard(function() NexusWishlistRoleConfirm:Click() end)
  print('OBSERVED',tag..' calls='..Desc()..' said='..said)
  C.guard(Roles()==0 and Writes()==0 and Saved()==saved and Stored(1)==nil and Stored('first')==nil,
   tag..': Confirm writes no role choice and no assignment',Desc())
  C.guard(Refused(said) and not RolePickerShown(),tag..': the role picker closes and the player is told to choose again',said)
  Restore()
 end
 -- Unreadable, then readable again as ANOTHER Saved Build.
 local tag='S4 unreadable then changed'
 if not Waiting(tag) then return end
 local saved=Saved()
 H.perks.serverBuildSlots=nil
 local said=Heard(function() NexusWishlistRoleConfirm:Click() end)
 print('OBSERVED',tag..' unreadable: calls='..Desc()..' said='..said..' message='..RolePickerMessage())
 C.guard(Roles()==0 and Writes()==0 and Saved()==saved,tag..': while the Saved Builds are unreadable nothing is written',Desc())
 C.guard(RolePickerShown() and RolePickerMessage()~='' and said:find(CHANGED,1,true)==nil,
  tag..': the role picker stays open with its message (retained retry)',RolePickerMessage())
 H.perks.serverBuildSlots=H.Clone(world)
 ServerNow(function(rows) rows[1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=2}}} end)
 C.setup(RolePickerShown(),tag..': fixture: the role picker is still open')
 said=Heard(function() NexusWishlistRoleConfirm:Click() end)
 print('OBSERVED',tag..' readable: calls='..Desc()..' said='..said)
 C.guard(Roles()==0 and Writes()==0 and Saved()==saved and Stored(1)==nil,
  tag..': the retry over a changed Saved Build writes no role choice and no assignment',Desc())
 C.guard(Refused(said) and not RolePickerShown(),tag..': a changed identity closes the picker for a new choice',said)
 Restore()
 -- Unreadable, then readable again as the SAME Saved Build.
 tag='S4 unreadable then same'
 if not Waiting(tag) then return end
 saved=Saved()
 H.perks.serverBuildSlots=nil
 said=Heard(function() NexusWishlistRoleConfirm:Click() end)
 C.guard(Roles()==0 and Writes()==0 and Saved()==saved and RolePickerShown(),
  tag..': while the Saved Builds are unreadable nothing is written and the picker stays open',Desc())
 Restore()
 C.setup(RolePickerShown(),tag..': fixture: the role picker is still open')
 said=Heard(function() NexusWishlistRoleConfirm:Click() end)
 print('OBSERVED',tag..' readable: calls='..Desc()..' said='..said)
 C.guard(Roles()==1 and Wrote('SetLoadoutWishlist',1)==1 and Writes()==2 and Stored(1)~=nil and Stored(1).name==EVIDENCE
  and Stored(2)==nil and not RolePickerShown() and said:find(CHANGED,1,true)==nil,
  tag..': the retry over the same Saved Build confirms the roles and assigns it, once',Desc())
 C.guard(Auto() and spends==0,'S4: Auto stays ON; nothing is spent')
end)

C.finish('(B2/NB3: every Auto-ON assignment route asks before any role or assignment write; NB1 no timing promise; NB4 fail-closed and accept-once)')
