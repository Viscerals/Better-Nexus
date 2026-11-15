local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local permit=false
local realInit=Nexus.CommunityBuilds.Init
local calls=0
Nexus.CommunityBuilds.Init=function(...)
 calls=calls+1
 if not permit then return {state='pending',phase='identities',progressDone=1,progressTotal=4}end
 return realInit(...)
end
local syncCalls,dpsCalls=0,0
local si,di=Nexus.Sync.Init,Nexus.DpsCapture.Init
Nexus.Sync.Init=function(...)syncCalls=syncCalls+1;return si(...)end
Nexus.DpsCapture.Init=function(...)dpsCalls=dpsCalls+1;return di(...)end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
SlashCmdList.NEXUS('loading')
local f=assert(NexusLoadingStatusFrame,'EXPECTED RED: read-only loading panel available before core readiness')
check(f:IsShown() and f:GetWidth()==430,'small non-fullscreen panel shown')
check(not NexusLoadingOpenWishlist:IsEnabled(),'local controls not falsely unlocked before Store readiness')
check(Nexus.LoadingStatus.Progress({state='pending',phase='scan',recordsSeen=9})==nil,'no invented total percentage')
local pct,txt=Nexus.LoadingStatus.Progress({state='pending',step='identities',stepDone=1,stepTotal=4})
check(pct==25 and txt:find('Current step: Preparing shared build information; 1 / 4 (25%)',1,true),'measured percentage explicitly current-step')
local pct2=Nexus.LoadingStatus.Progress({state='pending',stepDone=5,stepTotal=4})
check(pct2==nil,'invalid progress cannot display over100 percent')
H.Advance(5)
local s=Nexus.StartupStatus()
check(s.coreReady and s.state=='pending','local ready while real shared gate remains pending')
check(s.progressDone==1 and s.progressTotal==4 and s.step=='identities' and s.stepDone==1 and s.stepTotal==4,'read-only current-owner progress retained')
check(NexusLoadingOpenWishlist:IsEnabled(),'local navigation unlocks after real local readiness')
check(f.bar:GetValue()==25 and f.bar:IsShown() and f.detail:GetText():find('25%%'),'actual panel renders measured phase percent')
local before=calls
for i=1,100 do local x=Nexus.StartupStatus();Nexus.LoadingStatus.Update(x,true)end
check(calls==before and #H.sent==0,'status reads do not pump or send')
check(syncCalls==0 and dpsCalls==0,'unready shared services stay gated')
local chat=#H.chat;H.Advance(2)
check(#H.chat==chat,'no progress chat flood')
NexusLoadingOpenWishlist:Click()
check(NexusEditorFrame and NexusEditorFrame:IsShown(),'real local editor available while database loads')
local gray=0
for _,button in ipairs(H.frames)do
 if button.kind=='Button' and type(button:GetText())=='string' and button:GetText():find('|cff888888',1,true)then gray=gray+1 end
end
check(gray>=2,'data navigation shows gray loading labels')
Nexus.CommunityBuilds.Show()
check(NexusSharedStartupFrame:IsShown(),'guarded shared placeholder visible')
check(not NexusCommunityBuildsFrame or not NexusCommunityBuildsFrame:IsShown(),'no premature shared browser')
NexusSharedLoadingWishlists:Click()
check(not NexusSharedStartupFrame:IsShown() and NexusEditorFrame:IsShown(),'local return action cancels deferred shared focus')
NexusLoadingDismiss:Click();H.Advance(1)
check(not f:IsShown(),'dismissed loader stays dismissed while work continues')
check(calls>before,'dismissing status does not cancel work')
SlashCmdList.NEXUS('loading')
check(f:IsShown(),'read-only command reopens progress')
Nexus.Leaderboard.Show('lk')
check(NexusSharedStartupFrame:IsShown(),'Leaderboard withheld with same guarded placeholder')
permit=true;H.Advance(12)
s=Nexus.StartupStatus()
check(s.state=='ready' and s.syncReady and s.dpsReady,'real completion releases all shared services')
check(syncCalls==1 and dpsCalls==1,'each shared owner initialized once')
check(not NexusSharedStartupFrame:IsShown() and NexusLeaderboardFrame:IsShown(),'requested view opens after true completion')
H.Advance(4)
check(not f:IsShown(),'status automatically hides after ready without repeat frame creation')
SlashCmdList.NEXUS('loading')
check(f:IsShown() and f.bar:GetValue()==100,'explicit final status available')
local state=Nexus.StartupStatus();state.coreReady=false;state.state='pending'
check(Nexus.StartupStatus().state=='ready','presentation snapshot cannot mutate lifecycle authority')
SlashCmdList.NEXUS('status')
check(table.concat(H.chat,'\n'):find('auto OFF',1,true),'status work does not enable automation')

-- The automatic loading window follows the player's saved Hide Nexus Panel
-- choice (issue #164 panelHidden, through Nexus.Panel's own wanted
-- visibility, never its shown state). Each boot below is a fresh harness and
-- TOC load with a synthetic saved table; shared start-up is held pending as
-- above, so every observation is made while work is still loading. Every Show
-- of the loading window is counted from its creation, so an early flash is
-- seen, not only the final state. Synthetic profiles only.
do
 local F=dofile('tests/prototype/format5_support.lua')
 local function Fresh(db,beforeEvents)
  Nexus=nil;WishlistRealizerDB=nil;SlashCmdList=nil
  NexusLoadingStatusFrame=nil;NexusLoadingDismiss=nil;NexusLoadingOpenWishlist=nil
  NexusPanel=nil;NexusMinimapButton=nil
  local h=dofile('tests/prototype/harness.lua')
  NexusDB=db
  local r={h=h,shows=0,firstShowCore=nil,auto=0,frame=nil,permit=false,inits=0}
  local create=CreateFrame
  CreateFrame=function(kind,name,parent,...)
   local made=create(kind,name,parent,...)
   if name=='NexusLoadingStatusFrame' then
    r.frame=made
    local show=made.Show
    made.Show=function(self,...)
     r.shows=r.shows+1
     if r.firstShowCore==nil then r.firstShowCore=Nexus.StartupStatus().coreReady==true end
     return show(self,...)
    end
   end
   return made
  end
  T.Load()
  local init=Nexus.CommunityBuilds.Init
  Nexus.CommunityBuilds.Init=function(...)
   r.inits=r.inits+1
   if not r.permit then return {state='pending',phase='identities',progressDone=1,progressTotal=4}end
   return init(...)
  end
  -- Unforced calls are the lifecycle's automatic presentation pass.
  local update=Nexus.LoadingStatus.Update
  Nexus.LoadingStatus.Update=function(status,force,...)
   if not force then r.auto=r.auto+1 end
   return update(status,force,...)
  end
  if beforeEvents then beforeEvents(r) end
  h.Fire('ADDON_LOADED','Nexus');h.Fire('PLAYER_ENTERING_WORLD')
  return r
 end
 -- Steps the real lifecycle in 0.05 s turns until local readiness (bounded).
 local function UntilCore(r,label)
  for _=1,4000 do
   if Nexus.StartupStatus().coreReady then return end
   r.h.Advance(.05,.05)
   if label then assert(r.shows==0,label..': no loading window flashes while local data loads') end
  end
  error('bounded: local start-up did not become ready')
 end
 local function RoundTrip()
  local saved=F.Serialize(NexusDB)
  return assert(loadstring('return '..saved))(),saved
 end
 local function Quiet(r,label)
  check(#r.h.actions==0 and #r.h.sent==0 and Nexus.RecomputeStats().autoEnabled~=true,
   label..': no action, no send, Auto stays OFF')
 end

 -- L1 never hidden: the first automatic pass shows pending progress.
 local r=Fresh(F.Database())
 check(Nexus.StartupStatus().coreReady~=true,'L1: fixture: before local readiness')
 Nexus.LoadingStatus.Update()
 check(r.shows>=1 and r.frame~=nil and r.frame:IsShown() and r.firstShowCore==false,
  'L1: a never-hidden panel keeps the automatic pending window, before local readiness')
 UntilCore(r);r.h.Advance(1)
 check(r.frame:IsShown() and Nexus.StartupStatus().state=='pending' and r.auto>1 and NexusDB.panelHidden==nil,
  'L1: it stays while shared data is pending and writes no hidden choice')

 -- L2 the player's own hide (the X's owner, Panel.HideByPlayer) saves the
 -- choice; the automatic window follows it in this session too.
 Nexus.Panel.HideByPlayer()
 check(NexusDB.panelHidden==true and Nexus.Panel.VisibilityFacts().wanted==false,'L2: the player hide saves the hidden choice')
 local shows,calls=r.shows,r.auto
 r.h.Advance(1)
 check(not r.frame:IsShown() and r.shows==shows and r.auto>calls,'L2: automatic passes continue and keep the window hidden')

 -- L3 literal saved-data round trip and module reload: hidden from the
 -- first automatic pass, a forced update included, while start-up continues.
 local db,saved=RoundTrip()
 check(saved:find('["panelHidden"]=true',1,true)~=nil,'L3: fixture: the hidden choice is in the literal saved data')
 r=Fresh(db)
 check(Nexus.StartupStatus().coreReady~=true,'L3: fixture: before local readiness and Panel.Init')
 Nexus.LoadingStatus.Update()
 check(r.shows==0 and not (r.frame and r.frame:IsShown()),'L3: after a reload the first automatic pass shows no loading window')
 Nexus.LoadingStatus.Update(nil,true)
 check(r.shows==0,'L3: a forced update is not the player asking for the window')
 UntilCore(r,'L3');r.h.Advance(2)
 local s=Nexus.StartupStatus()
 check(s.coreReady and s.state=='pending' and r.auto>2 and r.inits>0 and r.shows==0,
  'L3: start-up still progresses while the window stays hidden')
 check(NexusDB.panelHidden==true,'L3: the hidden choice is unchanged')

 -- L4 /nexus loading opens it for this session; the hidden choice stays.
 SlashCmdList.NEXUS('loading')
 check(r.frame~=nil and r.frame:IsShown() and r.shows==1,'L4: /nexus loading opens progress while the panel stays hidden')
 check(NexusDB.panelHidden==true and Nexus.Panel.VisibilityFacts().wanted==false,'L4: it changes no hidden choice')
 r.h.Advance(1)
 check(r.frame:IsShown(),'L4: ordinary updates keep the requested window')

 -- L5 the next reload drops that request: the saved choice applies again.
 db=RoundTrip()
 r=Fresh(db)
 Nexus.LoadingStatus.Update()
 UntilCore(r,'L5');r.h.Advance(1)
 check(r.shows==0 and NexusDB.panelHidden==true,'L5: after the next reload the window stays hidden again')

 -- L6 the minimap button reopens the panel through its owner, clears the
 -- choice and normal pending progress appears.
 local mm=NexusMinimapButton
 check(mm~=nil and type(mm:GetScript('OnClick'))=='function','L6: fixture: the minimap button exists')
 mm:GetScript('OnClick')(mm,'LeftButton')
 check(NexusDB.panelHidden==nil and Nexus.Panel.VisibilityFacts().wanted==true,'L6: the minimap button clears the hidden choice')
 r.h.Advance(1)
 check(r.frame~=nil and r.frame:IsShown() and r.shows>=1 and Nexus.StartupStatus().state=='pending',
  'L6: normal pending progress appears again')

 -- L7 the loader's own X keeps it closed through updates and the panel's
 -- hide and reopen; only /nexus loading opens it again.
 NexusLoadingDismiss:Click()
 shows=r.shows
 r.h.Advance(1)
 check(not r.frame:IsShown() and r.shows==shows,'L7: the loader X keeps it closed through ordinary updates')
 Nexus.Panel.HideByPlayer();Nexus.Panel.Show();r.h.Advance(1)
 check(not r.frame:IsShown() and r.shows==shows and NexusDB.panelHidden==nil,'L7: hiding and reopening the panel do not undo that dismissal')
 SlashCmdList.NEXUS('loading')
 check(r.frame:IsShown() and r.shows==shows+1,'L7: /nexus loading reopens it')
 Quiet(r,'L7')

 -- L8 a read-only (future) saved root: its saved hidden choice applies, and
 -- a show or hide in the session changes the window but writes nothing.
 local fdb=F.Database({version=6,mutate=function(d)d.panelHidden=true end})
 local before=F.Serialize(fdb)
 r=Fresh(fdb)
 Nexus.LoadingStatus.Update()
 UntilCore(r,'L8');r.h.Advance(1)
 check(Nexus.MainInternals.SavedRootReadOnlyV1()=='future','L8: fixture: the saved root is read-only')
 check(r.shows==0,'L8: the saved hidden choice of a read-only root keeps the window hidden')
 mm=NexusMinimapButton
 mm:GetScript('OnClick')(mm,'LeftButton')
 check(rawget(NexusDB,'panelHidden')==true and Nexus.Panel.VisibilityFacts().wanted==true,'L8: showing the panel is session-only')
 r.h.Advance(1)
 check(r.frame~=nil and r.frame:IsShown(),'L8: the session show lets pending progress appear')
 Nexus.Panel.HideByPlayer();r.h.Advance(1)
 check(not r.frame:IsShown() and Nexus.Panel.VisibilityFacts().wanted==false,'L8: a session hide hides it again')
 check(F.Serialize(NexusDB)==before,'L8: no saved field is written')
 Quiet(r,'L8')

 -- L9 the client replaces NexusDB when saved data loads: an earlier root
 -- read is not latched, and the read creates no saved table.
 r=Fresh(nil,function()
  local had=rawget(_G,'NexusDB')
  check(Nexus.Panel.VisibilityFacts().wanted==true and rawget(_G,'NexusDB')==had,'L9: reading the choice creates no saved table')
  NexusDB=F.Database()
  check(Nexus.Panel.VisibilityFacts().wanted==true,'L9: fixture: a first saved root (never hidden) was read')
  NexusDB=F.Database({mutate=function(d)d.panelHidden=true end})
 end)
 Nexus.LoadingStatus.Update()
 check(r.shows==0 and Nexus.Panel.VisibilityFacts().wanted==false,'L9: the replacing saved root decides; the first is not latched')
end
print('PASS loading phase progress, early local controls, shared gating, cancellation and no chat spam checks='..checks)
