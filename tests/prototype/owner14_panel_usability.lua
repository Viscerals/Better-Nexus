-- Owner-approved Nexus usability follow-up, Panel/menu lane (owner-displayed
-- items 1, 2+9, 7, 8, 12, 14 and 15; displayed item 10 is excluded, so the
-- visible "Auto OFF" label must stay exactly as it is). Refs #171, #165,
-- #174, #164, #175, #169.
-- P1  item 1: a confirmed session pause shows a paused banner with Resume;
--     its real button resumes once through the real Nexus.SessionPause, the
--     banner goes on the redraw, Auto keeps its selection and nothing is
--     sent, saved or spent; a stale click resumes nothing.
-- P2  item 1: an unreadable or malformed Status shows the banner as unknown
--     with no Resume; a Resume that fails is reported and still paused; no
--     API is no banner; the pause is not saved and a module reload starts
--     unpaused; hiding and reopening the panel works while paused.
-- O1  items 2+9: Options is shorter and grouped; the duplicate coach entry is
--     gone while every distinct route stays reachable (top level or one list
--     down) and opens its owner once; opening reads only.
-- O2  item 9: setting rows keep their action words and add the current value;
--     no action row is ticked; Update notices ticks only current choices and
--     each row calls only its own setter.
-- X1  item 7: Details shows "+N more - Show all"; its button opens a list of
--     every extra copy of the last committed model, whole and in order; the
--     first hover keeps its 25-row bound; empty, unknown and stale are
--     distinct; reading, refreshing and closing change nothing.
-- H1  item 8: X and Hide Nexus Panel say once how to bring the panel back and
--     light the minimap button; a repeat hide says nothing; showing clears it.
-- U1  item 12: plain version and update words keep the exact installed build;
--     unknown is "no verified update information", never latest; the popup
--     keeps the full Releases address in its box and starts nothing.
-- F1  items 15 and 14: the footer "?" opens Help.Show('faq') once, fits the
--     420 px footer beside the hubs, leaves header line 1 to Auto, Options and
--     Close, and its hover says where the numbers are explained.
-- A1  item 10 excluded: the Auto button still reads "Auto OFF" / "Auto ON",
--     and no panel text or menu row says "Auto: Off".
-- The Readout-owned Automation settings row "Auto: OFF (the Auto button turns
-- it ON after its warning)" is pre-existing and not the excluded rename.
-- Categories (view_regression_support): EXPECT fails at f8cce3f (before this
-- lane), GUARD already held there, SETUP is the fixture. Synthetic offline
-- evidence only: native fit, hit order, focus, contrast, clipboard bytes and
-- performance are NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('owner14_panel_usability')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel
local REAL_PAUSE=Nexus.SessionPause
local LONG='Ünïcødé Flamebringer of the Very Long Ember Name That Never Fits ×3 (Rare:×2 Epic:×1)'
local function Extras(n)
 local out={}
 for i=1,n do out[i]=(i==7 and LONG) or (i==9 and 'Pipe || Echo ×1 (Common:×1)') or ('Extra Echo '..i..' ×1 (Uncommon:×1)') end
 return out
end
local function Model(shed)
 return {status='ready',level=40,auto=false,cards={{text='Frostwake Sigil (Rare)'}},recommendation='Take Frostwake Sigil.',
  progress={wishlistName='Owner14 plan',total=60,owned=22,missing={'Hollow Bell','Cinder Vow','Gale Rune'},
   shed=shed,toLock={},unknownTomes={}}}
end
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
-- The same without saved data, for steps that save only their own choice.
local function Acts()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local CB={refresh=0,toggle=0}
P.Init({RefreshDisplay=function() CB.refresh=CB.refresh+1;return true end,
 ToggleAuto=function() CB.toggle=CB.toggle+1;return false end,
 RequestFirstDisplay=function() return true end})
local function Said(fn)
 local lines,real={},print
 print=function(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end lines[#lines+1]=table.concat(t,' ') end
 local ok,err=pcall(fn)
 print=real
 return lines,ok,err
end
local function Plain(t) return V.Plain(t or '') end
local function Find(rows,text,prefix)
 for _,r in ipairs(rows or {}) do
  local t=type(r.text)=='string' and Plain(r.text) or ''
  if (prefix and t:sub(1,#text)==text) or t==text then return r end
 end
end
-- A row at the top level or one list down (the same stock dropdown levels).
local function Reach(top,text)
 local row=Find(top,text)
 if row then return row,'top' end
 for _,r in ipairs(top) do
  if type(r.menuList)=='table' then local sub=Find(r.menuList,text);if sub then return sub,Plain(r.text) end end
 end
end
local function Click(row) return row.func(row,row.arg1,row.arg2) end
local function Spy(owner,key,fn)
 local real=owner and owner[key]
 local s={n=0,args={}}
 if owner then owner[key]=function(...) s.n=s.n+1;s.args[s.n]={...};return true end end
 local ok,err=pcall(fn)
 if owner then owner[key]=real end
 if not ok then error(err,0) end
 return s
end
local function Banner() return NexusPanel._pauseBanner end
local function BannerShown() local b=Banner();return b~=nil and b:IsShown() and NexusPanel:IsShown() end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
C.setup(type(REAL_PAUSE)=='table' and type(REAL_PAUSE.Resume)=='function','fixture: the real core/SessionPause owner is loaded')
Nexus.DisableOrdinaryAutomation()
P.Show()
C.setup(P.Render(Model(Extras(41)))==true and NexusPanel:IsShown(),'fixture: the panel renders and shows')

C.scenario('P1 paused banner: real Resume button, once, through the session pause',function()
 Nexus.SessionPause=REAL_PAUSE
 if REAL_PAUSE.IsPaused() then REAL_PAUSE.Resume() end
 P.Render(Model(Extras(41)))
 C.guard(not REAL_PAUSE.IsPaused(),'P1: fixture: not paused at start')
 C.expect(Banner()==nil or not Banner():IsShown(),'P1: no banner while not paused')
 local autoBefore=Nexus.RecomputeStats().autoEnabled==true
 local saved=F.Serialize(NexusDB)
 C.setup(P.PauseNexus()==true and REAL_PAUSE.IsPaused(),'P1: fixture: Pause through the panel route is confirmed by the owner')
 C.guard(F.Serialize(NexusDB)==saved,'P1: the pause is memory only (no saved data written)')
 local b=Banner()
 C.expect(BannerShown(),'P1: a confirmed pause shows the paused banner')
 C.expect(b and Plain(b.title and b.title:GetText()):find('paused',1,true)~=nil,'P1: the banner says paused',b and b.title and b.title:GetText())
 C.expect(b and b.resume and b.resume:IsShown() and b.resume:IsEnabled(),'P1: its Resume button is shown and enabled')
 C.expect(b and Plain(b.resume and b.resume:GetText())=='Resume','P1: the button reads Resume')
 -- The banner stands outside the panel's own box: above, or below at the top of the screen.
 if b then
  local point,rel,relPoint=b:GetPoint(1)
  C.expect(rel==NexusPanel and ((point=='BOTTOMLEFT' and relPoint=='TOPLEFT') or (point=='TOPLEFT' and relPoint=='BOTTOMLEFT')),
   'P1: the banner is anchored outside the panel box, not over its layout',tostring(point)..'/'..tostring(relPoint))
  C.expect(b:GetWidth()==NexusPanel:GetWidth() and b:GetHeight()>=30,'P1: the banner spans the panel width',b:GetWidth()..'x'..b:GetHeight())
 end
 -- Real dispatch: count the owner's Resume while it still runs.
 local resumes=0
 REAL_PAUSE.Resume=(function(real) return function(...) resumes=resumes+1;return real(...) end end)(REAL_PAUSE.Resume)
 local before=Effects()
 local cb={refresh=CB.refresh,toggle=CB.toggle}
 if b and b.resume then b.resume:Click() end
 C.expect(resumes==1 and not REAL_PAUSE.IsPaused(),'P1: one click resumes once through Nexus.SessionPause',resumes)
 C.expect(not BannerShown(),'P1: the banner goes on the redraw')
 C.expect(resumes==1 and not Plain(NexusPanel._contextTitle:GetText()):find('paused',1,true),'P1: after Resume the title no longer says paused')
 C.guard((Nexus.RecomputeStats().autoEnabled==true)==autoBefore and CB.toggle==cb.toggle,'P1: Resume keeps the Auto selection; no Auto toggle')
 C.guard(Effects()==before,'P1: Resume sends, saves and spends nothing',Effects())
 -- A stale click on the hidden button resumes nothing.
 if b and b.resume then b.resume.enabled=true;b.resume:Click() end
 C.expect(resumes==1,'P1: a stale click after the pause ended calls no Resume',resumes)
 P.PauseNexus()
 C.expect(BannerShown(),'P1: pausing again shows the banner again')
 -- Passive routes keep working while paused.
 local list=P.ShowExtraList and P.ShowExtraList()
 C.expect(list~=nil and _G.NexusExtraCopiesList and _G.NexusExtraCopiesList:IsShown(),'P1: the complete extra list opens while paused')
 if _G.NexusExtraCopiesList then _G.NexusExtraCopiesList:Hide() end
 if b and b.resume then b.resume:Click() end
 C.expect(resumes==2 and not REAL_PAUSE.IsPaused(),'P1: the second Resume is again one call',resumes)
end)

C.scenario('P2 unknown, failure, no API, reload and hide while paused',function()
 local real=REAL_PAUSE
 for _,case in ipairs({{'a Status that throws',function() error('x') end},{'a malformed Status',function() return {paused='yes',epoch=-1} end}}) do
  local resumes=0
  Nexus.SessionPause={IsPaused=function() return true end,Status=case[2],Pause=function() end,
   Resume=function() resumes=resumes+1 end}
  P.Render(Model(Extras(41)))
  local b=Banner()
  C.expect(BannerShown() and b._nexusState=='unknown','P2: '..case[1]..' shows the banner as unknown',b and b._nexusState)
  C.expect(b and Plain(b.title:GetText()):find('cannot be read',1,true)~=nil,'P2: '..case[1]..': the banner says it cannot be read')
  C.expect(b and not b.resume:IsShown() and not b.resume:IsEnabled(),'P2: '..case[1]..': no Resume is offered')
  if b then b.resume.enabled=true;b.resume:Click() end
  if P.ResumeFromBanner then P.ResumeFromBanner() end
  C.expect(resumes==0,'P2: '..case[1]..': nothing resumes an unconfirmed pause',resumes)
  C.guard(not Plain(NexusPanel._contextTitle:GetText()):find('paused',1,true),'P2: '..case[1]..': the title claims no pause either way')
 end
 -- A Resume the owner refuses is reported and the banner stays.
 Nexus.SessionPause=real
 real.Pause()
 local saveResume=real.Resume
 real.Resume=function() error('owner failed') end
 P.Render(Model(Extras(41)))
 local said=Said(function() Banner().resume:Click() end)
 C.expect(table.concat(said,' '):find('did not resume',1,true)~=nil,'P2: a failed Resume says it did not resume',table.concat(said,' '))
 C.expect(BannerShown() and real.IsPaused(),'P2: after a failed Resume the banner still shows the pause')
 real.Resume=saveResume
 -- Hide and reopen while paused (item 8 with item 1).
 if P.HideByPlayer then P.HideByPlayer() else P.Hide() end
 C.guard(not NexusPanel:IsShown() and not Banner():IsVisible(),'P2: hiding while paused hides the panel and its banner')
 P.Show()
 C.guard(NexusPanel:IsShown() and real.IsPaused(),'P2: the panel reopens while paused')
 C.expect(BannerShown(),'P2: the banner is back with the panel')
 -- No API: no banner.
 Nexus.SessionPause=nil
 P.Render(Model(Extras(41)))
 C.expect(not BannerShown(),'P2: a build without the control shows no banner')
 Nexus.SessionPause=real
 -- Reload: the pause is memory only, so a module reload starts unpaused.
 real.Pause()
 local saved=F.Serialize(NexusDB)
 C.guard(not saved:find('session_pause',1,true) and not saved:find('sessionPause',1,true),'P2: the pause is not in saved data')
 H=F.Reload(function(h) F.OrbService(h) end)
 P=Nexus.Panel
 REAL_PAUSE=Nexus.SessionPause
 P.Init({RefreshDisplay=function() CB.refresh=CB.refresh+1;return true end,
  ToggleAuto=function() CB.toggle=CB.toggle+1;return false end,RequestFirstDisplay=function() return true end})
 Nexus.DisableOrdinaryAutomation()
 P.Show()
 C.setup(P.Render(Model(Extras(41)))==true,'P2: fixture: the reloaded panel renders')
 C.expect(not REAL_PAUSE.IsPaused() and not BannerShown(),'P2: after reload Nexus is unpaused and shows no banner')
end)

C.scenario('O1 Options: shorter, one coach entry, every distinct route reachable and opened once',function()
 local before=Effects()
 local top=P.MoreMenuItems(NexusPanel._menuBtn)
 C.guard(Effects()==before,'O1: building the menu changes nothing',Effects())
 print('OBSERVED','O1 top-level rows',#top)
 -- At f8cce3f the top level had 32 rows (seven titles); a known-good
 -- literal from that pin, not a recomputation.
 C.expect(#top<=24,'O1: the top level is shorter (32 rows at f8cce3f)',#top)
 C.expect(Find(top,'Help / Getting Started')==nil,'O1: the duplicate coach entry is gone')
 C.expect(Find(top,'Also on the panel footer')==nil,'O1: the footer duplicates no longer fill the top level')
 local setup=Find(top,'Setup / Welcome')
 C.guard(setup~=nil and type(setup.func)=='function','O1: the coach keeps its Setup / Welcome entry at the top level')
 for _,label in ipairs({'Questions (FAQ)','Auto explained (full details)','Open Settings...','Reset Panel Position','Hide Nexus Panel'}) do
  local row=Find(top,label)
  C.guard(row~=nil and type(row.func)=='function','O1: '..label..' stays a direct choice')
 end
 local routes={
  {'Reference (full manual)',Nexus.Help,'Show','start'},{'Setup information (read only)',Nexus.QuickStart,'ShowSetup'},
  {'Setup checklist and status',Nexus.QuickStart,'ShowChecklist'},{'Support report...',Nexus.SupportReportUI,'Show'},
  {'Log viewer...',Nexus.LogViewer,'Show'},{'Orbs / Lost Memories',Nexus.OrbPanel,'Show'},
  {'Wishlist Editor',Nexus.WishlistEditor,'Show'},{'Questions (FAQ)',Nexus.Help,'Show','faq'},
  {'Auto explained (full details)',Nexus.Help,'Show','rolling'},{'Setup / Welcome',Nexus.GuidedSetupUI,'Show'}}
 for _,r in ipairs(routes) do
  local row,where=Reach(top,r[1])
  C.expect(row~=nil and type(row.func)=='function','O1: '..r[1]..' is reachable ('..tostring(where)..')')
  if row and type(row.func)=='function' then
   local spy=Spy(r[2],r[3],function() Click(row) end)
   C.expect(spy.n==1 and (r[4]==nil or spy.args[1][1]==r[4]),'O1: '..r[1]..' opens its own window once',spy.n)
  end
 end
 local more=Find(top,'More help and windows')
 C.expect(more and more.hasArrow and type(more.menuList)=='table','O1: the optional windows are grouped one list down')
 C.guard(Effects()==before,'O1: every route opened, nothing acted, sent or saved',Effects())
end)

C.scenario('O2 setting rows add their current value; ticks only on current choices',function()
 local top=P.MoreMenuItems(NexusPanel._menuBtn)
 local function Row(prefix) return Find(top,prefix,true) end
 local dps=Row('Show DPS records') or Row('Hide DPS records')
 C.expect(dps~=nil and Plain(dps.text)=='Show DPS records (now hidden)','O2: the DPS row says what a click does and that they are hidden now',dps and dps.text)
 if dps then
  Click(dps)
  local again=Find(P.MoreMenuItems(NexusPanel._menuBtn),'Hide DPS records',true)
  C.expect(again and Plain(again.text)=='Hide DPS records (now shown)','O2: after the click it says hide, shown now',again and again.text)
  if again then Click(again) end
 end
 -- No action row (a label that begins with a verb) carries a tick.
 local ticked={}
 local function Walk(rows)
  for _,r in ipairs(rows) do
   local t=Plain(r.text)
   for _,verb in ipairs({'Show ','Hide ','Use ','Enable ','Disable ','Open ','Reset ','Pause ','Resume ','Larger ','Smaller '}) do
    if t:sub(1,#verb)==verb and (r.checked==true or (r.notCheckable~=true and not r.isTitle)) then ticked[#ticked+1]=t end
   end
   if type(r.menuList)=='table' and not t:find('^Appearance') then Walk(r.menuList) end
  end
 end
 Walk(top)
 C.guard(#ticked==0,'O2: no tick or checkbox beside an action',table.concat(ticked,', '))
 local hud=Row('Use Server Difficulty / Soul Ash HUD') or Row('Use Nexus Difficulty / Soul Ash HUD')
 C.expect(hud~=nil and (Plain(hud.text):find('(now: ',1,true)~=nil or (hud.disabled==true and Plain(hud.text):find('(game HUD not detected)',1,true)~=nil)),
  'O2: the HUD row says which HUD is in use, or that the game HUD is not detected',hud and hud.text)
 -- With a detected game HUD it names the one in use (ServerStatus as a boundary double).
 local SS=Nexus.ServerStatus
 local real={SS.IsDetected,SS.IsUsingNexusHud,SS.SetMode}
 local modes={}
 SS.IsDetected=function() return true end
 SS.IsUsingNexusHud=function() return true end
 SS.SetMode=function(m) modes[#modes+1]=m end
 local live=P.HudModeMenuItem()
 C.expect(Plain(live.text)=='Use Server Difficulty / Soul Ash HUD (now: Nexus)' and not live.disabled,'O2: the HUD row: switch to Server, Nexus now',live.text)
 Click(live)
 C.expect(#modes==1 and modes[1]=='server','O2: its click asks the HUD owner once for the server HUD',table.concat(modes,','))
 SS.IsDetected,SS.IsUsingNexusHud,SS.SetMode=real[1],real[2],real[3]
 local U=Nexus.Updates
 local notices=Row('Update notices: ')
 C.expect(notices and notices.hasArrow and type(notices.menuList)=='table','O2: Update notices is one row with its choices inside',notices and notices.text)
 if notices and type(notices.menuList)=='table' then
  local on=U.IsEnabled()
  C.expect(Plain(notices.text):find(on and 'Update notices: on' or 'Update notices: off',1,true)==1,'O2: its label says the current state',notices.text)
  local function Sub(t) return Find(notices.menuList,t) end
  C.expect(Sub('On') and Sub('On').checked==on and Sub('Off') and Sub('Off').checked==(not on),'O2: On/Off ticks the current value')
  local stable=U.Preference()=='stable'
  C.expect(Sub('Stable releases only') and Sub('Stable releases only').checked==stable
   and Sub('Stable releases and test builds').checked==(not stable),'O2: the announced builds tick the current value')
  local en=Spy(U,'SetEnabled',function() Click(Sub('Stable releases only')) end)
  C.expect(en.n==0,'O2: choosing which builds calls no SetEnabled',en.n)
  local pref=Spy(U,'SetPreference',function() Click(Sub('Off')) end)
  C.expect(pref.n==0,'O2: turning notices off calls no SetPreference',pref.n)
 end
 -- The Notices status row is never disabled.
 local status=Row('Version and updates') or Row('Update available') or Row('Newer public test')
 C.expect(status~=nil and not status.disabled and type(status.func)=='function','O2: the version and updates row opens the Releases popup',status and status.text)
end)

C.scenario('X1 the complete extra-copies list',function()
 Nexus.SessionPause=REAL_PAUSE
 P._playDetails=true
 local names=Extras(41)
 C.setup(P.Render(Model(names))==true,'X1: fixture: Details show 41 extra copies')
 local link=NexusPanel._extraAllBtn
 C.expect(link~=nil and link:IsShown(),'X1: the +N more row offers Show all')
 if link then
  local _,row=link:GetPoint(1)
  C.expect(row and Plain(row:GetText())=='+39 more - Show all','X1: the row says how many and Show all',row and row:GetText())
 end
 -- The first hover keeps its bound and points at the complete list.
 local hover=V.TooltipLines(function() NexusPanel._play.extraHit:GetScript('OnEnter')(NexusPanel._play.extraHit) end)
 local listed=0
 for _,l in ipairs(hover) do if l:find('^  • ') then listed=listed+1 end end
 C.guard(listed==25,'X1: the first hover still lists at most 25 names',listed)
 C.expect(table.concat(hover,'\n'):find('Show all',1,true)~=nil,'X1: the hover names the complete-list route')
 local before=Effects()
 local editor=0
 local realEditor=Nexus.WishlistEditor.Show
 Nexus.WishlistEditor.Show=function() editor=editor+1 end
 if link then link:Click() end
 local list=_G.NexusExtraCopiesList
 C.expect(list~=nil and list:IsShown(),'X1: Show all opens the list window')
 if list then
  local body=list.body:GetText() or ''
  local at,missing,order=0,{},true
  for i,name in ipairs(names) do
   local s=body:find(i..'. '..name,1,true)
   if not s then missing[#missing+1]=i elseif s<at then order=false else at=s end
  end
  C.expect(#missing==0 and order,'X1: every one of the 41 names is listed whole and in order','missing '..table.concat(missing,','))
  C.expect(body:find(LONG,1,true)~=nil and body:find('Pipe || Echo',1,true)~=nil,'X1: a long UTF-8 name and an escaped pipe stay whole')
  C.expect(Plain(list.title:GetText())=='Extra rolled copies: 41','X1: the title states the exact count',list.title:GetText())
  C.expect(list.note:GetText():find('Locked copies protected by this Saved Build are never listed',1,true)~=nil,
   'X1: the list keeps the protected-lock exclusion')
  C.expect(list.child:GetHeight()>=41*12,'X1: the scroll child holds a row for every name',list.child:GetHeight())
  local registered=false
  for _,n in ipairs(UISpecialFrames) do if n=='NexusExtraCopiesList' then registered=true end end
  C.expect(registered,'X1: Escape closes it (UISpecialFrames)')
  -- A committed render refreshes an open list; a failed one keeps the last committed model.
  P.Render(Model(Extras(3)))
  C.expect(Plain(list.title:GetText())=='Extra rolled copies: 3','X1: a committed render refreshes the open list',list.title:GetText())
  P.Render(Model({}))
  C.expect(Plain(list.title:GetText())=='Extra rolled copies: none' and (list.body:GetText() or ''):find('No extra rolled copies',1,true),
   'X1: an empty list says none')
  P.Render(Model(nil))
  C.expect(Plain(list.title:GetText())=='Extra rolled copies: not known','X1: a list never received is not known, not none',list.title:GetText())
  list.close:Click()
  C.expect(not list:IsShown(),'X1: Close closes it')
 end
 Nexus.WishlistEditor.Show=realEditor
 C.guard(editor==0,'X1: the list opens no Wishlist Editor')
 C.guard(Effects()==before,'X1: opening, refreshing and closing the list change nothing',Effects())
 P.Render(Model({'Only Echo ×1 (Rare:×1)'}))
 C.expect(not (NexusPanel._extraAllBtn and NexusPanel._extraAllBtn:IsShown()),'X1: a list the face shows whole offers no Show all')
 P._playDetails=false
 P.Render(Model(Extras(41)))
 C.expect(not (NexusPanel._extraAllBtn and NexusPanel._extraAllBtn:IsShown()),'X1: hidden Details hide Show all with the list')
end)

C.scenario('H1 hiding says once how to bring the panel back',function()
 local mm=_G.NexusMinimapButton
 C.setup(mm~=nil,'H1: fixture: the minimap button exists')
 local locks,unlocks=0,0
 mm.LockHighlight=function() locks=locks+1 end
 mm.UnlockHighlight=function() unlocks=unlocks+1 end
 P.Show()
 local acts=Acts()
 local said=Said(function() NexusPanel._closeBtn:Click() end)
 local text=table.concat(said,'\n')
 C.guard(not NexusPanel:IsShown() and NexusDB.panelHidden==true,'H1: X hides the panel and saves the hidden choice')
 C.expect(#said==1 and text:find('/nexus panel',1,true) and text:find('minimap',1,true)
  and text:find('Hiding does not turn Nexus off or change Auto',1,true),'H1: one line says how it comes back',text)
 C.guard(not text:find('type /nexus or',1,true),'H1: the restore command is /nexus panel, not bare /nexus')
 C.expect(locks==1,'H1: the minimap button is lit as the way back',locks)
 local again=Said(function() Click(Find(P.MoreMenuItems(NexusPanel._menuBtn),'Hide Nexus Panel')) end)
 C.expect(#again==0 and locks==1,'H1: hiding an already hidden panel says nothing more',#again)
 mm:GetScript('OnClick')(mm,'LeftButton')
 C.guard(NexusPanel:IsShown() and NexusDB.panelHidden==nil,'H1: the minimap button shows the panel again')
 C.expect(unlocks>=1,'H1: showing the panel clears the cue',unlocks)
 local third=Said(function() Click(Find(P.MoreMenuItems(NexusPanel._menuBtn),'Hide Nexus Panel')) end)
 C.expect(#third==1 and locks==2,'H1: the next deliberate hide says it once again',#third)
 P.Show()
 C.guard(Acts()==acts,'H1: hiding and showing take no action and send nothing',Acts())
 C.guard(Nexus.RecomputeStats().autoEnabled~=true,'H1: Auto stays OFF')
end)

C.scenario('U1 plain version and update words; full Releases address in its box',function()
 local U=Nexus.Updates
 local s=U.Status()
 local id=Nexus.ReleaseIdentity and Nexus.ReleaseIdentity() or {}
 C.guard(s.installed==id.display,'U1: the exact installed build is kept',tostring(s.installed))
 C.guard(s.detail:find('Installed: '..s.installed..' (',1,true)==1,'U1: the detail starts with the exact build, channel and label',s.detail)
 if s.state=='unknown' then
  C.expect(s.menu=='Version and updates: no verified update info','U1: the unknown menu row is plain',s.menu)
  C.expect(s.detail:find('No verified update information',1,true)~=nil,'U1: unknown is said as no verified update information',s.detail)
  local low=s.detail:lower()
  C.guard(not low:find('up to date',1,true) and not low:find('you have the latest',1,true) and not low:find('error',1,true),
   'U1: unknown is never up to date, latest or an error')
 end
 local acts=Acts()
 local saved=F.Serialize(NexusDB)
 H.popup=nil
 P.ShowUpdateStatus()
 local popup=H.popup
 C.setup(popup~=nil and popup.which=='NEXUS_UPDATE_RELEASES','U1: fixture: the popup opens')
 if popup then
  C.guard(popup.editBox:GetText()==U.ReleaseUrl() and U.ReleaseUrl()=='https://github.com/Viscerals/Better-Nexus/releases',
   'U1: the box holds the full canonical Releases address, byte for byte',popup.editBox:GetText())
  C.expect(tostring(popup.frame.text):find('copy this Releases page address',1,true)~=nil
   and tostring(popup.frame.text):find('Installation is manual',1,true)~=nil,'U1: the popup says what to do next and that installation is manual',popup.frame.text)
 end
 C.guard(#H.actions==0 and #H.sent==0,'U1: opening it downloads, sends and starts nothing')
 C.guard(F.Serialize(NexusDB)==saved,'U1: opening the popup writes no saved data')
 U.SetEnabled(false)
 C.expect(U.Status().menu=='Version and updates: notices off','U1: with notices off the row says so',U.Status().menu)
 U.SetEnabled(true)
 C.guard(Acts()==acts,'U1: reading and the notice setter take no action and send nothing',Acts())
end)

C.scenario('F1 footer FAQ shortcut and number explanations',function()
 P.Render(Model(Extras(41)))
 local faq=NexusPanel._faqBtn
 C.expect(faq~=nil and faq:IsShown() and Plain(faq:GetText())=='?','F1: the footer has a ? shortcut')
 if faq then
  local point,rel,relPoint,x=faq:GetPoint(1)
  C.expect(rel==NexusPanel._orbsHubBtn and point=='LEFT' and relPoint=='RIGHT' and x>=8,'F1: it sits after the Orbs hub, a separate target')
  -- Footer row: 10 + 3 hubs + 2 x 10 gaps + gap + ? must stay inside 420 px.
  local hub=NexusPanel._orbsHubBtn:GetWidth()
  C.expect(10+3*hub+20+x+faq:GetWidth()<=420-8,'F1: the hubs and ? fit the 420 px footer',10+3*hub+20+x+faq:GetWidth())
  C.expect(faq:GetWidth()>=22 and faq:GetHeight()>=22,'F1: a 22 px target at least',faq:GetWidth()..'x'..faq:GetHeight())
  local before=Effects()
  local spy=Spy(Nexus.Help,'Show',function() faq:Click() end)
  C.expect(spy.n==1 and spy.args[1][1]=='faq','F1: one click opens Help.Show("faq") once',spy.n)
  local tip=table.concat(V.TooltipLines(function() faq:GetScript('OnEnter')(faq) end),'\n')
  C.expect(tip:find('Questions (FAQ)',1,true) and tip:find('Soul Ash',1,true) and tip:find('Intensity',1,true)
   and tip:find('DPS',1,true),'F1: its hover says where the numbers are explained',tip)
  C.guard(Effects()==before,'F1: opening the FAQ changes nothing')
 end
 -- Header line 1 keeps Auto, Options and Close only (design/current).
 local headerChildren=0
 for _,c in ipairs({NexusPanel:GetChildren()}) do
  local p1={c:GetPoint(1)}
  if c~=faq and c:IsShown() and c:GetObjectType()=='Button' and p1[1]=='TOPRIGHT' and p1[2]==NexusPanel and p1[5]==-P.HeaderSlots().top then
   headerChildren=headerChildren+1
  end
 end
 C.guard(headerChildren<=3,'F1: header line 1 holds no new control',headerChildren)
 -- The difficulty card hover keeps its own facts (item 14 reuses, invents nothing).
 C.guard(P.NUMBERS_HINT==nil or not P.NUMBERS_HINT:find('bonus',1,true),'F1: no generic difficulty bonus meaning is invented')
end)

C.scenario('A1 Auto OFF stays exactly Auto OFF (displayed item 10 excluded)',function()
 P.Render(Model(Extras(41)))
 C.guard(Plain(NexusPanel._autoBtn:GetText())=='Auto OFF','A1: the Auto button reads exactly Auto OFF',NexusPanel._autoBtn:GetText())
 local bad={}
 local function Scan(rows)
  for _,r in ipairs(rows) do
   local t=Plain(r.text)
   -- The excluded proposal is the button's "Auto: Off" form. Readout's own
   -- Automation settings row "Auto: OFF (the Auto button ...)" predates it.
   if t:find('Auto: Off',1,true) or t:find('Auto: On',1,true) then bad[#bad+1]=t end
   if type(r.menuList)=='table' then Scan(r.menuList) end
  end
 end
 Scan(P.MoreMenuItems(NexusPanel._menuBtn))
 for _,line in ipairs(P.AutoSummaryLines()) do if line:find('Auto: Off',1,true) then bad[#bad+1]=line end end
 C.guard(#bad==0,'A1: no menu row or Auto hover renames it to Auto: Off',table.concat(bad,' | '))
end)

Nexus.SessionPause=REAL_PAUSE
Nexus.DisableOrdinaryAutomation()
C.finish('(owner-approved items 1, 2+9, 7, 8, 12, 14, 15 on the panel lane; Auto OFF unchanged; native NOT RUN)')
