-- UX M5 14d (LP-12): the one optional account-level Sync mode choice.
-- Store -> SyncModePolicy -> Build Library UI and back, through the real
-- production owners: the effective reader SavedFormat.SyncMode
-- (MainInternals.SavedSyncModeV1), the status seam SyncModeChoiceV1, the
-- counted-private StoreAuthorityOwner.UpdateSettingsV1 (its one new caller is
-- SyncModePolicy.ApplyChoice) and the "Sync mode..." draft dialog.
-- Healthy behaviour (EXPECT, fails on the preimage d15ba07c and on accepted
-- M4, which have no choice): opening makes a draft of the effective mode;
-- Cancel, X, Escape, closing the Library and reopening discard it and write
-- nothing; Apply writes the explicit choice even when the inherited mode is the
-- same, an identical stored choice is a no-op, a stored invalid value is
-- replaced; explicit Automatic overrides accepted legacy Off only after Apply;
-- the choice survives a reload; a stale draft and unwritable storage (future,
-- unverified, malformed, no database) are refused visibly with no session
-- override and no saved-graph change; Apply sends, queues, grants and calls no
-- Sync actor; Off chosen by the player blocks outbound on the existing path.
-- 14e (G): a distinct, valid saved root put in NexusDB under the coordinator
-- that initialized the first one is a replaced root: a draft opened on it, the
-- policy route and the Store owner refuse it ("replaced") and neither root's
-- graph changes; the bound root is writable again once restored, and a later
-- real initialization of the replacement (reload) is writable and persists.
-- M5 14E-Q5 (continuation 40, H): the post-ready Store mutation states. The
-- coordinator is the one MainLifecycle hands to Store.Init, captured by a
-- pass-through around Store.Init (the real Store.Init runs and its result is
-- returned). Store.RegisterCurrentCharacter, the public export, submits from
-- READY into MUTATION_BUILD. The lifecycle runs exactly one post-ready slice
-- per scheduler turn (MainLifecycle PumpStoreMutationSlice), so MUTATION_FINAL
-- is an observable state between turns. EXPECT:
--  - in MUTATION_BUILD the choice is writable with the READY root and settings
--    identity, and the dialog's Apply of a draft opened in READY saves and
--    reads back;
--  - in MUTATION_FINAL the policy route saves and reads back;
--  - in both states a distinct valid root is refused as replaced, with no write
--    to either root and no session setting;
--  - Apply leaves the mutation in its state and calls no Sync actor;
--  - the owned mutation then commits (MUTATION_COMMITTED, no drift) on the same
--    root;
--  - after a serialized reload the choice persists and is writable.
-- GUARD: the marker, the dormant syncMode and the registration row survive the
-- round trip.
-- Continuation 41: the registration row is checked against Store's own
-- canonical current-owner contract (Store.CurrentOwnerKey: owner key, name,
-- canonical realm suffix, the realm the candidate writes), not the fixture's
-- display realm "Ebonhold". SETUP states the owner and the row before the
-- mutation. Separate GUARDs check the row table's identity, the name and the
-- canonical realm after the commit, each printing its observed value.
-- Unchanged (GUARD, holds there too): settingsVersion, the accepted 3-5
-- classification, the old syncMode field, defaults, the Store facade and the
-- private owner entries; inherited modes without a choice.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Effects caused by the action are measured in windows with no time passing
-- (sends, queue admissions, refusals, manual grant, actor calls); normal
-- background Sync while time passes is not attributed to the action.
-- Escape is modelled as FrameXML CloseSpecialWindows (hide every shown
-- UISpecialFrames window); no native input. Synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('ux_sync_mode_choice')

local KEY='nexusSyncModeChoice'
local OFF_TEXT='saved Sync mode is Off'
local H,CB,P,calls,actorCalls

local ACTORS={
 Sync={'RequestSync','RequestFullLoadoutSync','RequestLoadout','RequestLockedRoles','BroadcastBuild',
  'BroadcastBuildSummary','BroadcastDpsRecord','BroadcastDps','BroadcastDelete','Init','Reset',
  'EnsureChannel','PumpPendingShare'},
 SyncWire={'SendPacket','PumpHandshake','Housekeep'},
 SyncModePolicy={'Reset','Bind','NoteExplicitShare'},
}
local function Boot(db)
 NexusQuickStart,NexusCommunityBuildsFrame,NexusLeaderboardFrame,NexusSyncModeDialog=nil,nil,nil,nil
 NexusHelpWindow,NexusOverwriteWarning,NexusPanel=nil,nil,nil
 H=F.Boot(db)
 CB,P=Nexus.CommunityBuilds,Nexus.SyncModePolicy
 calls,actorCalls={},{}
 local owner=Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
 local real=owner and owner.UpdateSettingsV1
 if type(real)=='function' then
  owner.UpdateSettingsV1=function(key,...) calls[#calls+1]=key;return real(key,...) end
 end
 for name,list in pairs(ACTORS) do
  local t=Nexus[name]
  if type(t)=='table' then
   for _,n in ipairs(list) do
    local f=rawget(t,n)
    if type(f)=='function' then t[n]=function(...) actorCalls[#actorCalls+1]=name..'.'..n;return f(...) end end
   end
  end
 end
 return H
end
local function Settings() return type(NexusDB)=='table' and rawget(NexusDB,'settings') or nil end
local function Stored() local s=Settings();return type(s)=='table' and rawget(s,KEY) or nil end
local function Effects()
 local st=Nexus.Sync.Stats() or {}
 return {sent=#H.sent,admitted=st.admittedPackets or 0,refused=st.modeRefused or 0,
  grant=P.ActiveManualGrant and P.ActiveManualGrant() or nil,actors=#actorCalls,writes=#calls}
end
local function NoEffect(a,b,writesToo)
 return a.sent==b.sent and a.admitted==b.admitted and a.refused==b.refused and a.grant==b.grant
  and a.actors==b.actors and (not writesToo or a.writes==b.writes)
end
local function EffText(e) return string.format('sent=%d admitted=%d refused=%d grant=%s actors=%d writes=%d',
 e.sent,e.admitted,e.refused,printable(e.grant),e.actors,e.writes) end
local function Dialog() return NexusSyncModeDialog end
local function Open(tag)
 CB.Show()
 local lib=NexusCommunityBuildsFrame
 local btn=lib and lib._modeBtn
 C.expect(btn~=nil and btn:IsShown() and V.Plain(btn:GetText())=='Sync mode...',tag..': the Build Library offers "Sync mode..." beside Sync Now',
  btn and btn:GetText())
 if not btn then return nil end
 btn:Click()
 local d=Dialog()
 C.expect(d~=nil and d:IsShown() and type(d._draft)=='table',tag..': the choice opens with a draft')
 return d
end
local function Option(d,mode)
 for _,o in ipairs(d and d.options or {}) do if o.mode==mode then return o end end
 return nil
end
local function Checked(d)
 local out={}
 for _,o in ipairs(d and d.options or {}) do if o:GetChecked() then out[#out+1]=o.mode end end
 return table.concat(out,',')
end
local function Escape()
 for _,name in ipairs(UISpecialFrames or {}) do
  local f=_G[name]
  if f and f.IsShown and f:IsShown() then f:Hide() end
 end
end
local function Registered(name)
 for _,n in ipairs(UISpecialFrames or {}) do if n==name then return true end end
 return false
end
-- The policy routes; absent on the preimage, where they record a failed
-- expectation instead of raising.
local function Apply(mode,token)
 if type(P.ApplyChoice)~='function' then return false,'no-policy-route' end
 return P.ApplyChoice(mode,token)
end
local function Status()
 return type(P.Choice)=='function' and P.Choice() or nil
end

C.scenario('A format-2 profile: draft lifecycle, same-value explicit write, no-op, Off, reload',function()
 Boot(F.Database({version=2}))
 C.setup(Nexus.StartupStatus().coreReady==true,'A: fixture: start-up reached core-ready')
 C.setup(rawget(Settings(),'syncMode')=='manual' and NexusDB.settingsVersion==2,'A: fixture: the format-2 settings store a dormant syncMode "manual"')
 C.guard(P.Mode()=='automatic','A: without a choice a format-2 profile stays Automatic (dormant syncMode not read)',P.Mode())
 local status=Status()
 C.expect(type(status)=='table' and status.writable==true and status.explicit==nil and status.inherited=='automatic',
  'A: the choice status is writable with no explicit choice, inheriting Automatic',status and printable(status.reason))
 local before=Effects()
 local d=Open('A open')
 if not d then return end
 local opened=Effects()
 C.expect(NoEffect(before,opened,true) and Stored()==nil,'A: opening writes, sends, queues and calls nothing',EffText(opened))
 C.expect(d._draft.mode=='automatic' and Checked(d)=='automatic','A: the draft starts at the effective mode',Checked(d))
 C.expect(V.Plain(d.current:GetText()):find('Automatic, the default (no choice saved)',1,true)~=nil,'A: it states the current mode and that no choice is saved',
  d.current:GetText())
 C.expect(Registered('NexusSyncModeDialog'),'A: Escape closes it (registered in UISpecialFrames)')
 -- Every way out of the draft writes nothing.
 local cases={
  {'Cancel',function() d.cancel:Click() end},
  {'X',function() d.close:Click() end},
  {'Escape',function() Escape() end},
  {'Library close',function() CB.Hide() end},
 }
 for _,case in ipairs(cases) do
  d=Open('A '..case[1])
  if not d then return end
  local o=Option(d,'off');if o then o:Click() end
  C.setup(d._draft and d._draft.mode=='off','A '..case[1]..': fixture: Off is selected in the draft')
  local e0=Effects()
  case[2]()
  local e1=Effects()
  C.expect(not d:IsShown() and d._draft==nil,'A '..case[1]..': the window closes and the draft is discarded')
  C.expect(Stored()==nil and P.Mode()=='automatic' and NoEffect(e0,e1,true),'A '..case[1]..': nothing is written, sent or called',EffText(e1))
 end
 -- Reopening replaces the draft with the effective mode.
 d=Open('A replace')
 if not d then return end
 local off=Option(d,'off');if off then off:Click() end
 d=Open('A replace again')
 C.expect(d and d._draft and d._draft.mode=='automatic' and Checked(d)=='automatic','A: reopening discards the Off draft for a fresh one',d and Checked(d))
 C.expect(Stored()==nil and #calls==0,'A: and nothing was written',#calls)
 -- Apply of the inherited value writes a separate explicit choice.
 local mark=Effects()
 d.apply:Click()
 local applied=Effects()
 C.expect(Stored()=='automatic' and #calls==1 and calls[1]==KEY,'A: Apply writes the explicit choice "automatic" even though it was inherited',
  printable(Stored())..' writes='..#calls)
 C.expect(V.Plain(d.result:GetText()):find('Saved: your Sync mode is now Automatic',1,true)~=nil,'A: the result is read back and stated',d.result:GetText())
 C.expect(V.Plain(d.current:GetText()):find('your saved choice',1,true)~=nil,'A: the current line now says it is your saved choice',d.current:GetText())
 C.expect(NoEffect(mark,applied,false),'A: Apply sends, queues, grants and calls no Sync actor',EffText(applied))
 -- The same stored explicit choice is a no-op.
 d.apply:Click()
 C.expect(#calls==1 and V.Plain(d.result:GetText()):find('Unchanged',1,true)~=nil,'A: applying the stored choice again writes nothing',d.result:GetText())
 local ok,result=Apply('automatic')
 C.expect(ok==true and result=='unchanged' and #calls==1,'A: and so does the policy route',printable(result))
 -- Off chosen by the player.
 off=Option(d,'off');if off then off:Click() end
 mark=Effects()
 d.apply:Click()
 applied=Effects()
 C.expect(Stored()=='off' and P.Mode()=='off' and #calls==2,'A: Apply Off saves Off and the policy honours it',printable(Stored()))
 C.expect(NoEffect(mark,applied,false),'A: Apply Off sends, queues and calls nothing',EffText(applied))
 C.guard(rawget(Settings(),'syncMode')=='manual' and NexusDB.settingsVersion==2,'A: the dormant syncMode and the format-2 marker are untouched')
 CB.Show();for _=1,20 do H.Advance(.05,.05) end
 local status1=V.Plain(NexusCommunityBuildsFrame._syncStatusText:GetText() or '')
 C.expect(status1:find(OFF_TEXT,1,true)~=nil,'A: the Build Library status states the saved Off mode',status1)
 local quiet=#H.sent
 for _=1,200 do H.Advance(.05,.05) end
 C.expect(#H.sent==quiet,'A: with Off chosen, nothing is sent while time passes (existing final-submit path)',#H.sent-quiet)
 -- Reload: the choice is saved data.
 local ok2=pcall(function() H=F.Reload() end)
 CB,P=Nexus.CommunityBuilds,Nexus.SyncModePolicy
 C.setup(ok2 and Nexus.StartupStatus().coreReady==true,'A: fixture: the profile reloaded')
 C.expect(P.Mode()=='off' and Stored()=='off','A: after a reload the saved Off choice is honoured',P.Mode())
 C.guard(rawget(Settings(),'syncMode')=='manual' and NexusDB.settingsVersion==2,'A: after the reload the dormant syncMode and marker are unchanged')
end)

C.scenario('B accepted format 5 legacy Off: explicit Automatic overrides it only after Apply',function()
 Boot(F.Database({mutate=function(db) db.settings.syncMode='off' end}))
 C.setup(Nexus.StartupStatus().coreReady==true,'B: fixture: start-up reached core-ready')
 C.guard(P.Mode()=='off','B: the accepted format-5 Off choice is honoured without a choice of yours',P.Mode())
 local d=Open('B')
 if not d then return end
 C.expect(V.Plain(d.current:GetText()):find('accepted saved settings of another Nexus version',1,true)~=nil,
  'B: the current line names the inherited source',d.current:GetText())
 local a=Option(d,'automatic');if a then a:Click() end
 C.expect(P.Mode()=='off' and Stored()==nil,'B: selecting Automatic alone changes nothing',P.Mode())
 d.apply:Click()
 C.expect(Stored()=='automatic' and P.Mode()=='automatic','B: after Apply the explicit Automatic overrides legacy Off',P.Mode())
 local class,version=Nexus.MainInternals.SavedFormatClassV1()
 C.guard(rawget(Settings(),'syncMode')=='off' and NexusDB.settingsVersion==5 and class=='known' and version==5,
  'B: the legacy syncMode, the format-5 marker and its accepted classification are unchanged',printable(class)..'/'..printable(version))
end)

C.scenario('C accepted format 5 legacy Manual: same-value explicit write, stored no-op, invalid stored value',function()
 Boot(F.Database())
 C.guard(P.Mode()=='manual','C: inherited Manual',P.Mode())
 local d=Open('C')
 if not d then return end
 C.setup(d._draft.mode=='manual','C: fixture: the draft starts at Manual')
 d.apply:Click()
 C.expect(Stored()=='manual' and #calls==1,'C: Apply writes the explicit Manual although the inherited mode is Manual',printable(Stored()))
 d.apply:Click()
 C.expect(#calls==1,'C: the identical stored choice is a no-op',#calls)
 -- A stored value this build does not accept is not a choice: the legacy mode
 -- applies and Apply replaces it.
 rawset(Settings(),KEY,'sometimes')
 local st=Status()
 C.expect(st and st.storedInvalid==true and st.explicit==nil and P.Mode()=='manual','C: an invalid stored value is ignored (legacy Manual applies)',
  st and printable(st.storedInvalid))
 local ok,result=Apply('manual',st and st.token)
 C.expect(ok==true and result=='saved' and Stored()=='manual' and #calls==2,'C: Apply replaces the invalid value',printable(result))
end)

C.scenario('D a stale draft is refused and writes nothing',function()
 Boot(F.Database({version=2}))
 local d=Open('D')
 if not d then return end
 local off=Option(d,'off');if off then off:Click() end
 local old=Settings()
 local copy={};for k,v in pairs(old) do copy[k]=v end
 NexusDB.settings=copy
 local e0=Effects()
 d.apply:Click()
 local e1=Effects()
 C.expect(rawget(old,KEY)==nil and rawget(copy,KEY)==nil and #calls==0,'D: Apply of a draft opened on replaced settings writes to neither table',#calls)
 C.expect(V.Plain(d.result:GetText()):find('changed after this window opened',1,true)~=nil and not d.apply:IsEnabled() and d._draft==nil,
  'D: the refusal is stated and the stale draft is discarded',d.result:GetText())
 C.expect(NoEffect(e0,e1,true),'D: nothing is sent or called',EffText(e1))
 NexusDB.settings=old
end)

C.scenario('E unwritable storage refuses visibly, no session override, graph unchanged',function()
 local roots={
  {'future',F.Database({version=9})},
  {'unverified',F.Database({mutate=function(db) db.settings.syncMode='banana' end})},
  {'malformed',F.Database({mutate=function(db) db.settingsVersion='5' end})},
 }
 for _,root in ipairs(roots) do
  local tag='E '..root[1]
  Boot(root[2])
  local graph=F.Serialize(NexusDB)
  local class=Nexus.MainInternals.SavedFormatClassV1()
  C.setup(class==root[1],tag..': fixture: the saved root is classified '..root[1],printable(class))
  -- The window itself, where this root lets the Build Library open.
  CB.Show()
  local lib=NexusCommunityBuildsFrame
  if lib and lib:IsShown() and lib._modeBtn then
   lib._modeBtn:Click()
   local d=Dialog()
   C.expect(d and d:IsShown() and not d.apply:IsEnabled()
    and V.Plain(d.result:GetText()):find('cannot be changed here',1,true)~=nil,
    tag..': the choice says it cannot be changed here and Apply is disabled',d and d.result:GetText())
   if d then d.cancel:Click() end
  else
   print('OBSERVED',tag,'the Build Library does not open on this root; the policy and Store refusals below still apply')
  end
  local ok,result=Apply('off')
  C.expect(ok==false and result=='saved-format',tag..': the policy refuses with the saved-format reason',printable(result))
  local owner=Nexus.MainInternals.StoreAuthorityOwner
  local r1,r2,r3=owner.UpdateSettingsV1(KEY,'off')
  C.expect(r1==nil and r2=='unavailable' and r3=='saved-format',tag..': the Store owner refuses the key itself',printable(r2)..'/'..printable(r3))
  local session=Nexus.Store.Settings()
  C.expect(rawget(session,KEY)==nil and P.Mode()=='automatic',tag..': no session-only override is made',P.Mode())
  C.guard(F.Serialize(NexusDB)==graph,tag..': the saved graph is unchanged')
 end
 -- No database loaded and an invalid value on a writable root.
 Boot(F.Database({version=2}))
 local saved=NexusDB
 NexusDB=nil
 local ok,result=Apply('off')
 local transient=Nexus.Store.Settings()
 NexusDB=saved
 C.expect(ok==false and result=='database' and rawget(transient,KEY)==nil,'E no database: refused, and no transient setting is written',printable(result))
 local before=#calls
 ok,result=Apply('sometimes')
 C.expect(ok==false and result=='invalid-value' and #calls==before and Stored()==nil,'E invalid value: refused before any write',printable(result))
 local r1,r2=Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1(KEY,'sometimes')
 C.expect(r1==nil and r2=='invalid-value' and Stored()==nil,'E invalid value: the Store owner refuses it too',printable(r2))
end)

C.scenario('F defaults, markers and owners unchanged',function()
 Boot(F.Database({version=2,mutate=function(db) db.settings.syncMode=nil end}))
 local defaults=Nexus.DefaultProfile and Nexus.DefaultProfile.defaultSettings or {}
 C.guard(rawget(defaults,KEY)==nil,'F: the default profile has no choice (absence inherits)')
 C.guard(Nexus.Store.SettingsVersion()==2,'F: settingsVersion stays 2')
 C.guard(Stored()==nil and P.Mode()=='automatic','F: a current profile without a choice is Automatic and stores nothing',P.Mode())
 CB.Show();for _=1,20 do H.Advance(.05,.05) end;CB.Hide()
 C.guard(Stored()==nil and #calls==0,'F: viewing the Build Library writes no choice',#calls)
end)

C.scenario('G a valid replacement root under the old coordinator is refused; its later initialization is writable',function()
 Boot(F.Database({version=2}))
 C.setup(Nexus.StartupStatus().coreReady==true,'G: fixture: start-up reached core-ready on the first root')
 local startup=Nexus.StartupStatus().state
 local R1=NexusDB
 local st1=Status()
 C.setup(type(st1)=='table' and st1.writable==true,'G: fixture: the initialized first root is writable',st1 and printable(st1.reason))
 -- A draft opened on the first root, then a distinct valid root replaces it.
 local d=Open('G stale')
 if not d then return end
 local off=Option(d,'off');if off then off:Click() end
 local R2=F.Database({version=2})
 C.setup(R2~=R1 and rawget(R2,'settings')~=rawget(R1,'settings'),'G: fixture: the replacement is a distinct root with its own settings')
 local g1=F.Serialize(R1)
 NexusDB=R2
 local g2=F.Serialize(R2)
 local e0=Effects()
 d.apply:Click()
 C.guard(V.Plain(d.result:GetText()):find('changed after this window opened',1,true)~=nil and d._draft==nil and #calls==0,
  'G: the draft opened on the first root is refused as stale',d.result:GetText())
 -- A fresh draft on the replacement root.
 local st2=Status()
 print('OBSERVED','G replacement status',st2 and printable(st2.writable),st2 and printable(st2.reason),st2 and printable(st2.format))
 C.expect(type(st2)=='table' and st2.writable==false and st2.reason=='replaced' and st2.format==(st1 and st1.format),
  'G: the valid replacement root is reported not writable, reason "replaced"',st2 and printable(st2.reason))
 local lib=NexusCommunityBuildsFrame
 if lib and lib._modeBtn then lib._modeBtn:Click() end
 d=Dialog()
 C.expect(d and d:IsShown() and not d.apply:IsEnabled()
  and V.Plain(d.result:GetText()):find('cannot be changed here: saved data was replaced after loading',1,true)~=nil,
  'G: a draft opened on it says so and Apply is disabled',d and d.result:GetText())
 local ok,result=Apply('off',st2 and st2.token)
 C.expect(ok==false and result=='replaced','G: the policy route refuses it with the same reason',printable(result))
 local r1,r2,r3=Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1(KEY,'off')
 C.expect(r1==nil and r2=='unavailable' and r3=='replaced','G: the Store owner refuses the key itself',printable(r2)..'/'..printable(r3))
 C.expect(F.Serialize(R1)==g1 and F.Serialize(R2)==g2 and #calls==1,
  'G: neither root\'s saved graph changes',#calls)
 C.expect(rawget(Nexus.Store.Settings(),KEY)==nil and P.Mode()=='automatic','G: no session-only override is made',P.Mode())
 local e1=Effects()
 C.expect(NoEffect(e0,e1,false),'G: nothing is sent, queued, granted or called',EffText(e1))
 if d then d.cancel:Click() end
 -- The bound root again: writable, and the write lands in it alone.
 NexusDB=R1
 C.guard(Nexus.StartupStatus().state==startup,'G: the start-up state is unchanged',Nexus.StartupStatus().state)
 local st3=Status()
 C.guard(type(st3)=='table' and st3.writable==true,'G: the restored bound root is writable again',st3 and printable(st3.reason))
 ok,result=Apply('off',st3 and st3.token)
 C.expect(ok==true and result=='saved' and rawget(rawget(R1,'settings'),KEY)=='off' and F.Serialize(R2)==g2,
  'G: Apply on the bound root saves there and leaves the replacement unchanged',printable(result))
 -- A later real initialization of the replacement: it becomes the bound root.
 NexusDB=R2
 local ok2=pcall(function() H=F.Reload() end)
 CB,P=Nexus.CommunityBuilds,Nexus.SyncModePolicy
 C.setup(ok2 and Nexus.StartupStatus().coreReady==true,'G: fixture: the replacement root was initialized by a reload')
 local st4=Status()
 C.expect(type(st4)=='table' and st4.writable==true and st4.explicit==nil,'G: once initialized it is writable, with no choice carried over',
  st4 and printable(st4.reason))
 ok,result=Apply('manual',st4 and st4.token)
 C.expect(ok==true and result=='saved' and Stored()=='manual' and P.Mode()=='manual','G: Apply saves into it and is read back',printable(result))
 ok2=pcall(function() H=F.Reload() end)
 CB,P=Nexus.CommunityBuilds,Nexus.SyncModePolicy
 C.setup(ok2 and Nexus.StartupStatus().coreReady==true,'G: fixture: it reloaded again')
 C.expect(Stored()=='manual' and P.Mode()=='manual','G: and the choice persists',P.Mode())
end)

C.scenario('H Apply in real MUTATION_BUILD and MUTATION_FINAL; the owned mutation commits; the choice persists',function()
 local BUILD,FINAL,READY='STORE_MUTATION_BUILD_PENDING','STORE_MUTATION_FINAL_COMMIT_PENDING','STORE_READY'
 -- The coordinator MainLifecycle binds through Store.Init. The real Store.Init
 -- runs with it and its result is returned unchanged.
 local coordinator
 F.fileHooks={['core\\Store.lua']=function()
  local store=Nexus.Store
  local init=store and store.Init
  if type(init)~='function' then return end
  store.Init=function(owner,...)
   if owner~=nil then coordinator=owner end
   return init(owner,...)
  end
 end}
 local booted,why=pcall(Boot,F.Database({version=2}))
 F.fileHooks=nil
 if not booted then error(why,0) end
 C.setup(Nexus.StartupStatus().coreReady==true,'H: fixture: start-up reached core-ready')
 local function State() return type(coordinator)=='table' and coordinator:State() or nil end
 C.setup(type(coordinator)=='table' and type(coordinator.State)=='function' and coordinator:Database()==NexusDB,
  'H: fixture: the coordinator bound through Store.Init is captured, and it holds this root')
 if type(coordinator)~='table' then return end
 -- Unrelated owners settle first: start-up's own registration mutation has
 -- committed, and no catalog root mutation or compaction work is pending (the
 -- catalog's bundle commit is the only writer of the authorityBundle that the
 -- mutation token pins). Read through their production status, for three
 -- consecutive turns.
 local function Quiet()
  local catalog,compaction=Nexus.BuildCatalog,Nexus.DataCompaction
  local root=catalog and type(catalog.RootState)=='function' and catalog.RootState() or {}
  local work=compaction and type(compaction.Stats)=='function' and compaction.Stats(NexusDB) or {}
  return State()==READY and root.state=='ROOT_ADMITTED' and root.candidate==false and work.pending~=true
 end
 local quiet=0
 for _=1,2000 do
  if Quiet() then quiet=quiet+1 else quiet=0 end
  if quiet>=3 then break end
  H.Advance(.05,.05)
 end
 C.setup(quiet>=3,'H: fixture: start-up\'s registration has committed and catalog and compaction work is idle',printable(State()))
 local R1=NexusDB
 local st0=Status()
 C.setup(type(st0)=='table' and st0.writable==true,'H: fixture: the choice is writable in READY',st0 and printable(st0.reason))
 if type(st0)~='table' or State()~=READY then return end
 local d=Open('H ready')
 if not d then return end
 local row=type(rawget(R1,'accountCharacters'))=='table' and R1.accountCharacters[F.OWNER] or nil
 -- Prerequisites, stated before the observed mutation. Store's canonical
 -- current-owner contract is the public export Store.CurrentOwnerKey: owner
 -- key, character name, and canonical realm suffix, the realm the registration
 -- candidate writes. The registration row is at that key.
 local ownerKey,ownerName,ownerRealm=Nexus.Store.CurrentOwnerKey()
 print('OBSERVED','H current owner','key='..printable(ownerKey),'name='..printable(ownerName),
  'canonical realm='..printable(ownerRealm),'fixture display realm='..printable(F.REALM),
  'row name before='..printable(row and row.name),'row realm before='..printable(row and row.realm))
 C.setup(ownerKey==F.OWNER and ownerName==F.NAME and type(ownerRealm)=='string' and ownerRealm~=''
  and ownerRealm==ownerKey:match('@(.+)$'),
  'H: fixture: Store\'s current owner is the fixture row key, with its character name and canonical realm suffix',
  printable(ownerKey)..' / '..printable(ownerName)..' / '..printable(ownerRealm))
 C.setup(type(row)=='table' and row.name==F.NAME,'H: fixture: the registration row is at that key before the observed mutation',
  printable(row and row.name))
 -- A distinct valid root put in NexusDB while the mutation is owned, with no
 -- time passing: refused by the policy and the Store owner, nothing written to
 -- either root or the session settings, and the mutation keeps its state.
 local function Replaced(tag,state)
  local R2=F.Database({version=2})
  local g1,g2,w=F.Serialize(R1),F.Serialize(R2),#calls
  NexusDB=R2
  local st=Status()
  local okR,resR=Apply('off',st and st.token)
  local r1,r2,r3=Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1(KEY,'off')
  local session=rawget(Nexus.Store.Settings(),KEY)
  NexusDB=R1
  C.expect(type(st)=='table' and st.writable==false and st.reason=='replaced' and okR==false and resR=='replaced'
   and r1==nil and r2=='unavailable' and r3=='replaced' and session==nil,
   tag..': a distinct valid root in NexusDB is refused as replaced by the policy and the Store owner, with no session setting',
   printable(st and st.reason)..' '..printable(resR)..' '..printable(r3))
  C.expect(F.Serialize(R1)==g1 and F.Serialize(R2)==g2 and #calls==w+1 and State()==state,
   tag..': neither root changes and the owned mutation keeps its state',printable(State()))
 end
 -- The production mutation admission: Store's public export, from READY.
 local begun=Nexus.Store.RegisterCurrentCharacter()
 print('OBSERVED','H begin',printable(type(begun)=='table' and begun.state),
  printable(type(begun)=='table' and (begun.store or begun.reason)),printable(State()))
 C.setup(type(begun)=='table' and begun.state=='pending' and begun.store==BUILD and State()==BUILD,
  'H: fixture: Store.RegisterCurrentCharacter submitted a mutation and the coordinator is in MUTATION_BUILD',
  printable(type(begun)=='table' and (begun.store or begun.reason)))
 if State()~=BUILD then return end
 -- MUTATION_BUILD.
 local stB=Status()
 C.expect(type(stB)=='table' and stB.writable==true and stB.token.db==st0.token.db and stB.token.settings==st0.token.settings,
  'H BUILD: the choice is writable in MUTATION_BUILD, with the READY root and settings identity',stB and printable(stB.reason))
 local off=Option(d,'off');if off then off:Click() end
 local e0,w0=Effects(),#calls
 d.apply:Click()
 local e1=Effects()
 C.expect(Stored()=='off' and P.Mode()=='off' and #calls==w0+1 and calls[#calls]==KEY
  and V.Plain(d.result:GetText()):find('Saved: your Sync mode is now Off',1,true)~=nil,
  'H BUILD: Apply of the draft opened in READY saves Off through the Store owner and reads it back',d.result:GetText())
 C.expect(State()==BUILD and NoEffect(e0,e1,false),
  'H BUILD: Apply leaves the mutation in MUTATION_BUILD and sends, queues, grants and calls nothing',printable(State())..' '..EffText(e1))
 Replaced('H BUILD',BUILD)
 -- One post-ready slice per scheduler turn: the first state after BUILD.
 for _=1,20 do if State()~=BUILD then break end;H.Advance(.05,.05) end
 local mid=coordinator:Result()
 print('OBSERVED','H after one slice',printable(State()),printable(mid and mid.state),printable(mid and (mid.store or mid.result)))
 C.setup(State()==FINAL,'H: fixture: the lifecycle\'s next post-ready slice moved the owned mutation to MUTATION_FINAL',
  printable(State())..' '..printable(mid and mid.result))
 if State()~=FINAL then return end
 -- MUTATION_FINAL.
 local stF=Status()
 C.expect(type(stF)=='table' and stF.writable==true and stF.token.db==st0.token.db and stF.token.settings==st0.token.settings,
  'H FINAL: the choice is writable in MUTATION_FINAL, with the same root and settings identity',stF and printable(stF.reason))
 local e2,w2=Effects(),#calls
 local ok,result,after=Apply('manual',stB.token)
 local e3=Effects()
 C.expect(ok==true and result=='saved' and Stored()=='manual' and P.Mode()=='manual' and #calls==w2+1
  and type(after)=='table' and after.explicit=='manual',
  'H FINAL: the policy route saves Manual and reads it back',printable(result))
 C.expect(State()==FINAL and NoEffect(e2,e3,false),
  'H FINAL: Apply leaves the mutation in MUTATION_FINAL and sends, queues, grants and calls nothing',printable(State())..' '..EffText(e3))
 Replaced('H FINAL',FINAL)
 -- The owned mutation completes on its own turns.
 for _=1,20 do if State()~=FINAL then break end;H.Advance(.05,.05) end
 local final=coordinator:Result()
 print('OBSERVED','H completion',printable(State()),printable(final and final.state),printable(final and final.result),
  printable(final and final.notification))
 C.expect(State()==READY and type(final)=='table' and final.state=='ready' and final.result=='MUTATION_COMMITTED',
  'H: the owned registration mutation then commits (no drift)',printable(final and final.result))
 C.expect(Stored()=='manual' and P.Mode()=='manual' and coordinator:Database()==R1 and NexusDB==R1,
  'H: after the commit the saved choice is Manual, on the root the coordinator holds',printable(Stored()))
 -- The registration row after the commit, each property on its own: the
 -- table is the one held before (Store CommitAccountRowCandidate applies the
 -- candidate onto the existing table), the name is kept, and the realm is the
 -- canonical one the candidate writes.
 local current=type(rawget(R1,'accountCharacters'))=='table' and R1.accountCharacters[F.OWNER] or nil
 print('OBSERVED','H registration row after commit','same table='..printable(row~=nil and current==row),
  'name='..printable(current and current.name),'realm='..printable(current and current.realm),
  'canonical realm='..printable(ownerRealm))
 C.guard(row~=nil and current==row,'H: the commit keeps the registration row table (its identity)',printable(row~=nil and current==row))
 C.guard(current~=nil and current.name==F.NAME and current.name==ownerName,'H: the row keeps the character name',
  printable(current and current.name))
 C.guard(current~=nil and type(ownerRealm)=='string' and current.realm==ownerRealm,
  'H: the row carries Store\'s canonical realm for the current owner (the realm the commit writes)',
  printable(current and current.realm)..' / '..printable(ownerRealm))
 -- Serialized reload: a new runtime initializes the round-tripped root.
 local reloaded=pcall(function() H=F.Reload() end)
 CB,P=Nexus.CommunityBuilds,Nexus.SyncModePolicy
 C.setup(reloaded and Nexus.StartupStatus().coreReady==true,'H: fixture: the profile reloaded from its serialized saved data')
 local st5=Status()
 C.expect(Stored()=='manual' and P.Mode()=='manual' and type(st5)=='table' and st5.explicit=='manual' and st5.writable==true,
  'H: after the reload the choice saved during the mutation persists, and the reloaded root is writable',P.Mode())
 local s=Settings()
 C.guard(NexusDB.settingsVersion==2 and type(s)=='table' and rawget(s,'syncMode')=='manual'
  and type(NexusDB.accountCharacters)=='table' and type(NexusDB.accountCharacters[F.OWNER])=='table'
  and NexusDB.accountCharacters[F.OWNER].name==F.NAME,
  'H: the marker, the dormant syncMode and the registration row survive the round trip')
end)


-- M2 stored choice observation: policy and the real mode-button/dialog are the
-- agreed seams. Fresh read-only boots and healthy-open/root-replacement cases
-- are labelled separately. Every effect window below advances no scheduler time.
local function M2Current(d,tag,state,label)
 local text=V.Plain(d.current:GetText())
 local lower=text:lower()
 C.expect(text:find('Current: Automatic',1,true)~=nil,tag..': effective Automatic is stated',text)
 if state=='recognized' then
  -- Check the saved-choice clause independently: the effective Automatic
  -- prefix must not stand in for a missing saved Automatic label.
  local savedClause=lower:match('saved choice%s+(.+)') or ''
  C.expect(V.Names(savedClause,label) and savedClause:find('not applied',1,true)~=nil
   and not lower:find('no choice saved',1,true),tag..': saved recognized label is present but not applied',text)
 elseif state=='invalid' then
  C.expect(lower:find('invalid',1,true)~=nil and not lower:find('no choice saved',1,true),
   tag..': present invalid data is not claimed absent',text)
 elseif state=='unknown' then
  C.expect((lower:find('unknown',1,true) or lower:find('unavailable',1,true))
   and not lower:find('no choice saved',1,true),tag..': uninspectable choice is unknown, not absent',text)
 else
  C.expect(lower:find('no choice saved',1,true)~=nil,tag..': confirmed absence is stated',text)
 end
 C.guard(d.current:GetWidth()==412 and d.current:GetHeight()==34,tag..': current text keeps its 412x34 box')
 local G=dofile('tests/prototype/layout_geometry_support.lua')
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16}) do
  local rows=G.Rows(text,412,model.char)
  C.expect(rows*model.line<=34,tag..': current text fits '..model.name..' model',rows..' rows')
 end
 local metrics=Nexus.LayoutMetrics
 local _,line=metrics.ConservativeText(1)
 C.expect(metrics.TextRows(text,412,1)*line<=34,tag..': current text fits conservative model')
end

C.scenario('I M2 fresh read-only boots: recognized stored choices remain visible but unapplied',function()
 local labels={automatic='Automatic',manual='Manual',off='Off'}
 for _,class in ipairs({'future','unverified','malformed'}) do
  for _,mode in ipairs({'automatic','manual','off'}) do
   local db=F.Database({version=class=='future' and 9 or 5,mutate=function(root)
    root.settings[KEY]=mode
    if class=='unverified' then root.settings.syncMode='banana'
    elseif class=='malformed' then root.settingsVersion='5' end
   end})
   Boot(db)
   local tag='I fresh '..class..' '..mode
   C.setup(Nexus.MainInternals.SavedFormatClassV1()==class,tag..': real fresh boot reaches expected read-only class')
   local graph=F.Serialize(db)
   local session=Nexus.Store.Settings()
   local sessionGraph=F.Serialize(session)
   local before=Effects()
   local st=Status()
   C.expect(st and st.storedChoiceState=='recognized' and st.storedChoicePresent==true
    and st.storedChoice==mode,tag..': the raw recognized stored choice is observed without honoring it')
   C.guard(st and st.effective=='automatic' and st.explicit==nil and not st.writable
    and P.Mode()=='automatic',tag..': effective policy and write refusal stay unchanged')
   CB.Show()
   local lib=NexusCommunityBuildsFrame
   if lib and lib:IsShown() and lib._modeBtn then
    lib._modeBtn:Click()
    local d=Dialog()
    C.setup(d and d:IsShown(),tag..': real mode button opens the dialog')
    if d and d:IsShown() then M2Current(d,tag,'recognized',labels[mode]);d.cancel:Click() end
   else
    print('OBSERVED',tag,'fresh read-only boot cannot open Library; UI assertions use distinct synthetic replacements below')
   end
   local ok,reason=Apply('off',st and st.token)
   local r1,r2,r3=Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1(KEY,'off')
   C.guard(ok==false and reason=='saved-format' and r1==nil and r2=='unavailable' and r3=='saved-format',
    tag..': both policy and Store owner refuse a write')
   C.guard(F.Serialize(db)==graph and Nexus.Store.Settings()==session and F.Serialize(session)==sessionGraph,
    tag..': saved graph, unknown fields, marker and session remain unchanged')
   C.guard(NoEffect(before,Effects(),false) and #calls==before.writes+1,tag..': observation/refusal sends, admits, grants and invokes no actor')
  end
 end
end)

C.scenario('J M2 real dialog after healthy-open then synthetic root replacement; not a fresh read-only boot',function()
 Boot(F.Database({version=2}))
 local d=Open('J healthy initial')
 if not d then return end
 d.cancel:Click()
 local healthy=NexusDB
 local healthyGraph=F.Serialize(healthy)
 local healthySession=Nexus.Store.Settings()
 local healthySessionGraph=F.Serialize(healthySession)
 local poison={index=0,text=0}
 local function Poison(t)
  return setmetatable(t,{__index=function() poison.index=poison.index+1;return nil end,
   __tostring=function() poison.text=poison.text+1;return 'POISON MUST NOT BE DISPLAYED' end})
 end
 local cases={
  {'recognized Automatic',function(r) r.settings[KEY]='automatic' end,'recognized','automatic','Automatic'},
  {'recognized Manual',function(r) r.settings[KEY]='manual' end,'recognized','manual','Manual'},
  {'recognized Off',function(r) r.settings[KEY]='off' end,'recognized','off','Off'},
  {'absent',function() end,'absent'},
  {'false',function(r) r.settings[KEY]=false end,'invalid'},
  {'true',function(r) r.settings[KEY]=true end,'invalid'},
  {'number',function(r) r.settings[KEY]=17 end,'invalid'},
  {'string',function(r) r.settings[KEY]='unknown-secret-value' end,'invalid'},
  {'table value',function(r) r.settings[KEY]=Poison({private='not-for-display'}) end,'invalid'},
  {'missing settings',function(r) r.settings=nil end,'unknown'},
  {'false settings',function(r) r.settings=false end,'unknown'},
  {'string settings',function(r) r.settings='unknown-secret-value' end,'unknown'},
  {'metatable settings',function(r) r.settings=Poison({[KEY]='manual'}) end,'unknown'},
  {'metatable root',function(r) Poison(r);r.settings[KEY]='manual' end,'unknown'},
 }
 for _,case in ipairs(cases) do
  local replacement=F.Database({version=9})
  case[2](replacement)
  NexusDB=replacement
  local tag='J synthetic '..case[1]
  local graph=F.Serialize(replacement)
  -- Acquire the real read-only session before measuring observation effects.
  local session=Nexus.Store.Settings()
  local sessionGraph=F.Serialize(session)
  local pi,pt=poison.index,poison.text
  local before=Effects()
  local st=Status()
  C.expect(st and st.storedChoiceState==case[3] and st.storedChoice==case[4],
   tag..': safe raw status distinguishes recognized, absent, invalid and unknown')
  C.expect(st and ((case[3]=='unknown' and st.storedChoicePresent==nil)
   or (case[3]=='absent' and st.storedChoicePresent==false)
   or ((case[3]=='invalid' or case[3]=='recognized') and st.storedChoicePresent==true)),
   tag..': presence is three-valued (false only for inspected absence)')
  local lib=NexusCommunityBuildsFrame
  C.setup(lib and lib._modeBtn,tag..': healthy-open Library retains the actual mode button')
  lib._modeBtn:Click()
  d=Dialog()
  C.setup(d and d:IsShown() and d._draft,tag..': mode button reaches the real dialog without advancing time')
  if not (d and d:IsShown() and d._draft) then return end
  M2Current(d,tag,case[3],case[5])
  C.guard(not d.apply:IsEnabled() and V.Plain(d.result:GetText()):find('cannot be changed here',1,true),
   tag..': independent write refusal remains visible')
  local off=Option(d,'off');C.setup(off~=nil,tag..': real Off option exists');off:Click()
  C.guard(P.Mode()=='automatic' and st and st.explicit==nil and not st.writable,
   tag..': selecting a draft does not change effective or explicit policy')
  local ok,why=Apply('off',d._draft.token)
  C.guard(ok==false and why=='saved-format',tag..': attempted Apply is refused')
  d.cancel:Click()
  C.guard(not d:IsShown() and d._draft==nil,tag..': Cancel discards the draft')
  C.expect(poison.index==pi and poison.text==pt,tag..': production observation, token and dialog invoke no __index/__tostring')
  C.guard(F.Serialize(replacement)==graph and F.Serialize(healthy)==healthyGraph
   and Nexus.Store.Settings()==session and F.Serialize(session)==sessionGraph
   and F.Serialize(healthySession)==healthySessionGraph,tag..': both durable roots and both session tables stay unchanged')
  C.guard(NoEffect(before,Effects(),true),tag..': no actor, traffic, admission, grant or Store write')
  C.guard(not d.current:GetText():find('unknown-secret-value',1,true)
   and not d.current:GetText():find('POISON',1,true),tag..': arbitrary data is not rendered')
  -- A second, genuinely enabled draft starts on the healthy bound root.
  -- Replace its root before the real Apply click: the production callback
  -- must refuse stale data (unlike clicking a disabled read-only control).
  NexusDB=healthy
  lib._modeBtn:Click()
  d=Dialog()
  C.setup(d and d:IsShown() and d.apply:IsEnabled(),tag..': healthy bound root creates an enabled draft')
  Option(d,'off'):Click()
  NexusDB=replacement
  local failedBefore=Effects()
  d.apply:Click()
  C.guard(d._draft==nil and not d.apply:IsEnabled()
   and V.Plain(d.result:GetText()):find('changed after this window opened',1,true),
   tag..': actual enabled Apply callback refuses the replaced root as stale')
  C.guard(NoEffect(failedBefore,Effects(),true) and F.Serialize(replacement)==graph
   and F.Serialize(healthy)==healthyGraph and F.Serialize(session)==sessionGraph
   and F.Serialize(healthySession)==healthySessionGraph,
   tag..': failed dialog Apply changes neither root/session nor traffic/actors')
  C.expect(poison.index==pi and poison.text==pt,tag..': failed dialog Apply also invokes no poison method')
  d.cancel:Click()
 end
 NexusDB=healthy
 C.guard(Status().writable==true and Status().token.db==tostring(healthy)
  and Status().token.settings==tostring(healthySession),
  'J restored: normal writable-root identity token remains unchanged')
end)

C.scenario('K M2 accepted false value and unavailable databases are not absent choices',function()
 Boot(F.Database({version=2,mutate=function(db) db.settings[KEY]=false end}))
 local st=Status()
 C.expect(st and st.storedChoiceState=='invalid' and st.storedChoicePresent==true
  and st.storedInvalid==true and st.explicit==nil and st.writable==true,
  'K accepted false: false is present-invalid while normal choice remains writable')
 local d=Open('K accepted false')
 if not d then return end
 -- Establish the Library first: its ordinary lazy UI initialization is not
 -- attributed to the observation/Cancel effect window below.
 local graph=F.Serialize(NexusDB)
 local before=Effects()
 M2Current(d,'K accepted false','invalid')
 d.cancel:Click()
 C.guard(F.Serialize(NexusDB)==graph and NoEffect(before,Effects(),true),
  'K accepted false: description/Cancel writes no settings or session and invokes no actor')
 local healthy=NexusDB
 for _,case in ipairs({{'nil'}, {'false',false}, {'string','not-a-database'}}) do
  NexusDB=case[2]
  local root=NexusDB
  local session=Nexus.Store.Settings()
  local sessionGraph=F.Serialize(session)
  local e0=Effects()
  st=Status()
  C.expect(st and st.storedChoiceState=='unknown' and st.storedChoicePresent==nil
   and st.storedChoice==nil,'K unavailable '..case[1]..': unreadable root has unknown choice')
  C.guard(st and st.explicit==nil and st.effective=='automatic' and not st.writable
   and st.reason=='database','K unavailable '..case[1]..': unchanged database write refusal and effective default')
  NexusCommunityBuildsFrame._modeBtn:Click()
  d=Dialog()
  C.setup(d and d:IsShown() and d._draft,'K unavailable '..case[1]..': healthy-open synthetic root replacement reaches dialog')
  M2Current(d,'K unavailable '..case[1],'unknown')
  local ok,why=Apply('off',d._draft.token)
  d.cancel:Click()
  C.guard(ok==false and why=='database' and NexusDB==root and F.Serialize(session)==sessionGraph
   and NoEffect(e0,Effects(),true),'K unavailable '..case[1]..': refused Apply and Cancel leave root/session/effects unchanged')
 end
 NexusDB=healthy
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(a draft-only choice; Apply alone writes through the Store owner; refusals are visible and leave storage unchanged)')
