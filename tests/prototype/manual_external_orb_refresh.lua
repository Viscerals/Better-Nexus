-- Manual Echo ownership changes made outside Nexus (an Orb used in the game's
-- own window, a permanent lock in the character progression UI, a Saved Build
-- save of the current run) and the HUD's STILL NEEDED and LOCKED TARGETS rows,
-- through an in-session loading screen and a true fresh reload.
--
-- Categories (tests/prototype/view_regression_support.lua): SETUP is the
-- fixture or an attribution fact (a SETUP failure is not red evidence);
-- EXPECT is the healthy contract this diagnosis asserts (the assignment's
-- ASSERT class); GUARD is a control read from source as holding on both
-- baselines, which must keep holding. Whether an EXPECT holds is decided by
-- the run; outputs/CAUSE.md gives the source reading behind every check.
--
-- Real TOC boot through format5_support/progress_refresh_support: the real
-- GameAdapter (hooks, Poll, reconciliation, getters), AutomationRuntime
-- (ConsumeDirty, projection cache, fallback, Step), Main (panel progress cache,
-- view model) and Panel. The host is the synthetic harness. A manual game
-- action is modelled only at the host boundary: the native call the game's own
-- UI makes (recorded by the harness as the player's call) and the server reply
-- as a replaced client mirror. Callbacks are only those the source subscribes
-- to (EchoJournal.OnDataChanged, PerkUI.Show, the hooked PerkService.SelectPerk,
-- PLAYER_LEAVING_WORLD/PLAYER_ENTERING_WORLD). "Silent" means no callback at
-- all: whether the client calls OnDataChanged after these replies is not
-- known, so every control that sends one says so. The only forced recompute is
-- a labelled QUALIFIED CONTROL after the normal path was observed. Level 80,
-- Auto OFF, Sync manual, an OrbService present; synthetic Echo ids only.
local S=dofile('tests/prototype/progress_refresh_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local F=S.F
local C=V.Checker('manual_external_orb_refresh')

local TOME=777019
local function E(i) return 200000+i end
local function Range(a,b) local t={} for i=a,b do t[#t+1]=i end return t end
local EXTRAS=Range(51,60) -- rolled copies that are not on the Wishlist (Orb sources)

-- {[spellId]=copies}: one copy of every listed Echo index.
local function Counts(...)
 local c={}
 for _,list in ipairs({...}) do
  for _,i in ipairs(list) do c[E(i)]=(c[E(i)] or 0)+1 end
 end
 return c
end
local function Rows(ids)
 local spec={}
 for _,i in ipairs(ids) do spec[#spec+1]={E(i),1,false} end
 return S.Rows(spec)
end
-- Wishlist W: Echo 11-19, one ordinary copy each; Echo 19 needs a tome.
local W=Rows(Range(11,19))

-- o: counts (granted), saved (Saved Build 2 contents), rows (Wishlist),
-- locked (locked mirror), discovered (Echo 19's tome), hold (granted reply
-- outstanding: the mirror is empty and RequestGrantedPerks answers nothing).
local function World(o)
 return {[2]={name='Build Two',verified=true,echoes=S.SlotRows(o.saved or o.counts)},
  [101]={name='Synthetic W',verified=false,echoes=S.Copy(o.rows or W)}}
end
local function Extras(o)
 return function(h)
  h.db[E(19)].requiredSpell=TOME
  h.names[TOME]='Tome of Echo 19'
  h.perks.discoveredEchoes=h.discovered
  if o.discovered then h.discovered[E(19)]=true end
  F.OrbService(h)
  if o.hold then h.holdGrantedResponse=true end
 end
end
local function Boot(o)
 return S.Boot({granted=o.hold and {} or o.counts,locked=o.locked or {},active=2,slots=World(o),
  associations={[2]=S.Association(101,'Synthetic W',o.rows or W)},before=Extras(o)})
end
-- A true fresh runtime: new harness and Lua globals, the saved table
-- round-tripped as literal data, the client mirrors as the game shows them.
local function Reload(o)
 local H=F.Reload(function(h)
  h.playerLevel=80
  h.granted=S.Granted(o.hold and {} or o.counts)
  h.locked=S.Copy(o.locked or {})
  h.perks.serverBuildSlots=World(o)
  h.perks.serverActiveSlot=2
  Extras(o)(h)
 end)
 C.setup(Nexus.StartupStatus().coreReady==true,'fresh runtime: start-up completed after the reload')
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 H.Advance(3)
 return H
end

-- What the panel committed (Panel.Render keeps the model it applied).
local function Progress()
 local m=Nexus.Panel and Nexus.Panel._lastModel
 return type(m)=='table' and type(m.progress)=='table' and m.progress or {}
end
-- Labels ("Echo 14 (Rare)") as sorted Echo indices; -1 marks a label not read.
local function Ids(list)
 local out={}
 for _,label in ipairs(type(list)=='table' and list or {}) do
  out[#out+1]=tonumber(tostring(label):match('^Echo (%d+)')) or -1
 end
 table.sort(out)
 return out
end
local function Needed() return Ids(Progress().missing) end
local function ToLock() return Ids(Progress().toLock) end
local function Same(a,b)
 if #a~=#b then return false end
 for i=1,#a do if a[i]~=b[i] then return false end end
 return true
end
local function Show(a) local t={} for i,v in ipairs(a) do t[i]=tostring(v) end return '{'..table.concat(t,',')..'}' end
-- The STILL NEEDED font string: created third after its label (ui/Panel.lua).
-- Its face is one line per row (the column's own FontString, then its
-- _nexusRows after native acceptance of test.163009); the rows that hold a
-- line, in order, are read back as the lines of one text.
local function Rendered()
 local f=_G.NexusPanel
 local regions=type(f)=='table' and f.regions or {}
 for i,r in ipairs(regions) do
  if r.text=='STILL NEEDED' then
   local column=regions[i+3]
   if not column then return nil end
   local lines={}
   for _,row in ipairs(column._nexusRows or {column}) do
    if (row.text or '')~='' then lines[#lines+1]=row.text end
   end
   return table.concat(lines,'\n')
  end
 end
end
local function NeedText(ids)
 if #ids==0 then return '|cff888888No remaining demand|r' end
 local lines={}
 for i=1,math.min(2,#ids) do lines[i]='Echo '..ids[i] end
 if #ids>2 then lines[#lines+1]='+'..(#ids-2)..' more' end
 return table.concat(lines,'\n')
end

local function Stats()
 local r=Nexus.RecomputeStats() or {}
 local e=Nexus.GameAdapter.EchoReconcileStats()
 local m=r.fallbackMismatchFields or {}
 local g=e.generations or {}
 local c=r.lastStepContext or {}
 return {steps=r.fullSteps or 0,repairs=r.fallbackRepairs or 0,checks=r.fallbackChecks or 0,
  grantedMismatch=m.granted or 0,lockedMismatch=m.locked or 0,lastFallback=tostring(r.lastFallbackReason),
  trigger=tostring(c.trigger),staticProbe=c.staticProbe==true,
  notes=e.notifications or 0,equivalent=e.equivalentNotifications or 0,
  granted=g.granted or 0,locked=g.locked or 0,slots=g.slots or 0,discovery=g.discovery or 0}
end
local function OwnedRevision() local _,_,_,r=Nexus.GameAdapter.PresentationRevisions();return r end
-- Main.BuildPanelProgress keys its cache only when this answers an epoch.
local function PanelCacheEligible()
 local cb=Nexus.CommunityBuilds
 if not (cb and cb.GetSelectedBuildForPanelKey) then return false end
 local ok,_,epoch=pcall(cb.GetSelectedBuildForPanelKey)
 return ok and type(epoch)=='number'
end
-- Nexus's own getters, read now (no request; a confirmed generation is unchanged).
local function GetterOwns(i,n)
 local o=Nexus.GameAdapter.Owned()
 return o.synced==true and (o.bySpell[E(i)] or 0)==n
end
local function GetterLocks(i,n)
 local l=Nexus.GameAdapter.LockedOwned()
 return l.synced==true and (l.bySpell[E(i)] or 0)==n
end
-- Sample ages are the time of the last normal read, not a fresh server answer.
local function Diag(label)
 local s,p=Stats(),Progress()
 local v=Nexus.GameAdapter.OwnershipTrustView() or {}
 print('DIAG '..label..': needed='..Show(Needed())..' owned='..tostring(p.owned)..'/'..tostring(p.total)
  ..' toLock='..Show(ToLock())..' locked='..tostring(p.lockedOwned)..'/'..tostring(p.lockedTotal)
  ..' rendered='..string.format('%q',tostring(Rendered()))
  ..' | generations granted='..s.granted..' locked='..s.locked..' slots='..s.slots
  ..' | callbacks='..s.notes..' equivalent='..s.equivalent..' steps='..s.steps..' lastStep='..s.trigger
  ..(s.staticProbe and '+static' or '')..' fallbackChecks='..s.checks..' repairs='..s.repairs..' last='..s.lastFallback
  ..' | sample ownedAge='..tostring(v.ownedAge)..' ownedSynced='..tostring(v.ownedSynced)
  ..' lockedAge='..tostring(v.lockedAge)..' lockedSynced='..tostring(v.lockedSynced)
  ..' | panelProgressCacheEligible='..tostring(PanelCacheEligible()))
end

-- Continue until a fallback check (or a static rebuild) has just reconciled,
-- so the next one is about five seconds away.
local function AfterFallbackCheck(H)
 local at=Nexus.RecomputeStats().lastFallbackCheckAt
 for _=1,160 do
  H.Advance(.05,.05)
  if Nexus.RecomputeStats().lastFallbackCheckAt~=at then return true end
 end
 return false
end
local function FirstStep(H,limit)
 local n,start=Stats().steps,H.now
 while H.now-start<limit-1e-9 do
  H.Advance(.05,.05)
  if Stats().steps>n then return H.now-start end
 end
 return nil
end
-- An in-session loading screen, through the frames Main registered.
local function Leave(H) H.Fire('PLAYER_LEAVING_WORLD');H.Advance(.5,.05) end
local function Enter(H) H.Fire('PLAYER_ENTERING_WORLD') end

-- The synthetic player's native calls, and the no-Nexus-action guard.
local function Player(H)
 local p={actions=#H.actions,sent=#H.sent,own=0}
 function p.native(label,writes,fn)
  local before=#H.actions
  local ok,err=pcall(fn)
  C.setup(ok and #H.actions-before==writes,'the player\'s native '..label..' reached the host',ok and (#H.actions-before) or err)
  p.own=p.own+writes
 end
 function p.quiet(label)
  local kinds={}
  for i=p.actions+1,#H.actions do kinds[#kinds+1]=tostring(H.actions[i][1]) end
  C.guard(#H.actions-p.actions==p.own,label..': Nexus made no host write of its own (Select, Banish, Freeze, Reroll, lock, unlock, tome toggle, Saved Build save/upload/activate, Orb spend); host writes are the player\'s '..p.own,table.concat(kinds,','))
  C.guard(#H.sent==p.sent,label..': Nexus sent no chat or addon message',#H.sent-p.sent)
 end
 return p
end

-- Before world entry: nothing reconciled or confirmed the change yet.
local function PreEntry(label,s0,r0,field)
 local s=Stats()
 C.setup(s[field]==s0[field] and OwnedRevision()==r0,label..': no reconciliation or confirmation ran between the manual change and world entry',
  field..' '..s0[field]..'->'..s[field]..', owned revision '..tostring(r0)..'->'..tostring(OwnedRevision()))
end
-- After world entry. o: field, s0, r0, getter, pred, want, text.
local function Hazard(H,label,o)
 C.setup(OwnedRevision()==o.r0,label..': world-entry handling itself confirmed no ownership before its step',tostring(o.r0)..'->'..tostring(OwnedRevision()))
 local dt=FirstStep(H,1)
 C.setup(dt~=nil,label..': a full step ran after world entry',dt)
 local s1=Stats()
 C.setup(s1.staticProbe and s1[o.field]==o.s0[o.field]+1 and s1.notes==o.s0.notes,
  label..': that step rebuilt the static context, whose reconciliation took the '..o.field..' change (generation +1, no client callback)',
  s1.trigger..(s1.staticProbe and '+static ' or ' ')..o.field..' '..o.s0[o.field]..'->'..s1[o.field]..', callbacks '..o.s0.notes..'->'..s1.notes)
 C.setup(o.getter(),label..': Nexus\'s own getter reads the new state')
 Diag(label..', first step after entry')
 C.expect(o.pred(),label..': the first full step after world entry renders what the getter reads ('..o.want..')',
  'needed '..Show(Needed())..' toLock '..Show(ToLock()))
 if o.text then C.expect(Rendered()==o.text,label..': the panel\'s STILL NEEDED text after that step',Rendered()) end
 local t=S.Within(H,6.5,o.pred)
 C.expect(t~=nil,label..': shown within the five-second fallback period after world entry',t)
 H.Advance(5)
 C.expect(o.pred(),label..': shown after a further fallback period','needed '..Show(Needed())..' toLock '..Show(ToLock()))
 Diag(label..', two fallback periods later')
 Nexus.RequestRecompute()
 local tf=S.Within(H,.6,o.pred)
 C.guard(tf~=nil,label..': QUALIFIED CONTROL (forced recompute, not a normal refresh): the same mirrors render correctly once the plan is recompiled',tf)
 if o.text then C.guard(Rendered()==o.text,label..': QUALIFIED CONTROL: panel text after the forced recompute',Rendered()) end
end

C.scenario('callback controls, tome, Saved Build save versus grant, true reload',function()
 local owned={11,12,13}
 local H=Boot({counts=Counts(owned,EXTRAS)})
 local p0=Progress()
 C.setup(p0.wishlistName=='Synthetic W' and p0.owned==3 and p0.total==9,'fixture: the assigned Wishlist reads 3/9',S.Text(S.Hud()))
 C.setup(Same(Needed(),Range(14,19)),'fixture: STILL NEEDED lists Echo 14-19',Show(Needed()))
 C.setup(Rendered()==NeedText(Range(14,19)),'fixture: the panel text shows that model',Rendered())
 C.setup(type(p0.unknownTomes)=='table' and #p0.unknownTomes==1,'fixture: Echo 19\'s undiscovered tome is a separate MISSING TOMES entry',type(p0.unknownTomes)=='table' and #p0.unknownTomes)
 C.setup(Nexus.GameAdapter.Owned().synced==true,'fixture: rolled ownership is synchronized')
 Diag('controls, boot')
 local p=Player(H)

 -- A client callback that carries no change.
 local s0=Stats()
 H.Notify();H.Advance(.5)
 C.guard(Same(Needed(),Range(14,19)) and Stats().granted==s0.granted and Stats().equivalent>s0.equivalent,
  'callback without a change: an equivalent reconciliation, STILL NEEDED unchanged',Show(Needed()))

 -- Positive control: a manual Orb result followed by the Echo-data callback.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0=Stats();owned={11,12,13,14}
 H.granted=S.Granted(Counts(owned,EXTRAS));H.Notify()
 local t=S.Within(H,.5,function() return Same(Needed(),Range(15,19)) end)
 C.guard(t~=nil,'notified manual change: STILL NEEDED drops Echo 14 within one poll',Show(Needed()))
 C.guard(Stats().granted==s0.granted+1 and Stats().repairs==s0.repairs,'notified manual change: reconciled by the callback, not by the fallback',
  'granted '..s0.granted..'->'..Stats().granted..', repairs '..s0.repairs..'->'..Stats().repairs)
 C.guard(Rendered()==NeedText(Range(15,19)),'notified manual change: the panel text follows',Rendered())

 -- Delayed callback: the reply is silent for one second, then the callback comes.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 owned={11,12,13,14,15}
 H.granted=S.Granted(Counts(owned,EXTRAS))
 H.Advance(1)
 Diag('delayed callback, one second before it arrives')
 H.Notify()
 t=S.Within(H,.5,function() return Same(Needed(),Range(16,19)) end)
 C.guard(t~=nil,'delayed callback: STILL NEEDED drops Echo 15 within one poll of the callback',Show(Needed()))

 -- Tome discovery (notified) is not ownership.
 H.discovered[E(19)]=true;H.Notify()
 t=S.Within(H,.5,function() return #(Progress().unknownTomes or {1})==0 end)
 C.guard(t~=nil,'tome discovery: MISSING TOMES clears within one poll',#(Progress().unknownTomes or {}))
 C.guard(Same(Needed(),Range(16,19)) and Progress().owned==5,'tome discovery: Echo 19 is still needed; a known tome is not an owned Echo',Show(Needed()))

 -- Saving the current run as a Saved Build (native save, then the slot mirror)
 -- is equipped-build data, not a grant; the actual grant after it is.
 local saved=Counts(owned,EXTRAS)
 p.native('PerkService.SaveServerBuildSlot(2)',1,function() return ProjectEbonhold.PerkService.SaveServerBuildSlot(2,'Build Two') end)
 H.perks.serverBuildSlots[2]={name='Build Two',verified=true,echoes=S.SlotRows(saved)}
 s0=Stats();H.Notify();H.Advance(.5)
 C.setup(Stats().slots==s0.slots+1,'Saved Build save: the slot mirror change reached Nexus','slots '..s0.slots..'->'..Stats().slots)
 C.setup(Progress().wishlistName=='Synthetic W' and Progress().total==9,'Saved Build save: the assignment is unchanged',S.Text(S.Hud()))
 C.guard(Same(Needed(),Range(16,19)) and Progress().owned==5 and Stats().granted==s0.granted,
  'Saved Build save alone: no grant, so STILL NEEDED and rolled ownership are unchanged',Show(Needed()))
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 owned={11,12,13,14,15,16}
 H.granted=S.Granted(Counts(owned,EXTRAS));H.Notify()
 t=S.Within(H,.5,function() return Same(Needed(),Range(17,19)) end)
 C.guard(t~=nil,'actual grant after the save: STILL NEEDED drops Echo 16',Show(Needed()))

 -- Positive control for the loading-screen order below: the same order with the callback.
 owned={11,12,13,14,15,16,17}
 H.granted=S.Granted(Counts(owned,EXTRAS));H.Notify()
 Leave(H);Enter(H)
 local dt=FirstStep(H,1)
 C.guard(dt~=nil and Same(Needed(),{18,19}),'notified manual change, then a loading screen: STILL NEEDED drops Echo 17',Show(Needed()))
 H.Advance(6)
 C.guard(Same(Needed(),{18,19}) and Rendered()==NeedText({18,19}),'notified manual change, then a loading screen: it stays dropped',Rendered())
 p.quiet('callback controls')

 -- One more manual Orb result lands silently just before /reload (no
 -- callback, no fallback in between); the fresh runtime reads the mirrors.
 owned={11,12,13,14,15,16,17,18}
 H=Reload({counts=Counts(owned,EXTRAS),saved=saved,discovered=true})
 C.guard(Same(Needed(),{19}) and Progress().owned==8 and Progress().total==9,'true reload: STILL NEEDED is read fresh (only Echo 19)',S.Text(S.Hud())..' '..Show(Needed()))
 C.guard(Rendered()==NeedText({19}),'true reload: the panel text follows',Rendered())
 C.guard(#(Progress().unknownTomes or {1})==0,'true reload: the discovered tome stays discovered',#(Progress().unknownTomes or {}))
 C.guard(#H.actions==0,'true reload: Nexus made no host write while starting',#H.actions)
 Diag('after the true reload')
end)

C.scenario('silent and early callbacks; reload with the granted reply outstanding',function()
 local H=Boot({counts=Counts({11,12,13},EXTRAS)})
 C.setup(Same(Needed(),Range(14,19)),'fixture: STILL NEEDED lists Echo 14-19',Show(Needed()))
 local p=Player(H)

 -- A silent manual change with nothing else happening: the fallback finds it.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 local s0=Stats()
 H.granted=S.Granted(Counts({11,12,13,14},EXTRAS))
 local t=S.Within(H,5.5,function() return Same(Needed(),Range(15,19)) end)
 local s1=Stats()
 print('DIAG silent manual change shown after '..tostring(t)..' s')
 C.guard(t~=nil,'silent manual change: STILL NEEDED drops Echo 14 within the five-second fallback period',Show(Needed()))
 C.guard(s1.notes==s0.notes and s1.repairs>s0.repairs and s1.grantedMismatch>s0.grantedMismatch,
  'silent manual change: no callback; the fallback found the granted change',
  'callbacks '..s0.notes..'->'..s1.notes..', repairs '..s0.repairs..'->'..s1.repairs)

 -- The callback arrives before its data, then the data lands silently.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0=Stats();H.Notify();H.Advance(.25)
 C.setup(Stats().equivalent==s0.equivalent+1 and Stats().granted==s0.granted,'early callback: consumed before its data, as an equivalent reconciliation')
 H.granted=S.Granted(Counts({11,12,13,14,15},EXTRAS))
 t=S.Within(H,5.5,function() return Same(Needed(),Range(16,19)) end)
 C.guard(t~=nil,'data after its callback: STILL NEEDED drops Echo 15 within the fallback period',Show(Needed()))
 p.quiet('silent controls')

 -- Fresh runtime whose granted mirror is still empty; the reply lands silently.
 local counts=Counts({11,12,13,14,15},EXTRAS)
 H=Reload({counts=counts,hold=true})
 C.setup(Nexus.GameAdapter.Owned().synced==false,'reload, reply outstanding: rolled ownership is not synchronized yet')
 C.setup(Progress().owned==0 and Same(Needed(),Range(11,19)),'reload, reply outstanding: STILL NEEDED lists every ordinary Wishlist Echo',S.Text(S.Hud())..' '..Show(Needed()))
 p=Player(H)
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 H.holdGrantedResponse=nil
 H.granted=S.Granted(counts)
 t=S.Within(H,5.5,function() return Same(Needed(),Range(16,19)) end)
 C.guard(t~=nil,'reload, silent granted reply: STILL NEEDED shows 5/9 within the fallback period',S.Text(S.Hud())..' '..Show(Needed()))
 C.guard(Nexus.GameAdapter.Owned().synced==true,'reload, silent granted reply: rolled ownership is synchronized')
 p.quiet('reload reply')

 -- The same reload and reply, then a loading screen before the next fallback check.
 H=Reload({counts=counts,hold=true})
 C.setup(Progress().owned==0 and Same(Needed(),Range(11,19)),'second reload, reply outstanding: STILL NEEDED lists every ordinary Wishlist Echo',S.Text(S.Hud())..' '..Show(Needed()))
 p=Player(H)
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0=Stats();local r0=OwnedRevision()
 H.holdGrantedResponse=nil
 H.granted=S.Granted(counts)
 Leave(H);PreEntry('reload, silent granted reply',s0,r0,'granted');Enter(H)
 Hazard(H,'reload, silent granted reply, loading screen',{field='granted',s0=s0,r0=r0,
  getter=function() return GetterOwns(15,1) end,pred=function() return Same(Needed(),Range(16,19)) end,
  want='5/9: Echo 16-19 still needed',text=NeedText(Range(16,19))})
 p.quiet('reload, loading screen')
end)

C.scenario('silent manual change and a manual Orb pick, each before a loading screen',function()
 local H=Boot({counts=Counts({11,12,13},EXTRAS)})
 C.setup(Same(Needed(),Range(14,19)),'fixture: STILL NEEDED lists Echo 14-19',Show(Needed()))
 Diag('loading-screen boot')
 local p=Player(H)

 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 local s0,r0=Stats(),OwnedRevision()
 H.granted=S.Granted(Counts({11,12,13,14},EXTRAS))
 Leave(H);PreEntry('silent manual change',s0,r0,'granted');Enter(H)
 Hazard(H,'silent manual change, loading screen',{field='granted',s0=s0,r0=r0,
  getter=function() return GetterOwns(14,1) end,pred=function() return Same(Needed(),Range(15,19)) end,
  want='Echo 14 owned: Echo 15-19 still needed',text=NeedText(Range(15,19))})

 -- The game's own Orb window: confirm a spend on an extra copy, the offer is
 -- shown, the player picks a missing Wishlist Echo; the server settles silently.
 C.setup(Same(Needed(),Range(15,19)),'Orb pick: starts from Echo 15-19 still needed',Show(Needed()))
 p.native('OrbService.ConfirmSpend(Echo 51)',1,function() return ProjectEbonhold.OrbService.ConfirmSpend(E(51),1) end)
 H.orbs.offer=true;H.orbs.charges=H.orbs.charges-1
 H.Board({{spellId=E(15),quality=S.Q(E(15))},{spellId=E(61),quality=S.Q(E(61))},{spellId=E(62),quality=S.Q(E(62))}})
 H.Advance(.3)
 r0=OwnedRevision()
 p.native('PerkService.SelectPerk(Echo 15)',1,function() return ProjectEbonhold.PerkService.SelectPerk(E(15)) end)
 C.setup(OwnedRevision()==r0+1,'Orb pick: Nexus\'s SelectPerk hook saw the manual pick (zero Nexus actions is not zero game changes)',tostring(r0)..'->'..tostring(OwnedRevision()))
 H.Advance(.3)
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0,r0=Stats(),OwnedRevision()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.orbs.offer=false
 H.granted=S.Granted(Counts({11,12,13,14,15},Range(52,60)))
 Leave(H);PreEntry('manual Orb pick',s0,r0,'granted');Enter(H)
 Hazard(H,'manual Orb pick, loading screen',{field='granted',s0=s0,r0=r0,
  getter=function() return GetterOwns(15,1) and GetterOwns(51,0) end,pred=function() return Same(Needed(),Range(16,19)) end,
  want='Echo 15 owned: Echo 16-19 still needed',text=NeedText(Range(16,19))})
 p.quiet('loading screen')
end)

C.scenario('manual permanent lock, without and before a loading screen',function()
 local H=Boot({counts=Counts({11,12,13,31,32},EXTRAS),rows=Rows({11,12,13,14,15,16,17,18,19,31,32})})
 C.setup(Same(Needed(),Range(14,19)) and Progress().total==11,'fixture: 5/11 before the locked roles',S.Text(S.Hud()))
 -- Echo 31 and 32 become locked targets of the Wishlist's own server row.
 for _,e in ipairs(H.perks.serverBuildSlots[101].echoes) do
  if e.spellId==E(31) or e.spellId==E(32) then e.locked=true end
 end
 H.Notify()
 C.setup(S.Within(H,6,function()
  local p=Progress()
  return Same(ToLock(),{31,32}) and p.lockedTotal==2 and p.lockedOwned==0 and p.total==9 and Same(Needed(),Range(14,19))
 end)~=nil,'fixture: Echo 31 and 32 are LOCKED TARGETS (0/2), Echo 14-19 still needed','toLock '..Show(ToLock())..' needed '..Show(Needed()))
 local p=Player(H)

 -- The progression UI locks an owned copy (LockPerk, then RequestGrantedPerks);
 -- the reply moves it from the granted mirror to the locked mirror, silently.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 p.native('PerkService.LockPerk(Echo 31)',1,function() return ProjectEbonhold.PerkService.LockPerk(E(31)) end)
 p.native('PerkService.RequestGrantedPerks()',0,function() return ProjectEbonhold.PerkService.RequestGrantedPerks() end)
 H.granted=S.Granted(Counts({11,12,13,32},EXTRAS))
 H.locked={{spellId=E(31),stacks=1}}
 local t=S.Within(H,5.5,function() return Same(ToLock(),{32}) and Progress().lockedOwned==1 end)
 C.guard(t~=nil,'silent manual lock: LOCKED TARGETS drops Echo 31 within the fallback period','toLock '..Show(ToLock()))
 C.guard(Same(Needed(),Range(14,19)),'silent manual lock: a permanent lock is not ordinary run ownership; STILL NEEDED unchanged',Show(Needed()))

 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 local s0,r0=Stats(),OwnedRevision()
 p.native('PerkService.LockPerk(Echo 32)',1,function() return ProjectEbonhold.PerkService.LockPerk(E(32)) end)
 p.native('PerkService.RequestGrantedPerks()',0,function() return ProjectEbonhold.PerkService.RequestGrantedPerks() end)
 H.granted=S.Granted(Counts({11,12,13},EXTRAS))
 H.locked={{spellId=E(31),stacks=1},{spellId=E(32),stacks=1}}
 Leave(H);PreEntry('silent manual lock',s0,r0,'locked');Enter(H)
 Hazard(H,'silent manual lock, loading screen',{field='locked',s0=s0,r0=r0,
  getter=function() return GetterLocks(32,1) end,pred=function() return Same(ToLock(),{}) and Progress().lockedOwned==2 end,
  want='Echo 32 locked: no locked target left, 2/2'})
 C.guard(Same(Needed(),Range(14,19)),'silent manual lock: STILL NEEDED unchanged throughout',Show(Needed()))
 p.quiet('permanent lock')
end)

C.finish('callback controls, tome, Saved Build save, true reloads, loading-screen orders, manual Orb pick and permanent lock')
