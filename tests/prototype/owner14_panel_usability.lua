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
-- P3  item 1 (v9, Root's ruling SPEC-R1; the last scenario of this file):
--     at the compact panel's width both banner texts are whole, wrapped in
--     their room, the strip is as tall as they need, Resume keeps its size
--     and place, and the strip's side of the panel follows its height.
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
-- X2  item 7: an actual failed render (the context header raises) marks an
--     already-open list not current at once, in its title and above the
--     names; the failed candidate never reaches it; the next good render
--     makes it current again; nothing is queried, sent or saved.
-- X4  item 7: on the 640 x 480 floor and ordinary screens, at the default,
--     16 px and double font models, in the listed, stale (after the actual
--     header failure), unknown and empty forms, the window fits the screen;
--     the title, the not-current warning, the X and Close stay pinned and
--     apart; the explanation and every name scroll in one region whose child
--     holds every wrapped line, and scrolling to its end reaches the last.
-- H1  item 8: X and Hide Nexus Panel say once how to bring the panel back and
--     light the minimap button; a repeat hide says nothing; showing clears it.
-- U1  item 12: plain version and update words keep the exact installed build;
--     unknown is "no verified update information", never latest; the popup
--     keeps the full Releases address in its box and starts nothing.
-- U2  review C-06: that box is found by the popup's editBox key or, for a
--     template without it, by the named child "<popup name>EditBox".
-- F1 items 15 and 14: the FAQ is one choice away in Options and opens
--     Help.Show('faq') once; that row's hover says where the numbers are
--     explained; header line 1 stays Auto, Options and Close. Main-panel visual
--     correction: the small "?" these items put after the footer hubs is
--     gone, because the three hubs are one width and span the footer row.
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

C.scenario('X2 a failed panel render marks an open extra list not current, without its failed candidate',function()
 Nexus.SessionPause=REAL_PAUSE
 P._playDetails=true
 local names=Extras(41)
 C.setup(P.Render(Model(names))==true and NexusPanel:IsShown(),'X2: fixture: a good render with 41 extra copies')
 local facts=P.ShowExtraList and P.ShowExtraList()
 local list=_G.NexusExtraCopiesList
 C.setup(list~=nil and list:IsShown() and facts and facts.stale==false,'X2: fixture: the complete list is open and current')
 if not list then return end
 local before=Effects()
 -- The actual apply failure: the context header (ApplyModel) raises.
 local realHeader=P.UpdateContextHeader
 P.UpdateContextHeader=function() error('injected header failure',0) end
 local ok,err=pcall(P.Render,Model({'Failed Candidate Echo ×9 (Epic:×9)'}))
 P.UpdateContextHeader=realHeader
 C.setup(not ok and tostring(err):find('injected header failure',1,true)~=nil,'X2: fixture: that render failed at the header',err)
 C.guard(not NexusPanel:IsShown() and P.ExtraListFacts().stale==true,'X2: the panel hides and its facts say stale')
 local shown=list:IsShown()
 local title=Plain(list.title:GetText())
 local status=Plain(list.status and list.status:GetText())
 local body=list.body:GetText() or ''
 C.expect(not shown or (list._nexusFacts and list._nexusFacts.stale==true),'X2: an open list takes the stale facts at once',
  list._nexusFacts and tostring(list._nexusFacts.stale))
 C.expect(not shown or (title:find('not current',1,true)~=nil and status:find('Not current',1,true)==1
  and list.status:IsShown()),'X2: it says not current in its title and above the names',title..' / '..status)
 C.expect(not body:find('Failed Candidate Echo',1,true),'X2: the failed candidate never reaches the list')
 C.guard(not shown or body:find('41. Extra Echo 41',1,true)~=nil,'X2: it keeps the last committed names, whole')
 C.guard(Effects()==before,'X2: marking it stale queries, sends, saves and spends nothing',Effects())
 -- The next good render makes it current again.
 C.setup(P.Render(Model(Extras(3)))==true,'X2: fixture: the next render succeeds')
 C.expect(list:IsShown() and Plain(list.title:GetText())=='Extra rolled copies: 3' and Plain(list.status:GetText())==''
  and not list.status:IsShown(),'X2: a good render makes the open list current again',list.title:GetText())
 list:Hide()
 P._playDetails=false
end)

C.scenario('X4 the list fits the screen it is on, with every line and its controls reachable',function()
 local G=dofile('tests/prototype/layout_geometry_support.lua')
 local methods=G.RegionMethods()
 local saved={GetStringHeight=methods.GetStringHeight,GetStringWidth=methods.GetStringWidth,
  GetTextWidth=methods.GetTextWidth,GetFont=methods.GetFont}
 local uiW,uiH=UIParent:GetWidth(),UIParent:GetHeight()
 P._playDetails=true
 -- Supported floor (LayoutMetrics.FitToScreen, the Community viewport: 640 x 480)
 -- with the largest text model, and ordinary screens.
 local cases={{640,480,'double'},{640,480,'px16'},{640,480,'default'},{1024,768,'px16'},{1366,768,'double'},{1920,1080,'default'}}
 for _,case in ipairs(cases) do
  local sw,sh,model=case[1],case[2],G.MODELS[case[3]]
  UIParent:SetSize(sw,sh)
  G.UseFont(model)
  for _,form in ipairs({'listed','stale','unknown','empty'}) do
   local why='X4 '..sw..'x'..sh..' '..model.name..' '..form
   if form=='stale' then
    P.Render(Model(Extras(41)));P.ShowExtraList()
    local realHeader=P.UpdateContextHeader
    P.UpdateContextHeader=function() error('injected',0) end
    pcall(P.Render,Model({'Failed Candidate Echo ×9 (Epic:×9)'}))
    P.UpdateContextHeader=realHeader
   else
    P.Render(Model(form=='listed' and Extras(41) or form=='empty' and {} or nil));P.ShowExtraList()
   end
   local list=_G.NexusExtraCopiesList
   if not C.setup(list and list:IsShown(),why..': fixture: the list is open') then break end
   local function R(region) return G.Rect(region,list) end
   local function T(text)
    local r=R(text)
    r[4]=math.max(r[4],r[2]+G.Rows(text:GetText(),text:GetWidth(),model.char)*model.line)
    return r
   end
   local W,Hh=list:GetWidth(),list:GetHeight()
   -- The window itself fits the screen: clamping cannot move a window that is larger than it.
   C.expect(W<=sw and Hh<=sh,why..': the window fits the screen',W..'x'..Hh..' on '..sw..'x'..sh)
   local box,scroll,close,closeX=R(list),R(list.scroll),R(list.close),R(list.closeX)
   print('OBSERVED',why,'window '..W..'x'..Hh,'scroll view '..(scroll[4]-scroll[2]),'child '..list.child:GetHeight())
   local title=T(list.title)
   local status=list.status:IsShown() and T(list.status) or nil
   -- Pinned parts and controls inside the window, apart from the scrolling region.
   C.expect(G.Inside(title,box) and G.Inside(close,box) and G.Inside(closeX,box) and G.Inside(scroll,box),
    why..': title, X, Close and the scrolling region are inside the window',G.Text(title)..' '..G.Text(scroll)..' '..G.Text(close))
   C.expect(title[4]<=(status and status[2] or scroll[2]) and (not status or status[4]<=scroll[2]) and scroll[4]<=close[2]
    and G.Apart(title,closeX),why..': title, status, scrolling region and Close do not overlap',
    G.Text(title)..' '..(status and G.Text(status) or '-')..' '..G.Text(scroll)..' '..G.Text(close))
   C.expect(scroll[4]-scroll[2]>=3*model.line,why..': the scrolling region shows three rows at least',scroll[4]-scroll[2])
   -- The stale warning is never scrolled away: it is pinned and shown whole.
   if form=='stale' then
    C.expect(status~=nil and Plain(list.status:GetText()):find('Not current',1,true)==1 and G.Inside(status,box),
     why..': the not-current warning is pinned in view')
    C.guard(not (list.body:GetText() or ''):find('Failed Candidate',1,true),why..': the failed candidate never reaches the list')
   else
    C.expect(status==nil,why..': a current list shows no warning')
   end
   -- Everything else scrolls: the note and every name sit in the scroll child,
   -- and the scroll child is as tall as their wrapped rows, so scrolling to the
   -- end reaches the last line.
   local child=list.child
   local inChild=list.note:GetParent()==child and list.body:GetParent()==child
   C.expect(inChild,why..': the note and the names scroll together')
   local need=0
   for _,text in ipairs({list.note,list.body}) do
    if (text:GetText() or '')~='' then need=need+G.Rows(text:GetText(),text:GetWidth(),model.char)*model.line end
   end
   C.expect(child:GetHeight()>=need,why..': the scroll child holds every wrapped line',child:GetHeight()..' < '..need)
   C.expect(list.body:GetWidth()<=scroll[3]-scroll[1] and list.note:GetWidth()<=scroll[3]-scroll[1],
    why..': the scrolled text is no wider than its region',list.body:GetWidth()..'/'..(scroll[3]-scroll[1]))
   local range=math.max(0,child:GetHeight()-(scroll[4]-scroll[2]))
   list.scroll:SetVerticalScroll(range)
   local bottom=R(child)
   C.expect(bottom[4]<=scroll[4]+0.5,why..': scrolled to the end, the last line is in the region',G.Text(bottom)..' / '..G.Text(scroll))
   list.scroll:SetVerticalScroll(0)
   if form=='listed' or form=='stale' then
    local body=list.body:GetText() or ''
    local missing=0
    for i,name in ipairs(Extras(41)) do if not body:find(i..'. '..name,1,true) then missing=missing+1 end end
    C.guard(missing==0,why..': every name, count and quality is listed whole',missing)
   end
   list.close:Click()
   C.guard(not list:IsShown(),why..': Close closes it')
  end
 end
 for key,fn in pairs(saved) do methods[key]=fn end
 UIParent:SetSize(uiW,uiH)
 P._playDetails=false
 P.Render(Model(Extras(41)))
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

-- U2 (review C-06): the Releases box under three popup templates. A
-- template that gives the popup no editBox key exposes its box only as the
-- named child "<popup name>EditBox"; the address is put there, highlighted
-- and focused. A popup with the key keeps using it and a same-named child is
-- untouched; a named child without the EditBox methods, or no box at all,
-- raises nothing. Synthetic popup frames
-- only: which form the build-12340 StaticPopup template provides is NOT_RUN,
-- and no clipboard or desktop action is taken.
C.scenario('U2 the Releases address reaches the popup box with or without its editBox key',function()
 local U=Nexus.Updates
 local keep=H.popupPool[1]
 local acts,saved=Acts(),F.Serialize(NexusDB)
 local function Box(name,parent)
  local box=CreateFrame('EditBox',name,parent)
  box.highlights=0
  box.HighlightText=function(self) self.highlights=self.highlights+1 end
  return box
 end
 local ok,err=pcall(function()
  -- Legacy: no editBox key, only the named child.
  local legacy=CreateFrame('Frame','NexusTestLegacyPopup1',UIParent)
  local named=Box('NexusTestLegacyPopup1EditBox',legacy)
  H.popupPool[1]=legacy
  P.ShowUpdateStatus()
  C.setup(legacy.editBox==nil and H.popup~=nil and H.popup.frame==legacy,'U2: fixture: the legacy popup has no editBox key')
  C.expect(named:GetText()==U.ReleaseUrl() and named:GetText()=='https://github.com/Viscerals/Better-Nexus/releases'
   and named.highlights==1 and named:HasFocus(),
   'U2: legacy: the named child holds the full address, highlighted and focused',named:GetText())
  -- Modern: the key wins over a same-named child.
  local modern=CreateFrame('Frame','NexusTestModernPopup1',UIParent)
  modern.editBox=Box(nil,modern)
  local other=Box('NexusTestModernPopup1EditBox',modern)
  H.popupPool[1]=modern
  P.ShowUpdateStatus()
  C.expect(modern.editBox:GetText()==U.ReleaseUrl() and modern.editBox.highlights==1 and modern.editBox:HasFocus()
   and other:GetText()=='' and other.highlights==0 and not other:HasFocus(),
   'U2: modern: the editBox key gets the address; a named child is not touched',other:GetText())
  -- Malformed: a named child without the EditBox methods is not used, and
  -- the show does not raise.
  local malformed=CreateFrame('Frame','NexusTestMalformedPopup1',UIParent)
  _G.NexusTestMalformedPopup1EditBox={}
  H.popupPool[1]=malformed
  local okMalformed,shownMalformed=pcall(P.ShowUpdateStatus)
  C.expect(okMalformed and shownMalformed==true and next(_G.NexusTestMalformedPopup1EditBox)==nil,
   'U2: a named child without SetText, HighlightText and SetFocus is left alone and nothing raises',tostring(shownMalformed))
  _G.NexusTestMalformedPopup1EditBox=nil
  -- Neither: nothing to fill, and the show does not raise.
  H.popupPool[1]=CreateFrame('Frame',nil,UIParent)
  local shown=P.ShowUpdateStatus()
  C.expect(shown==true and H.popup~=nil,'U2: without any box the popup still opens and nothing raises')
 end)
 H.popupPool[1]=keep
 C.setup(ok,'U2: fixture: the scenario ran',err)
 C.guard(Acts()==acts and F.Serialize(NexusDB)==saved,'U2: opening it takes no action, sends and writes nothing',Acts())
end)

C.scenario('F1 the FAQ from Options, no footer shortcut, and number explanations',function()
 P.Render(Model(Extras(41)))
 -- The visual corrections of the main panel:
 -- the three footer hubs are one width and span the footer row, so the small
 -- "?" that stood after them is gone. Help's FAQ stays one choice away in
 -- Options, through the route the "?" shared (Help.Show("faq")), and what the
 -- "?" hover said about the panel's numbers (item 14) is on that row's hover.
 -- The checks that stood here asked for the "?" itself (shown, after the Orbs
 -- hub, inside the 420 px footer, a 22 px target, one click to the FAQ, its
 -- hover); they are replaced by the checks of the route that remains and of
 -- the row the "?" left, not relaxed.
 local faq=NexusPanel._faqBtn
 C.expect(faq==nil or not faq:IsShown(),'F1: no "?" stands in the footer')
 -- Footer row: the left inset, three hubs of one width and the two gaps
 -- between them reach the right inset exactly (read from the hubs' own
 -- anchors, as before). The approved compact panel: the insets are the
 -- draft's 7 pixels, 5 units in the 284-unit reference panel, and the hubs
 -- its 6 pixels apart, so the row is 5 + 3 x 88 + 5 + 5 = 279 (it was 8 + 3
 -- x 130 + 7 + 7 = 412 in the 420-unit panel, between 8-unit insets).
 local hubs=NexusPanel._footerButtons
 local hub=hubs.plan:GetWidth()
 local _,_,_,left=hubs.plan:GetPoint(1)
 local _,_,_,first=hubs.explore:GetPoint(1)
 local _,_,_,second=hubs.orbs:GetPoint(1)
 local inset=math.floor(7*284/420+0.5)
 C.expect(hubs.explore:GetWidth()==hub and hubs.orbs:GetWidth()==hub and NexusPanel:GetWidth()==284 and inset==5
  and left==inset and first>0 and second>0 and math.abs(first-second)<=1
  and left+3*hub+first+second==NexusPanel:GetWidth()-inset,
  'F1: the three hubs are one width and span the footer between its insets, the draft\'s 7 pixels',
  tostring(left)..' + 3 x '..tostring(hub)..' + '..tostring(first)..' + '..tostring(second)..' in '..tostring(NexusPanel:GetWidth()))
 -- The route that remains: Options > Questions (FAQ), a direct choice (O1).
 local row=Find(P.MoreMenuItems(NexusPanel._menuBtn),'Questions (FAQ)')
 C.guard(row~=nil and type(row.func)=='function','F1: Questions (FAQ) is a direct choice in Options')
 if row and type(row.func)=='function' then
  local before=Effects()
  local spy=Spy(Nexus.Help,'Show',function() Click(row) end)
  C.guard(spy.n==1 and spy.args[1][1]=='faq','F1: one click opens Help.Show("faq") once',spy.n)
  local tip=Plain(row.tooltipTitle)..'\n'..Plain(row.tooltipText)
  C.expect(tip:find('Soul Ash',1,true) and tip:find('Intensity',1,true) and tip:find('DPS',1,true),
   'F1: that row\'s hover says where the numbers are explained',tip)
  C.guard(Effects()==before,'F1: opening the FAQ changes nothing')
 end
 -- Header line 1 keeps Auto, Options and Close only (design/current).
 local headerChildren=0
 for _,c in ipairs({NexusPanel:GetChildren()}) do
  local p1={c:GetPoint(1)}
  if c:IsShown() and c:GetObjectType()=='Button' and p1[1]=='TOPRIGHT' and p1[2]==NexusPanel and p1[5]==-P.HeaderSlots().top then
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

-- v9, Root's ruling SPEC-R1 on item 1's paused banner: "wrap whole text at
-- existing owned fonts, measure required height, preserve Resume
-- action/position/clamp and existing pause semantics. No fixed36 clipping,
-- shortening or hover-only substitute." The strip is as wide as the panel,
-- which the approved compact panel made 284 units at normal text (it was
-- 420), so its second text no longer fits one line beside Resume there.
-- Stated here from the strip's own design and the font model, not read from
-- the panel's code: each text has the strip's width less its two 8-unit
-- sides and, while Resume is offered, the button's 82 units (its 76 and its
-- 6-unit inset); it wraps there (layout_geometry_support's word wrap, G.Rows)
-- in a box as tall as its lines, never under the 16-unit line it had; while
-- both are one such line the strip is the 36 units it was, and otherwise it
-- is both boxes with 4 units above them, 2 between them and its 2-unit edge
-- line under them. Resume keeps its 76 x 22 size at the strip's right, 6
-- units in, in its middle, and the strip's side of the panel (above while
-- the screen holds it there, else below) follows the height it now has.
-- EXPECT fails at eef1608f: there each text was one 16-unit no-wrap line in
-- a fixed 36-unit strip, shortened by the client where it did not fit.
-- GUARD: the two reviewed texts, the strip's width, Resume's size and place,
-- and that showing the banner takes no action. Offline font models only;
-- the native wrap and glyph widths are NOT RUN. Runs last, so every
-- scenario above runs exactly as before.
C.scenario('P3 the paused banner shows both its texts whole at the compact panel\'s width, in a strip as tall as they need',function()
 local G=dofile('tests/prototype/layout_geometry_support.lua')
 local methods=G.RegionMethods()
 local saved={GetStringHeight=methods.GetStringHeight,GetStringWidth=methods.GetStringWidth,
  GetTextWidth=methods.GetTextWidth,GetFont=methods.GetFont}
 local TEXTS={paused={'Nexus is paused for this session.','Auto, Orb actions, sharing and DPS recording wait.'},
  unknown={'Pause state cannot be read right now.','Nexus may or may not be paused.'}}
 local unreadable={IsPaused=function() return true end,Status=function() error('x') end,Pause=function() end,Resume=function() end}
 local before=Acts()
 local grown,wrapped=0,false
 local ok,err=pcall(function()
  P.Show()
  for _,name in ipairs({'default','px16','double'}) do
   local model=G.MODELS[name]
   G.UseFont(model)
   for _,state in ipairs({'paused','unknown'}) do
    local why='P3 '..model.name..', '..state
    if state=='paused' then
     Nexus.SessionPause=REAL_PAUSE
     if not REAL_PAUSE.IsPaused() then P.PauseNexus() end
    else
     Nexus.SessionPause=unreadable
    end
    if not C.setup(P.Render(Model(Extras(41)))==true and BannerShown() and Banner()._nexusState==state,
     why..': fixture: the banner is shown in this state') then return end
    local b=Banner()
    local width=NexusPanel:GetWidth()
    local room=width-16-(state=='paused' and 82 or 0)
    C.guard(b:GetWidth()==width and Plain(b.title:GetText())==TEXTS[state][1] and Plain(b.note:GetText())==TEXTS[state][2],
     why..': the strip spans the panel and holds its two reviewed texts',b:GetWidth()..' of '..width)
    -- Each text: its room's width, and a box as tall as the font model
    -- itself measures its wrapped lines there (never under 16 units), which
    -- holds every line this file's own word wrap gives it.
    local boxes,lines={},{}
    for i,label in ipairs({b.title,b.note}) do
     lines[i]=G.Rows(TEXTS[state][i],room,model.char)
     boxes[i]=math.max(16,math.ceil(label:GetStringHeight() or 0))
     C.expect(label:GetWidth()==room and label:GetHeight()==boxes[i] and label:GetHeight()>=lines[i]*model.line-0.5,
      why..': '..(i==1 and 'the first' or 'the second')..' text has its room\'s width and a box as tall as its wrapped lines',
      tostring(label:GetWidth())..'x'..tostring(label:GetHeight())..' for '..lines[i]..' line(s) of '..model.line..' in '..room)
    end
    if lines[1]>1 or lines[2]>1 then wrapped=true end
    local want=(boxes[1]+boxes[2]>32) and math.max(36,boxes[1]+boxes[2]+8) or 36
    if want>36 then grown=grown+1 end
    C.expect(b:GetHeight()==want and (want==36 or 4+boxes[1]+2+boxes[2]==b:GetHeight()-2),
     why..': the strip is 36 units while each text is one 16-unit line, else as tall as both texts with 4 above, 2 between and its 2-unit edge under them',
     tostring(b:GetHeight())..' of '..want..' for '..boxes[1]..' + '..boxes[2])
    if state=='paused' then
     local point,rel,relPoint,x,y=b.resume:GetPoint(1)
     C.guard(b.resume:IsShown() and b.resume:IsEnabled() and Plain(b.resume:GetText())=='Resume'
      and b.resume:GetWidth()==76 and b.resume:GetHeight()==22 and point=='RIGHT' and rel==b and relPoint=='RIGHT' and x==-6 and y==0,
      why..': Resume keeps its size and its place at the strip\'s right, 6 units in, in its middle',
      tostring(point)..'/'..tostring(relPoint)..' '..tostring(x)..','..tostring(y))
     C.expect(b.resume:GetHeight()<=b:GetHeight() and 8+b.title:GetWidth()<=width-6-b.resume:GetWidth()
      and 8+b.note:GetWidth()<=width-6-b.resume:GetWidth(),
      why..': both texts end before Resume, which stays inside the strip',room..' of '..width)
    else
     C.guard(not b.resume:IsShown() and not b.resume:IsEnabled(),why..': an unreadable pause offers no Resume')
    end
    -- The strip's side of the panel follows the height it has now: a panel
    -- whose top leaves a 36-unit strip exactly its room above, and one that
    -- leaves this strip exactly its room. (The harness gives every region
    -- one top and one scale; the two tops are set here and removed again.)
    local uiTop=600
    rawset(UIParent,'GetTop',function() return uiTop end)
    for _,top in ipairs({uiTop-36-2,uiTop-b:GetHeight()-2}) do
     rawset(NexusPanel,'GetTop',function() return top end)
     local side=P.PlacePauseBanner()
     local point,rel,relPoint,x,y=b:GetPoint(1)
     local above=top+want+2<=uiTop
     C.expect(side==(above and 'above' or 'below') and rel==NexusPanel and x==0 and b:GetHeight()==want
      and ((above and point=='BOTTOMLEFT' and relPoint=='TOPLEFT' and y==2)
       or (not above and point=='TOPLEFT' and relPoint=='BOTTOMLEFT' and y==-2)),
      why..': the strip stands '..(above and 'above' or 'below')..' a panel whose top is '..top..' under a screen top of '..uiTop..', by its own '..want..' units',
      tostring(side)..' '..tostring(point)..'/'..tostring(relPoint)..' '..tostring(y))
    end
    rawset(NexusPanel,'GetTop',nil);rawset(UIParent,'GetTop',nil)
    P.PlacePauseBanner()
    if name=='default' and state=='paused' then
     C.setup(width==284 and lines[2]>=2 and want>36,
      why..': fixture: at normal text the 284-unit panel leaves the second text less than its one line needs, so it wraps and the strip grows',
      width..' wide, '..lines[2]..' line(s), strip '..want)
    end
   end
  end
 end)
 Nexus.SessionPause=REAL_PAUSE
 if REAL_PAUSE.IsPaused() then REAL_PAUSE.Resume() end
 for key,fn in pairs(saved) do methods[key]=fn end
 rawset(NexusPanel,'GetTop',nil);rawset(UIParent,'GetTop',nil)
 P.Render(Model(Extras(41)))
 C.setup(ok,'P3: fixture: the scenario ran',err)
 C.setup(wrapped and grown>0,'P3: fixture: a text needed more than one line and the strip grew for it in at least one case',grown)
 C.expect(not REAL_PAUSE.IsPaused() and not BannerShown(),'P3: after Resume there is no banner')
 C.guard(Acts()==before,'P3: showing, measuring and placing the banner takes no action, sends nothing and leaves Auto as it was',Acts())
end)

Nexus.SessionPause=REAL_PAUSE
Nexus.DisableOrdinaryAutomation()
C.finish('(owner-approved items 1, 2+9, 7, 8, 12, 14, 15 on the panel lane; Auto OFF unchanged; native NOT RUN)')
