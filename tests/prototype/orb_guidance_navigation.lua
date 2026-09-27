-- Passive Orb guidance on the main HUD and a passive "Open Orbs..." button.
--
-- Reported (owner, chat description of screenshots; no image bytes held):
-- with Auto ON and ordinary rolling paused by the Orb state, the HUD still
-- said "Active: Roll recommendations active"; a player at the end of normal
-- rolls did not know that Orbs were the next step, and the Orb window's
-- start refusal said only "Resolve the current Echo action before starting
-- Orb mode."
--
-- The guidance is presentation only: it never starts, resumes, approves,
-- spends, selects, locks, saves or changes a setting, and a decision never
-- reads it. The button only opens the Orb window, which reads and shows.
-- Expected outcomes are written out per case; the product helper is not used
-- as its own oracle. SYNTHETIC ids and counts.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

------------------------------------------------------------------------
-- 1. Precedence of the projection (real module, written expectations).
------------------------------------------------------------------------
do
 local F=dofile('tests/prototype/format5_support.lua')
 F.Boot(F.Database({}),function(h) h.playerLevel=60 end)
 local G=assert(Nexus.OrbGuidance,'the guidance module is loaded')
 local function P(obs) return G.Project(obs) end
 local base={plan=true,ordinaryAllowed=true,horizon=0,rolledMissing=4,lockMissing=0}
 local function With(t) local o={};for k,v in pairs(base) do o[k]=v end;for k,v in pairs(t) do o[k]=v end;return o end
 local r=P(base)
 check(r.state=='finished' and r.openOrbs and r.text:find('Normal rolls finished',1,true),'finished with rolled targets missing: review Orbs')
 check(not r.text:find('will',1,true) and not r.text:find('success',1,true),'and no eligibility or success promise: '..r.text)
 r=P(With({horizon=false}))
 check(r.state=='unknown' and not r.openOrbs,'a level alone is not "finished": an unknown roll count says so')
 r=P(With({horizon=12}))
 check(r.state=='rolling' and not r.openOrbs and r.text==nil,'with normal rolls left there is no Orb advice')
 r=P(With({board=true}))
 check(r.state=='choice' and not r.openOrbs,'an open Echo choice ranks before finished')
 r=P(With({board=true,intent='submitted'}))
 check(r.state=='waiting' and not r.openOrbs,'a submitted action ranks before "choose": not asked to choose while pending')
 r=P(With({board=true,inFlight=true}))
 check(r.state=='waiting','an unconfirmed latch is not dropped because a board is visible')
 r=P(With({intent='expired'}))
 check(r.state=='waiting','an expired intent is not confirmation: '..r.state)
 r=P(With({orbCapable=false}))
 check(r.state=='finished-no-orbs' and not r.openOrbs,'no Orb capability: named, no Orb advice: '..r.state)
 r=P(With({ordinaryAllowed=false,ordinaryWhy='orb state unknown',board=true,intent='uncertain'}))
 check(r.state=='orb-state' and r.openOrbs,'an unknown Orb state ranks first among ordinary blockers, with inspection')
 check(#r.blockers==3,'and every present blocker stays listed for details: '..#r.blockers)
 r=P(With({orbBlock='Ordinary rolling is blocked: an earlier Orb action is unresolved after a reload.',ordinaryAllowed=false}))
 check(r.state=='orb-run' and r.openOrbs and r.text:find('unresolved',1,true),'an unresolved old Orb action shows its recovery reason')
 check(not r.text:find('Start',1,true),'and suggests no start')
 r=P(With({rolledMissing=0,lockMissing=2}))
 check(r.state=='locks-only' and not r.openOrbs and r.text:find('Orbs do not fill locked slots',1,true),'only locks remain: no spending suggestion')
 r=P(With({plan=false}))
 check(r.state=='no-plan' and not r.openOrbs,'no assigned Wishlist: named, no readiness claim')
 r=P(With({horizon=0,rolledMissing=false}))
 check(r.state=='finished-unknown' and not r.openOrbs,'finished with unknown progress promises nothing')
end

------------------------------------------------------------------------
-- 2. The real HUD at level 80 (idle render), Auto ON.
------------------------------------------------------------------------
local F=dofile('tests/prototype/format5_support.lua')
local function Granted(n)
 local granted,id,left={},200001,n
 while left>0 do
  local stacks=math.min(5,left);local list={}
  for index=1,stacks do list[index]={spellId=id,quality=0} end
  granted['Echo '..(id-200000)]=list;left=left-stacks;id=id+1
 end
 return granted
end
local function Plan()
 -- 79 rolled copies: 200001-200015 x5 and 200016 x4 (synthetic).
 local rows={}
 for id=200001,200015 do rows[#rows+1]={spellId=id,quality=id%4,stacks=5,locked=false} end
 rows[#rows+1]={spellId=200016,quality=200016%4,stacks=4,locked=false}
 return rows
end
local H
local function Boot(opt)
 H=F.Boot(F.Database({}),function(h)
  h.playerLevel=opt.level or 80;h.granted=Granted(opt.rolled or 75);h.pendingRolls=opt.pendingRolls
  if opt.orbs~=false then
   -- A state-aware Orb service that is idle (synthetic). Spending is counted.
   ProjectEbonhold=ProjectEbonhold or {}
   ProjectEbonhold.OrbService={IsStateKnown=function() return true end,IsOfferPending=function() return false end,
    GetCharges=function() return 3 end,RequestCharges=function() return true end,
    ConfirmSpend=function() h.actions[#h.actions+1]={'orb-spend'};return true end}
  else
   if ProjectEbonhold then ProjectEbonhold.OrbService=nil end
  end
  if opt.before then opt.before(h) end
 end)
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 if opt.plan~=false then
  check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic Plan',opt.rows or Plan(),opt.design or {})==true,'fixture: plan set')
 end
 if opt.auto~=false then SlashCmdList.NEXUS('auto') end
 for _=1,6 do Nexus.RequestRecompute();H.Advance(.4) end
 return H
end
local function View()
 local m=Nexus.Panel._lastModel or {}
 local g=m.orbGuidance or {}
 local btn=NexusPanel and NexusPanel._orbsBtn
 local head=NexusPanel and NexusPanel._rollStatus and NexusPanel._rollStatus:GetText() or ''
 return {state=g.state,text=g.text,button=btn and btn:IsShown() or false,heading=head,paused=m.paused,auto=m.auto}
end

do
 Boot({pendingRolls=0})
 local v=View()
 check(v.state=='finished','level 80, server count 0, 4 rolled copies missing: '..tostring(v.state))
 check(v.button,'the passive Open Orbs button is offered')
 check(v.heading:find('Roll status',1,true) and not v.heading:find('Active',1,true),'the heading does not claim active rolling: '..v.heading)
 check(not (NexusOrbPanel and NexusOrbPanel:IsShown()),'nothing opens by itself')
 check(v.auto==true,'Auto stays ON (the guidance changes no setting)')
end
do
 Boot({pendingRolls=12})
 local v=View()
 check(v.state=='rolling' and not v.button,'level 80 with normal rolls left: no "finished", no Orb button: '..tostring(v.state))
end
do
 -- A client without an Orb service: the limitation is named, no button.
 Boot({pendingRolls=0,orbs=false})
 local v=View()
 check(v.state=='finished-no-orbs' and not v.button,'no Orb service: named, no Orb button: '..tostring(v.state))
 check(tostring(v.text):find('does not expose Orb mode',1,true)~=nil,'the text says so: '..tostring(v.text))
end
do
 -- Level 1: the game's roll count is not read on purpose; no Orb text and
 -- no extra HUD space appears.
 Boot({level=1,pendingRolls=0})
 local v=View()
 check(v.text==nil and not v.button,'level 1 shows no Orb guidance: '..tostring(v.state)..' / '..tostring(v.text))
end
do
 -- A latch the watchdog declared dead is still not a confirmed result.
 Boot({pendingRolls=0})
 H.perks.pendingSelectSpellId=200016;H.Notify()
 for _=1,30 do Nexus.RequestRecompute();H.Advance(.5) end
 check(not Nexus.GameAdapter.InFlight(),'fixture: the watchdog released the stuck latch')
 local v=View()
 check(v.state=='waiting' and not v.button,'an expired watchdog is not confirmation: still waiting: '..tostring(v.state))
 H.perks.pendingSelectSpellId=nil;H.Notify()
end
do
 -- The game reports a pending choice latch (an action without its result).
 Boot({pendingRolls=0})
 H.perks.pendingSelectSpellId=200016;H.Notify()
 for _=1,4 do Nexus.RequestRecompute();H.Advance(.4) end
 local v=View()
 check(v.state=='waiting' and not v.button,'an unconfirmed action: waiting, no Orb advice: '..tostring(v.state))
 H.perks.pendingSelectSpellId=nil;H.Notify()
end
do
 -- Rolled targets complete; one locked target remains.
 local design={[200020]={version=1,copies=1,rows={{spellId=200020,quality=0,stacks=1,locked=true,sourceRole='locked'}}}}
 Boot({pendingRolls=0,rolled=79,design=design})
 local v=View()
 check(v.state=='locks-only' and not v.button,'only locks remain: no Orb spending suggestion: '..tostring(v.state))
end
do
 -- Orb state unknown blocks ordinary rolling while a board is open.
 Boot({pendingRolls=3,before=function(h)
  ProjectEbonhold=ProjectEbonhold or {}
  ProjectEbonhold.OrbService={IsStateKnown=function() return false end,IsOfferPending=function() return false end}
 end})
 H.Board({{spellId=200016,quality=0},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify()
 for _=1,4 do Nexus.RequestRecompute();H.Advance(.4) end
 local v=View()
 check(v.paused~=nil,'fixture: automation is paused by the Orb state: '..tostring(v.paused))
 check(v.heading:find('Auto ON',1,true) and v.heading:find('paused',1,true),'the heading says Auto ON - paused: '..v.heading)
 check(not v.heading:find('Active',1,true),'and not that rolling is active')
 check(v.state=='orb-state' and v.button,'with the Orb button for inspection: '..tostring(v.state))
 check(v.auto==true,'Auto stays ON')
 ProjectEbonhold.OrbService=nil
end

------------------------------------------------------------------------
-- 3. The button is passive navigation. Every mutator is counted, refused
-- attempts included, and saved state is compared.
------------------------------------------------------------------------
local function Ser(v,seen)
 seen=seen or {}
 if type(v)~='table' then return tostring(v) end
 if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local o={};for _,k in ipairs(keys) do o[#o+1]=tostring(k)..'='..Ser(v[k],seen) end
 return '{'..table.concat(o,',')..'}'
end
local function Count(owner,names,calls)
 for _,n in ipairs(names) do
  local real=owner[n]
  if type(real)=='function' then owner[n]=function(...) calls[#calls+1]=n;return real(...) end end
 end
end
-- Two identical runs, with and without the click (the no-navigation
-- control): the same saved data, game actions and mutator calls. Between the
-- render and the click an Echo choice and an unconfirmed latch appear; the
-- button still only opens the window, which reads the current state.
local function RenderThenClick(click)
 Boot({pendingRolls=0})
 check(View().button,'fixture: the button is shown')
 local calls={}
 Count(Nexus.OrbRuntime,{'Start','Resume','Pause','Stop','Recheck','Prepare','Confirm','SetLimit','SetSource',
  'Exclude','ClearExclusions','SuggestSources','SetRecycle','SelectWishlist','UseAssignedWishlist','MoveTarget',
  'PrepareLimitIncrease','ConfirmLimit'},calls)
 Count(Nexus.GameAdapter,{'Take','Banish','Reroll','Freeze','Activate','Save','UploadWishlist','LockPerk','UnlockPerk',
  'SetLoadoutWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity'},calls)
 local auto0=View().auto
 H.Board({{spellId=200016,quality=0},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.perks.pendingSelectSpellId=200016
 if click then
  local before=#calls
  NexusPanel._orbsBtn:Click()
  check(NexusOrbPanel and NexusOrbPanel:IsShown(),'the click opens the Orb window')
  check(#calls==before,'the click itself calls no mutator: '..table.concat(calls,','))
  local shown=Nexus.OrbRuntime.Status()
  check(shown.canStart==false,'the window reads the current state: Start is not available')
  local why=tostring(shown.startReason)
  check(why:find('has no confirmed result',1,true)~=nil and why:find('An Echo choice is shown',1,true)~=nil,
   'and names the unconfirmed action and the choice opened after the render: '..why)
  check(not why:lower():find('choose',1,true),'without telling the player to choose it: '..why)
  check(not NexusOrbPanel.start:IsEnabled(),'the Start button is disabled')
 end
 for _=1,8 do H.Advance(.25) end
 check(View().auto==auto0,'Auto is unchanged')
 local out={db=Ser(NexusDB),actions=Ser(H.actions),calls=table.concat(calls,',')}
 H.perks.pendingSelectSpellId=nil;H.Board(nil);H.Notify()
 if click then
  NexusOrbPanel:Hide()
  for _=1,6 do Nexus.RequestRecompute();H.Advance(.4) end
  check(not NexusOrbPanel:IsShown(),'a closed Orb window does not reopen by itself')
 end
 return out
end
do
 local control=RenderThenClick(false)
 local opened=RenderThenClick(true)
 check(opened.calls==control.calls,'the same mutator calls with and without the click: ['..opened.calls..'] vs ['..control.calls..']')
 check(opened.actions==control.actions,'the same game actions with and without the click')
 check(opened.db==control.db,'the same saved data with and without the click')
end

-- The Orb window's start refusal is covered with a real Orb service in
-- orb_guidance_passive_open.lua.

print('PASS orb_guidance_navigation checks='..checks)
