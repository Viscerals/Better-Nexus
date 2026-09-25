-- A saved profile this build keeps read-only (future format, unverified
-- format 3-5, malformed marker) is never written, and the choices it records
-- keep their meaning. Real TOC boot, Store, catalog, runtime, editor, panel
-- and commands; synthetic data only; the client option service is the
-- harness stub. Covers AUD-01 (saved OFF permissions stay OFF, no client
-- picker change), AUD-02 (no durable write of any kind; a later legacy row is
-- served next session) and AUD-10 (one settings owner for editor and runtime).
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local PERMISSIONS={'autoPick','autoActivate','autoDisable','autoSave','autoBanish','autoReroll','autoFreeze','autoLockEchoes'}
local function Row(id)return {id=id,title='Synthetic '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
 ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,echoes={{spellId=200001,quality=1,stacks=1}}}end
local function Keys(t)local out={};for k in pairs(t)do out[#out+1]=tostring(k)end;table.sort(out);return table.concat(out,',')end
local function Copy(v)return assert(loadstring('return '..F.Serialize(v)))()end
local PROTECTED={
 {label='future format 6',class='future',saved=6,mutate=function(d)d.settingsVersion=6 end},
 {label='future format 99',class='future',saved=99,mutate=function(d)d.settingsVersion=99 end},
 {label='unverified format 5',class='unverified',saved=5,mutate=function(d)d.settings.syncMode='sometimes' end},
 {label='malformed marker 6.5',class='malformed',mutate=function(d)d.settingsVersion=6.5 end},
 {label='malformed marker "5"',class='malformed',mutate=function(d)d.settingsVersion='5' end},
}
local function Class()return (Nexus.MainInternals.SavedFormatClassV1())end
local function Writer()return Nexus.MainInternals.StoreAuthorityOwner end
-- Client auto-accept starts ON (the player's own choice); every write of it is
-- counted, and every SetSoloPicker call is counted where it is defined.
local function Picker(H)
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
 H.optionWrites=0;local set=ProjectEbonholdOptionsService.SetSetting
 ProjectEbonholdOptionsService.SetSetting=function(self,k,v)
  if k=='autoAcceptLoadoutEchoes' then H.optionWrites=H.optionWrites+1 end
  return set(self,k,v)
 end
 H.soloPickerCalls=0
 F.fileHooks={[ [[core\GameAdapter.lua]] ]=function()
  local original=Nexus.GameAdapter.SetSoloPicker
  Nexus.GameAdapter.SetSoloPicker=function(...)H.soloPickerCalls=H.soloPickerCalls+1;return original(...)end
 end}
end
local function Boot(db,before)
 local H=F.Boot(db,function(h)Picker(h);if before then before(h)end end);F.fileHooks=nil
 return H
end
local function ClientAutoAccept()return ProjectEbonholdOptionsService:GetSetting('autoAcceptLoadoutEchoes')end
-- Replies reach the player through chat or print; both are recorded.
local said,realPrint={},print
print=function(...)local parts={};for i=1,select('#',...)do parts[i]=tostring((select(i,...)))end;said[#said+1]=table.concat(parts,' ')end
local function Mark(H)return {chat=#H.chat,said=#said}end
local function SaidSince(H,mark,text)
 for i=mark.chat+1,#H.chat do if H.chat[i]:find(text,1,true)then return true end end
 for i=mark.said+1,#said do if said[i]:find(text,1,true)then return true end end
 return false
end

-- 1. AUD-01: the settings a read-only session runs with. Saved false stays
-- false, saved true stays true, missing and non-boolean permissions are false,
-- a shipped default never turns one on, and unknown saved fields are not run.
for _,case in ipairs(PROTECTED)do
 local variants={
  {'saved false',function(s)for _,k in ipairs(PERMISSIONS)do s[k]=false end end,false},
  {'saved true',function(s)for _,k in ipairs(PERMISSIONS)do s[k]=true end end,true},
  {'missing',function(s)for _,k in ipairs(PERMISSIONS)do s[k]=nil end end,false},
  {'non-boolean',function(s)local bad={'yes',1,{},0/0,'false','true',0,'on'};for i,k in ipairs(PERMISSIONS)do s[k]=bad[i] end end,false},
 }
 for _,variant in ipairs(variants)do
  local db=F.Database({mutate=function(d)variant[2](d.settings);d.settings.updateNotifications=false
   d.settings.anchorNames={};case.mutate(d)end})
  local savedSettings=F.Serialize(db.settings)
  local H=Boot(db)
  local label=case.label..', '..variant[1]
  check(Class()==case.class,label..': classification unchanged ('..tostring(Class())..')')
  local S=Nexus.Store.Settings()
  check(S~=NexusDB.settings,label..': the session settings are not the saved table')
  for _,k in ipairs(PERMISSIONS)do
   check(S[k]==variant[3],label..': effective '..k..'='..tostring(S[k])..' (expected '..tostring(variant[3])..')')
  end
  check(S.updateNotifications==false and type(S.anchorNames)=='table' and #S.anchorNames==0,label..': other saved choices keep their value')
  check(S.customGenSetting==nil and S.syncMode==nil,label..': unknown saved fields are not copied into executable settings')
  check(Nexus.Store.Settings()==S and Nexus.Store.Settings()==S,label..': repeated reads return the same table')
  check(F.Serialize(NexusDB.settings)==savedSettings,label..': saved settings unchanged')
  check(ClientAutoAccept()==true and H.optionWrites==0 and H.soloPickerCalls==0,label..': start-up leaves the client picker option alone')
 end
end
-- A settings table that is absent or not a plain table grants nothing.
for _,bad in ipairs({{'absent',nil},{'a string','settings'}})do
 local db=F.Database({version=6});db.settings=bad[2]
 local H=Boot(db)
 local S=Nexus.Store.Settings()
 for _,k in ipairs(PERMISSIONS)do check(S[k]==false,'settings '..bad[1]..': effective '..k..' is false')end
 check(rawget(NexusDB,'settings')==bad[2],'settings '..bad[1]..': left as saved')
end
-- A lever opt-out list that cannot be read keeps lever automation off.
do
 local db=F.Database({version=6,mutate=function(d)d.settings.autoActivate=true;d.settings.autoDisable=true
  d.settings.leverOptOut='broken'end})
 Boot(db)
 local S=Nexus.Store.Settings()
 check(S.autoActivate==false and S.autoDisable==false,'unreadable lever opt-outs: lever automation stays off')
 local db2=F.Database({version=6,mutate=function(d)d.settings.autoActivate=true;d.settings.leverOptOut={[7]=true,[9]=1}end})
 Boot(db2)
 S=Nexus.Store.Settings()
 check(S.autoActivate==true and S.leverOptOut[7]==true and S.leverOptOut[9]==true,'readable lever opt-outs are kept and honored')
end

-- 2. The runtime path: the session master switch ON does not authorize an
-- action the saved profile turned OFF. Real automation step and board.
local function AutoRun(mutate)
 local db=F.Database({mutate=mutate})
 local H=Boot(db,function(h)h.pendingRolls=2 end)
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false)
 local A=Nexus.GameAdapter
 check(A.SetFirstLoadoutWishlistIdentity('EchoWeaver planned',{{spellId=200001,quality=1,stacks=2}}),'fixture: first run plan')
 H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(.5)
 SlashCmdList.NEXUS('auto');H.Advance(3)
 local kinds={}
 for _,a in ipairs(H.actions)do kinds[a[1]]=(kinds[a[1]]or 0)+1 end
 return kinds,H
end
do
 local on={'autoPick','autoBanish','autoReroll','autoFreeze'}
 local kinds=AutoRun(function(d)d.settingsVersion=6;for _,k in ipairs(on)do d.settings[k]=true end end)
 check(Nexus.RecomputeStats().autoEnabled==true and (kinds.freeze or 0)==1,'control: saved true Freeze is used with the master ON')
 kinds=AutoRun(function(d)d.settingsVersion=6;for _,k in ipairs(on)do d.settings[k]=true end;d.settings.autoFreeze=false end)
 check(Nexus.RecomputeStats().autoEnabled==true and Nexus.Store.Settings().autoFreeze==false,'master ON, saved Freeze OFF')
 check(kinds.freeze==nil,'saved Freeze OFF: no Freeze is sent with the master ON')
 kinds=AutoRun(function(d)d.settings.syncMode='sometimes';for _,k in ipairs(on)do d.settings[k]=true end;d.settings.autoFreeze='yes'end)
 check(kinds.freeze==nil,'unverified format, non-boolean Freeze: no Freeze is sent')
 kinds=AutoRun(function(d)d.settingsVersion=6.5;for _,k in ipairs(PERMISSIONS)do d.settings[k]=nil end end)
 check(Nexus.RecomputeStats().autoEnabled==true and next(kinds)==nil,'malformed marker, no saved permissions: the master ON sends nothing')
 kinds=AutoRun(function(d)d.settingsVersion=6;for _,k in ipairs(on)do d.settings[k]=true end;d.settings.autoPick=false end)
 check(next(kinds)==nil,'saved autoPick OFF: the master ON sends nothing')
end

-- 3. The client picker option (AUD-01): never changed for a read-only
-- profile, also after another world entry; the supported path is unchanged.
for _,case in ipairs(PROTECTED)do
 for _,pick in ipairs({true,false})do
  local db=F.Database({mutate=function(d)d.settings.autoPick=pick;case.mutate(d)end})
  local H=Boot(db)
  H.Fire('PLAYER_ENTERING_WORLD');H.Advance(10,.5)
  local label=case.label..', saved autoPick '..tostring(pick)
  check(ClientAutoAccept()==true,label..': client auto-accept still ON')
  check(H.optionWrites==0 and H.soloPickerCalls==0,label..': SetSoloPicker never called ('..H.soloPickerCalls..')')
  check(Nexus.Store.State().priorAutoAccept==nil,label..': no remembered prior value is claimed')
 end
end
for _,control in ipairs({{'known format 5',nil},{'supported format 2',2}})do
 local db=F.Database({mutate=function(d)d.settings.autoPick=true;if control[2] then d.settingsVersion=control[2] end end})
 local H=Boot(db)
 check(Class()~='future' and ClientAutoAccept()==false and H.soloPickerCalls>=1,control[1]..': autoPick still takes over the picker')
 check(NexusDB.chars[F.OWNER] and NexusDB.chars[F.OWNER].priorAutoAccept==true,control[1]..': the prior value is saved for restoring')
end

-- 4. AUD-10: the editor's AutoLock switch and the runtime read one owner.
local function Label(H,text)
 for _,frame in ipairs(H.frames)do
  for _,region in ipairs(frame.regions or {})do
   if region.text==text then return region end
  end
 end
end
local function AutoLockBox(H)
 Nexus.WishlistEditor.Show()
 local label=Label(H,'Auto-manage locked Echo slots')
 return label and label.points[1][2]
end
for _,case in ipairs(PROTECTED)do
 local db=F.Database({mutate=function(d)d.settings.autoLockEchoes=false;case.mutate(d)end})
 local H=Boot(db)
 local box=assert(AutoLockBox(H),case.label..': the editor AutoLock switch exists')
 local chat=Mark(H)
 box:SetChecked(true);box:Click();Nexus.WishlistEditor.Refresh()
 local S=Nexus.Store.Settings()
 check(NexusDB.settings.autoLockEchoes==false,case.label..': the saved AutoLock value is unchanged')
 check(S.autoLockEchoes==true and box:GetChecked()==true,case.label..': editor and runtime settings agree (on)')
 check(SaidSince(H,chat,'for this session only'),case.label..': the switch says the change is for this session only')
 box:SetChecked(false);box:Click();Nexus.WishlistEditor.Refresh()
 check(S.autoLockEchoes==false and box:GetChecked()==false and NexusDB.settings.autoLockEchoes==false,case.label..': and off again, saved unchanged')
 local result=Writer().UpdateSettingsV1('autoLockEchoes','yes')
 check(result==nil and S.autoLockEchoes==false,case.label..': a non-boolean value is refused')
end
for _,version in ipairs({3,4,5,2})do
 local db=F.Database({version=version,mutate=function(d)d.settings.autoLockEchoes=false
  if version==3 then d.accountCharacters=nil end end})
 local H=Boot(db)
 local box=assert(AutoLockBox(H))
 local chat=Mark(H)
 box:SetChecked(true);box:Click();Nexus.WishlistEditor.Refresh()
 check(Nexus.Store.Settings()==NexusDB.settings and NexusDB.settings.autoLockEchoes==true and box:GetChecked()==true,
  'format '..version..': the editor switch is saved and seen by the runtime')
 check(not SaidSince(H,chat,'for this session only'),'format '..version..': no session-only notice')
 check(Writer().UpdateSettingsV1('autoReroll',false).mode=='durable' and NexusDB.settings.autoReroll==false,'format '..version..': settings writes stay durable')
end

-- 5. Session-only edits belong to the loaded saved data. Another saved root
-- never inherits them, and a profile change or reload rebuilds the session
-- settings from the saved values.
do
 local db=F.Database({version=6,mutate=function(d)d.settings.autoReroll=false end})
 local H=Boot(db)
 local chat=Mark(H)
 SlashCmdList.NEXUS('reroll on');SlashCmdList.NEXUS('anchor 200002')
 local S=Nexus.Store.Settings()
 check(S.autoReroll==true and S.anchorSpellId==200002,'session edit applies to the running session')
 check(SaidSince(H,chat,'This session only') and SaidSince(H,chat,'for this session only'),'the commands say the change is not saved')
 check(NexusDB.settings.autoReroll==false and NexusDB.settings.anchorSpellId==nil,'session edit is not saved')
 local first=NexusDB
 local other=F.Database({version=7,mutate=function(d)d.settings.autoReroll=true;d.settings.autoFreeze=false end})
 NexusDB=other
 local O=Nexus.Store.Settings()
 check(O~=S and O.autoReroll==true and O.autoFreeze==false and O.anchorSpellId==nil,'another saved root gets its own settings')
 NexusDB=first
 local B=Nexus.Store.Settings()
 check(B~=S and B~=O and B.autoReroll==false and B.anchorSpellId==nil,'a profile change drops session edits: rebuilt from the saved values')
 check(Nexus.Store.Settings()==B,'and the rebuilt settings are stable again')
 F.Reload()
 check(Nexus.Store.Settings().autoReroll==false and Nexus.Store.Settings().anchorSpellId==nil,'after a reload the saved values apply again')
end

-- 6. AUD-02: the whole saved root is unchanged through start-up, 120 seconds,
-- UI controls, commands, an automation run, another world entry, logout and a
-- reload. Every key, value and nested table is compared, not a version number.
local function Lifecycle(H)
 for _=1,240 do H.Advance(.5,.5) end
 Nexus.Panel.Toggle()
 if _G.NexusPanel and NexusPanel.scripts.OnDragStop then NexusPanel.scripts.OnDragStop(NexusPanel) end
 local mini=_G.NexusMinimapButton
 if mini and mini.scripts.OnDragStart then mini.scripts.OnDragStart(mini);H.Advance(.2);mini.scripts.OnDragStop(mini) end
 Nexus.ServerStatus.SetMode('server')
 Nexus.WishlistOverlay.Show();Nexus.WishlistOverlay.ToggleLock();Nexus.WishlistOverlay.SetScale(1.2)
 Nexus.WishlistOverlay.ResetPosition();Nexus.WishlistOverlay.Hide()
 local box=AutoLockBox(H);if box then box:SetChecked(true);box:Click() end
 if _G.NexusEditorSearch then NexusEditorSearch:SetText('Echo 1') end
 local classOnly=Label(H,'Current class only')
 if classOnly then classOnly.parent:SetChecked(false);classOnly.parent:Click() end
 if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Show then Nexus.CommunityBuilds.Show() end
 SlashCmdList.NEXUS('reroll on');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('anchor 200001')
 SlashCmdList.NEXUS('logclear')
 Nexus.Errors.Record('readonly-test','synthetic error')
 Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('EchoWeaver planned',{{spellId=200001,quality=1,stacks=2}})
 H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();SlashCmdList.NEXUS('auto');H.Advance(5)
 SlashCmdList.NEXUS('auto');H.Advance(1)
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20,.5)
 H.Fire('PLAYER_LOGOUT')
end
local function Preserved(label,db,expectCatalog)
 local before=F.Serialize(db);local keys=Keys(db)
 local H=Boot(db)
 check(Nexus.MainInternals.SavedRootReadOnlyV1()~=nil,label..': the saved root is read-only ('..tostring(Class())..')')
 check(Nexus.StartupStatus().state=='ready',label..': start-up completes ('..tostring(Nexus.StartupStatus().state)..')')
 if expectCatalog then
  check(Nexus.BuildCatalog.Get(expectCatalog)~=nil,label..': the saved Community row is served read-only')
  check(Nexus.BuildCatalog.Status().readOnly==true,label..': the catalog reports itself read-only')
 end
 Lifecycle(H)
 check(NexusDB==db,label..': the saved root is still the loaded table')
 check(Keys(db)==keys,label..': no top-level key added or removed ('..Keys(db)..')')
 check(F.Serialize(db)==before,label..': the whole saved root is unchanged after the session')
 F.Reload()
 check(Nexus.StartupStatus().state=='ready' and Class()~=nil,label..': reload starts again')
 for _=1,120 do H.Advance(.5,.5) end
 check(F.Serialize(NexusDB)==before,label..': still unchanged after a reload')
 return H
end
for _,case in ipairs(PROTECTED)do
 -- lockDesignTargets is the retired flat lock-target key that the editor and
 -- the runtime move into the character row and then remove.
 local db=F.Database({mutate=function(d)d.communityBuilds={['syn-1']=Row('syn-1')}
  d.lockDesignTargets={[200002]=true};case.mutate(d)end})
 Preserved(case.label..' (legacy rows only)',db,'syn-1')
end

-- Owners' own saved keys still show their saved values in a read-only
-- session (a false value included), and a session change stays in the session.
do
 local db=F.Database({version=6,mutate=function(d)d.overlayLocked=false;d.panelX=12;d.panelY=-7
  d.uiShowPerformance=false;d.soulAshHudMode='server';d.buildFilters={page=3,big={1,2}}end})
 local before=F.Serialize(db)
 Boot(db)
 check(Nexus.WishlistOverlay.IsLocked()==false,'read-only session: a saved false overlay lock is shown as saved')
 check(Nexus.ServerStatus.IsUsingNexusHud()==false,'read-only session: the saved HUD mode is shown as saved')
 local layout=Nexus.Panel.SavedLayoutRoot()
 check(layout~=NexusDB and layout.panelX==12 and layout.panelY==-7 and layout.uiShowPerformance==false,'read-only session: the saved panel layout is read')
 Nexus.WishlistOverlay.ToggleLock();Nexus.ServerStatus.SetMode('nexus')
 check(Nexus.WishlistOverlay.IsLocked()==true and Nexus.ServerStatus.IsUsingNexusHud()==true,'read-only session: a change applies to the session')
 check(F.Serialize(NexusDB)==before,'read-only session: and the saved keys are unchanged')
end

-- 7. A later legacy row is served next session. Session 1 writes no bundle;
-- the other addon then adds a row at the legacy location; session 2 serves
-- it, and the saved root is still exactly the input of each session.
for _,case in ipairs(PROTECTED)do
 local db=F.Database({mutate=function(d)d.communityBuilds={['syn-1']=Row('syn-1')};case.mutate(d)end})
 local H=Boot(db);for _=1,120 do H.Advance(.5,.5) end
 check(rawget(NexusDB,'authorityBundle')==nil,case.label..': session 1 writes no authority bundle')
 check(Nexus.BuildCatalog.Get('syn-1')~=nil,case.label..': session 1 serves the saved row')
 local saved=Copy(NexusDB);saved.communityBuilds['syn-2']=Row('syn-2')
 local input=F.Serialize(saved)
 H=Boot(saved);for _=1,120 do H.Advance(.5,.5) end
 check(Nexus.BuildCatalog.Get('syn-1')~=nil and Nexus.BuildCatalog.Get('syn-2')~=nil,case.label..': session 2 serves the later legacy row')
 check(F.Serialize(NexusDB)==input,case.label..': session 2 leaves its input unchanged')
end

-- 8. A read-only profile that already carries an authority bundle keeps it
-- byte for byte, is served from it, and refuses every catalog write.
do
 local supported=F.Database({version=2,mutate=function(d)d.communityBuilds={['syn-1']=Row('syn-1')}end})
 local H=Boot(supported);for _=1,120 do H.Advance(.5,.5) end
 check(type(rawget(NexusDB,'authorityBundle'))=='table','fixture: a supported session wrote its bundle')
 for _,case in ipairs(PROTECTED)do
  local db=Copy(NexusDB);db.settingsVersion=5;case.mutate(db)
  local bundle=F.Serialize(db.authorityBundle)
  H=Preserved(case.label..' (existing bundle)',db,'syn-1')
  check(F.Serialize(NexusDB.authorityBundle)==bundle,case.label..': the existing bundle is byte-identical')
  local ok,why=Nexus.BuildCatalog.Put(Row('syn-3'),{source='overlay'})
  check(ok~=true and why=='SAVED_FORMAT_READ_ONLY',case.label..': a catalog write is refused as read-only ('..tostring(why)..')')
  check(Nexus.BuildCatalog.Get('syn-3')==nil and F.Serialize(NexusDB.authorityBundle)==bundle,case.label..': nothing was written')
 end
end

-- 9. Supported and verified profiles are unchanged: durable settings, their
-- own bundle, and a writable catalog.
for _,version in ipairs({2,3,4,5})do
 local db=F.Database({version=version,mutate=function(d)d.communityBuilds={['syn-1']=Row('syn-1')}
  if version==3 then d.accountCharacters=nil end end})
 local H=Boot(db);for _=1,120 do H.Advance(.5,.5) end
 local label='format '..version
 check(Class()=='supported' or Class()=='known',label..': accepted')
 check(Nexus.Store.Settings()==NexusDB.settings and Nexus.MainInternals.SavedRootReadOnlyV1()==nil,label..': settings are the saved table')
 check(type(rawget(NexusDB,'authorityBundle'))=='table' and Nexus.BuildCatalog.Status().readOnly==false,label..': catalog writes its bundle')
 check(Nexus.BuildCatalog.Get('syn-1')~=nil and Nexus.StartupStatus().state=='ready',label..': served and ready')
 check(Nexus.MainInternals.WritableRootV1()==NexusDB,label..': owners write the saved root itself')
end
realPrint('PASS readonly_profile_preservation: read-only saved profiles keep saved choices (false stays false, invalid grants nothing), leave the client picker alone, share one settings owner with the editor, and are never written (whole root, existing bundle, reload); later legacy rows are served; supported formats unchanged checks='..checks)
