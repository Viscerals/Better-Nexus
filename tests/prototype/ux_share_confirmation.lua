-- UX M5 (UX-11 / LP-11): sharing your own Saved Build is its own action, set
-- apart from the draft-only Copy into Editor, and it starts only after an
-- explicit confirmation that says a shared build cannot be recalled. The
-- confirmation binds one build: its owner and the content PublishImportedBuild
-- sends. A changed owner, changed content, a closed Build Library, Cancel and
-- Escape start no Share; one approval starts at most one.
-- Healthy behaviour (EXPECT, fails on the accepted M4 source 23109b90 by
-- design: there the mirror's single detail button, in the Copy place,
-- publishes on click with no confirmation): the separate Share Build...
-- action and its confirmation text; Cancel, Escape, a closed Library, a
-- changed title and a changed player share nothing; Accept shares exactly the
-- confirmed build once, also when the selection moved; truthful completion,
-- refusal and waiting lines; the label, note and layout of the action.
-- Unchanged (GUARD, holds there too): Copy into Editor on an ordinary build
-- opens a draft and shares and sends nothing; Edit Build stays; Stop Sharing
-- stays on the ordinary listing; the saved Sync mode and marker; no game
-- action.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Effects are counted where they happen: calls of the real controller's
-- PublishImportedBuild (wrapped at its factory; two cases inject a refusal or
-- a waiting result there instead of calling it), Share hand-offs to
-- Sync.BroadcastBuildSummary and DPS-best hand-offs, the mirror's publication
-- and the catalog listing made from it. Normal background Sync is kept apart:
-- the format-5 profile is Manual, so idle Sync sends nothing. Every no-effect
-- window is checked first with no time passing (H.sent included), then again
-- after time passes by the Share-specific evidence only.
-- The popup is a FrameXML boundary model, as in stop_sharing_layer_support:
-- one shared slot, per-dialog OnShow/OnHide/OnAccept/OnCancel, Escape only
-- with hideOnEscape, StaticPopup_Visible by name. No native hit testing.
-- Real TOC boot, format-5 saved data, Saved import, Build Library window and
-- controller. Artificial names only; nothing leaves the process.
-- M5R2-MB1 (continuation 42): the completion line states the Share's actual
-- Sync result, read here from Sync's own Share record of the listing
-- (Sync.GetShareStatus). With this fixture's player name the listing's
-- summary is over the 247-byte line budget (core/SyncCompatibility.lua
-- PrepareSummary; size recomputed below from the stored listing and
-- printed), so S7 sees the final size refusal after the local save. The
-- admitted Manual Share, its follow-ups and its decoded summary are in
-- ux_share_admission.
-- M5 first disclosure stage (S13, S14): what may be sent, read from the real
-- controls: the Share tooltip, the confirmation note through the popup model
-- above, and the Automatic option of the existing Sync mode dialog (opened
-- and cancelled, never applied). EXPECT (fails on fcaeedd2 by design, after
-- its controls and popup are reached): no claim that the listing goes only to
-- players who ask; the summary carries no Echo list; the full listing can be
-- sent in answers, and an answer on the shared Sync channel can be kept by
-- other listeners; in Automatic a linked character-best Training Dummy or
-- Lich King DPS record may also be sent with its Echoes, locked Echoes and
-- player info without an additional request, also when the summary is not
-- queued; the Automatic option names that DPS content. GUARD: every DPS
-- statement stays conditional on Automatic and promises no send; the local
-- save, possible summary, update, Off, cannot-recall, local Stop Sharing and
-- unconfirmed-receipt clauses stay; the Automatic help keeps its requests and
-- answers and fits its 386x51 box under the default and 16 px offline models
-- and the runtime conservative model (models only, not native pixels);
-- viewing the dialog saves no mode and starts no grant, admission or send.
-- M5 qualifier correction (S14), EXPECT (fails on fc43f4b5 by design, after
-- the dialog and its Automatic option are reached): the Automatic help says
-- the DPS it may send is newly eligible (an eligibility or qualifying term)
-- and is the character's best for an encounter (Training Dummy and Lich King
-- named, or "encounter"), not a best across all encounters. Its former
-- "with their Record Loadout pages" suffix is not a required clause.
-- M5 disclosure parity (S13), EXPECT for the confirmation note and the Share
-- tooltip alike (the tooltip fails on 8babe397 by design, after the real
-- first-Share and update controls are reached; the unchanged note holds them):
-- Share saves the title, description and Echo list as the shared listing;
-- the possible summary has neither the Echo list nor the description; answers
-- can carry the full listing with its description, not just an Echo list; and
-- the Automatic DPS record may be sent also when the summary is not queued.
-- Fake boundary, disclosed: for the Automatic and Off notes SyncModePolicy.Mode
-- is replaced only during the one synchronous click that builds the note and
-- restored before any time passes; nothing is applied, saved, queued or sent,
-- and every confirmation is cancelled. The runtime stays on its saved Manual
-- mode, so no Automatic send is exercised or claimed here.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local printable=V.printable
local C=V.Checker('ux_share_confirmation')

local NAME1,NAME2='Artificial Share One','Artificial Share Two'
local NEW_TITLE='Artificial Share One renamed'
local DIALOG='NEXUS_SHARE_SAVED_BUILD'
local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end

-- Calls of the real controller's PublishImportedBuild, wrapped at its factory
-- right after core/CommunityController.lua loads (the facade's only instance).
local attempts,inject={},nil
F.fileHooks={['core\\CommunityController.lua']=function()
 local factory=Nexus.CommunityInternals and Nexus.CommunityInternals.Controller
 local new=factory and factory.New
 if type(new)~='function' then return end
 factory.New=function(...)
  local instance=new(...)
  local publish=type(instance)=='table' and instance.PublishImportedBuild
  if type(publish)=='function' then
   instance.PublishImportedBuild=function(id,onComplete)
    local entry={id=id,onComplete=onComplete,injected=inject}
    attempts[#attempts+1]=entry
    if inject=='refuse' then return false,'artificial refusal' end
    if inject=='pending' then entry.ticket={};return nil,'ROOT_MUTATION_PENDING',entry.ticket end
    return publish(id,onComplete)
   end
  end
  return instance
 end
end}
local H=F.Boot(F.Database(),function(h)
 h.perks.serverBuildSlots={[1]={name=NAME1,verified=true,echoes={E(200001,2),E(200002,1)}},
  [2]={name=NAME2,verified=true,echoes={E(200004,1),E(200005,1)}}}
 h.perks.serverActiveSlot=1
end)
F.fileHooks=nil
local CB=Nexus.CommunityBuilds

-- Share and DPS-best hand-offs, by the Saved Build they came from.
local handoffs,dpsBests={},{}
local realSummary=Nexus.Sync.BroadcastBuildSummary
Nexus.Sync.BroadcastBuildSummary=function(record,...)
 handoffs[#handoffs+1]=type(record)=='table' and record.sourceSavedBuildId or false
 return realSummary(record,...)
end
local realBest=Nexus.DpsCapture.BroadcastBestForBuild
Nexus.DpsCapture.BroadcastBestForBuild=function(buildId,...)
 dpsBests[#dpsBests+1]=buildId
 return realBest(buildId,...)
end

-- Every printed line (the renderer prints through the global print).
local realPrint,said=print,{}
print=function(...)
 local t={}
 for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end
 said[#said+1]=table.concat(t,' ')
 return realPrint(...)
end
local function SaidSince(mark,needle)
 for i=mark+1,#said do if V.Plain(said[i]):find(needle,1,true) then return V.Plain(said[i]) end end
 return nil
end

-- FrameXML popup boundary model.
local slot=CreateFrame('Frame','NexusTestPopupSlot',UIParent)
slot:SetFrameStrata('DIALOG');slot:Hide()
local shows=0
slot:SetScript('OnHide',function(self)
 local info=self.which and StaticPopupDialogs[self.which]
 if info and info.OnHide then info.OnHide(self) end
 self.which,self.data,self.text=nil,nil,nil
end)
StaticPopup_Show=function(which,a,b,data)
 local info=StaticPopupDialogs[which]
 if type(info)~='table' then return nil end
 if slot:IsShown() then slot:Hide() end
 shows=shows+1
 slot.which,slot.data=which,data
 slot.text=string.format(info.text or '',tostring(a or ''),tostring(b or ''))
 slot.button1,slot.button2=info.button1,info.button2
 slot:Show()
 if info.OnShow then info.OnShow(slot,data) end
 return slot
end
StaticPopup_Hide=function(which) if slot:IsShown() and slot.which==which then slot:Hide() end end
StaticPopup_Visible=function(which) return slot:IsShown() and slot.which==which and slot or nil end
local function Dismiss(accept)
 if not slot:IsShown() then return end
 local info=StaticPopupDialogs[slot.which]
 local action=info and (accept and info.OnAccept or info.OnCancel)
 if action then action(slot,slot.data) end
 slot:Hide()
end
local function Escape()
 local info=slot:IsShown() and StaticPopupDialogs[slot.which]
 if info and info.hideOnEscape then
  if info.OnCancel then info.OnCancel(slot,slot.data,'clicked') end
  slot:Hide()
 end
end

local function Until(limit,fn)
 for i=1,limit do
  if fn() then return i end
  H.Advance(.05,.05)
 end
 return nil
end
local function Import()
 local stats=CB.VirtualStats()
 return type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
end
local function ImportIdle() return Import().pending~=true end
local function Row(id)
 for _,b in pairs(CB.Builds() or {}) do if type(b)=='table' and b.id==id then return b end end
 return nil
end
local function Mirror(n)
 local found
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==n then found=b end
 end
 return found
end
-- The ordinary catalog listings made from Saved Build mirror `id`.
local function Listing(id)
 local n,found=0,nil
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild~=true and b.sourceSavedBuildId==id then n,found=n+1,b end
 end
 return n,found
end
local function Count(list,value) local n=0;for _,v in ipairs(list) do if v==value then n=n+1 end end;return n end
local function Real(id)
 local n=0
 for _,a in ipairs(attempts) do if a.id==id and not a.injected then n=n+1 end end
 return n
end
-- Share-specific evidence for one mirror.
local function Effects(id)
 local m=Row(id) or {}
 return {calls=Real(id),handoffs=Count(handoffs,id),published=m.publishedBuildId,listings=(Listing(id)),dps=#dpsBests}
end
local function Same(a,b)
 return a.calls==b.calls and a.handoffs==b.handoffs and a.published==b.published
  and a.listings==b.listings and a.dps==b.dps
end
local function Text(e)
 return string.format('calls=%d handoffs=%d published=%s listings=%d dps=%d',
  e.calls,e.handoffs,printable(e.published),e.listings,e.dps)
end

local function Panel()
 local f=NexusCommunityBuildsFrame
 return f and f._detailPanel
end
local function ShowBuild(id)
 CB.ShowBuild(id)
 Until(2000,function()
  local p=Panel()
  return p and p:IsShown() and p._nexusShownId==id and ImportIdle()
 end)
 local p=Panel()
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end
local function Label(button) return button and V.Plain(button:GetText()) or '' end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
C.setup(Nexus.SyncModePolicy.Mode()=='manual','fixture: the format-5 profile is Manual (idle Sync sends nothing)',Nexus.SyncModePolicy.Mode())
CB.Show()
C.setup(Until(4000,function() return Mirror(1)~=nil and Mirror(2)~=nil and ImportIdle() end)~=nil,
 'fixture: both server Saved Builds are imported as mirrors through the real Build Library')
local m1,m2=(Mirror(1) or {}).id,(Mirror(2) or {}).id
C.setup(m1~=nil and m2~=nil and CB.IsOwnBuild(m1)==true and CB.IsOwnBuild(m2)==true,
 "fixture: both mirrors are the character's own",printable(m1)..'/'..printable(m2))
C.setup((Row(m1) or {}).publishedBuildId==nil and (Listing(m1))==0 and (Listing(m2))==0,'fixture: neither was shared before')
local sentAtStart=#H.sent

-- Opens the confirmation of mirror `id` through its own action; returns the
-- panel, the bound data, the effects before and the send count at the click
-- (from there on, no time passes until the scenario's own check).
local function Open(tag,id)
 local panel=ShowBuild(id)
 C.setup(panel~=nil,tag..': fixture: the detail pane shows the mirror')
 local share=panel and panel.shareBtn
 C.expect(share~=nil and share:IsShown() and share:IsEnabled(),tag..': the mirror offers its own Share action')
 if not share then return nil end
 local before,sent=Effects(id),#H.sent
 share:Click()
 C.expect(slot:IsShown() and slot.which==DIALOG,tag..': the action opens the Share confirmation first',printable(slot.which))
 C.expect(Same(Effects(id),before) and #H.sent==sent,tag..': opening the confirmation shares and sends nothing',Text(Effects(id)))
 return panel,slot.data,before,sent
end
-- No Share effect now (no time passed, nothing sent), nor after time passes.
local function NoShare(tag,id,before,sent)
 C.expect(Same(Effects(id),before) and #H.sent==sent,tag..': no Share starts and nothing is sent',Text(Effects(id)))
 Until(40,function() return false end)
 C.expect(Same(Effects(id),before),tag..': and none follows after time passes',Text(Effects(id)))
end

C.scenario('S1 Share is a separate action; Copy is not offered on the mirror',function()
 local panel=ShowBuild(m1)
 C.setup(panel~=nil,'S1: fixture: the detail pane shows Saved Build 1')
 if not panel then return end
 local share=panel.shareBtn
 print('OBSERVED','S1 left='..Label(panel.lockBtn)..' shown='..tostring(panel.lockBtn:IsShown()),'share='..Label(share))
 C.expect(share~=nil and share:IsShown() and share:IsEnabled() and Label(share)=='Share Build...',
  'S1: your own Saved Build offers Share Build... as its own action',Label(share))
 C.expect(not panel.lockBtn:IsShown(),'S1: the draft Copy place offers nothing for the mirror',Label(panel.lockBtn))
 C.guard(panel.editBtn:IsShown() and not panel.deleteBtn:IsShown(),'S1: Edit Build stays; Stop Sharing is not offered on a mirror')
 local sp=share and {share:GetPoint(1)} or {}
 local ep={panel.editBtn:GetPoint(1)}
 C.expect(sp[1]=='BOTTOMRIGHT' and ep[1]=='BOTTOMLEFT','S1: Share stands at the right, apart from the left-hand actions',
  printable(sp[1])..'/'..printable(ep[1]))
 local tip=share and V.Plain(table.concat(V.TooltipLines(share:GetScript('OnEnter'),share),' ')) or ''
 C.expect(tip:find('confirm',1,true)~=nil and tip:find('cannot be recalled',1,true)~=nil and tip:find('Not Copy into Editor',1,true)~=nil,
  'S1: its tooltip says it asks to confirm, cannot be recalled and is not Copy into Editor',tip)
 local state=V.Plain(panel.editState:GetText() or '')
 C.expect(state:find('Share Build...',1,true)~=nil and state:find('after you confirm',1,true)~=nil,'S1: the mirror note names Share Build... and the confirmation',state)
 -- The harness clicks hidden buttons too: the Copy place must never share.
 local before,sent=Effects(m1),#H.sent
 panel.lockBtn:Click()
 C.expect(Same(Effects(m1),before) and not slot:IsShown() and #H.sent==sent,'S1: the Copy button never shares the mirror, even clicked while hidden',Text(Effects(m1)))
end)

C.scenario('S2 Cancel shares nothing',function()
 local panel,data,before,sent=Open('S2',m1)
 if not panel then return end
 C.expect(type(data)=='table' and data.id==m1,'S2: the confirmation is bound to Saved Build 1',printable(type(data)=='table' and data.id))
 local text=V.Plain(slot.text or '')
 print('OBSERVED','S2 confirmation='..text)
 C.expect(text:find(NAME1,1,true)~=nil and text:find('cannot be recalled',1,true)~=nil
  and text:find('Stop Sharing removes only the listing on this client',1,true)~=nil
  and text:find('cannot confirm who received',1,true)~=nil,
  'S2: it names the build and says a shared build cannot be recalled, Stop Sharing is local and receipt is not confirmed',text)
 C.guard(text:find('Sync mode is Off',1,true)==nil,'S2: no Off note under the Manual mode',text)
 C.expect(slot.button1=='Share' and slot.button2=='Cancel','S2: with Share and Cancel',printable(slot.button1)..'/'..printable(slot.button2))
 C.expect(slot:GetFrameStrata()=='FULLSCREEN_DIALOG','S2: shown above the DIALOG Build Library',slot:GetFrameStrata())
 Dismiss(false)
 C.expect(not slot:IsShown() and slot:GetFrameStrata()=='DIALOG','S2: Cancel closes it; the shared slot keeps its own layer',slot:GetFrameStrata())
 NoShare('S2 Cancel',m1,before,sent)
end)

C.scenario('S3 Escape shares nothing',function()
 local panel,_,before,sent=Open('S3',m1)
 if not panel then return end
 Escape()
 C.expect(not slot:IsShown(),'S3: Escape closes the confirmation')
 NoShare('S3 Escape',m1,before,sent)
end)

C.scenario('S4 closing the Build Library shares nothing, also with a late Accept',function()
 local panel,data,before,sent=Open('S4',m1)
 if not panel then return end
 CB.Hide()
 C.expect(not slot:IsShown(),'S4: closing the Build Library closes its Share confirmation')
 local mark=#said
 local info=StaticPopupDialogs[DIALOG]
 if info and info.OnAccept then info.OnAccept(slot,data) end
 C.expect(SaidSince(mark,'Share cancelled')~=nil,'S4: a late Accept of that confirmation says the Share was cancelled',SaidSince(mark,'Nexus'))
 NoShare('S4 closed Library',m1,before,sent)
 CB.Show()
end)

C.scenario('S5 a title changed after the confirmation opened: no Share',function()
 local panel,data=Open('S5',m1)
 if not panel then return end
 local ok,why=CB.EditBuild(m1,NEW_TITLE,nil,nil)
 C.setup(ok~=false,'S5: fixture: the owner edit of the title is accepted',printable(why))
 C.setup(Until(2000,function() return (Row(m1) or {}).title==NEW_TITLE and ImportIdle() end)~=nil,
  'S5: fixture: the mirror now has the new title',(Row(m1) or {}).title)
 C.setup(slot:IsShown() and slot.data==data,'S5: fixture: the same confirmation is still open')
 local before,sent,mark=Effects(m1),#H.sent,#said
 Dismiss(true)
 C.expect(SaidSince(mark,'Share cancelled')~=nil and SaidSince(mark,'Nothing was shared')~=nil,
  'S5: Accept says the Share was cancelled because the build changed',SaidSince(mark,'Nexus'))
 NoShare('S5 changed content',m1,before,sent)
end)

C.scenario('S6 a different player at Accept: no Share',function()
 local panel=Open('S6',m1)
 if not panel then return end
 local before,sent,mark=Effects(m1),#H.sent,#said
 local realUnitName=UnitName
 UnitName=function(unit)
  if unit==nil or unit=='player' then return 'DifferentPlayer','Ebonhold' end
  return realUnitName(unit)
 end
 local ok,err=pcall(Dismiss,true)
 UnitName=realUnitName
 C.setup(ok,'S6: fixture: Accept ran',printable(err))
 C.expect(SaidSince(mark,'Share cancelled')~=nil,'S6: Accept by another player says the Share was cancelled',SaidSince(mark,'Nexus'))
 NoShare('S6 changed owner',m1,before,sent)
end)

local listingId
C.scenario('S7 Accept shares the confirmed build once, also when the selection moved',function()
 local panel,data,before=Open('S7',m1)
 if not panel then return end
 C.setup(ShowBuild(m2)~=nil and slot:IsShown() and slot.data==data,
  'S7: fixture: Saved Build 2 is now selected and the confirmation of Saved Build 1 is still open')
 local mark=#said
 Dismiss(true)
 C.expect(Real(m1)==before.calls+1 and Real(m2)==0,'S7: Accept starts exactly one Share, of the confirmed Saved Build 1, none of the selected Saved Build 2',
  'm1='..Real(m1)..' m2='..Real(m2))
 C.expect(Until(4000,function()
  local e=Effects(m1)
  return e.published~=nil and e.listings==1 and ImportIdle()
 end)~=nil,'S7: Saved Build 1 now has its one shared listing in the local catalog',Text(Effects(m1)))
 local _,listing=Listing(m1)
 listingId=listing and listing.id
 C.expect(Count(handoffs,m1)==1,'S7: the listing was handed to Sync once',Count(handoffs,m1))
 local line=SaidSince(mark,'locally as your shared listing')
 print('OBSERVED','S7 completion='..printable(line))
 C.expect(line~=nil and line:find(NEW_TITLE,1,true)~=nil,
  'S7: the completion line names the build and says it was saved locally as your shared listing',line)
 -- Sync's own Share record of the listing, and the summary size recomputed
 -- from the stored listing as core/SyncCompatibility.lua SummaryEncode and
 -- PrepareSummary build it (escaped length: each "|" counts twice).
 local status=listingId and Nexus.Sync.GetShareStatus(listingId) or nil
 local size
 local row=listingId and Nexus.BuildCatalog.Get(listingId) or nil
 if type(row)=='table' and row.link==nil then
  local n=0
  for _,e in ipairs(type(row.echoes)=='table' and row.echoes or {}) do n=n+(tonumber(e.stacks or e.count) or 1) end
  local payload={id=row.id,t=row.title,a=row.author,o=row.ownerKey,c=row.class,
   m=tonumber(row.lastModified) or tonumber(row.postedAt) or 0,h=row.fingerprintHash,n=n,x=row.autoDps and 1 or nil}
  local message='WLBI|'..tostring((UnitName('player')))..'|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(payload))
  size=#message+select(2,message:gsub('|',''))
 end
 print('OBSERVED','S7 share status','outcome='..printable(status and status.outcome),'reason='..printable(status and status.reason),
  'queueAdmitted='..printable(status and status.queueAdmitted),'summary escaped bytes='..printable(size)..' (budget 247)')
 local admitted=status~=nil and status.queueAdmitted==true
 C.expect(line~=nil and status~=nil and status.id==listingId
  and (admitted and line:find('queued its summary',1,true)~=nil and line:find('not confirmed',1,true)~=nil
   or not admitted and line:find('not queued',1,true)~=nil and line:find('nothing was sent',1,true)~=nil
    and line:find('queued its summary',1,true)==nil),
  'S7: the line states the actual Sync result of this Share (queued and not confirmed, or not queued and nothing sent), never a bare hand-off',line)
 C.expect(size~=nil and status~=nil and (size>247 and not admitted and status.reason=='summary too large'
   and line~=nil and line:find('summary too large',1,true)~=nil or size<=247 and admitted),
  'S7: a summary over the line budget is a final visible refusal after the local save, not a queued claim',printable(size)..' / '..printable(status and status.reason))
 C.expect(SaidSince(mark,'to community builds')==nil,'S7: no "shared to community builds" claim',SaidSince(mark,'to community builds'))
 C.guard((Listing(m2))==0 and Count(handoffs,m2)==0,'S7: Saved Build 2 is not shared')
 -- The same approval cannot start a second Share.
 local calls=Real(m1)
 local info=StaticPopupDialogs[DIALOG]
 if info and info.OnAccept then info.OnAccept(slot,data) end
 C.expect(Real(m1)==calls and Count(handoffs,m1)==1,'S7: the same approval cannot start a second Share',Text(Effects(m1)))
end)

C.scenario('S8 the shared Saved Build offers Update Shared Build... in the same separate place',function()
 local panel=ShowBuild(m1)
 C.setup(panel~=nil,'S8: fixture: the detail pane shows Saved Build 1')
 if not panel then return end
 C.expect(panel.shareBtn and panel.shareBtn:IsShown() and Label(panel.shareBtn)=='Update Shared Build...',
  'S8: the action now reads Update Shared Build...',Label(panel.shareBtn))
 C.expect(not panel.lockBtn:IsShown(),'S8: still no Copy on the mirror')
 local state=V.Plain(panel.editState:GetText() or '')
 C.expect(state:find('saved on this client',1,true)~=nil and state:find('not confirmed',1,true)~=nil and state:sub(1,7)~='Shared.',
  'S8: the note says the listing is saved on this client and receipt is not confirmed (not a bare "Shared.")',state)
 local opened=Open('S8',m1)
 if opened then
  C.expect(V.Plain(slot.text or ''):find('as an update',1,true)~=nil,'S8: the confirmation says this sends an update',V.Plain(slot.text or ''))
  Dismiss(false)
 end
end)

C.scenario('S9 a refused Share is stated with its reason and claims nothing',function()
 local panel=Open('S9',m2)
 if not panel then return end
 local mark=#said
 inject='refuse';Dismiss(true);inject=nil
 local line=SaidSince(mark,'Not shared:')
 print('OBSERVED','S9 refusal='..printable(line))
 C.expect(line~=nil and line:find(NAME2,1,true)~=nil and line:find('artificial refusal',1,true)~=nil
  and line:find('Nothing was saved or sent',1,true)~=nil,'S9: the refusal names the build and its reason and claims nothing',line)
 C.guard(Effects(m2).published==nil and (Listing(m2))==0 and Count(handoffs,m2)==0,'S9: nothing was shared')
 panel=ShowBuild(m2)
 C.expect(panel and panel.shareBtn:IsShown() and panel.shareBtn:IsEnabled() and Label(panel.shareBtn)=='Share Build...',
  'S9: Share stays available for a new explicit attempt',panel and Label(panel.shareBtn))
end)

C.scenario('S10 a waiting Share: stated, not repeatable, settled only by its own completion',function()
 local panel=Open('S10',m2)
 if not panel then return end
 local mark=#said
 inject='pending';Dismiss(true);inject=nil
 local entry=attempts[#attempts]
 C.setup(entry and entry.injected=='pending' and entry.id==m2 and type(entry.onComplete)=='function','S10: fixture: the injected waiting result reached the renderer')
 if not (entry and type(entry.onComplete)=='function') then return end
 C.expect(SaidSince(mark,'to share — not sent yet')~=nil,'S10: the wait is stated as not sent yet',SaidSince(mark,'Nexus'))
 CB.Refresh();panel=Panel()
 C.expect(Label(panel.shareBtn)=='Sharing...' and not panel.shareBtn:IsEnabled(),'S10: while it waits the action reads Sharing... and is disabled',Label(panel.shareBtn))
 local before,count=shows,#attempts
 panel.shareBtn:GetScript('OnClick')(panel.shareBtn)
 C.expect(shows==before and #attempts==count,'S10: no second confirmation or Share while one waits')
 mark=#said
 entry.onComplete(true,'artificial-id',{})
 C.expect(SaidSince(mark,'locally as your shared listing')==nil,'S10: a completion with another ticket claims nothing')
 entry.onComplete(true,'artificial-id',entry.ticket)
 local line=SaidSince(mark,'locally as your shared listing')
 -- This injected completion reports no queue result: none may be claimed.
 C.expect(line~=nil and line:find('not confirmed',1,true)~=nil and line:find('queued its summary',1,true)==nil,
  'S10: its own completion is stated without a receipt claim (and, reporting no queue result, without a queue claim)',line)
 Until(40,function() local p=Panel();return p and Label(p.shareBtn)=='Share Build...' end)
 panel=Panel()
 C.expect(Label(panel.shareBtn)=='Share Build...' and panel.shareBtn:IsEnabled(),'S10: afterwards the action is available again',Label(panel.shareBtn))
end)

C.scenario('S11 Copy into Editor on an ordinary build opens a draft and shares nothing',function()
 if not listingId then
  -- S7 could not share (the accepted M4 source has no separate action).
  -- Account for what really happened there first: S1's click on the old
  -- mirror button published Saved Build 1 for real, so its real ordinary
  -- listing is used when it exists.
  local n1,l1=Listing(m1)
  print('OBSERVED','S11 earlier real publication of Saved Build 1: controller calls='..Real(m1)..' listings='..n1)
  listingId=l1 and l1.id
 end
 if not listingId then
  -- Otherwise Saved Build 2 is published through the unchanged public facade.
  -- PublishImportedBuild refuses outright (false, reason; nothing retained)
  -- while the catalog is busy at maintenance start, so this waits for the
  -- catalog's own manual-write readiness, prints every complete result and
  -- retries only those busy refusals, a bounded number of times.
  local BUSY={MAINTENANCE_ACTIVE=true,ROOT_MUTATION_PENDING=true,ROOT_ADMISSION_PENDING=true}
  local catalog=Nexus.BuildCatalog
  local function Ready()
   local status=catalog and type(catalog.ManualPreparationStatus)=='function' and catalog.ManualPreparationStatus() or nil
   return ImportIdle() and type(status)=='table' and status.ready==true
  end
  for attempt=1,8 do
   Until(400,Ready)
   local called,ok,why,ticket=pcall(CB.PublishImportedBuild,m2)
   print('OBSERVED','S11 fixture publish of Saved Build 2, attempt '..attempt..': called='..printable(called)
    ..' ok='..printable(ok)..' why='..printable(why)..' ticket='..type(ticket))
   if called and (ok==true or (ok==nil and why=='ROOT_MUTATION_PENDING')) then
    Until(4000,function() return (Listing(m2))==1 and ImportIdle() end)
    break
   end
   if not (called and ok==false and BUSY[why]) then break end
  end
  local _,l2=Listing(m2)
  listingId=l2 and l2.id
 end
 local listingRow=listingId and Row(listingId) or nil
 C.setup(listingRow~=nil and listingRow.sourceSavedBuildId~=nil,'S11: fixture: an ordinary own listing made from a Saved Build exists',printable(listingId))
 if not listingRow then return end
 local source=listingRow.sourceSavedBuildId
 local panel=ShowBuild(listingId)
 C.setup(panel~=nil,'S11: fixture: the detail pane shows the listing')
 if not panel then return end
 C.guard(panel.lockBtn:IsShown() and Label(panel.lockBtn)=='Copy into Editor','S11: the ordinary own listing offers Copy into Editor',Label(panel.lockBtn))
 C.guard(not (panel.shareBtn and panel.shareBtn:IsShown()),'S11: and no Saved Build Share action')
 C.guard(panel.deleteBtn:IsShown() and Label(panel.deleteBtn)=='Stop Sharing','S11: Stop Sharing stays on the listing',Label(panel.deleteBtn))
 local copyTip=V.Plain(table.concat(V.TooltipLines(panel.lockBtn:GetScript('OnEnter'),panel.lockBtn),' '))
 C.guard(copyTip:find('draft',1,true)~=nil,'S11: the Copy tooltip describes a draft',copyTip)
 C.expect(copyTip:find('does not activate, spend or share',1,true)~=nil,'S11: and says the draft shares nothing',copyTip)
 local editor=Nexus.WishlistEditor
 local realOpen,opened=editor.OpenForCandidate,0
 editor.OpenForCandidate=function(...) opened=opened+1;return realOpen(...) end
 local before,sent,total=Effects(source),#H.sent,#attempts
 local ok,err=pcall(function() panel.lockBtn:Click() end)
 editor.OpenForCandidate=realOpen
 C.setup(ok and opened==1,'S11: fixture: Copy into Editor opened one draft',printable(err)..' opened='..opened)
 C.guard(Same(Effects(source),before) and #attempts==total and #H.sent==sent,'S11: Copy into Editor shares and sends nothing',Text(Effects(source)))
 if NexusEditorFrame and NexusEditorFrame.Hide then NexusEditorFrame:Hide() end
 CB.Show()
end)

C.scenario('S12 the Share action fits apart from the other actions',function()
 local function Check(tag,id,label)
  local panel=ShowBuild(id)
  if not panel then C.setup(false,tag..': fixture: the detail pane is shown');return end
  CB.Refresh();Until(20,function() return false end)
  panel=Panel()
  local root=NexusCommunityBuildsFrame
  local share,edit=panel.shareBtn,panel.editBtn
  if not (share and share:IsShown()) then
   C.expect(false,tag..': the mirror offers its own Share action to place');return
  end
  local r,er,pr=G.Rect(share,root),G.Rect(edit,root),G.Rect(panel,root)
  print('OBSERVED','S12',tag,'share',G.Text(r),'edit',G.Text(er),'panel',G.Text(pr))
  C.expect(Label(share)==label and G.Inside(r,pr),tag..': "'..label..'" lies inside the detail panel',G.Text(r)..' in '..G.Text(pr))
  C.expect(G.Apart(r,er),tag..': it does not overlap Edit Build',G.Text(r)..' / '..G.Text(er))
  C.expect(math.abs(r[3]-(pr[3]-8))<0.5,tag..': it is right-aligned in its own area',G.Text(r))
  C.expect(share:GetWidth()>=G.Length(G.Visible(share:GetText()))*G.model.char+20 and share:GetHeight()>=G.model.line+4,
   tag..': it is wide and tall enough for its label',share:GetWidth()..'x'..share:GetHeight())
 end
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(m)
  for _,v in ipairs({{w=1366,h=768},{w=800,h=600}}) do
   UIParent:SetSize(v.w,v.h)
   local tag='S12 '..m.name..' '..v.w..'x'..v.h
   Check(tag..' shared',m1,'Update Shared Build...')
   Check(tag..' unshared',m2,'Share Build...')
  end
 end
 G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768)
end)

-- Disclosure reading (S13, S14), in lower case, one sentence at a time
-- (split at . ; ! ? and line breaks): semantic facts and negative claims,
-- not one copied sentence.
-- Merge composition (M7 with current135): current135's actual wire
-- semantics supersede continuation 51's requester-only and exact-build
-- reading of the confirmation and tooltip. Kept from continuation 51 and M7:
-- the Manual fixture and the listing of S7 (SETUP), the DPS-best hand-off of
-- the confirmed Share (GUARD), the exact action label read before each
-- confirmation (SETUP) and M7's identity statement in the confirmation.
local function Sentences(text)
 local out={}
 for s in (V.Plain(text):lower()..'.'):gmatch('([^%.;!?\n]+)') do
  s=s:gsub('^%s+',''):gsub('%s+$','')
  if s~='' then out[#out+1]=s end
 end
 return out
end
local function Sentence(text,match)
 for _,s in ipairs(Sentences(text)) do if match(s) then return s end end
 return nil
end
local function Has(s,needle) return s:find(needle,1,true)~=nil end
local function Word(s,word) return s:find('%f[%a]'..word..'%f[%A]')~=nil end
-- A claim that the listing reaches only the players who ask for it.
local function RequesterOnly(s)
 return Word(s,'only') and (Has(s,'who ask') or Has(s,'request') or Has(s,'answer') or Has(s,'who fetch'))
end
-- What the Automatic DPS statement must say.
local DPS_FACTS={
 {'conditional (if, may)',function(s) return Word(s,'if') and Word(s,'may') end},
 {"the character's best",function(s) return Has(s,"character's best") or Has(s,'character-best') end},
 {'linked to the listing',function(s) return Has(s,'linked') end},
 {'Training Dummy or Lich King',function(s) return Has(s,'training dummy') and Has(s,'lich king') end},
 {'Echoes and locked Echoes',function(s) return Has(s,'echoes') and Has(s,'locked echoes') end},
 {'player info',function(s) return Has(s,'player info')
  or (Has(s,'name') and Has(s,'realm') and Has(s,'class') and Has(s,'level')) end},
 {'no additional request',function(s) return Has(s,'without an additional request')
  or Has(s,'without anyone asking') or Has(s,'unasked') end},
}
local function Missing(s)
 local out={}
 for _,fact in ipairs(DPS_FACTS) do if not (s and fact[2](s)) then out[#out+1]=fact[1] end end
 return out
end
-- A DPS statement not conditional on Automatic, or one that promises a send
-- or claims every or a personal best.
local function UnconditionalDps(text)
 return Sentence(text,function(s)
  return Has(s,'dps') and not (Has(s,'in automatic') and Word(s,'may') and not Word(s,'every')
   and not Word(s,'always') and not Word(s,'will') and not Has(s,'personal'))
 end)
end
-- A sentence that denies the summary its description, with its Echo list
-- ("no Echo list or description", "neither ... nor its description") or on
-- its own ("no description"); one that only names the description does not.
local function DeniesDescription(s)
 return s:find('%f[%a]no echo list,? or [%a ]-description')~=nil
  or s:find('%f[%a]nor [%a ]-description')~=nil or s:find('%f[%a]no description')~=nil
end
-- A sentence that says answers can carry the full listing: named so, or with
-- its description among what can be sent (an Echo list alone is not it).
local function AnswersCarryListing(s)
 if not (Has(s,'answer') and (Has(s,'can be sent') or Has(s,'may be sent'))) then return false end
 return Has(s,'full listing') or (Has(s,'description') and not DeniesDescription(s)
  and s:find('%f[%a]not [%a ]-description')==nil)
end
-- The disclosure checks shared by the confirmation note and the tooltip:
-- both are read for every clause, the DPS record's independence from the
-- summary included.
local function Disclosure(tag,what,text)
 local only=Sentence(text,RequesterOnly)
 C.expect(only==nil,tag..': the '..what..' makes no claim that the listing goes only to players who ask',only)
 C.expect(Sentence(text,function(s) return Has(s,'save') and Has(s,'listing') and Has(s,'title')
  and Has(s,'description') and Has(s,'echo list') end)~=nil,
  tag..': the '..what..' says Share saves the title, description and Echo list as the shared listing',text)
 C.expect(Sentence(text,function(s) return Has(s,'summary') and Has(s,'no echo list') end)~=nil,
  tag..': the '..what..' says the summary carries no Echo list',text)
 C.expect(Sentence(text,function(s) return Has(s,'summary') and DeniesDescription(s) end)~=nil,
  tag..': the '..what..' says the summary carries no description either',text)
 C.expect(Sentence(text,function(s) return Has(s,'answer') and (Has(s,'echo list') or Has(s,'full listing'))
  and (Has(s,'can be sent') or Has(s,'may be sent')) end)~=nil,
  tag..': the '..what..' says the full listing can be sent in answers, not only to askers',text)
 C.expect(Sentence(text,AnswersCarryListing)~=nil,
  tag..': the '..what..' says answers can carry the full listing with its description, not just an Echo list',text)
 C.expect(Sentence(text,function(s) return Has(s,'sync channel') and (Has(s,'kept') or Has(s,'keep')) end)~=nil,
  tag..': the '..what..' says an answer on the shared Sync channel can be kept by other listeners',text)
 local dps=Sentence(text,function(s) return Has(s,'in automatic') and Has(s,'dps') end)
 local missing=Missing(dps)
 C.expect(dps~=nil and #missing==0,
  tag..': the '..what..' says in Automatic a linked character-best DPS record may also be sent with its Echoes, locked Echoes and player info, unasked',
  dps and ('missing: '..table.concat(missing,', ')) or 'no Automatic DPS statement')
 C.expect(dps~=nil and Has(dps,'summary') and (Has(dps,'not queued') or Has(dps,'not admitted')),
  tag..': the '..what..' does not tie that DPS record to the summary being queued',dps)
 local loose=UnconditionalDps(text)
 C.guard(loose==nil,tag..': every DPS statement in the '..what..' is conditional on Automatic and promises no send',loose)
 local lower=V.Plain(text):lower()
 C.guard(not Has(lower,'everyone') and not Has(lower,'every answer') and not Has(lower,'all players'),
  tag..': the '..what..' claims no delivery to everyone',text)
end

-- The Share confirmation of mirror `id`, opened by its own action while the
-- Sync mode reads as `mode`, then cancelled: its text and the tooltip. The
-- mode is replaced only for that synchronous click, before any time passes.
-- `label` is the exact action label expected before the click.
local function ReadShare(tag,id,mode,label)
 local panel=ShowBuild(id)
 local share=panel and panel.shareBtn
 C.setup(share~=nil and share:IsShown() and share:IsEnabled(),tag..': fixture: the mirror offers its Share action')
 if not (share and share:IsShown() and share:IsEnabled()) then return nil end
 C.setup(label==nil or Label(share)==label,tag..': fixture: the action reads "'..tostring(label)..'"',Label(share))
 local policy=Nexus.SyncModePolicy
 local realMode=policy.Mode
 local before,sent,shown=Effects(id),#H.sent,shows
 policy.Mode=function() return mode end
 local ok,err=pcall(function() share:Click() end)
 local opened=ok and slot:IsShown() and slot.which==DIALOG and shows==shown+1
 local text=opened and V.Plain(slot.text or '') or nil
 local tip=V.Plain(table.concat(V.TooltipLines(share:GetScript('OnEnter'),share),' '))
 policy.Mode=realMode
 C.setup(opened,tag..': fixture: the action opened its confirmation',printable(err))
 Dismiss(false)
 C.guard(Same(Effects(id),before) and #H.sent==sent and not slot:IsShown() and policy.Mode()=='manual',
  tag..': reading and cancelling it shares and sends nothing; the Sync mode reads Manual again',Text(Effects(id)))
 return text,tip
end

C.scenario('S13 the Share confirmation and its tooltip say what may be sent, in Manual, Automatic and Off',function()
 C.setup(Nexus.SyncModePolicy.Mode()=='manual','S13: fixture: the saved mode is still Manual',Nexus.SyncModePolicy.Mode())
 local listing=(Row(m1) or {}).publishedBuildId
 C.setup(listing~=nil,'S13: fixture: Saved Build 1 has its shared listing (S7)',printable(listing))
 if listing~=nil then
  C.guard(Count(dpsBests,listing)>=1,
   'S13: the confirmed Share of Saved Build 1 handed its listing to the DPS-best hand-off (the linked record this copy describes)',
   'listing='..printable(listing)..' calls='..Count(dpsBests,listing))
 end
 local e1,e2=Effects(m1),Effects(m2)
 for _,id in ipairs({m2,m1}) do
  local published=(Row(id) or {}).publishedBuildId~=nil
  local case=published and 'update' or 'first Share'
  local clause=published and 'as an update' or 'as your shared listing'
  local label=published and 'Update Shared Build...' or 'Share Build...'
  local manualTip
  for _,mode in ipairs({'manual','automatic','off'}) do
   local tag='S13 '..case..' '..mode
   local text,tip=ReadShare(tag,id,mode,label)
   if text then
    print('OBSERVED',tag,'confirmation='..text)
    Disclosure(tag,'confirmation',text)
    local t=text:lower()
    local title=tostring((Row(id) or {}).title or '?'):lower()
    C.guard(Has(t,title) and Has(t,clause) and Has(t,'saves') and Has(t,'on this client')
     and Has(t,'queues a short summary') and Has(t,'if your saved sync mode and its size allow')
     and Has(t,'cannot be recalled') and Has(t,'stop sharing removes only the listing on this client')
     and Has(t,'cannot confirm who received'),
     tag..': it keeps the build name, local save, possible summary, '..clause..', cannot-recall, local Stop Sharing and unconfirmed-receipt clauses',text)
    C.guard(Has(t,'character name, realm and class'),
     tag..': it keeps the M7 statement that the listing is listed with your character name, realm and class',text)
    if mode=='off' then
     C.guard(Has(t,'your saved sync mode is off') and Has(t,'not sent'),tag..': under Off it says the listing is saved here and not sent',text)
    else
     C.guard(not Has(t,'sync mode is off'),tag..': no Off note outside Off',text)
    end
   end
   if tip and mode=='manual' then
    manualTip=tip
    print('OBSERVED','S13 '..case..' tooltip='..tip)
    Disclosure('S13 '..case..' tooltip','tooltip',tip)
    local l=tip:lower()
    C.guard(Has(l,'confirm') and Has(l,'cannot be recalled') and Has(l,'not copy into editor')
     and Has(l,'not saving or activating a server saved build'),
     'S13 '..case..' tooltip: it keeps the confirmed-Share, cannot-recall, not-Copy and not-a-server-save meanings',tip)
   elseif tip then
    C.guard(tip==manualTip,tag..': the tooltip reads the same in every mode',tip)
   end
  end
 end
 Until(40,function() return false end)
 C.guard(Same(Effects(m1),e1) and Same(Effects(m2),e2) and Nexus.SyncModePolicy.Mode()=='manual'
  and NexusDB.settings.syncMode=='manual',
  'S13: no Share and no mode change follows after time passes',Text(Effects(m1))..' / '..Text(Effects(m2)))
end)

C.scenario('S14 the Automatic option of the Sync mode dialog names its DPS sends; viewing it changes nothing',function()
 local root=NexusCommunityBuildsFrame
 local modeBtn=root and root._modeBtn
 C.setup(root~=nil and root:IsShown() and modeBtn~=nil and modeBtn:IsShown() and modeBtn:IsEnabled(),
  'S14: fixture: the Build Library shows its Sync mode... action')
 if not (modeBtn and modeBtn:IsShown() and modeBtn:IsEnabled()) then return end
 local policy=Nexus.SyncModePolicy
 local function Bytes()
  local settings=rawget(NexusDB,'settings') or {}
  local key=(policy.Choice() or {}).key or 'nexusSyncModeChoice'
  return printable(rawget(settings,key))..'|'..printable(rawget(settings,'syncMode'))..'|'..printable(rawget(NexusDB,'settingsVersion'))
 end
 local function Counters()
  local stats,parts=Nexus.Sync.Stats(),{}
  for _,key in ipairs({'admittedPackets','admittedControl','admittedBulk','admittedShare','admissionRejected','modeRefused','sendAttempts'}) do
   parts[#parts+1]=key..'='..printable(stats[key])
  end
  return table.concat(parts,' ')
 end
 local bytes,explicit,grant=Bytes(),(policy.Choice() or {}).explicit,policy.ActiveManualGrant()
 local counters,sent,mark,e1,e2=Counters(),#H.sent,#said,Effects(m1),Effects(m2)
 modeBtn:Click()
 local d=NexusSyncModeDialog
 local auto
 for _,option in ipairs(d and d.options or {}) do if option.mode=='automatic' then auto=option end end
 C.setup(d~=nil and d:IsShown() and auto~=nil and auto.help~=nil,'S14: fixture: the dialog is open with its Automatic option')
 if not (d and auto and auto.help) then if d then d:Hide() end;return end
 auto:Click()
 C.guard(d._draft~=nil and d._draft.mode=='automatic' and auto:GetChecked()==true and Bytes()==bytes,
  'S14: selecting the Automatic option changes only the uncommitted draft',Bytes())
 local help=V.Plain(auto.help:GetText() or '')
 local h=help:lower()
 print('OBSERVED','S14 Automatic help='..help)
 C.expect(Word(h,'may') and (Has(h,"character's best") or Has(h,'character-best')) and Has(h,'dps')
  and Has(h,'echoes') and Has(h,'locked') and Has(h,'player info'),
  'S14: the Automatic option says a new character-best DPS may be sent with its Echoes, locked Echoes and player info',help)
 -- Its qualifiers (M5 qualifier correction), read from the help's DPS
 -- sentence, not one copied sentence: that DPS is a newly eligible one (an
 -- eligibility or qualifying term), and the character's best for an
 -- encounter (both encounter names, or "encounter"), not across all of them.
 local dpsHelp=Sentence(help,function(s) return Has(s,'dps') end)
 C.expect(dpsHelp~=nil and (dpsHelp:find('%f[%a]eligib')~=nil or dpsHelp:find('%f[%a]qualif')~=nil),
  'S14: the Automatic option says the DPS it may send is newly eligible (an eligibility or qualifying term)',help)
 C.expect(dpsHelp~=nil and (Has(dpsHelp,'training dummy') and Has(dpsHelp,'lich king')
   or dpsHelp:find('%f[%a]encounter')~=nil) and not Has(dpsHelp,'all encounters'),
  'S14: the Automatic option scopes that character best to an encounter (Training Dummy or Lich King), not a best across all encounters',help)
 C.guard(Has(h,'without a click') and Has(h,'request') and Has(h,'answer'),
  'S14: it still names the requests and answers Automatic may send without a click',help)
 C.guard(not Has(h,'personal') and not Word(h,'every') and not Word(h,'always') and not Word(h,'will'),
  'S14: it promises no send and claims no personal best beyond the character best',help)
 local width,height=auto.help:GetWidth(),auto.help:GetHeight()
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16}) do
  local rows=G.Rows(help,width,model.char)
  print('OBSERVED','S14 fit',model.name,rows..' rows x '..model.line..' px in '..width..'x'..height)
  C.guard(rows>0 and rows*model.line<=height,'S14: under the '..model.name..' model the Automatic help fits its box',rows..' rows')
 end
 local metrics=Nexus.LayoutMetrics
 local _,line=metrics.ConservativeText(1)
 local rows=metrics.TextRows(help,width,1)
 C.guard(rows>0 and rows*line<=height,'S14: under the runtime conservative text model it fits too',rows..' rows x '..line..' px')
 d.cancel:Click()
 C.guard(not d:IsShown() and d._draft==nil,'S14: Cancel closes the dialog and discards the draft')
 C.guard(Bytes()==bytes and (policy.Choice() or {}).explicit==explicit and policy.Mode()=='manual'
  and policy.ActiveManualGrant()==grant,'S14: viewing it saved no Sync mode and started no Sync Now grant',bytes..' -> '..Bytes())
 C.guard(Counters()==counters and #H.sent==sent and SaidSince(mark,'Sync mode:')==nil
  and Same(Effects(m1),e1) and Same(Effects(m2),e2),
  'S14: it admitted, sent and shared nothing, and Apply was not used',Counters())
 Until(40,function() return false end)
 C.guard(Bytes()==bytes and policy.Mode()=='manual' and Same(Effects(m1),e1) and Same(Effects(m2),e2),
  'S14: nothing follows after time passes',Bytes())
end)

print('OBSERVED','attempts='..#attempts,'handoffs='..#handoffs,'dpsBestHandoffs='..#dpsBests,
 'background H.sent during the test='..(#H.sent-sentAtStart))
C.guard(#H.actions==0,'no game action: nothing was activated, saved to the server or spent',#H.actions)
C.guard(NexusDB.settings.syncMode=='manual' and NexusDB.settingsVersion==5,'the saved Sync mode and marker are unchanged',
 printable(NexusDB.settings.syncMode)..'/'..printable(NexusDB.settingsVersion))
print=realPrint
C.finish('(Share is separate from Copy and runs once per bound confirmation; Cancel, Escape, a closed Library and a changed owner or content share nothing)')
