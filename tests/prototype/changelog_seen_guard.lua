-- The one-time release note records lastChangelogSeen only when the saved-data
-- owner reports a durable write and local start-up completed. A failed or
-- read-only start-up shows and closes the note without consuming it, so the
-- acknowledgement is not lost together with the session that could not save
-- it. Real TOC boot; synthetic saved data only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local KEY='prototype-P1.6-assigned-orbs'
local function Seen()
 local top=NexusDB.lastChangelogSeen
 local settings=type(NexusDB.settings)=='table' and NexusDB.settings.lastChangelogSeen or nil
 return top,settings
end
local function Popup() return NexusChangelogPopup end
local function CloseButton()
 local popup=Popup();if not popup then return nil end
 for _,child in ipairs(popup.children or {}) do
  if child.kind=='Button' and child:GetText()=='Got it' then return child end
 end
end
local function Record(id)
 return {id=id,title='Synthetic '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
end
local function Overlay(n)local m={};for i=1,n do m['syn-'..i]=Record('syn-'..i) end;return m end

-- 1. Positive control: an ordinary start-up records the acknowledgement once.
local ok=F.Database({mutate=function(db)db.hasSeenQuickStart=true end})
local H=F.Boot(ok)
H.Advance(3,.05)
local s=Nexus.StartupStatus()
check(s.coreReady and s.state~='failed','control: local start-up completed: '..tostring(s.reason))
check(Nexus.Store.StateWriteStatus().mode=='durable','control: the saved-data owner is writable')
check(Nexus.Changelog.CanRecordSeen()==true,'control: the acknowledgement may be recorded')
check(Popup() and Popup():IsShown(),'control: the release note is shown')
local top,settings=Seen()
check(top==KEY and settings==KEY,'control: the acknowledgement is recorded in both places')
local button=CloseButton()
check(button~=nil,'control: the note has its close button')
button:Click()
check(not Popup():IsShown(),'control: the note closes')
H=F.Reload();H.Advance(3,.05)
check(not (Popup() and Popup():IsShown()),'control: the recorded note is not offered again')

-- 2. A refused shared catalog: local tools start, saved data stays as found.
-- The note is shown and closes, and the acknowledgement is not consumed.
local refused={settingsVersion=2,settings={autoPick=false},chars={},hasSeenQuickStart=true,
 communityBuilds=Overlay(2049)}
local H2=F.Boot(refused)
H2.Advance(3,.05)
local r=Nexus.StartupStatus()
check(r.state=='failed' and r.reason=='ROOT_SLOT_LIMIT' and r.coreReady==true,
 'capacity: the shared catalog is refused and local tools start: '..tostring(r.reason))
check(Nexus.Changelog.CanRecordSeen()==false,'capacity: the acknowledgement is withheld in a failed start-up')
check(Popup() and Popup():IsShown(),'capacity: the release note is still shown')
local top2,settings2=Seen()
check(top2==nil and settings2==nil,'capacity: nothing was written: '..tostring(top2)..'/'..tostring(settings2))
CloseButton():Click()
check(not Popup():IsShown(),'capacity: the note closes normally')
top2,settings2=Seen()
check(top2==nil and settings2==nil,'capacity: closing the note writes nothing either')
H2=F.Reload();H2.Advance(3,.05)
check(Popup():IsShown(),'capacity: the note is offered again in the next session')
local top3,settings3=Seen()
check(top3==nil and settings3==nil,'capacity: the reload records nothing')

-- 3. The same profile once the shared catalog fits: the note is recorded.
NexusDB.communityBuilds['syn-2049']=nil
H2=F.Reload();H2.Advance(3,.05)
local back=Nexus.StartupStatus()
check(back.coreReady and back.state~='failed','recovered: start-up completes: '..tostring(back.reason))
local top4,settings4=Seen()
check(top4==KEY and settings4==KEY,'recovered: the acknowledgement is recorded normally')

-- 4. A malformed saved format marker: the session runs read-only. The note is
-- viewable and closes, and the acknowledgement is never written.
local readOnly=F.Database({mutate=function(db)db.settingsVersion={version=5};db.hasSeenQuickStart=true end})
local H3=F.Boot(readOnly)
H3.Advance(3,.05)
local w=Nexus.Store.StateWriteStatus()
check(w.mode=='unavailable' and w.format=='malformed','read-only: the saved-data owner is not writable: '..tostring(w.mode))
check(Nexus.Changelog.CanRecordSeen()==false,'read-only: the acknowledgement is withheld')
check(Popup() and Popup():IsShown(),'read-only: the release note is still viewable')
CloseButton():Click()
check(not Popup():IsShown(),'read-only: the note closes normally')
Nexus.Changelog.ShowIfNeeded()
local top5,settings5=Seen()
check(top5==nil and settings5==nil,'read-only: no acknowledgement is written: '..tostring(top5)..'/'..tostring(settings5))
check(type(rawget(NexusDB,'settingsVersion'))=='table','read-only: the malformed marker is unchanged')

----------------------------------------------------------------------------
-- 5-8. The release note and the setup window open together (owner report,
-- startup-dialog-overlap-v18: the P1.6 note over the information-only setup
-- window, the setup window's buttons drawn over the note's body, both
-- windows' texts colliding, "Got it" and Close both visible).
-- The setup window here is the real QuickStart window through its real
-- information-only route (QuickStart.ShowSetup, the Options menu's "Setup
-- information (read only)"), and the note is the real one shown by its own
-- start-up timer (Changelog.ShowIfNeeded after PLAYER_ENTERING_WORLD). Both
-- are real window trees: the window, the opaque base the appearance puts one
-- level under it (Theme.StyleWindow) and every button of the window.
-- EXPECT (by reading, expected to fail at eb4df21c; Root runs it): whenever
-- both windows are shown, every frame of one window's tree draws below every
-- frame of the other's. Frames draw by strata, then by frame level, and
-- regions (text, textures) draw with their frame. So one window's button at a
-- level at or above the other window's lowest frame draws over that window's
-- opaque base or its body text. Equal strata and level is not an order: the
-- client may draw either first. Either window may be the front one. A window
-- that is not shown at all (hidden, or deferred until the other closes) is
-- not interleaved with anything. Asked in both orders (note first; setup
-- first during start-up, then reopened over the note), and in a refused and
-- a read-only start-up, where the note is shown but not recorded.
-- GUARD, in every run: the setup route still opens its window when asked
-- (information only: it records nothing); the note is recorded exactly when
-- it is displayed and the saved-data owner is durable, never in a refused or
-- read-only session, and never by the setup window; no game action, no
-- message, Auto stays OFF. Scenarios 1-4 above run unchanged and first.
-- MODEL, this test only (the shared harness answers frame level 1 and
-- strata MEDIUM for every frame whatever its parent, so it cannot see an
-- inherited order). Installed before the TOC loads, on every frame made
-- through CreateFrame and on UIParent:
--   * strata: a frame's own SetFrameStrata, else its nearest ancestor's;
--     setting a frame's strata also clears its descendants' own strata, so
--     they follow it. UIParent is MEDIUM.
--   * level: a frame's own SetFrameLevel (absolute, floored, never below 0),
--     else its parent's level + 1, read when asked (so a child without its
--     own level follows its parent). UIParent is 0.
--   * order: (strata, level). Equal keys are unordered.
--   * Raise, Lower and SetToplevel are not modelled: a call is recorded and
--     named in the EXPECT's message, and it changes no level here.
-- Not modelled: the client's own re-levelling of children, toplevel
-- raising on click, the order between equal keys, layers inside one frame,
-- pixel geometry and mouse hits. This is an offline model; the native order
-- must still be seen in the game.
local STRATA={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local ORDER={unmodelled={}}
local function Modelled(f) return type(f)=='table' and rawget(f,'_orderModel')==true end
local function Strata(f)
 local o,guard=f,0
 while type(o)=='table' and guard<64 do
  local s=rawget(o,'_orderStrata') or rawget(o,'strata')
  if STRATA[s] then return s end
  o=rawget(o,'parent');guard=guard+1
 end
 return 'MEDIUM'
end
local function Level(f,depth)
 depth=(depth or 0)+1
 local own=rawget(f,'_orderLevel')
 if own then return own end
 local parent=rawget(f,'parent')
 if Modelled(parent) and depth<64 then return Level(parent,depth)+1 end
 if type(parent)=='table' then return (tonumber(parent:GetFrameLevel()) or 0)+1 end
 return 0
end
local function ClearStrata(f)
 for _,child in ipairs(rawget(f,'children') or {}) do
  if Modelled(child) then rawset(child,'_orderStrata',nil);ClearStrata(child) end
 end
end
local function Adopt(f)
 if type(f)~='table' then return f end
 rawset(f,'_orderModel',true)
 rawset(f,'GetFrameLevel',function(self) return Level(self) end)
 rawset(f,'SetFrameLevel',function(self,v)
  v=tonumber(v)
  if v then rawset(self,'_orderLevel',math.max(0,math.floor(v))) end
 end)
 rawset(f,'GetFrameStrata',function(self) return Strata(self) end)
 rawset(f,'SetFrameStrata',function(self,s)
  if STRATA[s] then rawset(self,'_orderStrata',s);ClearStrata(self) end
 end)
 for _,call in ipairs({'Raise','Lower','SetToplevel'}) do
  rawset(f,call,function(self)
   ORDER.unmodelled[#ORDER.unmodelled+1]=call..' on '..tostring(rawget(self,'name') or rawget(self,'kind'))
  end)
 end
 return f
end
-- F.Boot's `before` hook: after the harness loads, before the TOC. The two
-- windows' names are cleared first, so a frame of an earlier session is
-- never read as this session's window.
local function InstallOrder()
 NexusChangelogPopup,NexusQuickStart,NexusQuickStartEscape=nil,nil,nil
 ORDER.unmodelled={}
 Adopt(UIParent);rawset(UIParent,'_orderLevel',0)
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,...) return Adopt(create(kind,name,parent,...)) end
end
-- The shown frames of a window's tree (the window, its base, its buttons and
-- their own child frames). Texts and textures draw with their frame.
local function Frames(root,out)
 out=out or {}
 if Modelled(root) and root:IsVisible() then out[#out+1]=root end
 for _,child in ipairs(rawget(root,'children') or {}) do
  if Modelled(child) then Frames(child,out) end
 end
 return out
end
local function Key(f) return STRATA[Strata(f)]*65536+Level(f) end
local function Describe(f)
 local text=rawget(f,'text')
 local label=rawget(f,'name') or (tostring(rawget(f,'kind'))..((type(text)=='string' and text~='') and (' "'..text..'"') or ''))
 return label..' '..Strata(f)..'/'..Level(f)
end
local function Span(root)
 local low,high,lowFrame
 for _,f in ipairs(Frames(root)) do
  local k=Key(f)
  if not low or k<low then low,lowFrame=k,f end
  if not high or k>high then high=k end
 end
 return low,high,lowFrame
end
-- The frames of `back` that draw at or above `floor`.
local function Reach(back,floor)
 local out={}
 for _,f in ipairs(Frames(back)) do if Key(f)>=floor then out[#out+1]=Describe(f) end end
 return out
end
-- The two windows' default places overlap (both centred on UIParent); nil
-- when either is anchored otherwise, so nothing is claimed.
local function Box(f)
 local p,rel,rp,x,y=f:GetPoint(1)
 if p~='CENTER' or rel~=UIParent or rp~='CENTER' then return nil end
 local w,h=tonumber(f:GetWidth()) or 0,tonumber(f:GetHeight()) or 0
 x,y=tonumber(x) or 0,tonumber(y) or 0
 return x-w/2,x+w/2,y-h/2,y+h/2
end
local function Overlap(a,b)
 local al,ar,ab,at=Box(a)
 local bl,br,bb,bt=Box(b)
 if not (al and bl) then return nil end
 return al<br and bl<ar and ab<bt and bb<at
end
local expects,expectMisses=0,{}
local function Layers(tag)
 expects=expects+1
 local note,setup=Popup(),NexusQuickStart
 if not (note and setup and note:IsVisible() and setup:IsVisible()) then return end
 check(Overlap(note,setup)~=false,tag..': fixture: at their places the two windows overlap')
 local noteLow,noteHigh,noteFloor=Span(note)
 local setupLow,setupHigh,setupFloor=Span(setup)
 check(noteLow and setupLow,tag..': fixture: both windows have shown frames')
 if noteHigh<setupLow or setupHigh<noteLow then return end
 expectMisses[#expectMisses+1]=tag..': the two windows interleave. Setup frames drawn at or above the note\'s lowest frame ('
  ..Describe(noteFloor)..'): '..table.concat(Reach(setup,noteLow),', ')
  ..'. Note frames drawn at or above the setup window\'s lowest frame ('..Describe(setupFloor)..'): '
  ..table.concat(Reach(note,setupLow),', ')
  ..(#ORDER.unmodelled>0 and ('. Unmodelled order calls: '..table.concat(ORDER.unmodelled,', ')) or '')
end
local function Quiet(H,tag,acts,sent)
 check(#H.actions==acts and #H.sent==sent,tag..': no game action and no message: actions '
  ..(#H.actions-acts)..', messages '..(#H.sent-sent))
 check(Nexus.RecomputeStats().autoEnabled~=true,tag..': Auto stays OFF')
end
local function OpenSetup(tag)
 local shown,why=Nexus.QuickStart.ShowSetup()
 check(shown==true and NexusQuickStart~=nil and NexusQuickStart:IsShown() and rawget(NexusQuickStart,'_informational')==true,
  tag..': the information-only setup window opens when asked: '..tostring(why))
end
local function CloseSetup(tag)
 local close=NexusQuickStart and rawget(NexusQuickStart,'close')
 check(close~=nil,tag..': fixture: the setup window has its Close')
 close:Click()
 check(not NexusQuickStart:IsShown(),tag..': the setup window closes')
end
local function Durable(db) return F.Database({mutate=function(d)d.hasSeenQuickStart=true;if db then db(d) end end}) end

-- 5. The note first (the observed state), then the setup window, closed and
-- opened again over it, then the note closed.
do
 local tag='overlap note-first'
 local H5=F.Boot(Durable(),InstallOrder)
 H5.Advance(3,.05)
 check(Popup() and Popup():IsShown(),tag..': fixture: the release note is shown by its start-up timer')
 local t,s=Seen()
 check(t==KEY and s==KEY,tag..': the note is recorded on display in a durable start-up')
 local acts,sent=#H5.actions,#H5.sent
 OpenSetup(tag)
 Layers(tag..', setup opened over the note')
 CloseSetup(tag)
 OpenSetup(tag..' (reopened)')
 Layers(tag..', setup reopened over the note')
 if Popup():IsShown() then
  CloseButton():Click()
  check(not Popup():IsShown(),tag..': the note closes')
 end
 check(NexusQuickStart:IsShown(),tag..': the setup window stays open after the note')
 t,s=Seen()
 check(t==KEY and s==KEY,tag..': the acknowledgement is unchanged')
 check(rawget(NexusDB,'hasSeenQuickStart')==true,tag..': the setup window records nothing of its own')
 Quiet(H5,tag,acts,sent)
end

-- 6. The setup window first, during start-up, then the note's timer; then
-- the setup window opened again while the note is shown.
do
 local tag='overlap setup-first'
 local opened,early
 local H6=F.Boot(Durable(),InstallOrder,function()
  early=Nexus.StartupStatus().state
  opened={Nexus.QuickStart.ShowSetup()}
 end)
 check(opened and opened[1]==true,tag..': the information-only setup window opens at start-up (state '..tostring(early)..'): '
  ..tostring(opened and opened[2]))
 local acts,sent=#H6.actions,#H6.sent
 H6.Advance(3,.05)
 Layers(tag..', the note arrives while setup is open')
 local shownNote=Popup()~=nil and Popup():IsShown()
 local t,s=Seen()
 check((shownNote and t==KEY and s==KEY) or (not shownNote and t==nil and s==nil),
  tag..': the note is recorded exactly when it is displayed: shown '..tostring(shownNote)..', recorded '..tostring(t)..'/'..tostring(s))
 if shownNote then
  OpenSetup(tag..' (reopened)')
  Layers(tag..', setup reopened over the note')
 end
 Quiet(H6,tag,acts,sent)
end

-- 7. A refused start-up (the shared catalog over its limit): the note is
-- shown and not recorded, and the setup window opens over it.
do
 local tag='overlap refused'
 local H7=F.Boot({settingsVersion=2,settings={autoPick=false},chars={},hasSeenQuickStart=true,
  communityBuilds=Overlay(2049)},InstallOrder)
 H7.Advance(3,.05)
 local r7=Nexus.StartupStatus()
 check(r7.state=='failed' and r7.reason=='ROOT_SLOT_LIMIT',tag..': fixture: the start-up is refused: '..tostring(r7.reason))
 check(Popup() and Popup():IsShown(),tag..': fixture: the note is shown')
 local acts,sent=#H7.actions,#H7.sent
 OpenSetup(tag)
 Layers(tag..', setup opened over the note')
 local t,s=Seen()
 check(t==nil and s==nil,tag..': nothing is recorded: '..tostring(t)..'/'..tostring(s))
 Quiet(H7,tag,acts,sent)
end

-- 8. A read-only start-up (malformed format marker): the same, and the
-- marker stays as found.
do
 local tag='overlap read-only'
 local H8=F.Boot(Durable(function(d)d.settingsVersion={version=5} end),InstallOrder)
 H8.Advance(3,.05)
 check(Nexus.Store.StateWriteStatus().mode=='unavailable',tag..': fixture: the saved-data owner is not writable')
 check(Popup() and Popup():IsShown(),tag..': fixture: the note is shown')
 local acts,sent=#H8.actions,#H8.sent
 OpenSetup(tag)
 Layers(tag..', setup opened over the note')
 CloseSetup(tag)
 OpenSetup(tag..' (reopened)')
 Layers(tag..', setup reopened over the note')
 local t,s=Seen()
 check(t==nil and s==nil,tag..': nothing is recorded: '..tostring(t)..'/'..tostring(s))
 check(type(rawget(NexusDB,'settingsVersion'))=='table',tag..': the malformed marker is unchanged')
 Quiet(H8,tag,acts,sent)
end

-- The collected EXPECT fails only after every check above ran.
if #expectMisses>0 then
 error('changelog_seen_guard: EXPECT the release note and the setup window never interleave ('..#expectMisses..' of '
  ..expects..' layer checks): '..table.concat(expectMisses,' | ')..'; checks='..checks,0)
end
print('PASS changelog_seen_guard: recorded on a durable start-up; withheld, viewable and re-offered on a refused or read-only one; the release note and the setup window never interleave checks='..checks..' layers='..expects)
