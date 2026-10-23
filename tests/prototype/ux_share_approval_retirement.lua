-- M7 (M5R-NB02, M5R-NB01 disclosure; journey J4): only the latest Share
-- confirmation shown is a live approval. Cancel, Escape, a newer confirmation
-- in its place and closing the Build Library (also when it is opened again)
-- retire it: a late Accept of a retired confirmation says "Share cancelled"
-- and shares nothing. A live confirmation still shares its own confirmed build
-- once, also when the selection moved. The confirmation also says the listing
-- carries the character name, realm and class, and that a DPS record held for
-- this exact build may be queued separately if the saved mode allows.
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a, where a retired confirmation's
-- late Accept still shared; not executed by the author); GUARD already holds
-- there and must keep holding; SETUP is the fixture.
-- The popup is the FrameXML boundary model of ux_share_confirmation: one
-- shared slot; OnShow, OnHide, OnAccept and OnCancel per dialog; Accept runs
-- before the slot hides, as in the client; Escape only with hideOnEscape. A
-- late Accept is the dialog's own OnAccept called with the retired data, as a
-- reused or stale dialog frame would. No native hit testing.
-- Effects are counted where they happen: calls of the real controller's
-- PublishImportedBuild (wrapped at its factory), Share hand-offs to
-- Sync.BroadcastBuildSummary, the mirror's publication and its listing.
-- Real TOC boot, format-5 saved data (Manual, so idle Sync sends nothing),
-- Saved import, Build Library and controller. Artificial names only.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('ux_share_approval_retirement')

local NAME1,NAME2='Artificial Retire One','Artificial Retire Two'
local DIALOG='NEXUS_SHARE_SAVED_BUILD'
local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end

local attempts={}
F.fileHooks={['core\\CommunityController.lua']=function()
 local factory=Nexus.CommunityInternals and Nexus.CommunityInternals.Controller
 local new=factory and factory.New
 if type(new)~='function' then return end
 factory.New=function(...)
  local instance=new(...)
  local publish=type(instance)=='table' and instance.PublishImportedBuild
  if type(publish)=='function' then
   instance.PublishImportedBuild=function(id,onComplete)
    attempts[#attempts+1]={id=id}
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

local handoffs={}
local realSummary=Nexus.Sync.BroadcastBuildSummary
Nexus.Sync.BroadcastBuildSummary=function(record,...)
 handoffs[#handoffs+1]=type(record)=='table' and record.sourceSavedBuildId or false
 return realSummary(record,...)
end
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

-- FrameXML popup boundary model (as ux_share_confirmation).
local slot=CreateFrame('Frame','NexusTestRetirePopupSlot',UIParent)
slot:SetFrameStrata('DIALOG');slot:Hide()
slot:SetScript('OnHide',function(self)
 local info=self.which and StaticPopupDialogs[self.which]
 if info and info.OnHide then info.OnHide(self) end
 self.which,self.data,self.text=nil,nil,nil
end)
StaticPopup_Show=function(which,a,b,data)
 local info=StaticPopupDialogs[which]
 if type(info)~='table' then return nil end
 if slot:IsShown() then slot:Hide() end
 slot.which,slot.data=which,data
 slot.text=string.format(info.text or '',tostring(a or ''),tostring(b or ''))
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
local function LateAccept(data)
 local info=StaticPopupDialogs[DIALOG]
 if info and info.OnAccept then info.OnAccept(slot,data) end
end

local function Until(limit,fn)
 for i=1,limit do if fn() then return i end;H.Advance(.05,.05) end
 return nil
end
local function ImportIdle()
 local stats=CB.VirtualStats()
 local import=type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
 return import.pending~=true
end
local function Row(id) for _,b in pairs(CB.Builds() or {}) do if type(b)=='table' and b.id==id then return b end end end
local function Mirror(n)
 local found
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==n then found=b end
 end
 return found
end
local function Real(id) local n=0;for _,a in ipairs(attempts) do if a.id==id then n=n+1 end end;return n end
local function Count(list,value) local n=0;for _,v in ipairs(list) do if v==value then n=n+1 end end;return n end
local function Effects(id) local m=Row(id) or {};return {calls=Real(id),handoffs=Count(handoffs,id),published=m.publishedBuildId} end
local function Same(a,b) return a.calls==b.calls and a.handoffs==b.handoffs and a.published==b.published end
local function Text(e) return 'calls='..e.calls..' handoffs='..e.handoffs..' published='..printable(e.published) end
local function Panel() local f=NexusCommunityBuildsFrame;return f and f._detailPanel end
local function ShowBuild(id)
 CB.ShowBuild(id)
 Until(2000,function() local p=Panel();return p and p:IsShown() and p._nexusShownId==id and ImportIdle() end)
 local p=Panel()
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end
local function Open(tag,id)
 local panel=ShowBuild(id)
 C.setup(panel~=nil and panel.shareBtn:IsShown() and panel.shareBtn:IsEnabled(),tag..': fixture: the mirror offers its Share action')
 if not panel then return nil end
 panel.shareBtn:Click()
 C.setup(slot:IsShown() and slot.which==DIALOG and type(slot.data)=='table' and slot.data.id==id,tag..': fixture: its confirmation is open')
 return slot.data,panel
end
-- EXPECT both: on M6 a retired confirmation's late Accept still shared.
local function NoShare(tag,id,before)
 C.expect(Same(Effects(id),before),tag..': nothing is shared at once',Text(Effects(id)))
 Until(40,function() return false end)
 C.expect(Same(Effects(id),before),tag..': and no Share follows',Text(Effects(id)))
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
CB.Show()
C.setup(Until(4000,function() return Mirror(1)~=nil and Mirror(2)~=nil and ImportIdle() end)~=nil,'fixture: both Saved Builds are imported as mirrors')
local m1,m2=(Mirror(1) or {}).id,(Mirror(2) or {}).id

C.scenario('R1 the confirmation discloses identity and a possible linked DPS record',function()
 local data=Open('R1',m1)
 if not data then return end
 local text=V.Plain(slot.text or '')
 print('OBSERVED','R1 confirmation='..text)
 C.expect(text:find('character name, realm and class',1,true)~=nil,'R1: it says the listing carries your character name, realm and class',text)
 C.expect(text:find('DPS record you hold for this exact build may also be queued separately',1,true)~=nil
  and text:find('if your saved Sync mode allows it',1,true)~=nil,'R1: it says a linked DPS record may also be queued, by the saved mode',text)
 C.guard(text:find('cannot be recalled',1,true)~=nil and text:find('cannot confirm who received',1,true)~=nil,'R1: the recall and receipt statements stay',text)
 Dismiss(false)
end)

C.scenario('R2 Cancel retires the confirmation: a late Accept shares nothing',function()
 local data=Open('R2',m1)
 if not data then return end
 local before=Effects(m1)
 Dismiss(false)
 local mark=#said
 LateAccept(data)
 C.expect(SaidSince(mark,'Share cancelled')~=nil and SaidSince(mark,'Nothing was shared')~=nil,'R2: the late Accept says the Share was cancelled',SaidSince(mark,'Nexus'))
 NoShare('R2 cancelled',m1,before)
end)

C.scenario('R3 Escape retires the confirmation: a late Accept shares nothing',function()
 local data=Open('R3',m1)
 if not data then return end
 local before=Effects(m1)
 Escape()
 local mark=#said
 LateAccept(data)
 C.expect(SaidSince(mark,'Share cancelled')~=nil,'R3: the late Accept says the Share was cancelled',SaidSince(mark,'Nexus'))
 NoShare('R3 escaped',m1,before)
end)

C.scenario('R4 closing and reopening the Library retires the confirmation',function()
 local data=Open('R4',m1)
 if not data then return end
 local before=Effects(m1)
 CB.Hide()
 C.guard(not slot:IsShown(),'R4: closing the Library closes its confirmation')
 CB.Show()
 C.setup(NexusCommunityBuildsFrame:IsShown(),'R4: fixture: the Library is open again')
 local mark=#said
 LateAccept(data)
 C.expect(SaidSince(mark,'Share cancelled')~=nil,'R4: a late Accept after reopening says the Share was cancelled',SaidSince(mark,'Nexus'))
 NoShare('R4 reopened',m1,before)
end)

C.scenario('R5 a newer confirmation retires the older one; the newer one still shares once',function()
 local older=Open('R5',m1)
 if not older then return end
 local before1=Effects(m1)
 local newer=Open('R5 newer',m2)
 if not newer then return end
 C.setup(older~=newer,'R5: fixture: two different confirmations')
 local mark=#said
 LateAccept(older)
 C.expect(SaidSince(mark,'Share cancelled')~=nil,'R5: Accept of the replaced confirmation says the Share was cancelled',SaidSince(mark,'Nexus'))
 C.expect(Same(Effects(m1),before1),'R5: the replaced confirmation shares nothing',Text(Effects(m1)))
 local before2=Effects(m2)
 Dismiss(true)
 C.guard(Real(m2)==before2.calls+1,'R5: the live confirmation starts exactly one Share of its own build',Real(m2))
 C.guard(Until(4000,function() return Effects(m2).published~=nil and ImportIdle() end)~=nil,'R5: and its listing is saved locally',Text(Effects(m2)))
 local calls=Real(m2)
 LateAccept(newer)
 C.guard(Real(m2)==calls,'R5: the same approval cannot start a second Share',Real(m2))
end)

C.scenario('R6 a live confirmation still shares its own build when the selection moved',function()
 local data=Open('R6',m1)
 if not data then return end
 C.setup(ShowBuild(m2)~=nil and slot:IsShown() and slot.data==data,'R6: fixture: the other mirror is selected; the confirmation is still open')
 local before=Effects(m1)
 Dismiss(true)
 C.guard(Real(m1)==before.calls+1 and Count(handoffs,m2)<=1,'R6: Accept starts one Share of the confirmed build',Real(m1))
end)

print=realPrint
C.guard(#H.actions==0,'no game action: nothing was activated, saved to the server or spent',#H.actions)
C.guard(NexusDB.settings.syncMode=='manual' and NexusDB.settingsVersion==5,'the saved Sync mode and marker are unchanged',
 printable(NexusDB.settings.syncMode)..'/'..printable(NexusDB.settingsVersion))
C.finish('(only the latest shown confirmation is live; retired ones share nothing; live ones share once)')
