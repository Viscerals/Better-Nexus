-- Full-UI localization, HUD family (issues #143-#148): every code-owned
-- visible string of ui/Readout.lua, ui/Theme.lua, ui/CallboardStatus.lua,
-- ui/Nameplate.lua, ui/ServerStatus.lua and ui/LayoutMetrics.lua reaches its
-- real display receiver through the reviewed seam. A synthetic pseudo pack
-- (tests/prototype/l10n_pseudo_support.lua) is active from session start; the
-- real windows are driven through their real entry points (Panel.Render with
-- synthetic models, the real charge and offer-card hovers, the Options and
-- Automation menu builders, the Callboard rewards hover, the unit-tooltip
-- hook Nameplate.Init installed on GameTooltip, the Hardcore chat notice and
-- the panel layout). A text that still shows plain English did not pass the
-- seam. Also: unknown (?) and zero (0) charges stay distinct, the estimate
-- marker stays code-owned, long and non-ASCII names are inserted verbatim, a
-- pseudo pack without some keys shows their exact English, a long-expansion
-- pack still renders, an English session shows the exact legacy bytes (also
-- with the seam absent), a translated Nexus badge keeps the duplicate check,
-- and rendering, hovering and opening menus change no saved table and make
-- no send or game action.
-- Synthetic offline evidence only: no native font, glyph, fit or pixel claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local LB=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local OPEN,CLOSE=S.OPEN,S.CLOSE

local checks,failures=0,{}
local function check(ok,message,detail)
 checks=checks+1
 if not ok then failures[#failures+1]=message..(detail~=nil and (' :: '..tostring(detail)) or '') end
 return ok
end
local function P(text) return OPEN..text..CLOSE end

-- Data that is never translated: fixture Echo and player names, the product
-- name Nexus, version strings. Everything else must be marked.
local DATA={Cinder=true,Lattice=true,Hollow=true,Bell=true,Ashen=true,Tithe=true,Nexus=true,
 Alicia=true,Bravo=true,Authorita=true,Peerling=true,Callboard=true,Quest=true}
-- The leaderboard fixture's build title (user data) precedes the rank line.
local TITLE='Leaderboard fixture build'
local function allow(word,text)
 if DATA[word]==true then return true end
 return text:find(TITLE,1,true)~=nil and (word=='Leaderboard' or word=='fixture' or word=='build')
end
-- One of the heading's forms (the row picks the first that fits).
local function HasForm(heading,forms,wrap)
 for _,form in ipairs(forms) do if heading:find(wrap(form),1,true) then return true end end
 return false
end
local function Strict(label,texts)
 local missing=S.Untranslated(texts,allow)
 local shown={}
 for i=1,math.min(#missing,6) do shown[#shown+1]=missing[i].word..' in '..V.printable(missing[i].text) end
 check(#missing==0,label..': every visible code-owned word passed the seam',table.concat(shown,' || '))
 return #missing==0
end

local CARDS={
 {text='Cinder Lattice (Epic)',highlight=true,facts={name='Cinder Lattice',quality=3}},
 {text='Hollow Bell (Rare)',facts={name='Hollow Bell',quality=2}},
 {text='[Guaranteed offer] Ashen Tithe (Uncommon)',facts={name='Ashen Tithe',quality=1}},
}
local function Model(o)
 o=o or {}
 return {status='ready',level=40,auto=o.auto,paused=o.paused,cards=o.cards or {},
  recommendation=o.recommendation or '',charges=o.charges,
  progress={wishlistName='Synthetic HUD plan',total=6,owned=1,missing={},shed={},toLock={},unknownTomes={}}}
end
local function Saved()
 return F.Serialize(NexusDB or {})..'#'..F.Serialize(WishlistRealizerDB or {})
end

-- The real unit-tooltip hook (Nameplate.Init's OnTooltipSetUnit script on
-- GameTooltip) for one hover of player `name`. Returns the lines it added.
local function HookHover(name,preset)
 local hook=GameTooltip:GetScript('OnTooltipSetUnit')
 assert(type(hook)=='function','Nameplate.Init installed the unit-tooltip hook')
 local lines,saved={},{}
 for _,k in ipairs({'GetUnit','NumLines','AddLine','Show','GetName'}) do saved[k]=rawget(GameTooltip,k) end
 local regions={}
 local function add(text)
  lines[#lines+1]=text
  local r=regions[#lines] or {GetText=function(self) return self.text end}
  r.text=text;regions[#lines]=r;_G['GameTooltipTextLeft'..#lines]=r
 end
 for _,line in ipairs(preset or {name}) do add(line) end
 local before=#lines
 rawset(GameTooltip,'GetUnit',function() return name,V.UNIT end)
 rawset(GameTooltip,'NumLines',function() return #lines end)
 rawset(GameTooltip,'AddLine',function(_,text) add(text) end)
 rawset(GameTooltip,'Show',function() end)
 rawset(GameTooltip,'GetName',function() return 'GameTooltip' end)
 local ok,err=pcall(V.WithUnit,name,hook,GameTooltip)
 for k,v in pairs(saved) do rawset(GameTooltip,k,v) end
 for _,k in ipairs({'GetUnit','NumLines','AddLine','Show','GetName'}) do if saved[k]==nil then rawset(GameTooltip,k,nil) end end
 assert(ok,err)
 local added={}
 for i=before+1,#lines do added[#added+1]=lines[i] end
 return added,lines
end

------------------------------------------------------------------------
-- One HUD session: renders every family surface and returns what showed.
------------------------------------------------------------------------
local function HudSession()
 local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
 local Pn,R=Nexus.Panel,Nexus.Readout
 Nexus.DisableOrdinaryAutomation()
 Pn.Show()
 local out={H=H}
 -- Callboard objective with difficulty rewards and a completed quest-log row.
 ProjectEbonhold.ObjectivesService={GetActiveObjective=function()
  return {title='Callboard Quest',questId=77,objectiveText='Bring the tome',normalSoulAshes=1200,normalXp=900,
   hc1SoulAshes=2500000,hc1Money=45000,hc2Xp=1500}
 end}
 GetNumQuestLogEntries=function() return 1 end
 GetQuestLogTitle=function(i) if i==1 then return 'Callboard Quest',80,nil,nil,nil,nil,1,nil,77 end end
 H.Fire('QUEST_LOG_UPDATE');H.Advance(.25);H.Advance(1)
 Pn.Render(Model({auto=false}))
 -- Warm-up render (first layout, lazily built widgets), then the passivity window.
 Pn.Render(Model({auto=false,cards=CARDS,recommendation='Take a needed Echo',
  charges={banish=0,reroll=nil,freeze=3,trustworthy=false,arrived=true}}))
 local savedBefore,sentBefore,actionsBefore=Saved(),#H.sent,#H.actions

 -- Auto OFF offer: cards, heading, target, compact charges and its legend.
 Pn.Render(Model({auto=false,cards=CARDS,recommendation='Take a needed Echo',
  charges={banish=0,reroll=nil,freeze=3,trustworthy=false,arrived=true}}))
 local cards=NexusPanel._offerCards or {}
 out.cards={}
 for i=1,3 do
  local c=cards[i]
  if c then
   local hover=S.CaptureTooltip(c:GetScript('OnEnter'),c)
   -- Hover: the complete line, then the tag line when the card has one
   -- (the closing sentence is the panel family's own copy).
   local tagged=(c._nexusTag or '')~=''
   out.cards[i]={name=c.name:GetText(),quality=c.quality:GetText(),tag=c.tag:GetText(),
    full=hover[1],hoverTag=tagged and hover[2] or nil,shown=c:IsShown()}
  end
 end
 out.headingOff=NexusPanel._rollStatus:GetText()
 out.bodyOff=NexusPanel._rollRec:GetText()
 -- Count disclosure (approved main-panel design: "Counts stay behind
 -- Details", the compact charges among them). The charges are counts: with
 -- Details closed, as the panel opens, the compact row and its hover are not
 -- on the panel; they are the open Details view's. This session therefore
 -- observes the closed panel first, opens Details for the charge-format and
 -- legend reads only, and observes the closed panel again afterwards.
 -- Details is the panel's own memory-only state (Panel._playDetails, what
 -- its Details control toggles; nothing is saved). It is put back as it was
 -- also when a read raises, so nothing later in the session runs with it
 -- left open.
 local function ChargeRow()
  local text,hit=NexusPanel._chargesText,NexusPanel._chargesHover
  return {shown=text:IsShown() and true or false,hover=hit:IsShown() and true or false,text=text:GetText() or ''}
 end
 local function Charged()
  return Model({auto=false,cards=CARDS,recommendation='Take a needed Echo',
   charges={banish=0,reroll=nil,freeze=3,trustworthy=false,arrived=true}})
 end
 out.detailsAtStart=Pn._playDetails==true
 out.chargesClosed=ChargeRow()
 local wasDetails=Pn._playDetails
 local okCharges,errCharges=pcall(function()
  Pn._playDetails=true
  Pn.Render(Charged())
  out.chargesOpen=ChargeRow()
  out.charges=NexusPanel._chargesText:GetText()
  local hover=NexusPanel._chargesHover
  out.legend=S.CaptureTooltip(hover:GetScript('OnEnter'),hover)
  -- Unknown counts (arrived=false) and an all-zero trusted row.
  Pn.Render(Model({auto=false,cards=CARDS,charges={banish=2,reroll=2,freeze=2,arrived=false}}))
  out.chargesUnknown=NexusPanel._chargesText:GetText()
  Pn.Render(Model({auto=false,cards=CARDS,charges={banish=0,reroll=0,freeze=0,trustworthy=true,arrived=true}}))
  out.chargesZero=NexusPanel._chargesText:GetText()
 end)
 Pn._playDetails=wasDetails
 if not okCharges then error(errCharges,0) end
 Pn.Render(Charged())
 out.detailsAtEnd=Pn._playDetails==true
 out.chargesClosedAgain=ChargeRow()

 -- Auto ON: recommended tag, Auto scope row; waiting and paused notes.
 Pn.Render(Model({auto=true,cards=CARDS}))
 out.headingOn=NexusPanel._rollStatus:GetText()
 out.tagOn=cards[1] and cards[1].tag:GetText()
 -- Approved panel cleanup (compact Auto ON): the Auto scope row is closed
 -- behind its own control until the player opens it. Open it (memory only)
 -- and render the same model again, then read the row as before.
 if NexusPanel._autoInfoBtn and not (NexusPanel._autoScopeText and NexusPanel._autoScopeText:IsShown()) then
  NexusPanel._autoInfoBtn:Click()
  Pn.Render(Model({auto=true,cards=CARDS}))
 end
 out.scope=NexusPanel._autoScopeText and NexusPanel._autoScopeText:GetText()
 Pn.Render(Model({auto=true,paused='unsynced'}))
 out.headingWait=NexusPanel._rollStatus:GetText()
 out.bodyWait=NexusPanel._rollRec:GetText()
 Pn.Render(Model({auto=true,paused='user acting'}))
 out.bodyHeld=NexusPanel._rollRec:GetText()
 Pn.Render(Model({auto=true,paused='orb state unknown'}))
 out.bodyOrbHeld=NexusPanel._rollRec:GetText()

 -- Menus through their real builders (no click).
 local identity=function(fn) return fn end
 out.autoMenu={}
 for _,item in ipairs(Pn.AutomationMenuItems(identity)) do out.autoMenu[#out.autoMenu+1]=item.text end
 out.appearance=nil
 for _,item in ipairs(Pn.MoreMenuItems()) do
  -- Found by its Theme.HELP hover, not by the panel's (translatable) title.
  if type(item.menuList)=='table' and item.tooltipText~=nil and item.tooltipText==Nexus.Theme.HELP then out.appearance=item end
 end
 out.themeMenu={}
 local themeItems=Nexus.Theme.MenuItems(function() end)
 for _,item in ipairs(themeItems) do
  out.themeMenu[#out.themeMenu+1]=item.text
  if item.tooltipTitle then out.themeMenu[#out.themeMenu+1]=item.tooltipTitle end
  if item.tooltipText then out.themeMenu[#out.themeMenu+1]=item.tooltipText end
 end
 out.detail=Pn.AutoDetailLines()
 out.scopeLines=R.AutomationScopeLines({selected=true,held='user acting',readOnly=true,settings={autoPick=true}})
 out.settingsRows=R.AutomationSettingsRows({selected=false,readOnly=true,settings={autoReroll=false}})
 out.status={}
 for _,kind in ipairs(R.STATUS_KINDS) do out.status[#out.status+1]=R.StatusText(kind,'x') end
 out.refusals={R.AutoRefusalText('orb'),R.AutoRefusalText('warning'),R.AutoRefusalText('x',''),R.AutoRefusalText('x','raw status')}
 out.legacyStatus={R.Status({advisorOnly=true,level=12,charges={banish=1,trustworthy=false}}),R.Status({synced=false}),R.Status({})}
 out.queue=R.QueueLines({entries={{name='Cinder Lattice',wanted=true},{name='Hollow Bell'}}},3)
 out.tome=R.TOME_PARAGRAPH

 -- Theme refusal notice to chat (no saved write: an unknown id is refused).
 out.themeChat=S.CaptureChat(function() Nexus.Theme.Notify(select(2,Nexus.Theme.SetStyle('bogus-style'))) end)

 -- Callboard: the panel row and the rewards hover (with rows and without).
 local summary=Nexus.CallboardStatus.GetSummary()
 out.callboardLines=summary and summary.lines or {}
 Pn.Render(Model({auto=false}))
 out.callboardRow=NexusPanel._callboardLine and NexusPanel._callboardLine:GetText()
 local owner=CreateFrame('Frame',nil,UIParent)
 out.rewards=S.CaptureTooltip(Nexus.CallboardStatus.ShowRewardsTooltip,owner)

 -- Hardcore notice (no published control in the harness: printed once).
 out.serverChat=S.CaptureChat(Nexus.ServerStatus.OpenHardcoreMenu)

 -- Panel layout: the Orb mini-panel button label chosen by LayoutMetrics.
 local wide=Nexus.LayoutMetrics.Panel({width=420,fontScale=1,uiScale=1,revision=1,activeRoll=true,orbButton=true})
 local narrow=Nexus.LayoutMetrics.Panel({width=300,fontScale=2,uiScale=1,revision=1,activeRoll=true,orbButton=true})
 out.miniWide,out.miniNarrow=wide and wide.orbMiniButtonLabel,narrow and narrow.orbMiniButtonLabel

 out.passive={saved=Saved()==savedBefore,sent=#H.sent-sentBefore,actions=#H.actions-actionsBefore}
 -- Outside the passivity window: an explicit colour choice notifies in chat.
 local chosen
 for _,item in ipairs(themeItems) do if not chosen and item.func and item.checked~=true and not item.disabled and item.text~=themeItems[1].text then chosen=item end end
 out.themeChoice=chosen and S.CaptureChat(chosen.func) or {}
 return out
end

-- The nameplate session: real leaderboard fixture and the installed hook.
local function NameplateSession()
 local fx=LB.New({players={
  {name='Alicia',class='MAGE',dps={dummy=40000},locked=0},
  {name='Bravo',class='PRIEST',dps={lk=20000},locked=0},
 }})
 local H=F.Boot(fx:Install(F.Database({version=2})))
 for _=1,400 do H.Advance(.05,.05) end
 local out={H=H}
 local savedBefore,sentBefore,actionsBefore=Saved(),#H.sent,#H.actions
 out.alicia,out.aliciaAll=HookHover('Alicia')
 out.aliciaAgain=select(1,HookHover('Alicia',out.aliciaAll))
 out.bravo=HookHover('Bravo')
 -- Author and peer lines: display-only stand-ins for the catalog and Sync answers.
 local catalog,sync=Nexus.BuildCatalog,Nexus.Sync
 local isAuthor,peer=catalog.IsAuthor,sync.GetPeerInfo
 catalog.IsAuthor=function(n) return n=='Authorita' end
 sync.GetPeerInfo=function(n) if n=='Peerling' then return {version='1.2.3'} end return peer and peer(n) end
 out.author=HookHover('Authorita')
 out.peer=HookHover('Peerling')
 catalog.IsAuthor,sync.GetPeerInfo=isAuthor,peer
 out.passive={saved=Saved()==savedBefore,sent=#H.sent-sentBefore,actions=#H.actions-actionsBefore}
 return out
end

local function Flatten(list,into)
 into=into or {}
 for _,v in ipairs(list or {}) do if type(v)=='string' and v~='' then into[#into+1]=v end end
 return into
end

------------------------------------------------------------------------
-- 1. Pseudo session (wrap mode)
------------------------------------------------------------------------
S.InstallBootHook()
local hud=HudSession()
check(Nexus.Localization.ActiveLanguage()=='frFR','pseudo pack is the session language')
local d=Nexus.Localization.Diagnostics()
check(d.base.undeclared==0 and d.base.missingDeclared==0,'composed catalog: no undeclared or missing declared key',
 tostring(d.base.undeclared)..'/'..tostring(d.base.missingDeclared))
-- Offer cards (FontStrings and hover lines).
local cardTexts={}
for i=1,3 do
 local c=hud.cards[i]
 check(c and c.shown,'offer card '..i..' is shown')
 if c then
  cardTexts[#cardTexts+1]=c.quality;cardTexts[#cardTexts+1]=c.tag;cardTexts[#cardTexts+1]=c.full
  if c.hoverTag then cardTexts[#cardTexts+1]=c.hoverTag end
 end
end
Strict('offer cards (quality, tag, hover)',cardTexts)
check(hud.cards[1] and hud.cards[1].name=='Cinder Lattice','Echo names are data, inserted unchanged',hud.cards[1] and hud.cards[1].name)
check(hud.cards[1] and hud.cards[1].quality==P('Epic') and hud.cards[1].tag=='> '..P('Wishlist pick'),
 'marked card: shown quality and the code-owned "> " before the pick tag',hud.cards[1] and (hud.cards[1].quality..'|'..hud.cards[1].tag))
check(hud.cards[3] and hud.cards[3].tag=='['..P('Guaranteed offer')..']'
 and hud.cards[3].full=='['..P('Guaranteed offer')..'] '..P('Ashen Tithe ('..P('Uncommon')..')'),
 'guaranteed card: code-owned brackets around the shown marker; hover line re-rendered from the parse',hud.cards[3] and hud.cards[3].full)
check(HasForm(hud.headingOff,{'Current offer - you choose','Offer - you choose','You choose'},P),
 'offer heading (Auto OFF, a fitting form) reaches the heading row',hud.headingOff)
check(hud.bodyOff:find(P('Cinder Lattice ('..P('Epic')..')'),1,true)~=nil,'recommendation target reaches the body',hud.bodyOff)
-- Charges are counts, behind Details: closed, open, closed again (HudSession).
local function Row(row) return type(row)=='table' and (tostring(row.shown)..'/'..tostring(row.hover)..'/['..tostring(row.text)..']') or 'not read' end
check(hud.detailsAtStart==false and type(hud.chargesClosed)=='table' and hud.chargesClosed.shown==false
 and hud.chargesClosed.hover==false and hud.chargesClosed.text=='',
 'count disclosure: with Details closed the compact charge row and its hover are not on the panel',Row(hud.chargesClosed))
check(type(hud.chargesOpen)=='table' and hud.chargesOpen.shown==true and hud.chargesOpen.hover==true and hud.chargesOpen.text==hud.charges,
 'count disclosure: with Details open the compact charge row and its hover are shown',Row(hud.chargesOpen))
check(hud.detailsAtEnd==false and type(hud.chargesClosedAgain)=='table' and hud.chargesClosedAgain.shown==false
 and hud.chargesClosedAgain.hover==false and hud.chargesClosedAgain.text=='',
 'count disclosure: closed again, the same model shows no charge row or hover',Row(hud.chargesClosedAgain))
-- Charges: unknown ? and zero 0 distinct; " ~" code-owned after the whole row.
check(hud.charges==P('B:0 R:? F:3')..' ~','compact row: zero is 0, unknown is ?, the estimate marker follows the row',hud.charges)
check(hud.chargesUnknown==P('B:? R:? F:?'),'unreported counts stay ? (never 0)',hud.chargesUnknown)
check(hud.chargesZero==P('B:0 R:0 F:0'),'reported zero counts stay 0',hud.chargesZero)
check(#hud.legend==6 and hud.legend[2]==hud.charges,'charge hover: title, the complete row and four legend lines',#hud.legend)
local legend={}
for i=3,#hud.legend do legend[#legend+1]=hud.legend[i] end
Strict('charge legend hover',legend)
check(hud.legend[3]==P('B, R and F: the Banish, Reroll and Freeze charges left this run, as the game reported them when Nexus made its last decision.')
 and hud.legend[4]:sub(1,3)=='?: ' and hud.legend[5]:sub(1,3)=='~: ','legend keeps the code-owned ? and ~ marks',hud.legend[4])
-- Auto ON, waiting and paused.
check(HasForm(hud.headingOn,{'Current offer - Auto ON','Offer - Auto ON','Auto ON'},P),'offer heading (Auto ON)',hud.headingOn)
check(hud.tagOn=='> '..P('Recommended'),'Auto ON tag',hud.tagOn)
check(hud.scope==P('Auto may choose offers and, if its save permission is on, save a better finished run over this Saved Build. It never loads a build or starts Orbs.'),
 'Auto scope row reaches its FontString',hud.scope)
check(hud.headingWait:find('... '..P('Waiting for offer data'),1,true)~=nil,'waiting heading',hud.headingWait)
check(hud.bodyWait:find('... '..OPEN..'Waiting for current Echo data.',1,true)~=nil,'waiting note in the body',hud.bodyWait)
check(hud.bodyHeld:find(OPEN..'Paused: '..P("You made an Echo choice in the game's window; Nexus waits about 3 seconds before it acts again.")
 ..' '..P('What helps: wait without choosing; it continues by itself.')..CLOSE,1,true)~=nil,'paused note: reason and hint in one template',hud.bodyHeld)
check(hud.bodyOrbHeld:find(P('What helps: finish, pause or stop the Orb run in Orbs (... menu), or wait until Nexus can read the Orb state.'),1,true)~=nil,
 'Orb hold hint (raw reason matched, shown text translated)',hud.bodyOrbHeld)
-- Menus.
Strict('Automation settings menu items',hud.autoMenu)
check(#hud.autoMenu>=12,'Automation settings menu has its rows',#hud.autoMenu)
Strict('Appearance menu items and hovers',hud.themeMenu)
check(hud.appearance and hud.appearance.tooltipText==P(
 'Appearance changes only how Nexus windows look. Style sets the structure (Nexus Vista is the default; Nexus Slate is the earlier shared dark style of the imported 1.19.3 source and test.9094, with the same colours and shapes; the Orb windows, plain in test.9094, now use it too). Colour sets the accents; Nexus Amethyst purple is the Vista default. The difficulty / Soul Ash card keeps its own look, and no choice changes automation or gameplay.'),
 'Options > Appearance hover is the shown Theme.HELP',hud.appearance and hud.appearance.tooltipText)
check(hud.appearance and hud.appearance.text:find(P(P('Nexus Vista')..', '..P('Nexus Amethyst')),1,true)~=nil,
 'Options > Appearance row carries the shown Theme.Summary',hud.appearance and hud.appearance.text)
check(hud.appearance and hud.appearance.menuList and hud.appearance.menuList[1].text==P('Appearance: style'),'Appearance submenu title')
local scopeShown=false
for _,line in ipairs(hud.detail) do if line==P('With Auto ON, Nexus may only do what these permissions allow:') then scopeShown=true end end
check(scopeShown,'Auto explained lines include the shown scope intro')
Strict('Automation scope lines',hud.scopeLines)
Strict('Automation settings rows',(function() local t={} for _,r in ipairs(hud.settingsRows) do t[#t+1]=r.text end return t end)())
check(hud.settingsRows[3] and hud.settingsRows[3].command=='reroll on' and hud.settingsRows[3].key=='autoReroll',
 'settings rows keep their identity fields (key, command) under a translated label')
Strict('status vocabulary',hud.status)
Strict('Auto refusal lines',hud.refusals)
check(hud.refusals[2]:find('/nexus report',1,true)~=nil,'slash command stays code-owned inside the template',hud.refusals[2])
Strict('legacy status sentence',hud.legacyStatus)
check(hud.legacyStatus[1]==P('Lv 12 - '..P('No Wishlist assigned - recommendations only'))..' | '..P(P('Banish:1 Reroll:0 Freeze:0')..' (estimated)'),
 'legacy status keeps its own knownness (0) and " | " join',hud.legacyStatus[1])
Strict('predicted queue lines',hud.queue)
Strict('tome paragraph',{hud.tome})
-- Chat and tooltips of the other files.
Strict('Theme refusal chat',hud.themeChat)
check(#hud.themeChat==1 and hud.themeChat[1]=='Nexus: '..P('That style is not available in this build. Nothing changed.'),
 'Theme notice reaches chat with its code-owned prefix',hud.themeChat[1])
Strict('Theme choice chat',hud.themeChoice)
check(#hud.themeChoice==1 and hud.themeChoice[1]:find('Nexus: '..OPEN..'Appearance: ',1,true)==1,'explicit colour choice notice',hud.themeChoice[1])
Strict('Callboard progress line',hud.callboardLines)
check(hud.callboardLines[1]=='|cff66d966'..P('Ready for turn-in')..'|r','completed objective line',hud.callboardLines[1])
check(type(hud.callboardRow)=='string' and hud.callboardRow:find(P('Ready for turn-in'),1,true)~=nil,'the panel Callboard row shows it',hud.callboardRow)
Strict('Callboard rewards hover',hud.rewards)
check(hud.rewards[1]==P('Rewards by Difficulty') and #hud.rewards>=7,'rewards hover lines',#hud.rewards)
local tiers=table.concat(hud.rewards,'\n')
check(tiers:find(P('Normal'),1,true) and tiers:find(P('Hardcore I'),1,true) and tiers:find(P('900 XP'),1,true)
 and tiers:find(P('2.50M Ash'),1,true) and tiers:find(P('1K Ash'),1,true) and tiers:find(P('1500 XP'),1,true),'difficulty names and reward units shown; amounts inserted verbatim',tiers)
Strict('Hardcore notice chat',hud.serverChat)
check(#hud.serverChat==1 and hud.serverChat[1]:find('|cff7fd5ffNexus:|r '..OPEN,1,true)==1,'Hardcore notice keeps the code-owned prefix',hud.serverChat[1])
check(hud.miniWide==P('Orb mini panel') and hud.miniNarrow==P('Mini'),'Orb mini-panel label (wide and narrow)',
 tostring(hud.miniWide)..'|'..tostring(hud.miniNarrow))
check(hud.passive.saved and hud.passive.sent==0 and hud.passive.actions==0,
 'passive: rendering, hovering and opening menus change no saved table, send nothing, act on nothing',
 tostring(hud.passive.saved)..' sent='..hud.passive.sent..' actions='..hud.passive.actions)

S.InstallBootHook()
local np=NameplateSession()
local npLines=Flatten(np.alicia,Flatten(np.bravo,Flatten(np.author,Flatten(np.peer))))
Strict('unit tooltip lines (real hook)',npLines)
check(np.alicia[1]=='|cff7fd5ff'..P('Nexus user')..'|r' and #np.alicia==2,'badge and rank line added once',#np.alicia)
check(np.alicia[2] and np.alicia[2]:find(OPEN..'|cffffd200'..P('1st')..'|r on leaderboard  |cff4dff8040k|r  '..P('Dummy')..CLOSE,1,true)~=nil,
 'rank line: ordinal, DPS and category inserted into one sentence',np.alicia[2])
check(#np.aliciaAgain==0,'translated badge still marks the tooltip: a second hook call adds nothing',#np.aliciaAgain)
check(np.bravo[2] and np.bravo[2]:find(P('1st'),1,true)~=nil and np.bravo[2]:find(P('LK'),1,true)~=nil,'LK category rank line',np.bravo[2])
check(np.author[2]=='|cff888888'..P('Community build author')..'|r','author line',np.author[2])
check(np.peer[1]=='|cff7fd5ff'..P('Nexus user')..'|r  |cff888888v1.2.3|r' and np.peer[2]=='|cff888888'..P('Nexus user seen on the build-sharing network')..'|r',
 'peer badge with version data and the peer line',tostring(np.peer[1])..'|'..tostring(np.peer[2]))
check(np.passive.saved and np.passive.sent==0 and np.passive.actions==0,'passive: unit-tooltip hovers write, send and do nothing')

------------------------------------------------------------------------
-- 2. Templates: unknown count ?, zero 0, long and non-ASCII names verbatim.
------------------------------------------------------------------------
do
 local R=Nexus.Readout
 local long=string.rep('Ë',60)..' Kaltherzflügel der Ewigkeit'
 local o=R.OfferCard(long..' (Rare)',false,false,{name=long,quality=2})
 check(o.name==long and o.full==P(long..' ('..P('Rare')..')'),'a long non-ASCII Echo name is inserted verbatim',o.full)
 local t=R.RecommendationWithTarget('',long..' (Rare)',{name=long,quality=2})
 check(t==P('Take: '..P(long..' ('..P('Rare')..')')),'take target with a long name',t)
 local L=Nexus.Localization
 check((L.Format('readout.charge_counts',{banish=L.Count(nil),reroll=L.Count(0),freeze=L.Count(4)}))==P('B:? R:0 F:4'),
  'count slots: nil is ?, zero is 0 (seam contract on the family row)')
 check(R.ChargesLine({banish=0,reroll=0/0,freeze=-1,arrived=true})==P('B:0 R:? F:?'),'ChargesLine: invalid counts are ?, zero stays 0')
 -- R5 P37: a card without a supplied name carries its generated fallback
 -- as a fact; the line text and its parsing keep "spell <id>" raw, and the
 -- display says the fallback through main.value.unknown_spell. A supplied
 -- name that reads like "spell 123" stays as it is.
 local nameless={spellId=200123,quality=2}
 local facts=R.CardFacts(nameless)
 local line=R.CardLine(nameless,'wanted')
 check(facts.generated==true and facts.spellId==200123 and facts.name=='spell 200123' and line:find('^spell 200123 %(Rare%)')~=nil,
  'R5 P37: the raw line and facts keep the generated name: '..line)
 local o=R.OfferCard(line,false,false,facts)
 check(o.name==P('spell 200123'),'R5 P37: the offer card says the generated name through its key: '..tostring(o.name))
 check(R.CardLineShown(line,facts):find(P(P('spell 200123')..' ('..P('Rare')..')'),1,true)==1,'R5 P37: the one-line row says it too: '..R.CardLineShown(line,facts))
 check(R.RecommendationWithTarget('',line,facts)==P('Take: '..P(P('spell 200123')..' ('..P('Rare')..')')),'R5 P37: the take target says it too')
 local real={name='spell 123',spellId=200999,quality=2}
 local realFacts=R.CardFacts(real)
 local ro=R.OfferCard(R.CardLine(real),false,false,realFacts)
 check(not realFacts.generated and ro.name=='spell 123','R5 P37: a supplied name that reads like the fallback stays verbatim: '..tostring(ro.name))
 local q=R.QueueLines({entries={{spellId=200124,wanted=true},{name='spell 7'}}},2)
 check(q[1]==P('1. '..P('spell 200124')..' [wanted] (predicted)') and q[2]==P('2. spell 7 (predicted)'),'R5 P37: queue lines: generated through its key, supplied verbatim: '..table.concat(q,' | '))
end

------------------------------------------------------------------------
-- 3. Long mode on the densest surface: renders, no error, text shown.
------------------------------------------------------------------------
S.InstallBootHook('long')
local okLong,longHud=pcall(HudSession)
check(okLong,'long mode: the HUD session runs without error',longHud)
if okLong then
 check(type(longHud.cards[1])=='table' and S.IsPseudo(longHud.cards[1].quality),'long mode: card quality shown',longHud.cards[1] and longHud.cards[1].quality)
 check(S.IsPseudo(longHud.headingOff),'long mode: heading shown',longHud.headingOff)
 -- Its doubled-letter entry exceeds the 256-byte text contract, so the pack
 -- refuses it and the exact English is shown (the documented fallback).
 check(longHud.scope=='Auto may choose offers and, if its save permission is on, save a better finished run over this Saved Build. It never loads a build or starts Orbs.',
  'long mode: an over-contract entry falls back to the exact English Auto scope row',longHud.scope)
 check(#longHud.autoMenu>=12 and S.IsPseudo(longHud.autoMenu[1]),'long mode: Automation menu shown',#longHud.autoMenu)
 check(S.IsPseudo(longHud.rewards[1] or ''),'long mode: rewards hover shown',longHud.rewards[1])
 check(S.IsPseudo(longHud.legend[3] or ''),'long mode: legend shown',longHud.legend[3])
 check(longHud.passive.saved and longHud.passive.sent==0 and longHud.passive.actions==0,'long mode: still passive')
end

------------------------------------------------------------------------
-- 4. Missing entries fall back to the exact English.
------------------------------------------------------------------------
local entries=S.PseudoEntries()
local REMOVED={'readout.label.offer_pick','readout.value.quality_epic','readout.tooltip.charges_legend_unknown',
 'theme.menu.style_title','callboard.heading.rewards_by_difficulty','readout.heading.offer_you_choose'}
for _,k in ipairs(REMOVED) do check(entries[k]~=nil,'fixture: pseudo entry exists for '..k);entries[k]=nil end
S.InstallBootHook(nil,entries)
local partial=HudSession()
check(partial.cards[1] and partial.cards[1].tag=='> Wishlist pick' and partial.cards[1].quality=='Epic',
 'missing entries: pick tag and quality show exact English',partial.cards[1] and partial.cards[1].tag)
check(partial.legend[4]=='?: the game has not reported that count yet. It is unknown, not zero.','missing legend entry is English',partial.legend[4])
check(partial.themeMenu[1]=='Appearance: style','missing menu title is English',partial.themeMenu[1])
check(partial.rewards[1]=='Rewards by Difficulty','missing hover title is English',partial.rewards[1])
check(not S.IsPseudo(partial.headingOff) or partial.headingOff:find(P('Current offer - you choose'),1,true)==nil,
 'the removed long heading is never shown as pseudo',partial.headingOff)
check(Nexus.Readout.OfferHeading(false)=='Current offer - you choose','missing heading entry is exact English')
check(S.IsPseudo(partial.cards[2] and partial.cards[2].quality or ''),'other keys stay translated beside the missing ones')

------------------------------------------------------------------------
-- 5. English session: exact legacy bytes; the same with the seam absent.
------------------------------------------------------------------------
local en=HudSession()
check(Nexus.Localization.ActiveLanguage()=='enUS','English session')
local function NoSeam(fn,...)
 local seam=Nexus.Localization;Nexus.Localization=nil
 local r={pcall(fn,...)};Nexus.Localization=seam
 assert(r[1],r[2]);return unpack(r,2)
end
local R=Nexus.Readout
check(en.cards[1].quality=='Epic' and en.cards[1].tag=='> Wishlist pick' and en.cards[3].tag=='[Guaranteed offer]'
 and en.cards[3].full=='[Guaranteed offer] Ashen Tithe (Uncommon)','English cards are byte-identical',en.cards[3].full)
check(en.charges=='B:0 R:? F:3 ~' and en.chargesUnknown=='B:? R:? F:?' and en.chargesZero=='B:0 R:0 F:0','English charge rows')
check(en.detailsAtStart==false and en.chargesClosed.shown==false and en.chargesClosed.text=='' and en.chargesOpen.shown==true
 and en.chargesOpen.text=='B:0 R:? F:3 ~' and en.detailsAtEnd==false and en.chargesClosedAgain.shown==false and en.chargesClosedAgain.text=='',
 'English count disclosure: no charge row with Details closed, the row with Details open, none again once closed')
check(en.legend[3]=='B, R and F: the Banish, Reroll and Freeze charges left this run, as the game reported them when Nexus made its last decision.'
 and en.legend[6]=='Shown with Auto OFF, where you choose; with Auto ON Nexus uses these charges itself.','English legend')
check(en.bodyOff:find('Cinder Lattice (Epic)',1,true)~=nil and en.scope=='Auto may choose offers and, if its save permission is on, save a better finished run over this Saved Build. It never loads a build or starts Orbs.',
 'English target and Auto scope row')
check(en.themeMenu[1]=='Appearance: style' and en.appearance.text:find('Nexus Vista, Nexus Amethyst',1,true)~=nil,'English Appearance menu')
check(en.rewards[1]=='Rewards by Difficulty' and en.serverChat[1]=="|cff7fd5ffNexus:|r The Hardcore menu is not available yet. Choose 'Use Server Difficulty / Soul Ash HUD' in the Nexus menu and open it from the server HUD.",
 'English Callboard hover and Hardcore notice',en.serverChat[1])
check(en.miniWide=='Orb mini panel' and en.miniNarrow=='Mini','English mini-panel labels')
check(en.passive.saved and en.passive.sent==0 and en.passive.actions==0,'English session: passive')
-- Every builder: catalog English equals the code's legacy English (seam absent).
local same,total=0,0
local function Same(label,fn,...)
 total=total+1
 local a=F.Serialize({fn(...)});local b=F.Serialize({NoSeam(fn,...)})
 if check(a==b,'English == seam-absent legacy bytes: '..label,a..' vs '..b) then same=same+1 end
end
for _,auto in ipairs({true,false}) do Same('OfferHeadingForms',R.OfferHeadingForms,auto) end
Same('OfferCard',R.OfferCard,CARDS[3].text,true,false,CARDS[3].facts,false)
Same('OfferCard freeze',R.OfferCard,'Hollow Bell (Rare) wanted',false,false,nil,true)
Same('ChargesLegend',R.ChargesLegend)
Same('Status',R.Status,{level=3,advisorOnly=true,charges={banish=2,trustworthy=false}})
for _,kind in ipairs(R.STATUS_KINDS) do Same('StatusText '..kind,R.StatusText,kind,'detail') end
for _,reason in ipairs({'manual mode','loading screen (waiting for world entry)','settling after world entry','user acting',
 'Another Echo automation addon is loaded -- disable it','client auto-accept re-enabled','orb state unknown','other','unsynced'}) do
 Same('AutoHoldNote '..reason,R.AutoHoldNote,reason)
end
for _,k in ipairs({'orb','warning','x'}) do Same('AutoRefusalText '..k,R.AutoRefusalText,k,'') end
Same('AutomationScopeLines',R.AutomationScopeLines,{selected=true,held='user acting',readOnly=true,settings={autoPick=false,autoActivate=true}})
Same('AutomationSettingsRows',R.AutomationSettingsRows,{selected=true,readOnly=true,settings={autoReroll=false,autoFreeze=true}})
Same('QueueLines',R.QueueLines,{entries={{name='A',wanted=true},{name='B'}}},2)
Same('RecommendationWithTarget',R.RecommendationWithTarget,'Take a needed Echo',CARDS[1].text,CARDS[1].facts)
-- R5 P37: the generated fallback's English is the raw bytes.
do
 local nameless={spellId=200123,quality=2}
 local facts=R.CardFacts(nameless)
 local line=R.CardLine(nameless,'wanted')
 Same('OfferCard generated name',R.OfferCard,line,false,false,facts,false)
 Same('CardLineShown generated name',R.CardLineShown,line,facts)
 Same('QueueLines generated name',R.QueueLines,{entries={{spellId=200124,wanted=true}}},1)
 check(R.OfferCard(line,false,false,facts).name=='spell 200123','R5 P37 English: the generated name is the exact English')
end
for _,k in ipairs({'OFFER_PICK_TAG','OFFER_RECOMMENDED_TAG','OFFER_FREEZE_TAG','OFFER_GUARANTEED_TAG','WAITING_OFFER_HEADING',
 'WAITING_OFFER_NOTE','AUTO_ON_NOTE','TOME_PARAGRAPH'}) do Same(k,function() return R[k] end) end
Same('Theme.MenuItems',function() local t={} for _,i in ipairs(Nexus.Theme.MenuItems()) do t[#t+1]={i.text,i.tooltipTitle,i.tooltipText} end return t end)
Same('Theme.HELP',function() return Nexus.Theme.HELP end)
Same('Theme.Summary',Nexus.Theme.Summary)
Same('Theme.SetStyle refusal',function() return select(2,Nexus.Theme.SetStyle('bogus')) end)
Same('Callboard rewards hover',S.CaptureTooltip,Nexus.CallboardStatus.ShowRewardsTooltip,CreateFrame('Frame',nil,UIParent))
check(same==total,'English and legacy bytes agree for every builder',same..'/'..total)

local npEn=NameplateSession()
check(npEn.alicia[1]=='|cff7fd5ffNexus user|r' and npEn.alicia[2]=='|cff888888'..TITLE..'...|r  |cffffd2001st|r on leaderboard  |cff4dff8040k|r  Dummy'
 and #npEn.aliciaAgain==0 and npEn.bravo[2]=='|cff888888'..TITLE..'...|r  |cffffd2001st|r on leaderboard  |cff4dff8020k|r  LK'
 and npEn.author[2]=='|cff888888Community build author|r' and npEn.peer[2]=='|cff888888Nexus user seen on the build-sharing network|r',
 'English unit tooltip lines are byte-identical; the badge still deduplicates',tostring(npEn.alicia[2])..' | '..tostring(npEn.bravo[2]))

if #failures>0 then
 for _,f in ipairs(failures) do print('FAIL',f) end
 error('l10n_ui_hud: '..#failures..' of '..checks..' checks failed')
end
print('l10n_ui_hud: '..checks..' checks')
