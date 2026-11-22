-- Start/Stop surfaces (2026-11-19, field report on test.9106: "Stop appears to
-- do nothing"; Start/Stop with old Pause/Resume/recovery controls and "Use
-- Pause or Stop"). The Orb window, the main-panel strip and the mini panel
-- operate the one Start/Stop runner: Stop is offered exactly while the runner
-- is ON and ends it; the earlier runtime's Pause, Resume, its Stop of an old
-- receipt and the obsolete close notice are gone. The receipt's history words
-- stay, the mini panel still opens passively and is reused, and the ordinary
-- flow is unchanged. Synthetic game services only.
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
local OFFER_HIT={{spellId=410004,quality=3},{spellId=410002,quality=2},{spellId=410005,quality=0}}
-- A receipt restored after a reload (an earlier session's Orb action), then
-- the surfaces of this session.
local function World()
 if NexusOrbAuto then NexusOrbAuto:SetScript('OnUpdate',nil);NexusOrbAuto:SetScript('OnEvent',nil);NexusOrbAuto:Hide() end
 local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
 local H,R,A,O=S.Fresh();H.OrbPlan()
 assert(R.Start(3));assert(R.Stop());H.Offer()
 O.offer=false;H.perks.currentChoice=nil
 R=S.Reload(H);S.Pass(H,R,A);S.Rechecks(H,R,2)
 assert(R.Status().pending,'setup: a restored receipt')
 ProjectEbonhold.OrbService.CanRerollOffer=function() return O.charges>0 end
 ProjectEbonhold.OrbService.RerollOffer=function() H.actions[#H.actions+1]={'orb-redraw'};return true end
 local M=Nexus.OrbAuto
 local f=Nexus.OrbPanel.Show();H.Advance(.3)
 Nexus.Panel.Show();H.Advance(.3)
 local strip=NexusPanel._orbControls
 local mini=Nexus.OrbPanel.ShowMini();H.Advance(.3)
 local function refresh() Nexus.OrbPanel.Refresh();strip.refresh();H.Advance(.3) end
 return H,R,A,O,M,f,strip,mini,refresh
end
local function shown(c) return c~=nil and c:IsShown() end
local function on(c) return shown(c) and c:IsEnabled() end
-- What each surface offers, in one line for the messages.
local function offers(f,strip,mini)
 local out={}
 for _,p in ipairs({{'main',f,{'start','stop','pause','resume','cont','review'}},{'strip',strip,{'primary','pause','resume','stop','details','dismiss'}},
  {'mini',mini,{'pause','resume','stop','open'}}}) do
  for _,k in ipairs(p[3]) do local c=p[2][k];if shown(c) then out[#out+1]=p[1]..'.'..k..(c:IsEnabled() and '+' or '-') end end
 end
 return table.concat(out,' ')
end
local function noLegacy(tag,f,strip,mini)
 for _,k in ipairs({'pause','resume','primary'}) do check(not shown(strip[k]),tag..': the strip shows no '..k) end
 for _,k in ipairs({'pause','resume'}) do check(not shown(mini[k]),tag..': the mini panel shows no '..k) end
 for _,k in ipairs({'pause','resume','cont','review'}) do check(not shown(f[k]),tag..': the Orb window shows no '..k) end
 check(not shown(f.closeNotice),tag..': no "Use Pause or Stop" notice')
end

-- 1. Before any run: Start is the control; no Stop anywhere; the receipt's
-- history words stay on the strip; no recovery action is offered.
do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 refresh()
 local o=offers(f,strip,mini)
 check(on(f.start),'1: Start is offered: '..o)
 check(not on(f.stop) and not on(strip.stop) and not on(mini.stop),'1: no Stop is offered with nothing running: '..o)
 noLegacy('1',f,strip,mini)
 check(shown(strip) and (strip.summary:GetText() or ''):find('unavailable after reload',1,true)~=nil,'1: the strip keeps the receipt\'s history words: '..tostring(strip.summary:GetText()))
 check(on(strip.details),'1: Details stays offered')
end

-- 2. Running (a spend awaiting its offer) and waiting (no answer for a long
-- time): every surface offers the runner's Stop and nothing else of the kind.
for _,phase in ipairs({'running','waiting'}) do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 check(M.Start(),'2 '..phase..': Start');H.Advance(.5)
 if phase=='waiting' then H.Advance(25) end
 refresh()
 local o=offers(f,strip,mini)
 check(M.Active() and M.Status().inflight=='spend','2 '..phase..': setup: the runner waits on its spend')
 check(not on(f.start) and on(f.stop) and on(strip.stop) and on(mini.stop),'2 '..phase..': Stop is offered everywhere, Start is not: '..o)
 noLegacy('2 '..phase,f,strip,mini)
end
-- Each surface's Stop ends the runner, at once, and nothing is sent after it.
for _,where in ipairs({'main','strip','mini'}) do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 check(M.Start(),'2 '..where..': Start');H.Advance(.5);refresh()
 local sent=#H.actions
 if where=='main' then f.stop:Click() elseif where=='strip' then strip.stop:Click() else mini.stop:Click() end
 check(not M.Active() and M.Status().state=='STOPPED','2 '..where..': its Stop ends the runner')
 O.offer=true;H.Board(OFFER_HIT);H.Advance(2)
 check(#H.actions==sent,'2 '..where..': nothing is sent after Stop')
end

-- 3. Stopped (the field case): no surface keeps a Stop that does nothing, the
-- receipt is not changed by any click, and Start is offered again.
do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 check(M.Start(),'3: Start');H.Advance(.5)
 M.Stop();refresh()
 local o=offers(f,strip,mini)
 check(not on(f.stop) and not on(strip.stop) and not on(mini.stop),'3: after Stop no surface offers a Stop that does nothing: '..o)
 check(on(f.start),'3: Start is offered again: '..o)
 noLegacy('3',f,strip,mini)
 local before=R.Status().state
 local saved=H.Clone(Nexus.Store.State().orbRefinement.pending)
 for _,c in ipairs({f.stop,strip.stop,mini.stop,strip.pause,strip.resume,mini.pause,mini.resume}) do if c and c:IsEnabled() then c:Click() end end
 H.Advance(.5)
 local now=Nexus.Store.State().orbRefinement.pending
 local same=now~=nil
 for k,v in pairs(saved) do if type(v)~='table' and now[k]~=v then same=false end end
 check(same and R.Status().state==before,'3: the restored receipt is unchanged by the surfaces: '..tostring(before)..' -> '..tostring(R.Status().state))
 -- next-run visibility: a new Start shows on every surface again
 check(M.Start(),'3: a new Start');H.Advance(.5);refresh()
 check(on(f.stop) and on(strip.stop) and on(mini.stop) and shown(strip),'3: the next run is shown with its Stop on every surface: '..offers(f,strip,mini))
 M.Stop()
end

-- 4. The mini panel opens passively and is reused: opening it sends nothing,
-- starts nothing and returns the same panel.
do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 local sent=#H.actions
 local again=Nexus.OrbPanel.ShowMini();H.Advance(.5)
 check(rawequal(again,mini) and mini:IsShown(),'4: ShowMini reuses the one panel')
 check(#H.actions==sent and not M.Active(),'4: opening it sends nothing and starts nothing')
end

-- 5. The ordinary flow is unchanged by the surfaces (no run): Auto can be
-- turned on, a needed Echo on a free draw is taken, and no Orb is spent.
do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 SlashCmdList.NEXUS('auto')
 check(Nexus.RecomputeStats().autoEnabled==true,'5: ordinary Auto turns ON')
 local takes,spends=H.Count('take'),H.Count('orb-spend')
 H.Board({{spellId=410005,quality=0},{spellId=410002,quality=2},{spellId=410006,quality=3}})
 for _=1,20 do H.Notify();A.Poll();H.Advance(.25) end
 refresh()
 check(H.Count('take')==takes+1 and H.Count('orb-spend')==spends,'5: ordinary Auto takes the needed Echo; no Orb is spent')
 check(not M.Active(),'5: no run was started')
end

-- 6. Rendered wording (2026-11-19, user/coordinator-approved scoped
-- correction): what the player reads names Start and Stop, no maximum, Pause,
-- Resume or Continue. Read from the actual rendered windows and tooltips.
do
 local H,R,A,O,M,f,strip,mini,refresh=World()
 local function tip(widget)
  local lines={}
  local set,add,own,show=rawget(GameTooltip,'SetText'),rawget(GameTooltip,'AddLine'),rawget(GameTooltip,'SetOwner'),rawget(GameTooltip,'Show')
  rawset(GameTooltip,'SetText',function(_,t) lines[#lines+1]=t end);rawset(GameTooltip,'AddLine',function(_,t) lines[#lines+1]=t end)
  rawset(GameTooltip,'SetOwner',function() end);rawset(GameTooltip,'Show',function() end)
  local fn=widget:GetScript('OnEnter');if fn then fn(widget) end
  rawset(GameTooltip,'SetText',set);rawset(GameTooltip,'AddLine',add);rawset(GameTooltip,'SetOwner',own);rawset(GameTooltip,'Show',show)
  return table.concat(lines,'\n')
 end
 local OLD={'until you enter another amount','Maximum follows','Use Pause or Stop','Pause, Resume and Stop','approved maximum','whole-number maximum'}
 local function clean(tag,text)
  for _,w in ipairs(OLD) do check(not tostring(text):find(w,1,true),tag..': no "'..w..'": '..tostring(text)) end
 end
 refresh()
 local balance=f.balance:GetText() or ''
 check(balance:find('Start rolls until your Wishlist goal is met, you press Stop, or no Orb can be used safely.',1,true)~=nil,'6: the balance box says what Start does: '..balance)
 clean('6 balance box',balance)
 check(M.Start(),'6: Start');H.Advance(.5);refresh()
 check(not (f.balance:GetText() or ''):find('Start rolls until',1,true),'6: while the run is ON the balance box does not repeat what Start does')
 M.Stop();refresh()
 local closeTip=tip(mini.close)
 check(closeTip:find('use Stop',1,true)~=nil,'6: the mini Close tooltip names Stop: '..closeTip)
 clean('6 mini Close tooltip',closeTip)
 local miniTip=tip(f.miniPanel)
 check(miniTip:find("this run's status and Stop",1,true)~=nil,'6: the Mini panel tooltip names Stop: '..miniTip)
 clean('6 Mini panel tooltip',miniTip)
 local hub=table.concat(Nexus.Panel.HubTooltipLines('orbs') or {},'\n')
 check(hub:find('a run continues. Use Stop.',1,true)~=nil,'6: the main panel Orbs hover names Stop: '..hub)
 clean('6 main panel Orbs hover',hub)
 Nexus.Help.Show('orbs')
 local page=NexusHelpWindow.body:GetText() or ''
 check(page:find('There is no maximum to set',1,true)~=nil,'6: the Help Orbs page says there is no maximum')
 clean('6 Help Orbs page',page)
 Nexus.Help.Hide()
end

print('PASS orb auto surfaces: '..checks..' checks')
