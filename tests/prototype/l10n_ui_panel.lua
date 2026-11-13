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
--         The header's Build and Wishlist rows show one reviewed line as a
--         caption and a name, in two regions: each such row is read as its
--         row, and only when it is proven to be the real seam's own line
--         (HEADER ROWS below); an untranslated caption and an untranslated
--         name are each still reported (negative controls).
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
 'Tome Echo','Pipe','Echo',LONGNAME,'Tome of Kaltherz','Pseudo','English','Deutsch','Fran','Espa','Polski','Portugu','Русский',
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

-- HEADER ROWS. Main-panel visual correction ("Split Build/Wishlist captions
-- from values"): the header shows each reviewed line, "Build: <name>" and
-- "Wishlist: <name>", as its label in a caption column and the rest of the
-- line beside it. One seam output then stands in two regions. In the pseudo
-- session the caption holds the line's opening mark and the name its closing
-- mark, so neither region is a whole marked text (S.Unmarked: an opener
-- without its closer, a stray closer) and the scan below, which reads one
-- region at a time, reports both. The words did pass the seam; what changed is
-- that a region no longer holds the whole line.
-- Such a row is therefore read as the player reads it, the caption and then
-- the name, but only when it is PROVEN here to be the real seam's own line:
--   * the caption and the name are both among the panel's visible texts now
--     (S.VisibleTexts: shown and not empty; no product flag is read and the
--     panel's own split is not called);
--   * this test asks the real seam for the row's line itself,
--     Localization.Format(<the row's reviewed key>, {<its slot> = <form>}),
--     with a form the owner's own API gives for the model shown
--     (UserText.DestinationFields over the model's destination facts, as
--     the scenario takes its owner phrases: the row's value or its compact
--     value);
--   * that line begins with exactly the caption's bytes, ends with exactly
--     the name's bytes and holds nothing between them but white space.
-- So nothing shown is outside that line, nothing of the line is missing but
-- the white space between the two columns, and the order is the line's own.
-- A proven row's line then stands among the collected texts where the name
-- stood, as often as the name was collected, with the caption's entries
-- folded into it, and the unchanged scan reads every shown byte of the row as
-- the one seam output it is. A row that is not proven keeps its two regions
-- as they are, which the scan reports: an untranslated caption or name is
-- part of no seam line of this session. Nothing is left out and no word is
-- allowed by name. `seen` counts the rows shown split and the proven ones.
local HEADER_ROWS={
 {caption='_contextBuildCaption',name='_contextBuild',key='panel.label.context_build',slot='build',field=2},
 {caption='_contextWishlistCaption',name='_contextWishlist',key='panel.label.context_wishlist',slot='wishlist',field=3},
}
-- The real seam's line for `row` that is made of exactly the shown pieces
-- `caption` and `name`, or nil when no owner form gives such a line.
local function SeamLine(row,caption,name,model)
 local L,U,P=Nexus.Localization,Nexus.UserText,Nexus.Panel
 if type(caption)~='string' or caption=='' or type(name)~='string' or name=='' then return nil end
 if not (U and U.DestinationFields) then return nil end
 local fields=U.DestinationFields(P.DestinationFacts(model) or {})
 local field=type(fields)=='table' and fields[row.field] or nil
 if type(field)~='table' then return nil end
 for _,form in ipairs({'value','compact'}) do
  local shown=field[form]
  if type(shown)=='string' and shown~='' then
   local line,source=L.Format(row.key,{[row.slot]=shown})
   if type(line)=='string' and source~='unavailable' and #caption+#name<=#line
    and line:sub(1,#caption)==caption and line:sub(#line-#name+1)==name
    and line:sub(#caption+1,#line-#name):find('^%s*$') then return line end
  end
 end
 return nil
end
-- The panel's visible texts (S.VisibleTexts), each proven header row as its
-- one line. Every other text, and every row that is not proven, is as
-- S.VisibleTexts gave it.
local function PanelTexts(P,seen)
 local visible=S.VisibleTexts(NexusPanel)
 for _,row in ipairs(HEADER_ROWS) do
  local caption,name=NexusPanel[row.caption],NexusPanel[row.name]
  local captions,names=0,0
  for _,item in ipairs(visible) do
   if item.frame==caption then captions=captions+1 elseif item.frame==name then names=names+1 end
  end
  -- Shown split: the caption and the name are both among the visible texts.
  if caption and name and captions>0 and names>0 then
   seen.split=seen.split+1
   local line=SeamLine(row,caption:GetText(),name:GetText(),P._lastModel)
   if line then
    local out={}
    for _,item in ipairs(visible) do
     if item.frame==name then out[#out+1]={text=line,frame=name}
     elseif item.frame~=caption then out[#out+1]=item end
    end
    visible=out
    seen.proven=seen.proven+1;seen[row.slot]=seen[row.slot]+1
   end
  end
 end
 return visible
end

local function Boot(mode,entries,english)
 if not english then S.InstallBootHook(mode,entries) end
 local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
 return H,Nexus.Panel
end

-- The panel scenario: renders, menus, hovers. Returns every collected text
-- (tagged), plus the foreign phrases their owners' APIs return now, plus the
-- count of the header rows shown split and of those proven (PanelTexts).
local function Scenario(H,P,langStatus)
 local texts,foreign={},{}
 local rows={split=0,proven=0,build=0,wishlist=0}
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
  Add(tag,PanelTexts(P,rows))
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
 -- R5 P73: the missing-tome list. The producer marks only a generated
 -- "Tome of <Echo>" (no catalog tome name) beside its raw text; discovery,
 -- dedup, count and the raw sort are unchanged. The hover says a generated
 -- name through main.value.unknown_tome and a catalog tome name as it is.
 do
  local A,svc=Nexus.GameAdapter,ProjectEbonhold.PerkService
  local realCat,realDisc=A.Catalog,svc.GetDiscoveredEchoes
  A.Catalog=function() return {rows={[1]={name='Kaltherz',requiredSpell=50},[2]={name='Aschen',requiredSpell=60},[3]={requiredSpell=70}},
   levers={[50]={members={1},tomeName='Tome of Kaltherz'},[60]={members={2}}}} end
  svc.GetDiscoveredEchoes=function() return {} end
  local out=A.UnknownTomesForEchoes({{spellId=1},{spellId=2},{spellId=3},{spellId=2}})
  A.Catalog,svc.GetDiscoveredEchoes=realCat,realDisc
  check(#out==3 and out[1]=='Tome of 3' and out[2]=='Tome of Aschen' and out[3]=='Tome of Kaltherz',
   'R5 P73: raw texts, dedup and raw sort unchanged: '..table.concat(out,' | '))
  check(out.generated and out.generated[1].echo=='3' and out.generated[2].echo=='Aschen' and out.generated[3]==nil,
   'R5 P73: only the generated names carry provenance')
  Render('tomes',Model{performance=PERF,bestDps=BEST,serverStatus=SS,unknownTomes=out})
  local hit=P.EnsurePlayWidgets().tomesHit
  local lines=S.CaptureTooltip(hit:GetScript('OnEnter'),hit)
  local L=Nexus.Localization
  local function Has(want) for _,l in ipairs(lines) do if l==want then return true end end return false end
  local g1,g2=L.Format('main.value.unknown_tome',{echo='3'}),L.Format('main.value.unknown_tome',{echo='Aschen'})
  check(Has('  • '..g1) and Has('  • '..g2) and Has('  • Tome of Kaltherz'),'R5 P73: the hover says generated names through the key, the catalog name as it is: '..table.concat(lines,' | '))
  check(L.ActiveLanguage()=='enUS' or (g1~='Tome of 3' and not Has('  • Tome of 3')),'R5 P73: in a translated session the generated name is not the raw English')
 end
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
 Add('paused',PanelTexts(P,rows));Add('paused hover',Hovers(NexusPanel));Add('paused menu',MenuTexts(P.SessionMenuItems()))
 Add('paused auto',P.AutoSummaryLines());Add('paused detail',P.AutoDetailLines())
 state='unknown';P.UpdatePauseBanner()
 Add('pause unknown',PanelTexts(P,rows));Add('pause unknown hover',Hovers(NexusPanel));Add('pause unknown menu',MenuTexts(P.SessionMenuItems()))
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
 return texts,foreign,rows
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
 local texts,foreign,rows=Scenario(H,P,LANG)
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
 -- The header rows (HEADER ROWS above). The scan just passed with each proven
 -- row read as its line; this says that such rows were there at all, in both
 -- the Build and the Wishlist line, and that none shown split was left
 -- unproven (an unproven row keeps its two regions, which the scan reports).
 check(rows.split>0 and rows.proven==rows.split and rows.build>0 and rows.wishlist>0,
  'PSEUDO: every header row shown as a caption and a name is the real seam\'s own line for its owner\'s value ('
   ..rows.proven..' of '..rows.split..' rows; Build '..rows.build..', Wishlist '..rows.wishlist..')')
 -- Negative controls for those rows: an untranslated caption and an
 -- untranslated name are each still reported. A control puts plain English
 -- into ONE shown region of a proven row through that region's own SetText
 -- (nothing is rendered meanwhile), then takes the same collection
 -- (PanelTexts) and the same scan (Leftovers) as above: the row must be left
 -- unproven and the scan must name the injected text. The captions are the
 -- exact English labels a caption that skipped the seam would show. The
 -- region gets its own text back; at the end both rows are proven again.
 do
  P.Render(Model{})
  local function HeaderTexts()
   local seen,list={split=0,proven=0,build=0,wishlist=0},{}
   for _,item in ipairs(PanelTexts(P,seen)) do
    for _,row in ipairs(HEADER_ROWS) do
     if item.frame==NexusPanel[row.caption] or item.frame==NexusPanel[row.name] then
      list[#list+1]={tag='header control',text=item.text}
     end
    end
   end
   return list,seen
  end
  local list,seen=HeaderTexts()
  check(seen.split==2 and seen.proven==2 and #list>0 and #Leftovers(list,foreign)==0,
   'PSEUDO: control baseline: the Build and the Wishlist row are shown as a caption and a name, both are proven and pass the scan ('
    ..seen.proven..' of '..seen.split..' rows, '..#list..' texts)')
  for _,case in ipairs({{'_contextBuildCaption','Build:','Build caption'},{'_contextBuild','Untranslated build name','Build name'},
   {'_contextWishlistCaption','Wishlist:','Wishlist caption'},{'_contextWishlist','Untranslated wishlist name','Wishlist name'}}) do
   local region=NexusPanel[case[1]]
   local kept=region:GetText()
   region:SetText(case[2])
   local bad,badSeen=HeaderTexts()
   local reported=false
   for _,line in ipairs(Leftovers(bad,foreign)) do
    if line:sub(-(#case[2]+4))==' in '..case[2] then reported=true end
   end
   region:SetText(kept)
   check(badSeen.split==2 and badSeen.proven==1 and reported,
    'PSEUDO: an untranslated '..case[3]..' ("'..case[2]..'") is not read as a seam line and the scan reports it ('
     ..badSeen.proven..' of '..badSeen.split..' rows proven, reported '..tostring(reported)..')')
  end
  local again,againSeen=HeaderTexts()
  check(againSeen.split==2 and againSeen.proven==2 and #Leftovers(again,foreign)==0,
   'PSEUDO: the controls left both header rows as they were ('..againSeen.proven..' of '..againSeen.split..' rows proven)')
 end
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
  'Hide the Nexus panel. Hiding does not turn Nexus off or change Auto; type /nexus panel or click the Nexus minimap button to show it again.'}) do
  check(byText[want],'ENGLISH: Options menu shows exact "'..want..'"')
 end
 -- The FAQ row's hover. Main-panel visual correction: the footer "?" is gone
 -- (three hubs span the footer), so Options > Questions (FAQ) is the one
 -- control that opens the FAQ, and its hover says, whole, what both hovers
 -- said. The row's explanation ("... Reading it changes nothing.") stood in
 -- the list above as one exact menu text while it was the whole hover; it is
 -- the hover's first paragraph now and is checked here instead, at the row
 -- itself and byte for byte, with the complete note on opening the FAQ that
 -- the "?" carried after it. The third paragraph is the numbers legend that
 -- "?" also carried: the catalog's own entry, whole. The hover is exactly
 -- these three, a blank line between them, and nothing else.
 local READING='Short answers: what to do next, which Wishlist is used, Auto, Sync, pause or hide. Reading it changes nothing.'
 local OPENING='Short answers: what to do next, which Wishlist is used, Auto, Sync, pause or hide. Opening it changes nothing.'
 local faq,faqRows=nil,0
 local function CountFaqRows(list)
  for _,item in ipairs(list or {}) do
   if item.text=='Questions (FAQ)' then faqRows=faqRows+1 end
   if type(item.menuList)=='table' then CountFaqRows(item.menuList) end
  end
 end
 CountFaqRows(items)
 for _,item in ipairs(items) do if item.text=='Questions (FAQ)' then faq=item end end
 check(faq~=nil and faqRows==1 and type(faq.func)=='function' and not faq.disabled and not faq.isTitle and faq.menuList==nil,
  'ENGLISH: Questions (FAQ) is a row of the Options menu once, at its top level, and a click acts on it ('..faqRows..')')
 -- That row is the control that opens the FAQ: its own click calls Help's
 -- route for the FAQ page, once (the route is recorded here, not opened).
 local help,opened=Nexus.Help,{}
 check(type(help)=='table' and type(help.Show)=='function','ENGLISH: Help and its route are loaded')
 local realShow=help.Show
 help.Show=function(page) opened[#opened+1]=page end
 local clicked,why=pcall(faq.func,faq)
 help.Show=realShow
 check(clicked and #opened==1 and opened[1]=='faq','ENGLISH: the Questions (FAQ) row opens the FAQ: one Help.Show("faq") ('
  ..tostring(clicked and #opened or why)..')')
 local hover=faq.tooltipText
 check(type(hover)=='string' and hover:sub(1,#READING)==READING,
  'ENGLISH: the FAQ row\'s hover begins with its complete explanation, exact: '..tostring(hover):sub(1,#READING))
 check(hover:sub(#READING+1,#READING+2)=='\n\n' and hover:sub(#READING+3,#READING+2+#OPENING)==OPENING,
  'ENGLISH: after a blank line the FAQ row\'s hover gives the complete note on opening the FAQ, exact: '
   ..hover:sub(#READING+3,#READING+2+#OPENING))
 local legend,legendSource=L.Text('panel.tooltip.numbers_hint')
 check(legendSource=='base' and legend:find('Soul Ash',1,true) and legend:find('Intensity',1,true) and legend:find('DPS',1,true),
  'ENGLISH: the numbers legend is the catalog\'s English entry and names the difficulty card\'s Soul Ash and Intensity and the DPS rows')
 check(hover==READING..'\n\n'..OPENING..'\n\n'..legend,
  'ENGLISH: the FAQ row\'s hover is its explanation, the note on opening and the numbers legend, each whole, and nothing else')
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
 local texts,_,rows=Scenario(H,P,LANG)
 local pseudo=0
 for _,t in ipairs(texts) do if S.IsPseudo(t.text) then pseudo=pseudo+1 end end
 check(pseudo>150,'LONG: expanded pseudo text is shown without error ('..pseudo..')')
 -- No row is required to be shown split here (a longer caption may leave its
 -- line whole); a row that is shown split is still the real seam's own line.
 check(rows.proven==rows.split,'LONG: every header row shown as a caption and a name is the real seam\'s own line ('
  ..rows.proven..' of '..rows.split..' rows)')
 local d=Nexus.Localization.Diagnostics()
 check(d.byReason.output_limit==0 and d.byReason.invalid_arguments==0,'LONG: no template refused its expanded output')
end

---------------------------------------------------------------- MISSING
do
 local entries=S.PseudoEntries()
 -- The approved compact panel (design draft "Nexus compact panel"; its
 -- decision on the footer's words): the first footer hub reads "Wishlist"
 -- (panel.button.hub_wishlist) and the second "Builds"
 -- (panel.button.hub_builds); what each opens is unchanged and stays on its
 -- hover. EXPECT: the entry removed here was panel.button.plan, the hub's
 -- former name, and the hub was expected to read the English "Plan". The
 -- entry of the name the hub shows now is removed instead, and the hub must
 -- show that name's exact English.
 local removed={['panel.button.hub_wishlist']='Wishlist',['panel.menu.faq']='Questions (FAQ)',['panel.label.more_count']='+{count} more',
  ['panel.tooltip.minimap_drag']='Drag to reposition'}
 for k in pairs(removed) do check(entries[k]~=nil,'MISSING: fixture: a pseudo entry exists for '..k);entries[k]=nil end
 local H,P=Boot(nil,entries)
 P.Init({RefreshDisplay=function() return true end,ToggleAuto=function() return false end,RequestFirstDisplay=function() return true end})
 P.Show();P.Render(Model{})
 check(NexusPanel._footerButtons.plan:GetText()=='Wishlist','MISSING: the Wishlist hub shows exact English')
 check(NexusPanel._footerButtons.explore:GetText():find(S.OPEN,1,true)~=nil,'MISSING: a present entry is still the pseudo text')
 local faq
 for _,item in ipairs(P.MoreMenuItems(NexusPanel._menuBtn)) do if item.text=='Questions (FAQ)' then faq=item end end
 check(faq~=nil and S.IsPseudo(faq.tooltipTitle),'MISSING: the FAQ row falls back to exact English, its hover stays pseudo')
 check(P.DetailNameLines({'a','b','c'})[3]=='+1 more','MISSING: a template without an entry renders the English template')
end

---------------------------------------------------------------- PENDING (C-04)
-- While shared data is not ready, Explore's real final OnEnter (after the
-- real creation and script order of the TOC boot) gives LoadingStatus's own
-- explanation beside the hub hover. The expected lines are LoadingStatus's
-- own hook output on a probe button it binds. Ready, the hover is the hub
-- hover alone. The greying registry still greys and restores the label.
-- Passive: no saved table changes, no action and no send.
do
 local H,P=Boot(nil,nil,true)
 P.Init({RefreshDisplay=function() return true end,ToggleAuto=function() return false end,RequestFirstDisplay=function() return true end})
 P.Show();P.Render(Model{})
 local LS=Nexus.LoadingStatus
 check(LS~=nil and type(LS.BindSharedButton)=='function','PENDING: LoadingStatus is loaded')
 local explore=NexusPanel._footerButtons.explore
 -- The approved compact panel: this hub's name is "Builds"
 -- (panel.button.hub_builds; it was panel.button.explore, "Explore"). The
 -- name the hub shows is the one the loading explanation and the greying
 -- registry are bound with, so the probe below is bound with it too.
 local label=Nexus.Localization.Text('panel.button.hub_builds')
 check(label=='Builds','PENDING: fixture: the hub\'s reviewed English name is Builds: '..tostring(label))
 local realStatus=Nexus.StartupStatus
 local saved,saved2,acts,sent=F.Serialize(NexusDB),F.Serialize(WishlistRealizerDB),#H.actions,#H.sent
 local probe=CreateFrame('Button',nil,UIParent)
 LS.BindSharedButton(probe,label)
 local function Has(lines,want) for _,l in ipairs(lines) do if l==want then return true end end return false end
 for _,status in ipairs({{state='pending',coreReady=false,phase='store-validation'},
  {state='pending',coreReady=true,phase='scan',step='scan',recordsSeen=12},
  {state='failed',coreReady=true,reason='fixture'}}) do
  Nexus.StartupStatus=function() return status end
  local want=S.CaptureTooltip(probe:GetScript('OnEnter'),probe)
  check(#want==3,'PENDING: LoadingStatus explains a '..status.state..' shared view ('..#want..' lines)')
  local got=S.CaptureTooltip(explore:GetScript('OnEnter'),explore)
  for _,line in ipairs(want) do
   check(Has(got,line),'PENDING: the Explore hover gives the loading explanation "'..tostring(line)..'" in: '..table.concat(got,' | '))
  end
  local hub=P.HubTooltipLines('explore')
  check(got[1]==hub[1],'PENDING: the hub title stays first')
  for _,line in ipairs(hub) do check(Has(got,line),'PENDING: the hub hover keeps "'..tostring(line)..'"') end
  LS.Update(status,true)
  check(explore._nexusDataLoading==true and explore:GetText()=='|cff888888'..label..'|r','PENDING: the greying registry greys Explore')
 end
 local ready={state='ready',coreReady=true,phase='complete'}
 Nexus.StartupStatus=function() return ready end
 local got=S.CaptureTooltip(explore:GetScript('OnEnter'),explore)
 local hub=P.HubTooltipLines('explore')
 check(#got==#hub,'READY: the Explore hover is the hub hover alone ('..#got..' lines)')
 for i,line in ipairs(hub) do check(got[i]==line,'READY: hub hover line '..i..' exact') end
 LS.Update(ready,true)
 check(explore._nexusDataLoading==false and explore:GetText()==label,'READY: the greying registry restores the Explore label')
 Nexus.StartupStatus=realStatus
 check(F.Serialize(NexusDB)==saved and F.Serialize(WishlistRealizerDB)==saved2,'PENDING PASSIVE: no saved table changed')
 check(#H.actions==acts and #H.sent==sent,'PENDING PASSIVE: no action and no send')
end

print('PASS l10n_ui_panel checks='..checks..' (synthetic pseudo-locale; native NOT_RUN)')
