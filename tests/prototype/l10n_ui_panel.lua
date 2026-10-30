-- Full UI localization, panel family (ui/Panel.lua): display-boundary
-- coverage of the main HUD through the real TOC boot and real entry points.
-- PSEUDO  a session-start pseudo pack built from the real English catalog:
--         every code-owned word the panel shows (setup, restoring, progress
--         with Details open, offer cards with Auto OFF/ON, waiting, paused,
--         completed, DPS records, the extra-copies list, the paused banner),
--         every menu level built by its real builder (Options, More help and
--         windows, Automation, Language, Plan/Explore hubs, Session, Panel
--         size, HUD, Update notices), every hover reached through its real
--         OnEnter, the chat lines and the Releases popup passed the seam.
--         Text produced by other owners is removed only as the exact bytes
--         that owner's own API returns in this session (listed, narrow).
--         Diagnostics record no fallback, wrong kind or bad argument.
-- PASSIVE rendering, hovering and building menus change no saved table,
--         send nothing and take no action.
-- TEMPLATE unknown count shows "?", zero "0", long and non-ASCII names are
--         inserted verbatim.
-- ENGLISH a plain boot shows the exact English bytes for representative keys.
-- LONG    the long pseudo mode renders the densest state and the menus.
-- MISSING a pack without some panel entries shows those in exact English.
-- Synthetic offline evidence only: no glyph, font, layout or native claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end

local LONGNAME='Ünïcødé Flamebringer of the Very Long Ember Name That Never Fits'
-- Fixture data shown verbatim (names, never translated).
local DATA={'Owner14 plan','Frostwake Sigil','Hollow Bell','Cinder Vow','Gale Rune','Extra Echo','Locked Echo',
 'Tome Echo','Pipe','Echo',LONGNAME,'Pseudo','English','Deutsch','Fran','Espa','Polski','Portugu','Русский',
 'Uncommon','Common','Rare','Epic','HC3','Normal','Pinned Sigil','Callboard Hunt','Slay','wolves','again','thrice'}

local function Model(o)
 o=o or {}
 local m={status='ready',level=40,auto=o.auto==true,character='Testchar',
  cards=o.cards or {},recommendation=o.recommendation or '',
  progress={wishlistName=o.noName and nil or 'Owner14 plan',total=o.total or 60,owned=o.owned or 22,
   missing={'Hollow Bell ×1 (Rare:×1)','Cinder Vow ×2 (Epic:×2)','Gale Rune ×1 (Rare:×1)'},
   shed=o.shed or {'Extra Echo 1 ×1 (Uncommon:×1)','Extra Echo 2 ×1 (Uncommon:×1)','Extra Echo 3 ×1 (Common:×1)'},
   toLock=o.toLock or {'Locked Echo A','Locked Echo B','Locked Echo C'},
   unknownTomes=o.unknownTomes or {'Tome Echo A','Tome Echo B'},activeSlot=o.slot or 2,activeSlotName='Pinned Sigil',
   performance=o.performance},
  assignment=o.assignment or {state='ready'},
  serverStatus=o.serverStatus,bestDps=o.bestDps,paused=o.paused,effective=o.effective}
 for k,v in pairs(o.extra or {}) do m[k]=v end
 return m
end
local PERF={dummy={personal={dps=4812,duration=42},global={dps=9100,player='Otherplayer'}},lk={personal={dps=2200},global=nil}}
local BEST={dummy={dps=4812},lk={dps=2200},info={dps=4812,category='dummy',title='Pinned Sigil'}}
local SS={tier='HC3',mode='Hardcore',ash='12,345',gain='x2',intensity=120,intensityMax=500,intensityLevel=2}
local CARDS={{text='Frostwake Sigil (Rare)'},{text='Hollow Bell (Epic)'},{text='Gale Rune (Rare)'}}

-- Every text under a menu item list, recursively (text and hover).
local function MenuTexts(items,out)
 out=out or {}
 for _,item in ipairs(items or {}) do
  for _,field in ipairs({'text','tooltipTitle','tooltipText'}) do
   if type(item[field])=='string' and item[field]~='' then out[#out+1]=item[field] end
  end
  if type(item.menuList)=='table' then MenuTexts(item.menuList,out) end
 end
 return out
end

-- The OnEnter hovers of every shown frame under root (real scripts).
local function Hovers(root,out,seen)
 out=out or {};seen=seen or {}
 if not root or seen[root] then return out end
 seen[root]=true
 local enter=root.GetScript and root:GetScript('OnEnter')
 if enter and (not root.IsShown or root:IsShown()) then
  -- One text per tooltip: a block's marks may span several of its lines.
  local lines={}
  for _,line in ipairs(S.CaptureTooltip(enter,root)) do
   if type(line)=='string' and line~='' and line~=' ' then lines[#lines+1]=line end
  end
  if #lines>0 then out[#out+1]=table.concat(lines,'\n') end
 end
 for _,c in ipairs(root.children or {}) do Hovers(c,out,seen) end
 return out
end

local function Boot(mode,entries,english)
 if not english then S.InstallBootHook(mode,entries) end
 local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
 return H,Nexus.Panel
end

-- The panel scenario: renders, menus, hovers. Returns every collected text
-- (tagged), plus the foreign phrases their owners' APIs return now.
local function Scenario(H,P,langStatus)
 local texts,foreign={},{}
 local function Add(tag,list) for _,t in ipairs(list) do texts[#texts+1]={tag=tag,text=type(t)=='table' and t.text or t} end end
 local function Foreign(v) if type(v)=='string' and v~='' then foreign[#foreign+1]=v end end
 local function ForeignList(list) for _,v in ipairs(list or {}) do Foreign(type(v)=='table' and (v.text or v.shown) or v) end end
 P.Init({RefreshDisplay=function() return true end,ToggleAuto=function() return false end,
  RequestFirstDisplay=function() return true end,LanguageStatus=function() return langStatus end,
  ChooseLanguage=function() return {state='saved',pending=true,id='frFR'} end})
 P.Show()
 local R,U=Nexus.Readout,Nexus.UserText
 local function Render(tag,m,after)
  P.Render(m)
  if after then after() end
  local model=P._lastModel
  -- Other owners' words for this exact model (their own APIs, this session).
  Foreign(model.status);Foreign(model.recommendation);Foreign(model.autoNote)
  if U and U.DestinationFields then
   local fields,tip=U.DestinationFields(P.DestinationFacts(model) or {})
   for _,f in ipairs(fields or {}) do Foreign(f.value);Foreign(f.compact) end
   ForeignList(tip)
  end
  ForeignList(P.DestinationLines(model))
  if U and U.RunProgressText then
   local pr=model.progress or {}
   Foreign(U.RunProgressText(pr.owned,pr.total,#(pr.toLock or {}),#(pr.unknownTomes or {})>0))
   Foreign(U.RunProgressText(pr.owned,pr.total,#(pr.toLock or {})))
  end
  if R then
   ForeignList(R.OfferHeadingForms and R.OfferHeadingForms(model.auto))
   Foreign(R.AUTO_ON_NOTE);Foreign(R.WAITING_OFFER_HEADING);ForeignList(R.ChargesLegend and R.ChargesLegend())
   for i,c in ipairs(model.cards or {}) do
    if R.OfferCard then local o=R.OfferCard(c.text,false,model.auto,c.facts,false);Foreign(o.name);Foreign(o.quality);Foreign(o.tag);Foreign(o.full)
     o=R.OfferCard(c.text,true,model.auto,c.facts,false);Foreign(o.tag);Foreign(o.full);Foreign(o.shown) end
    Foreign(c.text)
   end
   if R.StatusParts then for _,k in ipairs({'ready','loading','unknown','unavailable','unconfirmed','awaiting'}) do local s=R.StatusParts(k);Foreign(s.glyph..' '..s.word..': ');Foreign(s.word) end end
  end
  Foreign(U and U.BEST_KNOWN);Foreign(U and U.RECORD_SCOPE)
  Add(tag,S.VisibleTexts(NexusPanel))
  Add(tag..' hover',Hovers(NexusPanel))
 end
 -- Setup (no Wishlist) and restoring.
 Render('setup',Model{total=0,noName=true,assignment={state='unassigned'}})
 Render('restoring',Model{total=0,noName=true,assignment={state='restoring'}})
 Render('unavailable',Model{total=0,noName=true,assignment={state='unavailable'}})
 -- Assigned progress, Details expanded, DPS records shown.
 Render('progress',Model{performance=PERF,bestDps=BEST,serverStatus=SS})
 if not P._playDetails then P.TogglePlanDetails() end
 Render('details',Model{performance=PERF,bestDps=BEST,serverStatus=SS,shed={'Extra Echo 1 ×1 (Uncommon:×1)','Extra Echo 2 ×1 (Uncommon:×1)','Extra Echo 3 ×1 (Common:×1)','Extra Echo 4 ×1 (Common:×1)'}})
 -- A Callboard objective (its words are ui/CallboardStatus.lua data) and the
 -- Orb guidance with its Open Orbs... and Orb mini panel buttons.
 local cb=Nexus.CallboardStatus and Nexus.CallboardStatus.GetSummary
 if Nexus.CallboardStatus then
  Nexus.CallboardStatus.GetSummary=function() return {observed=true,lines={'Slay wolves','Slay wolves again','Slay wolves thrice'}} end
 end
 local guide={state='orb-run',text='Orb guidance fixture',openOrbs=true}
 Foreign(guide.text)
 Render('callboard orb',Model{cards=CARDS,auto=false,extra={orbGuidance=guide}})
 -- The Callboard rewards hover is ui/CallboardStatus.lua's own tooltip.
 if Nexus.CallboardStatus and Nexus.CallboardStatus.ShowRewardsTooltip then
  ForeignList(S.CaptureTooltip(Nexus.CallboardStatus.ShowRewardsTooltip,NexusPanel))
 end
 if Nexus.CallboardStatus then Nexus.CallboardStatus.GetSummary=cb end
 -- The minimap button's hover (its version is build data).
 Foreign(Nexus.VERSION)
 if NexusMinimapButton then Add('minimap',{table.concat(S.CaptureTooltip(NexusMinimapButton:GetScript('OnEnter'),NexusMinimapButton),'\n')}) end
 -- Offer cards: Auto OFF (player chooses) and Auto ON; waiting; paused; held.
 Render('offer off',Model{cards=CARDS,recommendation='Take Frostwake Sigil.',auto=false,serverStatus=SS})
 Render('offer on',Model{cards=CARDS,recommendation='Take Frostwake Sigil.',auto=true})
 Render('preview',Model{cards=CARDS,auto=false,slot=0,extra={}})
 Render('waiting',Model{auto=true,paused='waiting for three-card board',effective={state='waiting',reason='waiting for three-card board'}})
 Render('rechecking',Model{auto=true,paused='x',effective={state='rechecking',reason='x'}})
 Render('no offer',Model{auto=false,cards={},recommendation=''})
 -- Completed (status card hidden: the fallback badge), named and unnamed.
 Render('complete',Model{total=10,owned=10,toLock={},unknownTomes={},shed={},performance=PERF,bestDps=BEST})
 Render('complete ss',Model{total=10,owned=10,toLock={},unknownTomes={},shed={},serverStatus=SS})
 -- Extra copies list window (listed, empty, unknown).
 P.Render(Model{shed={'Extra Echo 1 ×1 (Uncommon:×1)','Extra Echo 2','Extra Echo 3','Extra Echo 4'}})
 P.ShowExtraList();Add('extra list',S.VisibleTexts(NexusExtraCopiesList))
 P.Render(Model{shed={}});P.ShowExtraList();Add('extra empty',S.VisibleTexts(NexusExtraCopiesList))
 local noShed=Model{};noShed.progress.shed=nil;P.Render(noShed);P.ShowExtraList();Add('extra unknown',S.VisibleTexts(NexusExtraCopiesList))
 NexusExtraCopiesList:Hide()
 -- Session pause: paused, unknown, not available, unpaused (banner and menu).
 local real=Nexus.SessionPause
 local state='paused'
 Nexus.SessionPause={Status=function() if state=='unknown' then error('x') end return {paused=state=='paused',epoch=1} end,
  Pause=function() return {paused=true,epoch=2} end,Resume=function() return {paused=true,epoch=2} end}
 P.Render(Model{cards=CARDS,auto=true,extra={_nexusSessionPaused=true}})
 Add('paused',S.VisibleTexts(NexusPanel));Add('paused hover',Hovers(NexusPanel));Add('paused menu',MenuTexts(P.SessionMenuItems()))
 Add('paused auto',P.AutoSummaryLines());Add('paused detail',P.AutoDetailLines())
 state='unknown';P.UpdatePauseBanner()
 Add('pause unknown',S.VisibleTexts(NexusPanel));Add('pause unknown hover',Hovers(NexusPanel));Add('pause unknown menu',MenuTexts(P.SessionMenuItems()))
 Add('pause unknown auto',P.AutoSummaryLines());Add('pause unknown detail',P.AutoDetailLines())
 state='running';P.UpdatePauseBanner();Add('pause menu',MenuTexts(P.SessionMenuItems()))
 Nexus.SessionPause=nil;Add('pause none menu',MenuTexts(P.SessionMenuItems()))
 Nexus.SessionPause=real
 -- Auto hover and detail lines in each selection.
 for _,m in ipairs({Model{auto=true},Model{auto=false},Model{auto=true,paused='manual mode',effective={state='paused',reason='settling after world entry',hold=true}}}) do
  P.Render(m);Add('auto',P.AutoSummaryLines());Add('auto detail',P.AutoDetailLines())
  Add('auto hover',{table.concat(S.CaptureTooltip(P.ShowAutoTooltip,NexusPanel._autoBtn),'\n')})
  if R and R.AutoHoldText then Foreign(R.AutoHoldText(m.paused)) end
  if R and R.AutomationScopeLines then
   ForeignList(R.AutomationScopeLines({selected=m.auto==true,held=m.auto and m.paused or nil,settings=Nexus.Store.Settings()}))
  end
  if U and U.Message and m.effective then Foreign(U.Message(m.effective.reason)) end
 end
 local auto0=P._lastModel;auto0.auto=nil;Add('auto unknown',P.AutoSummaryLines())
 -- Every menu through its real builder.
 Add('options',MenuTexts(P.MoreMenuItems(NexusPanel._menuBtn)))
 Add('windows',MenuTexts(P.MoreWindowsItems()))
 Add('hub plan',MenuTexts(P.HubMenuItems('plan')));Add('hub explore',MenuTexts(P.HubMenuItems('explore')))
 for _,k in ipairs({'plan','explore','orbs'}) do Add('hub tip '..k,P.HubTooltipLines(k)) end
 Add('language',MenuTexts(P.LanguageMenuItems(function(fn) return fn end)))
 Add('language label',{P.LanguageMenuLabel()})
 for _,r in ipairs({{state='saved',pending=true,id='frFR'},{state='saved',preferencePending=true,id='frFR'},{state='saved',id='frFR'},
  {state='saved',automatic=true,resolved='enUS'},{state='unchanged',id='frFR',pending=true},{state='session'},{state='unconfirmed'},
  {state='refused',reason='drift'},{state='refused',reason='nope'}}) do Add('language result',{P.LanguageResultText(r,'frFR')}) end
 -- Other owners' menu rows.
 if Nexus.Theme then Foreign(Nexus.Theme.Summary and Nexus.Theme.Summary());Foreign(Nexus.Theme.HELP);ForeignList(MenuTexts(Nexus.Theme.MenuItems and Nexus.Theme.MenuItems(function() end))) end
 if Nexus.Updates and Nexus.Updates.Status then local st=Nexus.Updates.Status();Foreign(st.menu);Foreign(st.detail) end
 if R and R.AutomationSettingsRows then
  for _,sel in ipairs({true,false}) do ForeignList(R.AutomationSettingsRows({selected=sel,settings=Nexus.Store.Settings()})) end
 end
 if R and R.AutomationScopeLines then ForeignList(R.AutomationScopeLines({selected=true,settings=Nexus.Store.Settings()}));ForeignList(R.AutomationScopeLines({selected=false,settings=Nexus.Store.Settings()})) end
 local orbLine=P.OrbHubLine();Add('orb line',{orbLine});Add('shared line',{P.SharedDataLine()})
 return texts,foreign
end

local LANG={active='frFR',pending=true,preferencePending=false,automatic=false,saved='frFR',activeAutomatic=false,
 automaticPreference='automatic',automaticLanguage='enUS',savedUnsupported=true,sessionOnly=true,refusal='drift'}

-- Removes every foreign phrase and fixture datum, then reports the English
-- left over. A phrase is removed only when an owner API returned it exactly.
local function Leftovers(texts,foreign)
 table.sort(foreign,function(a,b) return #a>#b end)
 local out={}
 for _,item in ipairs(texts) do
  local rest=S.Unmarked(item.text)
  for _,f in ipairs(foreign) do
   local plain=S.Unmarked(f)
   if #plain>1 then
    local i=rest:find(plain,1,true)
    while i do rest=rest:sub(1,i-1)..' '..rest:sub(i+#plain);i=rest:find(plain,1,true) end
   end
  end
  for _,d in ipairs(DATA) do
   local i=rest:find(d,1,true)
   while i do rest=rest:sub(1,i-1)..' '..rest:sub(i+#d);i=rest:find(d,1,true) end
  end
  -- Code-owned symbols and the product name around translated text.
  rest=rest:gsub('Nexus',' '):gsub('DPS',' ')
  local word=S.LooksUntranslated(rest)
  if word then out[#out+1]=item.tag..': '..word..' in '..item.text end
 end
 return out
end

---------------------------------------------------------------- PSEUDO
do
 local H,P=Boot()
 local L=Nexus.Localization
 check(L.ActiveLanguage()=='frFR','PSEUDO: the pseudo pack is the session language from boot')
 local d0=L.Diagnostics()
 local saved,acts,sent=F.Serialize(NexusDB),#H.actions,#H.sent
 local saved2=F.Serialize(WishlistRealizerDB)
 local texts,foreign=Scenario(H,P,LANG)
 -- Passivity: rendering, hovering and building menus wrote, sent and did nothing.
 -- (The Details toggle is memory only.)
 check(F.Serialize(NexusDB)==saved and F.Serialize(WishlistRealizerDB)==saved2,'PASSIVE: no saved table changed')
 check(#H.actions==acts and #H.sent==sent,'PASSIVE: no action and no send')
 local d1=L.Diagnostics()
 for _,why in ipairs({'invalid_key','unknown_key','wrong_key_kind','format_requires_arguments','invalid_arguments','output_limit','missing_candidate','invalid_candidate'}) do
  check(d1.byReason[why]==d0.byReason[why],'PSEUDO: no '..why..' while rendering the panel ('..tostring(d1.byReason[why]-d0.byReason[why])..')')
 end
 check(#texts>200,'PSEUDO: the scenario reached the real receivers ('..#texts..' texts)')
 local pseudo=0
 for _,t in ipairs(texts) do if S.IsPseudo(t.text) then pseudo=pseudo+1 end end
 check(pseudo>150,'PSEUDO: pseudo text reached the display receivers ('..pseudo..')')
 local left=Leftovers(texts,foreign)
 -- The four labels help_action_first quotes ("Hide Nexus Panel", "No Echo
 -- choice is showing.", "Auto ON — paused", "Status: ") are reviewed keys now
 -- (owner follow-up v2), so nothing is kept back here.
 local real=left
 -- Negative control: the scan does report plain English it is shown.
 local control=Leftovers({{text='Plain English control line',tag='control'}},foreign)
 check(#control==1,'PSEUDO: the scan reports plain English it is shown (negative control: '..#control..')')
 if #real>0 then for i=1,math.min(#real,40) do print('UNTRANSLATED',real[i]) end end
 check(#real==0,'PSEUDO: every visible code-owned word passed the seam ('..#real..' left)')
 -- Chat lines and the Releases popup.
 local chat=S.CaptureChat(function()
  P.HideByPlayer()
  local jt=Nexus.JournalTab.OpenBuilds
  Nexus.JournalTab.OpenBuilds=function() return false,'unavailable' end
  P.OpenMyBuilds();P.OpenAssignment()
  Nexus.JournalTab.OpenBuilds=jt
  local sp=Nexus.SessionPause
  Nexus.SessionPause={Status=function() return {paused=false,epoch=1} end,Pause=function() error('no') end,Resume=function() return {paused=false,epoch=1} end}
  P.PauseNexus();Nexus.SessionPause=nil;P.ResumeNexus();Nexus.SessionPause=sp
  P.ChooseLanguage('frFR')
 end)
 check(#chat>=5,'CHAT: the chat lines were printed ('..#chat..')')
 for _,line in ipairs(chat) do
  local rest=S.Unmarked(line):gsub('Nexus',' ')
  check(S.IsPseudo(line) and not S.LooksUntranslated(rest:gsub('/nexus panel',' ')),'CHAT: translated: '..line)
 end
 H.popup=nil;P.ShowUpdateStatus()
 local text=H.popup and tostring(H.popup.frame.text) or ''
 check(text:find(S.OPEN..'To check or update',1,true)~=nil,'POPUP: the Releases popup paragraph is translated: '..text)
 check(H.popup.editBox:GetText()=='https://github.com/Viscerals/Better-Nexus/releases','POPUP: the address is unchanged')
 -- Templates: unknown is "?", zero "0", long/non-ASCII names verbatim.
 check(L.Format('panel.label.more_count',{count=L.Count(nil)})==S.OPEN..'+? more'..S.CLOSE,'TEMPLATE: an unknown count shows ?')
 check(L.Format('panel.value.count_copies',{count=L.Count(0)})==S.OPEN..'0 copies'..S.CLOSE,'TEMPLATE: zero shows 0')
 P.Show() -- the chat step above hid the panel (HideByPlayer)
 local m=Model{total=10,owned=10,toLock={},unknownTomes={},shed={}};m.progress.wishlistName=LONGNAME
 P.Render(m)
 local found=false
 for _,t in ipairs(S.VisibleTexts(NexusPanel)) do
  if t.text:find("'"..LONGNAME:sub(1,20),1,true) and S.IsPseudo(t.text) then found=true end
 end
 check(found,'TEMPLATE: a long non-ASCII Wishlist name is inserted verbatim inside the translated sentence')
end

---------------------------------------------------------------- ENGLISH
do
 local H,P=Boot(nil,nil,true)
 local L=Nexus.Localization
 check(L.ActiveLanguage()=='enUS','ENGLISH: plain boot is English')
 local base=L.Diagnostics().base
 check(base.present and base.undeclared==0 and base.missingDeclared==0 and base.rejected==0,'ENGLISH: the composed catalog boots whole (undeclared 0, missingDeclared 0)')
 P.Init({RefreshDisplay=function() return true end,ToggleAuto=function() return false end,RequestFirstDisplay=function() return true end,
  LanguageStatus=function() return LANG end})
 P.Show();P.Render(Model{cards=CARDS,auto=false})
 check(NexusPanel._autoBtn:GetText()=='|cffd9d9d9Auto OFF|r','ENGLISH: Auto OFF exact')
 P.SetAuto(true);check(NexusPanel._autoBtn:GetText()=='|cff2ee62eAuto ON|r','ENGLISH: Auto ON exact')
 local items=P.MoreMenuItems(NexusPanel._menuBtn)
 local byText={}
 for _,t in ipairs(MenuTexts(items)) do byText[t]=true end
 for _,want in ipairs({'Help and setup','Questions (FAQ)','Setup / Welcome','Auto explained (full details)','More help and windows','Settings',
  'Open Settings...','Automation settings','Show DPS records (now hidden)','Notices','Session','Panel','Main panel size: 100%','Reset Panel Position',
  'Hide Nexus Panel','Larger (+5%)','Smaller (-5%)','Reset to 100%',
  'Short answers: what to do next, which Wishlist is used, Auto, Sync, pause or hide. Reading it changes nothing.',
  'Hide the Nexus panel. Hiding does not turn Nexus off or change Auto; type /nexus panel or click the Nexus minimap button to show it again.'}) do
  check(byText[want],'ENGLISH: Options menu shows exact "'..want..'"')
 end
 check(byText['Update notices: on, stable releases only'] or byText['Update notices: on, stable + test builds'] or byText['Update notices: off'],
  'ENGLISH: the Update notices row is one of its exact English forms')
 local lang=MenuTexts(P.LanguageMenuItems(function(fn) return fn end))
 local all=table.concat(lang,'\n')
 check(all:find('Nexus language',1,true) and all:find('Changes unavailable: the saved data changed since start-up; reload first.',1,true)
  and all:find('Automatic (English)',1,true),'ENGLISH: language rows exact')
 check(P.LanguageResultText({state='refused',reason='nope'})=='The language cannot be changed right now: the change was refused. Nothing was changed.','ENGLISH: language refusal exact')
 check(P.DetailNameLines({'a','b','c','d'})[3]=='+2 more','ENGLISH: +N more exact')
 P.Render(Model{shed={'a','b','c','d'}})
 local lines=P.HubTooltipLines('orbs')
 check(lines[1]=='Orbs / Lost Memories' and lines[4]=='Closing the Orb window or its mini panel only hides it; an approved run continues. Use Pause or Stop.','ENGLISH: Orbs hub hover exact')
 local chat=S.CaptureChat(function() P.HideByPlayer() end)
 check(chat[1]=='|cffffd200Nexus:|r |cffffffffThe Nexus panel is hidden.|r Show it again: type |cffffffff/nexus panel|r or click the Nexus minimap button. Hiding does not turn Nexus off or change Auto.','ENGLISH: hide chat exact: '..tostring(chat[1]))
 P.Show()
 H.popup=nil;P.ShowUpdateStatus()
 -- The harness keeps the dialog's own text (the client substitutes %s).
 check(tostring(H.popup.frame.text)=='%s\n\nTo check or update, copy this Releases page address into your web browser. Installation is manual: Nexus downloads and installs nothing.','ENGLISH: popup text exact')
 local size=P.PanelSizeMenuItem()
 check(size.tooltipText=="Makes this panel larger or smaller, 50% to 150%. Other Nexus windows, the Wishlist overlay, the game's difficulty HUD and your UI scale keep their own size. A screen too small for the size shows it smaller until it fits.",'ENGLISH: size hover exact')
 local auto=P.AutoSummaryLines()
 check(auto[#auto]=='Full details: Options > Auto explained.','ENGLISH: Auto hover last line exact')
 check(L.Diagnostics().misses==0,'ENGLISH: no fallback recorded')
end

---------------------------------------------------------------- LONG
do
 local H,P=Boot('long')
 local texts=Scenario(H,P,LANG)
 local pseudo=0
 for _,t in ipairs(texts) do if S.IsPseudo(t.text) then pseudo=pseudo+1 end end
 check(pseudo>150,'LONG: expanded pseudo text is shown without error ('..pseudo..')')
 local d=Nexus.Localization.Diagnostics()
 check(d.byReason.output_limit==0 and d.byReason.invalid_arguments==0,'LONG: no template refused its expanded output')
end

---------------------------------------------------------------- MISSING
do
 local entries=S.PseudoEntries()
 local removed={['panel.button.plan']='Plan',['panel.menu.faq']='Questions (FAQ)',['panel.label.more_count']='+{count} more',
  ['panel.tooltip.minimap_drag']='Drag to reposition'}
 for k in pairs(removed) do entries[k]=nil end
 local H,P=Boot(nil,entries)
 P.Init({RefreshDisplay=function() return true end,ToggleAuto=function() return false end,RequestFirstDisplay=function() return true end})
 P.Show();P.Render(Model{})
 check(NexusPanel._footerButtons.plan:GetText()=='Plan','MISSING: Plan shows exact English')
 check(NexusPanel._footerButtons.explore:GetText():find(S.OPEN,1,true)~=nil,'MISSING: a present entry is still the pseudo text')
 local faq
 for _,item in ipairs(P.MoreMenuItems(NexusPanel._menuBtn)) do if item.text=='Questions (FAQ)' then faq=item end end
 check(faq~=nil and S.IsPseudo(faq.tooltipTitle),'MISSING: the FAQ row falls back to exact English, its hover stays pseudo')
 check(P.DetailNameLines({'a','b','c'})[3]=='+1 more','MISSING: a template without an entry renders the English template')
end

print('PASS l10n_ui_panel checks='..checks..' (synthetic pseudo-locale; native NOT_RUN)')
