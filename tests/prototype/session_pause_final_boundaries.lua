-- Issue #171 review repairs (Standards S1-S3, Spec F1): a pause raised inside
-- a callback that runs after an owner's first pause check still stops the new
-- work behind it. Each case pauses from inside a real dependency callback
-- (boundary sink, native request, option read, tome read, slot read, CTL,
-- channel read, whisper guard, Details read), and each has an unpaused
-- control on the same rig. Already-sent work and its marks are kept.
local function Reset()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
end
-- Wraps t[name] so that its first call (or every call while `armed`) pauses.
local function PauseInside(t,name,quick)
 local f=t[name];local state={armed=true,calls=0}
 t[name]=function(...)
  state.calls=state.calls+1
  if state.armed then
   state.armed=false;Nexus.SessionPause.Pause()
   if quick then Nexus.SessionPause.Resume() end
  end
  return f(...)
 end
 state.restore=function() t[name]=f end
 return state
end

local failures={}
local function Case(name,fn)
 local ok,err=pcall(fn)
 print((ok and 'CASE PASS ' or 'CASE FAIL ')..name..(ok and '' or (': '..tostring(err))))
 if not ok then failures[#failures+1]=name end
end

-- B1. Orb Select: Pause inside the "pick_call" boundary sink.
Case('B1',function()
for _,pause in ipairs({false,true}) do
 Reset()
 local H=dofile('tests/prototype/orbs_support.lua');local M,B=H.M,H.A.Orbs
 H.OrbPlan({{spellId=410002,quality=2,stacks=3}});H.Approve(3)
 B.BoundarySink(function(event) if pause and event=='pick_call' then Nexus.SessionPause.Pause() end end)
 H.Offer()
 if pause then
  assert(H.Count('take')==0,'B1: no SelectPerk after a pause inside the pick boundary, takes='..H.Count('take'))
  local s=M.Status()
  assert(not s.running and s.pending and s.spent<=1 and (s.uncertain or 0)==0,'B1: the run is held, its receipt kept, no new exposure')
 else
  assert(H.Count('take')==1,'B1 control: the choice is selected')
 end
end
end)

-- B2. Orb RequestRefresh: Pause inside the Orb count request. The count
-- request already sent keeps its mark; the ownership request is not sent.
Case('B2',function()
for _,pause in ipairs({false,true}) do
 Reset()
 local H=dofile('tests/prototype/orbs_support.lua');local B=H.A.Orbs
 local before=H.grantedRequests or 0
 local w=pause and PauseInside(ProjectEbonhold.OrbService,'RequestCharges')
 local ok,why,mark=B.RequestRefresh(false)
 if pause then
  w.restore()
  assert(H.O.requests==1,'B2: the Orb count request was sent once')
  assert((H.grantedRequests or 0)==before,'B2: no ownership request after the pause')
  assert(not ok and why=='session_paused' and type(mark)=='table','B2: refused with the sent request\'s mark kept: '..tostring(why))
 else
  assert(ok and (H.grantedRequests or 0)==before+1,'B2 control: both requests are sent')
 end
end
end)

-- B3-B5 on the ordinary rig.
local function Boot(before)
 Reset()
 local H=dofile('tests/prototype/harness.lua')
 if before then before(H) end
 H.Boot();H.Advance(1)
 return H
end

-- B3. SetSoloPicker: Pause inside the option read.
Case('B3',function()
for _,pause in ipairs({false,true}) do
 local H=Boot()
 local opts=ProjectEbonholdOptionsService
 opts:SetSetting('autoAcceptLoadoutEchoes',true)
 local sets=0;local set=opts.SetSetting
 opts.SetSetting=function(...)sets=sets+1;return set(...) end
 local w=pause and PauseInside(opts,'GetSetting')
 local ok=Nexus.GameAdapter.SetSoloPicker()
 if pause then
  w.restore()
  assert(not ok and sets==0,'B3: no option change after a pause inside its read')
  assert(opts:GetSetting('autoAcceptLoadoutEchoes')==true,'B3: the option is as the player set it')
  assert(Nexus.Store.State().priorAutoAccept==nil,'B3: no restore lease recorded')
 else
  assert(ok and sets==1 and Nexus.Store.State().priorAutoAccept==true,'B3 control: changed with its lease recorded')
 end
end
end)

-- B4. ToggleLever: Pause inside the tome member read.
Case('B4',function()
for _,pause in ipairs({false,true}) do
 local H=Boot(function(h)
  h.names[777001]='Tome of Lever';h.AddEcho(300001,'Lever',1,1,0);h.db[300001].requiredSpell=777001
  h.discovered[300001]=true;h.perks.discoveredEchoes=h.discovered;h.playerLevel=1
 end)
 local toggles=0;local toggle=H.service.ToggleTomeEcho
 H.service.ToggleTomeEcho=function(...)toggles=toggles+1;return toggle(...) end
 local w=pause and PauseInside(H.service,'IsTomeEchoDisabled')
 local ok,why=Nexus.GameAdapter.ToggleLever(777001,true)
 if pause then
  w.restore()
  assert(not ok and toggles==0,'B4: no tome toggle after a pause inside its read: '..tostring(why))
  local st=Nexus.Store.State()
  assert(not (st.tomeTogglePending and st.tomeTogglePending[777001]),'B4: no pending entry')
 else
  assert(ok and toggles==1,'B4 control: the toggle is sent: '..tostring(why))
 end
end
end)

-- B5. UploadWishlist: Pause inside the server slot read of its stale check.
Case('B5',function()
for _,pause in ipairs({false,true}) do
 local H=Boot()
 H.perks.serverBuildSlots={[2]={name='Plan',echoes={{spellId=200001,quality=1,stacks=1}}}}
 H.Notify();H.Advance(1)
 local A=Nexus.GameAdapter
 local token=A.ServerWishlistSlotToken(2)
 local uploads=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploads=uploads+1 end end
 local w=pause and PauseInside(H.service,'GetServerBuildSlots')
 local ok,why=A.UploadWishlist(2,'Plan',{{spellId=200002,quality=2,stacks=1}},{[token or 'none']=true})
 local after=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then after=after+1 end end
 if pause then
  w.restore()
  assert(not ok and after==uploads,'B5: no upload after a pause inside its slot read: '..tostring(why))
 else
  assert(ok and after==uploads+1,'B5 control: uploaded: '..tostring(why))
 end
end
end)

-- B6. Direct Wire packet: Pause inside the channel-list read that proves the
-- connection just before submission.
Case('B6',function()
for _,pause in ipairs({false,true}) do
 local H=Boot()
 local n=#H.sent
 local w=pause and PauseInside(_G,'GetChannelList')
 local ok=Nexus.SyncWire.SendPacket('WLRQ|PrototypeTester|0,0,0,0',{},1)
 if pause then
  w.restore()
  assert(not ok and #H.sent==n,'B6: no packet after a pause inside the connection read')
  assert(Nexus.SyncWire.Stats().suspended==false,'B6: not a transport fault')
 else
  assert(ok and #H.sent==n+1,'B6 control: sent')
 end
end
end)

-- B7. Diagnostic whisper: Pause inside its peer guard.
Case('B7',function()
for _,pause in ipairs({false,true}) do
 local H=Boot()
 local n=#H.sent
 local w=pause and PauseInside(Nexus.SyncWire,'IsWhisperTargetBlocked')
 Nexus.Sync.SendStatusTo('Peer')
 if pause then
  w.restore()
  assert(#H.sent==n,'B7: no whisper after a pause inside its guard')
 else
  assert(#H.sent==n+1 and H.sent[#H.sent].kind=='WHISPER','B7 control: whispered')
 end
end
end)

-- B8. DPS: Pause (or a quick Pause and Resume) inside the final Details read
-- at the end of the combat. The earlier record stays; nothing new is written.
Case('B8',function()
do
 local T=dofile('tests/prototype/startup_support.lua')
 Reset()
 local H=dofile('tests/prototype/harness.lua')
 NexusDB=T.Profile(0,0)
 for i=1,79 do H.AddEcho(300000+i,'Echo '..(300000+i),2,4,300000+i) end
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 local D=Nexus.DpsCapture
 local realUnitName=UnitName
 UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realUnitName(unit) end
 UnitExists=function(unit) return unit=='target' end
 local combat={total=100000}
 function combat:GetActor() return {total=self.total,Tempo=function() return 10 end} end
 function combat:GetCombatTime() return 10 end
 local details={GetCurrentCombat=function() return combat end}
 Details=details;DETAILS_ATTRIBUTE_DAMAGE=1
 local granted,echoes={},{}
 for i=1,79 do granted[H.names[300000+i]]={{spellId=300000+i,quality=2}};echoes[i]={spellId=300000+i,quality=2,stacks=1,locked=false} end
 H.granted=granted;H.locked={}
 H.perks.serverBuildSlots={[1]={name='Saved',verified=true,echoes=echoes}};H.perks.serverActiveSlot=1
 H.Notify();Nexus.GameAdapter.Poll();H.Advance(1)
 local function Best() local b=D.GetCurrentPersonalBest('dummy');return b and b.dps or 0 end
 local function Combat(total,quick,pauseAtEnd)
  combat.total=total
  H.Fire('PLAYER_REGEN_DISABLED');H.Advance(36,.05)
  local w=pauseAtEnd and PauseInside(details,'GetCurrentCombat',quick)
  H.Fire('PLAYER_REGEN_ENABLED')
  if w then w.restore() end
  H.Advance(.5)
  if Nexus.SessionPause.IsPaused() then Nexus.SessionPause.Resume() end
 end
 Combat(100000)
 local first=Best();assert(first>0,'B8 control: a complete combat is recorded')
 Combat(300000,false,true)
 assert(Best()==first,'B8: a pause inside the final Details read records nothing: '..tostring(Best()))
 Combat(400000,true,true)
 assert(Best()==first,'B8: a quick Pause and Resume inside the final read records nothing')
 Combat(500000)
 assert(Best()>first,'B8: the next complete combat is recorded')
end
end)

assert(#failures==0,'failed cases: '..table.concat(failures,', '))
print('PASS session pause final boundaries hold after callback-raised pauses')
