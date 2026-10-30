-- Full UI localization (issues #143-#148), journal family: the Nexus Progress
-- tab inside the game's Echo Journal (page, Wishlist strip, Wishlist chooser,
-- Auto ON consent, chat) and the Plan alternatives window (Flexible plan
-- chooser) show their code-owned text through Nexus.Localization at display.
--
-- Four real TOC boots in this process (tests/prototype/harness.lua):
--  PSEUDO  a pseudo pack (l10n_pseudo_support) is the session language from
--          load: every visible text of the real windows in their main states,
--          their real OnEnter hovers, the real consent dialog and real chat
--          lines must be pseudo-marked; only listed data and the two pending
--          literals may stay plain. Render, hover, navigation and Cancel are
--          checked passive (saved tables, sends, actions, popups unchanged).
--  LONG    the long pseudo model on the densest states: no error, text shown.
--  MISSING a pseudo pack without some journal/plan keys: those show exact
--          English, the rest stays pseudo.
--  ENGLISH no pack: exact English bytes for representative keys at their real
--          receivers, unknown "?" vs zero "0", long and non-ASCII names
--          inserted verbatim.
-- Synthetic offline evidence only: no native font, glyph, layout or client
-- behaviour is claimed (native NOT_RUN).
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua') -- F.Serialize only (no boot)
local checks,failures=0,{}
local function check(ok,label,detail)
 checks=checks+1
 if not ok then failures[#failures+1]=label..(detail and (' :: '..tostring(detail)) or '') end
end

local H
local FAMILIES={'Arcane Echo','Fire Echo','Frost Echo','Shadow Echo'}
local OFF_LINE='Holy Echo  (a later run may reduce these extras)'
local NOTES_FIRST='Compares the assigned Wishlist with the active Saved Build; planned locked targets are not proof of ownership.'
local UNICODE='\195\156n\195\175c\195\184d\195\169 \226\156\147 Plan' -- "Ünïcødé ✓ Plan"
local LONG_NAME=string.rep('Long Plan Name ',13)..'End'
local function Copy(list) local out={} for i,v in ipairs(list) do out[i]=v end return out end
local function Target(tag,total,rep,miss,off)
 return ("Wishlist 'L10n plan'%s: %d Echo families -- %d represented, %d missing, %d off-Wishlist families in the saved build")
  :format(tag,total,rep,miss,off)
end
local function Tome(name,id,state,pending,extra)
 local t={name=name,leverId=id,observed=state,known=true,status=state=='disabled' and 'Disabled' or 'Enabled',
  icon='Interface\\Icons\\Tome_'..id,iconSource='tome spell',echoNames={name..' Echo'},pending=pending}
 for k,v in pairs(extra or {}) do t[k]=v end
 return t
end
-- Provider sections (the automation runtime's own English; pending family).
local function Sections(kind)
 local notes={title='Notes',lines={NOTES_FIRST,'about 3 runs'}}
 if kind=='valid' then
  return {{title='Target',lines={Target(' (Echo Wishlist build)',5,1,4,1)}},{title='Pending (4)',lines=Copy(FAMILIES)},
   {title='Extra copies compared with the plan',lines={OFF_LINE}},
   {title='Tome requests awaiting confirmation',lines={'Tome request text fallback'},
    tomeRows={Tome('Tome of Enabling',880201,'disabled','enable'),Tome('Tome of Disabling',880202,'enabled','disable'),
     Tome('Tome of Unknown',880203,'enabled','sideways')}},
   {title='Tome states',lines={'fallback'},tomeRows={Tome('Tome of Stale',880204,'enabled',nil,{stale=true,
     iconSource='representative Echo spell',reason='Server reason text',plan='Plan text',echoNames={'One Echo','Two Echo'}}),
    Tome('Tome of Nothing',880205,'mixed',nil,{status='',icon=nil,iconSource=nil,echoNames={}}),
    Tome('Tome of Other',880206,'enabled',nil,{iconSource='elsewhere',leverId=nil})}},notes}
 elseif kind=='one' then
  return {{title='Target',lines={Target('',2,1,1,0)}},{title='Pending (1)',lines={'Arcane Echo'}},
   {title='Extra copies compared with the plan',lines={}},{title='Notes',lines={NOTES_FIRST,'estimate unavailable'}}}
 elseif kind=='two' then
  return {{title='Target',lines={Target('',3,1,2,0)}},{title='Pending (2)',lines={'Arcane Echo','Fire Echo'}},notes}
 elseif kind=='none_missing' then
  return {{title='Target',lines={Target('',2,2,0,0)}},{title='Pending (0)',lines={}},
   {title='Extra copies compared with the plan',lines={}},notes}
 elseif kind=='zero' then
  return {{title='Target',lines={Target('',0,0,0,0)}},{title='Pending (0)',lines={}},notes}
 elseif kind=='no_target' then
  return {{title='Target',lines={'No wishlist set - advisor only'}}}
 elseif kind=='no_summary' then
  return {{title='Pending (4)',lines=Copy(FAMILIES)},notes}
 elseif kind=='no_pending' then
  return {{title='Target',lines={Target('',5,1,4,1)}},notes}
 elseif kind=='bad_pending' then
  return {{title='Target',lines={Target('',5,1,4,1)}},{title='Pending (3)',lines=Copy(FAMILIES)},notes}
 elseif kind=='contradictory' then
  return {{title='Target',lines={Target('',9,1,4,1)}},{title='Pending (4)',lines=Copy(FAMILIES)},notes}
 elseif kind=='grammar' then
  return {{title='Target',lines={Target(' (new tag)',5,1,4,1)}},{title='Pending (4)',lines=Copy(FAMILIES)},notes}
 end
end
local PAGE_KINDS={'valid','one','two','none_missing','zero','no_target','no_summary','no_pending','bad_pending',
 'contradictory','grammar'}
local providerData,providerFails=nil,false
local CAT={rows={[300001]={spellId=300001,quality=2,maxStack=5,name='Alpha Echo'},
 [300002]={spellId=300002,quality=1,maxStack=3,groupId=7,name=UNICODE},
 [300003]={spellId=300003,quality=0,maxStack=1,name='Gamma Echo'}}}

-- Data that is never translated: fixture names, provider lines and titles
-- (and their UserText.Message forms), game names. Exact whole texts only.
local DATA={}
local function Data(text) DATA[text]=true end
local function Boot(mode,entries)
 Nexus=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusDB=nil
 if mode then S.InstallBootHook(mode~='wrap' and mode or nil,entries) end
 H=dofile('tests/prototype/harness.lua')
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,ConfirmSpend=function()error('no spend')end}
 H.Boot()
 local echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}
 H.perks.serverBuildSlots={[1]={name='Main Build',verified=true,echoes=H.Clone(echoes)},
  [2]={name='',verified=true,echoes=H.Clone(echoes)},[3]={name='Empty',verified=true,echoes={}},
  [101]={name='Plan A',verified=false,echoes=H.Clone(echoes)},[102]={name=UNICODE,verified=false,echoes=H.Clone(echoes)},
  [103]={name=LONG_NAME,verified=false,echoes=H.Clone(echoes)}}
 H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();H.Advance(2)
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:SetSize(570,450)
 CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
 CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
 providerData,providerFails=nil,false
 assert(Nexus.JournalTab.TryInstall(function()
  if providerFails then error('provider failed') end
  return providerData
 end),'SETUP: the real Journal tab installs')
 if NexusJournalScroll then NexusJournalScroll:SetSize(520,360) end
 journal:Show()
 local active=mode and Nexus.Localization.ActiveLanguage() or 'enUS'
 assert(mode and active=='frFR' or (not mode and active=='enUS'),'SETUP: session language '..tostring(active))
 return H
end

local collected
local function Add(where,text) if type(text)=='string' and text~='' then collected[#collected+1]={where=where,text=text} end end
local function Scan(where,root) for _,item in ipairs(S.VisibleTexts(root)) do Add(where,item.text) end end
local function Hover(where,frame)
 local fn=frame and frame:GetScript('OnEnter')
 if not fn then check(false,'SETUP hover reachable: '..where);return {} end
 local lines=S.CaptureTooltip(function() fn(frame) end)
 for _,l in ipairs(lines) do Add(where..' hover',l) end
 local leave=frame:GetScript('OnLeave');if leave then leave(frame) end
 return lines
end
local function Chat(where,fn)
 local lines=S.CaptureChat(fn)
 for _,l in ipairs(lines) do Add(where..' chat',l) end
 return lines
end
local function Page() return NexusJournalScroll and NexusJournalScroll.scrollChild end
local function ButtonOn(root,pred)
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and pred(f) then
   local p=f.parent;while p and p~=root do p=p.parent end
   if p==root then return f end
  end
 end
end
local function Rows(tome)
 local out={}
 for _,f in ipairs(H.frames) do
  if f.parent==Page() and f.label and f.status and f:IsVisible() and ((f.tome~=nil)==tome) then out[#out+1]=f end
 end
 return out
end
local function OpenPage()
 if not NexusJournalPanel:IsVisible() then NexusJournalTab:Click() end
 assert(NexusJournalPanel:IsVisible(),'SETUP: the Nexus Progress page opens through its tab')
end
local function Details(want)
 local b=ButtonOn(Page(),function(f) return f.scripts.OnClick and f:GetWidth()==112 end)
 assert(b,'SETUP: the Show/Hide details button')
 local shown=Page() and false
 for _,item in ipairs(S.VisibleTexts(Page())) do
  if S.Unmarked(item.text):find('About this page',1,true) or item.text:find('About this page',1,true)
   or item.text:find('\194\171About',1,true) then shown=true end
 end
 if shown~=want then b:Click() end
 return b
end
local function Render(kind,details)
 providerFails=kind=='error'
 providerData=(kind~='error' and kind~='nodata') and {sections=Sections(kind),version='Nexus build 1.0'} or nil
 OpenPage()
 Nexus.JournalTab.Refresh()
 Details(details)
 Nexus.JournalTab.Refresh()
end

-- Every page state, hover, strip, picker and chooser state; returns nothing.
local function DriveJournal(tag)
 local J=Nexus.JournalTab
 Hover(tag..' tab',NexusJournalTab)
 Scan(tag..' tab',NexusJournalTab)
 for _,kind in ipairs({'nodata','error'}) do
  for _,d in ipairs({false,true}) do Render(kind,d);Scan(tag..' page '..kind,NexusJournalPanel) end
 end
 for _,kind in ipairs(PAGE_KINDS) do
  for _,d in ipairs({false,true}) do
   Render(kind,d);Scan(tag..' page '..kind..(d and ' details' or ''),NexusJournalPanel)
   for _,row in ipairs(Rows(false)) do Hover(tag..' family row '..kind,row) end
   for _,row in ipairs(Rows(true)) do Hover(tag..' tome row '..kind,row) end
   for _,b in ipairs({J._pageHelpButton,J._pageReferenceButton}) do Hover(tag..' page button',b) end
   local details=ButtonOn(Page(),function(f) return f:GetWidth()==112 end);Hover(tag..' details button',details)
   local builds=ButtonOn(Page(),function(f) return f:GetWidth()==150 end)
   if builds then Hover(tag..' builds button',builds) end
  end
 end
 -- The intro and counts hovers (frames without text, over their lines).
 Render('valid',false)
 for _,f in ipairs(H.frames) do
  if f.parent==Page() and f.kind=='Frame' and not f.label and f.scripts.OnEnter and f:IsShown() then Hover(tag..' page hover',f) end
 end
 -- Counts hover with an empty and an unreadable off-Wishlist list.
 for _,kind in ipairs({'one','two'}) do
  Render(kind,false)
  for _,f in ipairs(H.frames) do
   if f.parent==Page() and f.kind=='Frame' and not f.label and f.scripts.OnEnter and f:IsShown() then Hover(tag..' counts hover '..kind,f) end
  end
 end
 -- Back to the Journal: the strip, its hovers and the chooser.
 NexusJournalTab:Click()
 J.RefreshAssociations()
 local strip=NexusLoadoutAssociationPanel
 Scan(tag..' strip',strip)
 Hover(tag..' strip selector',NexusActiveWishlistSelector)
 Hover(tag..' strip new',strip.newWishlist)
 Hover(tag..' strip design',strip.design)
 NexusActiveWishlistSelector:Click()
 local picker=NexusWishlistOnlyPicker
 Scan(tag..' picker',picker)
 Hover(tag..' strip selector (picker open)',NexusActiveWishlistSelector)
 for _,r in ipairs(picker.children) do
  if r.nameButton and r:IsVisible() then Hover(tag..' picker row',r.nameButton);Hover(tag..' picker gear',r.gear) end
 end
 NexusActiveWishlistSelector:Click()
end

-- Strip and picker for the other targets: unnamed Saved Build, empty Saved
-- Build, no Saved Build; an assigned Wishlist (Unassign row, design hovers).
local function DriveTargets(tag)
 local J=Nexus.JournalTab
 for _,slot in ipairs({2,3,0}) do
  H.perks.serverActiveSlot=slot;H.Notify();Nexus.GameAdapter.Poll()
  J.RefreshAssociations()
  Scan(tag..' strip slot '..slot,NexusLoadoutAssociationPanel)
  Hover(tag..' selector slot '..slot,NexusActiveWishlistSelector)
  Hover(tag..' design slot '..slot,NexusLoadoutAssociationPanel.design)
  NexusActiveWishlistSelector:Click()
  Scan(tag..' picker slot '..slot,NexusWishlistOnlyPicker)
  for _,r in ipairs(NexusWishlistOnlyPicker.children) do
   if r.nameButton and r:IsVisible() then Hover(tag..' picker row slot '..slot,r.nameButton) end
  end
  if NexusWishlistOnlyPicker.clearRow and NexusWishlistOnlyPicker.clearRow:IsVisible() then
   Hover(tag..' unassign slot '..slot,NexusWishlistOnlyPicker.clearRow)
  end
  NexusActiveWishlistSelector:Click()
 end
 H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
end

-- The Plan alternatives window in its main states (no Save: passive part).
local function NewChooser(withStore)
 return Nexus.FlexiblePlanChooser.New({catalog=function() return CAT end,openDraft=function() return true end,
  persistence=withStore and Nexus.FlexiblePlanStore.New({store=Nexus.Store}) or nil})
end
local function CatalogAction(id)
 for _,r in ipairs(NexusFlexiblePlanCatalog.children) do if r.spellId==id and r.action then return r.action end end
end
local function PoolRow(id)
 for _,r in ipairs(NexusFlexiblePlanPool.children) do if r.spellId==id and r.count then return r end end
end
local function DriveChooser(tag,chooser)
 chooser.Show()
 Scan(tag..' chooser empty',NexusFlexiblePlanChooser)
 CatalogAction(300001):Click();CatalogAction(300002):Click()
 Scan(tag..' chooser two rows',NexusFlexiblePlanChooser)
 PoolRow(300001).count:SetText('2')
 Scan(tag..' chooser pending',NexusFlexiblePlanChooser)
 NexusFlexiblePlanOpen:Click() -- refused while a count is pending
 Scan(tag..' chooser refusal',NexusFlexiblePlanChooser)
 PoolRow(300001).action:Click()
 PoolRow(300002).count:SetText('99');PoolRow(300002).action:Click() -- refused: invalid selection
 Scan(tag..' chooser invalid',NexusFlexiblePlanChooser)
 PoolRow(300002).count:SetText('0');PoolRow(300002).action:Click()
 chooser.LoadPool() -- nothing saved: refused, pool unchanged
 Scan(tag..' chooser nothing saved',NexusFlexiblePlanChooser)
 chooser.Hide()
end

local function Snapshot()
 return {db=F.Serialize(NexusDB or {}),wr=F.Serialize(WishlistRealizerDB or {}),sent=#H.sent,actions=#H.actions,
  state=F.Serialize(Nexus.Store.State() or {}),popup=H.popup and H.popup.which or 'none'}
end
local function SameSnapshot(a,b)
 return a.db==b.db and a.wr==b.wr and a.sent==b.sent and a.actions==b.actions and a.state==b.state and a.popup==b.popup
end

local PENDING_LITERALS={}
-- Owner integration (pseudo helper fix f571dd5): a seam text that the code
-- shortens (ShortName: a prefix plus "...") has no closing marker. It counts
-- as reviewed text only when it is the opener plus a prefix, cut on a UTF-8
-- character boundary, of a real pseudo entry, then "...", with optional
-- code-owned trailing ":"; anything else stays reported.
local PSEUDO_VALUES
local function Plain(text) return (tostring(text):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
local function ShortenedSeamText(text)
 local body=Plain(text):match('^('..S.OPEN..'.-)%.%.%.:?$')
 if not body or body:find(S.CLOSE,1,true) or not Nexus.Localization.IsText(body) then return false end
 PSEUDO_VALUES=PSEUDO_VALUES or S.PseudoEntries()
 for _,value in pairs(PSEUDO_VALUES) do if value:sub(1,#body)==body then return true end end
 return false
end
local function Allowed(text)
 if ShortenedSeamText(text) then return true end
 local rest=S.Unmarked(text):gsub('^%s+',''):gsub('%s+$','')
 if rest=='' or DATA[rest] or PENDING_LITERALS[rest] then return true end
 -- A row or selector shows a data name plus code-owned punctuation.
 local name=rest:match('^(.-):$') or rest:match('^(.-)%.%.%.$')
 if name and (DATA[name] or DATA[name..'...']) then return true end
 -- The chat prefix "Nexus:" is code-owned product branding around reviewed text.
 if text:find('^|cff%x%x%x%x%x%xNexus:|r ') then
  local body=S.Unmarked(text:gsub('^|cff%x%x%x%x%x%xNexus:|r ',''))
  return body:gsub('%s','')=='' or DATA[body]==true
 end
 return false
end
local function Untranslated()
 local out={}
 for _,item in ipairs(collected) do
  if not Allowed(item.text) and S.LooksUntranslated(item.text) then out[#out+1]=item.where..': '..item.text end
 end
 return out
end
local function RegisterData()
 for _,n in ipairs(FAMILIES) do Data(n) end
 for _,n in ipairs({'Holy Echo','Main Build','Plan A',UNICODE,LONG_NAME,'Empty','Alpha Echo','Gamma Echo','Nexus build 1.0',
  'Tome of Enabling','Tome of Disabling','Tome of Unknown','Tome of Stale','Tome of Nothing','Tome of Other','Enabled',
  'Disabled','Server reason text','Plan text','Tome request text fallback','fallback','about 3 runs',OFF_LINE,NOTES_FIRST,
  'estimate unavailable','No wishlist set - advisor only'}) do Data(n) end
 -- Provider section titles and lines as shown (UserText.Message applies).
 for _,kind in ipairs(PAGE_KINDS) do
  for _,sec in ipairs(Sections(kind)) do
   Data(sec.title);Data(Nexus.UserText.Message(sec.title))
   for _,l in ipairs(sec.lines or {}) do l=tostring(l);Data(l);Data(Nexus.UserText.Message(l)) end
  end
 end
 -- The provider Target line's head (the Wishlist title as supplied).
 Data("Wishlist 'L10n plan'");Data("Wishlist 'L10n plan' (Echo Wishlist build)")
 for _,n in ipairs({'Main Build','Plan A',UNICODE,LONG_NAME}) do
  Data(n:sub(1,17)..'...');Data(n:sub(1,18)..'...');Data(n:sub(1,21)..'...');Data(n:sub(1,25)..'...')
 end
end

------------------------------------------------------------------------
-- PSEUDO
------------------------------------------------------------------------
Boot('wrap')
RegisterData()
collected={}
local before=Snapshot()
DriveJournal('pseudo')
DriveTargets('pseudo')
local chooser=NewChooser(true)
DriveChooser('pseudo',chooser)
DriveChooser('pseudo no-store',NewChooser(false))
-- Unavailable catalog state.
do
 local c=Nexus.FlexiblePlanChooser.New({catalog=function() return nil end,openDraft=function() end})
 c.Show();Scan('pseudo chooser no catalog',NexusFlexiblePlanChooser);c.Hide()
end
-- The Auto ON consent: shown, read and cancelled (Cancel changes nothing).
local J=Nexus.JournalTab
local realAuto=J.AutoSelected
J.AutoSelected=function() return true end
J.RefreshAssociations();NexusActiveWishlistSelector:Click()
local planRow
for _,r in ipairs(NexusWishlistOnlyPicker.children) do
 if r.nameButton and r:IsVisible() and S.Unmarked(r.nameButton.text:GetText()):find(UNICODE,1,true) then planRow=r end
end
check(planRow~=nil,'SETUP pseudo: the picker lists the non-ASCII Wishlist')
if planRow then planRow.nameButton:Click() end
local p=H.popup
check(p and p.which=='NEXUS_ASSIGN_WISHLIST_AUTO_ON','PSEUDO consent: the Auto ON click asks first')
if p then
 local d=StaticPopupDialogs[p.which]
 local shown=string.format(d.text,p.arg1,p.arg2)
 Add('pseudo consent dialog',shown);Add('pseudo consent button',d.button1);Add('pseudo consent button',d.button2)
 check(S.IsPseudo(d.button1) and S.IsPseudo(d.button2),'PSEUDO consent: both dialog buttons are reviewed text',d.button1)
 check(shown:find("'"..UNICODE.."'",1,true)~=nil,'PSEUDO consent: the non-ASCII Wishlist name is inserted verbatim',shown)
 check(shown:find("'Main Build'",1,true)~=nil and shown:find('\n',1,true)~=nil,'PSEUDO consent: target named; question and consequence on two lines',shown)
 H.popup=nil -- Cancel: the dialog has no OnCancel; dismissing assigns nothing
end
-- Chat lines that need no write: refusal with no dialog, editor unavailable,
-- associate first, the Echoes page coach and its unconfirmed variant.
do
 local realShow=StaticPopup_Show;StaticPopup_Show=nil
 Chat('pseudo consent unavailable',function()
  J.AssignWithConsent('Plan A','target',true,function() error('must not assign') end)
 end)
 StaticPopup_Show=realShow
 local editor=Nexus.WishlistEditor;Nexus.WishlistEditor=nil
 Chat('pseudo editor unavailable',function() NexusLoadoutAssociationPanel.newWishlist:Click() end)
 Nexus.WishlistEditor=editor
 H.perks.serverActiveSlot=3;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
 local unlinked=NexusLoadoutAssociationPanel.design:GetScript('OnClick')
 Chat('pseudo associate first',function() unlinked() end)
 H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
 NexusActiveWishlistSelector:Hide()
 local coach=Chat('pseudo coach',function() J.OpenBuilds(true) end)
 NexusActiveWishlistSelector:Show()
 check(#coach==1,'PSEUDO chat: the Echoes page coach is printed once',#coach)
 local slots=Nexus.GameAdapter.Slots;Nexus.GameAdapter.Slots=function() return nil end
 local unconfirmed=Chat('pseudo unconfirmed',function() J.OpenBuilds(true) end)
 Nexus.GameAdapter.Slots=slots
 check(#unconfirmed==1,'PSEUDO chat: the unconfirmed page message is printed once',#unconfirmed)
 ProjectEbonholdEchoJournal:Hide()
 local missingButton=Chat('pseudo progression',function() J.OpenBuilds(false) end)
 ProjectEbonholdEchoJournal:Show()
 check(#missingButton==1,'PSEUDO chat: the missing Character Progression button is reported',#missingButton)
end
local after=Snapshot()
check(SameSnapshot(before,after),'PASSIVE: render, hover, navigation, chooser input and Cancel wrote, sent and did nothing',
 before.db==after.db and 'state/sent/actions/popup differ' or 'NexusDB differs')
-- The owner check after a dialog: an accept after the saved data changed
-- assigns nothing and says so.
do
 local realOwner=Nexus.Store.CurrentOwnerKey
 J.AssignWithConsent('Plan A','target',true,function() error('must not assign') end)
 local q=H.popup;H.popup=nil
 Nexus.Store.CurrentOwnerKey=function() return 'someone-else' end
 Chat('pseudo owner changed',function() StaticPopupDialogs[q.which].OnAccept(q.frame,q.data) end)
 Nexus.Store.CurrentOwnerKey=realOwner
end
check(SameSnapshot(before,Snapshot()),'PASSIVE: a stale accept assigns nothing')
J.AutoSelected=realAuto
-- Deliberate actions after the passive window: an assignment's receipt and
-- the pool Save, Reset and Load saved question (cancelled).
do
 J.RefreshAssociations();NexusActiveWishlistSelector:Click()
 local row
 for _,r in ipairs(NexusWishlistOnlyPicker.children) do
  if r.nameButton and r:IsVisible() and S.Unmarked(r.nameButton.text:GetText()):find(UNICODE,1,true) then row=r end
 end
 local receipt=Chat('pseudo assigned',function() row.nameButton:Click() end)
 local found
 for _,l in ipairs(receipt) do if S.IsPseudo(l) and l:find("'"..UNICODE.."'",1,true) then found=l end end
 check(found~=nil,'PSEUDO chat: the assignment receipt is reviewed text with the name verbatim',table.concat(receipt,' | '))
 -- A fresh chooser: each window instance owns the NexusFlexiblePlan* globals.
 chooser=NewChooser(true)
 chooser.Show()
 CatalogAction(300003):Click()
 chooser.SavePool();Scan('pseudo chooser saved',NexusFlexiblePlanChooser)
 NexusFlexiblePlanReset:Click();Scan('pseudo chooser has saved',NexusFlexiblePlanChooser)
 CatalogAction(300001):Click()
 chooser.LoadPool()
 local q=H.popup
 check(q and q.which=='NEXUS_FLEXIBLE_PLAN_LOAD','PSEUDO plan: Load saved over unsaved changes asks first')
 if q then
  local d=StaticPopupDialogs[q.which]
  Add('pseudo plan load dialog',d.text);Add('pseudo plan load dialog',d.button1);Add('pseudo plan load dialog',d.button2)
  Scan('pseudo chooser asking',NexusFlexiblePlanChooser)
  d.OnCancel(q.frame,q.data);H.popup=nil
  Scan('pseudo chooser cancelled',NexusFlexiblePlanChooser)
 end
 -- Remove saved: an empty pool saved over the saved one asks first.
 NexusFlexiblePlanReset:Click();chooser.SavePool()
 q=H.popup
 check(q and q.which=='NEXUS_FLEXIBLE_PLAN_CLEAR','PSEUDO plan: saving an empty pool over a saved one asks first')
 if q then
  local d=StaticPopupDialogs[q.which]
  Add('pseudo plan clear dialog',d.text);Add('pseudo plan clear dialog',d.button1);Add('pseudo plan clear dialog',d.button2)
  Scan('pseudo chooser asking clear',NexusFlexiblePlanChooser)
  d.OnCancel(q.frame,q.data);H.popup=nil
 end
 chooser.Hide()
end
-- Every shown text is well-formed UTF-8 (a shortened label never ends inside
-- a multi-byte character), colour codes aside.
local function WellFormedUtf8(t)
 local i,n=1,#t
 while i<=n do
  local c=t:byte(i);local w
  if c<0x80 then w=1 elseif c>=0xC2 and c<=0xDF then w=2 elseif c>=0xE0 and c<=0xEF then w=3 elseif c>=0xF0 and c<=0xF4 then w=4 else return false end
  if i+w-1>n then return false end
  for k=i+1,i+w-1 do local d=t:byte(k);if d<0x80 or d>0xBF then return false end end
  i=i+w
 end
 return true
end
local broken={}
for _,item in ipairs(collected) do
 local plain=Plain(item.text):gsub('||','|')
 if not WellFormedUtf8(plain) then broken[#broken+1]=item.where..': '..item.text end
end
check(#broken==0,'PSEUDO: every shown text is well-formed UTF-8 ('..#collected..' texts)',table.concat(broken,string.char(10)..'  '))
local missing=Untranslated()
check(#missing==0,'PSEUDO: every visible code-owned text passed the seam ('..#collected..' texts scanned)',
 table.concat(missing,'\n  '))
check(#collected>250,'SETUP pseudo: the scan reached the real receivers',#collected)
-- Representative receivers really show the pseudo text.
check(S.IsPseudo(NexusJournalTab:GetText()),'PSEUDO tab label is reviewed text',NexusJournalTab:GetText())
local counts,dialogs=0,0
for _,item in ipairs(collected) do
 if item.text:find('|cff7fd17f',1,true) and S.IsPseudo(item.text) then counts=counts+1 end
 if item.where:find('dialog',1,true) and S.IsPseudo(item.text) then dialogs=dialogs+1 end
end
check(counts>0,'PSEUDO: the coloured counts row keeps its colours inside reviewed text')
check(dialogs>=7,'PSEUDO: consent and pool dialogs show reviewed text',dialogs)
-- Template slots through the seam: unknown is "?", zero is "0".
local L=Nexus.Localization
check(L.Format('journal.heading.missing_count',{count=L.Count(nil)})=='\194\171Missing (?)\194\187','PSEUDO template: unknown count is ?')
check(L.Format('journal.heading.missing_count',{count=L.Count(0)})=='\194\171Missing (0)\194\187','PSEUDO template: zero count is 0')
local zeroBudget
for _,item in ipairs(collected) do if item.text:find('\194\1710 / 256',1,true) then zeroBudget=item.text end end
check(zeroBudget and zeroBudget:find('Chosen: 0 /',1,true),'PSEUDO: the empty pool budget shows known zeros',zeroBudget)

------------------------------------------------------------------------
-- LONG (densest states)
------------------------------------------------------------------------
Boot('long')
collected={}
local okLong,errLong=pcall(function()
 Render('valid',true);Scan('long page',NexusJournalPanel)
 for _,row in ipairs(Rows(true)) do Hover('long tome row',row) end
 NexusJournalTab:Click();J=Nexus.JournalTab;J.RefreshAssociations()
 Hover('long selector',NexusActiveWishlistSelector)
 NexusActiveWishlistSelector:Click();Scan('long picker',NexusWishlistOnlyPicker);NexusActiveWishlistSelector:Click()
 DriveChooser('long',NewChooser(true))
end)
check(okLong,'LONG: the densest states render without error',errLong)
local longShown=0
for _,item in ipairs(collected) do if S.IsPseudo(item.text) and #item.text>0 then longShown=longShown+1 end end
check(longShown>60,'LONG: expanded text is still shown at the receivers',longShown)

------------------------------------------------------------------------
-- MISSING entries fall back to exact English
------------------------------------------------------------------------
local REMOVED={'journal.tab.nexus_progress','journal.button.show_details','journal.label.counts_represented',
 'journal.title.picker_assign_to','plan.button.save_pool','plan.status.persist_empty'}
local entries=S.PseudoEntries()
for _,k in ipairs(REMOVED) do assert(entries[k],'SETUP: '..k..' is a catalog key');entries[k]=nil end
Boot('wrap',entries)
J=Nexus.JournalTab
check(NexusJournalTab:GetText()=='Nexus Progress','MISSING: the tab label falls back to exact English',NexusJournalTab:GetText())
Render('valid',false)
local toggle=ButtonOn(Page(),function(f) return f:GetWidth()==112 end)
check(toggle and toggle:GetText()=='Show details','MISSING: Show details falls back to exact English',toggle and toggle:GetText())
local countsLine,intro
for _,item in ipairs(S.VisibleTexts(NexusJournalPanel)) do
 if item.text:find('|cff7fd17f',1,true) then countsLine=item.text end
 if item.text:find('Read-only',1,true) then intro=item.text end
end
check(countsLine and countsLine:find('^|cff7fd17fRepresented|r 1 of 5   \194\171'),'MISSING: a missing template shows its English while its neighbours stay reviewed',countsLine)
check(intro and S.IsPseudo(intro),'MISSING: other keys stay pseudo',intro)
NexusJournalTab:Click();J.RefreshAssociations();NexusActiveWishlistSelector:Click()
check(NexusWishlistOnlyPicker.title:GetText()=='Assign to: Main Build','MISSING: the picker title template falls back to English',NexusWishlistOnlyPicker.title:GetText())
NexusActiveWishlistSelector:Click()
local c=NewChooser(true);c.Show()
check(NexusFlexiblePlanSave:GetText()=='Save pool' and S.IsPseudo(NexusFlexiblePlanLoad:GetText()),'MISSING: Save pool English, Load saved reviewed',NexusFlexiblePlanSave:GetText())
local persistText
for _,item in ipairs(S.VisibleTexts(NexusFlexiblePlanChooser)) do if item.text:find('Save pool stores',1,true) then persistText=item.text end end
check(persistText=="Not saved. Save pool stores this character's planning pool; Load saved restores it. Hide keeps this session; Reset clears only this session.",
 'MISSING: the pool status falls back to exact English',persistText)
c.Hide()

------------------------------------------------------------------------
-- UTF8 (owner integration): a multi-byte translation that the strip label
-- shortens (ShortName, 21 bytes) is cut on a character boundary, never
-- inside a UTF-8 sequence. Synthetic Cyrillic draft text, not a reviewed
-- translation.
------------------------------------------------------------------------
do
 local utf8Entries=S.PseudoEntries()
 -- Cyrillic "empty saved build slot": 2-byte letters, so an 18-byte prefix
 -- ends inside a character.
 utf8Entries['journal.label.empty_saved_build']='\208\159\209\131\209\129\209\130\208\190\208\185 \209\129\208\187\208\190\209\130 \209\129\208\190\209\133\209\128\208\176\208\189\209\145\208\189\208\189\208\190\208\185 \209\129\208\177\208\190\209\128\208\186\208\184'
 Boot('wrap',utf8Entries)
 J=Nexus.JournalTab
 H.perks.serverActiveSlot=3;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
 local label=NexusLoadoutAssociationPanel.label and NexusLoadoutAssociationPanel.label:GetText()
 check(type(label)=='string' and label:find('...',1,true)~=nil,'UTF8 SETUP: the empty Saved Build strip label is shortened',label)
 check(label and WellFormedUtf8(Plain(label)),'UTF8: the shortened multi-byte strip label is well-formed UTF-8',label)
 H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
end

------------------------------------------------------------------------
-- ENGLISH exact bytes at the real receivers
------------------------------------------------------------------------
Boot(nil)
J=Nexus.JournalTab
local function Texts(root) local out={} for _,item in ipairs(S.VisibleTexts(root)) do out[item.text]=true end return out end
check(NexusJournalTab:GetText()=='Nexus Progress','ENGLISH tab label')
local tabHover=Hover('english tab',NexusJournalTab)
check(tabHover[2]=="Opens Nexus's progress page in the Echo Journal. Opening it changes nothing.",'ENGLISH tab hover',tabHover[2])
Render('valid',false)
local t=Texts(NexusJournalPanel)
check(t['Build Progress'] and t['Assigned Wishlist vs active Saved Build. Read-only.'],'ENGLISH heading and intro')
check(t['Still missing 4 Echo families: Arcane Echo, Fire Echo, Frost Echo and 1 more.'],'ENGLISH takeaway (more than three)')
check(t['|cff7fd17fRepresented|r 1 of 5   |cffffa040Missing|r 4   |cff9eb2c8Off Wishlist|r 1'],'ENGLISH counts row with colours')
check(t['Missing (4)'] and t['Off Wishlist (1)'],'ENGLISH row headings')
check(t['|cff8a8a8aEstimate, not a prediction: about 3 runs. Based only on what is known to be missing; no future offer is assumed.|r'],'ENGLISH estimate line')
check(t['Show details'] and t['Help'] and t['Reference'],'ENGLISH page buttons')
local fam=Rows(false)[1]
local famHover=Hover('english family row',fam)
check(fam.status:GetText()=='Missing' and famHover[2]=='Missing: no known copy of this requested Echo family.','ENGLISH family row badge and hover',famHover[2])
Render('valid',true)
t=Texts(NexusJournalPanel)
check(t['About this page'] and t['Change the assigned Wishlist in My Builds.'] and t['Hide details']
 and t['|cff8a8a8aListed above under Missing (4).|r'],'ENGLISH details notes')
local tomeLines={}
for _,row in ipairs(Rows(true)) do
 for _,l in ipairs(Hover('english tome',row)) do tomeLines[l]=true end
 tomeLines['badge '..row.status:GetText()]=true
end
check(tomeLines['Enable requested; awaiting confirmation. A request is not a confirmed change.']
 and tomeLines['Last observed in the client mirror: Disabled'] and tomeLines['Client mirror: Enabled']
 and tomeLines['Echoes: One Echo, Two Echo'] and tomeLines['Echo: Tome of Enabling Echo'] and tomeLines['Control ID: 880201']
 and tomeLines["Icon: a member Echo's spell icon; the tome's own icon was unavailable."]
 and tomeLines['This reading may be stale; Tome state coverage gives the reason.']
 and tomeLines['badge Enable pending'] and tomeLines['badge Request pending'] and tomeLines['badge Unknown']
 and tomeLines['Request direction unknown; awaiting confirmation. A request is not a confirmed change.'],'ENGLISH tome rows and hovers')
for kind,want in pairs({one='Still missing 1 Echo family: Arcane Echo.',two='Still missing 2 Echo families: Arcane Echo, Fire Echo.',
 none_missing='No requested Echo family is missing: each has at least one known copy. That is family coverage, not copy completeness; requested copies may still be missing.',
 zero='This Wishlist requests no Echo families, so there is no family progress to show.',
 no_target='No Wishlist is assigned. Assign one in My Builds to see its progress.',
 no_summary='Build Progress is unavailable: the Wishlist summary line is missing. The lines that were received are under Show details.',
 no_pending='Family progress is unknown: the list of missing families was not received. Nothing is treated as complete; the original lines are under Show details.',
 bad_pending='Family progress is unknown: the list of missing families could not be read or does not match its count. Nothing is treated as complete; the original lines are under Show details.',
 contradictory='Family progress is unknown: the supplied counts and lists do not agree. Nothing is treated as complete; the original lines are under Show details.',
 grammar='Family progress is unknown: the Wishlist summary line could not be read. Nothing is treated as complete; the original lines are under Show details.'}) do
 Render(kind,false)
 check(Texts(NexusJournalPanel)[want],'ENGLISH takeaway '..kind,want)
end
Render('one',false)
t=Texts(NexusJournalPanel)
check(t['|cff7fd17fRepresented|r 1 of 2   |cffffa040Missing|r 1   |cff9eb2c8Off Wishlist:|r none listed'] and t['|cff8a8a8aEstimate: unavailable.|r'],'ENGLISH empty off list and no estimate')
Render('two',false)
check(Texts(NexusJournalPanel)['|cff7fd17fRepresented|r 1 of 3   |cffffa040Missing|r 2   |cff9eb2c8Off Wishlist:|r unavailable'],'ENGLISH unreadable off list')
Render('nodata',false);check(Texts(NexusJournalPanel)['|cff8a8a8ano data yet|r'],'ENGLISH no data yet')
Render('error',true)
t=Texts(NexusJournalPanel)
check(t['|cff8a8a8aBuild Progress data could not be read. Nothing is assumed.|r']
 and t['|cff8a8a8aBuild Progress data could not be read, so there are no sections to show.|r'],'ENGLISH provider failure')
NexusJournalTab:Click();J.RefreshAssociations()
check(NexusLoadoutAssociationPanel.label:GetText()=='|cffffffffMain Build:|r' and NexusActiveWishlistSelector.text:GetText()=='|cff8a8a8aSelect wishlist...|r','ENGLISH strip label and selector')
local sel=Hover('english selector',NexusActiveWishlistSelector)
check(sel[1]=='Automation Wishlist' and sel[2]=='Assigns a wishlist reference to the Saved Build currently selected in the server dropdown. Assigning by itself does not change any Saved Build.','ENGLISH selector hover',sel[2])
NexusActiveWishlistSelector:Click()
check(NexusWishlistOnlyPicker.title:GetText()=='Assign to: Main Build','ENGLISH picker title')
NexusActiveWishlistSelector:Click()
for slot,want in pairs({[2]={'|cffffffffSaved Build 2:|r','Assign to: Saved Build 2'},[3]={'|cffffffffEmpty Saved Build ...:|r','Empty Saved Build: assigning is refused'},
 [0]={'|cffffffffNo Saved Build sel...:|r','Assign to: first-run target'}}) do
 H.perks.serverActiveSlot=slot;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
 NexusActiveWishlistSelector:Click()
 check(NexusLoadoutAssociationPanel.label:GetText()==want[1] and NexusWishlistOnlyPicker.title:GetText()==want[2],
  'ENGLISH strip and picker for slot '..slot,NexusLoadoutAssociationPanel.label:GetText()..' / '..NexusWishlistOnlyPicker.title:GetText())
 NexusActiveWishlistSelector:Click()
end
H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();J.RefreshAssociations()
-- The consent question: exact original bytes, long and non-ASCII names verbatim.
realAuto=J.AutoSelected;J.AutoSelected=function() return true end
J.AssignWithConsent(LONG_NAME,"Saved Build '"..UNICODE.."'",true,function() error('must not assign') end)
p=H.popup;H.popup=nil
local d=StaticPopupDialogs[p.which]
check(string.format(d.text,p.arg1,p.arg2)=="Assign '"..LONG_NAME.."' to Saved Build '"..UNICODE.."'?\n"
 .."Auto is ON. Assigning by itself does not change the Saved Build. But when it is active and a finished run at level 80 passes Auto's checks, Nexus may replace it with the run. Cancel changes nothing. To avoid that, choose Cancel, turn Auto OFF, then assign.",
 'ENGLISH consent question exact, names verbatim',d.text)
check(d.button1=='Assign' and d.button2=='Cancel','ENGLISH consent buttons')
J.AssignWithConsent('50% plan','the first-run target',true,function() end)
p=H.popup;H.popup=nil
check(string.format(StaticPopupDialogs[p.which].text,p.arg1,p.arg2):find("^Assign '50%% plan' to the first%-run target%?\n"),'ENGLISH a "%" in a name survives the client formatting')
local refusal=Chat('english consent unavailable',function()
 local realShow=StaticPopup_Show;StaticPopup_Show=nil
 J.AssignWithConsent('Plan A','target',true,function() error('must not assign') end)
 StaticPopup_Show=realShow
end)
J.AutoSelected=realAuto
check(refusal[1]=='|cffff6060Nexus:|r Nothing was assigned: Auto is ON and the confirmation that names its consequence could not be shown. Turn Auto OFF to assign, or try again later.','ENGLISH consent unavailable chat',refusal[1])
-- The chooser.
c=NewChooser(true);c.Show()
local ct=Texts(NexusFlexiblePlanChooser)
check(ct['Plan alternatives'] and ct['Catalog'] and ct['Your pool / exact counts'] and ct['Open as new Wishlist draft']
 and ct['Save pool'] and ct['Load saved'] and ct['Reset pool'] and ct['Hide']
 and ct['Add exact Echo IDs, then Set each count. Set: shows the committed count; * marks pending input. 0 unchooses.'],'ENGLISH chooser labels')
check(ct['0 / 256 alternatives     Chosen: 0 / 79 ordinary copies'],'ENGLISH budget line with zeros')
check(ct["Not saved. Save pool stores this character's planning pool; Load saved restores it. Hide keeps this session; Reset clears only this session."],'ENGLISH empty pool status')
check(ct['#300001  Q2  Alpha Echo'] and ct['#300002  Q1  '..UNICODE],'ENGLISH catalog rows, non-ASCII name verbatim')
CatalogAction(300002):Click()
ct=Texts(NexusFlexiblePlanChooser)
check(ct['Set: 0  #300002  Q1 / max 3  '..UNICODE] and ct['Added'] and ct['Not saved. Save pool stores this pool on this character.'],'ENGLISH pool row and new pool status')
PoolRow(300002).count:SetText('2')
ct=Texts(NexusFlexiblePlanChooser)
check(ct['Set *'] and ct['Unsaved changes: Set each edited count before Save pool.']
 and ct['Count input is pending. Use Set for each edited count before opening a draft.'],'ENGLISH pending count')
NexusFlexiblePlanOpen:Click()
ct=Texts(NexusFlexiblePlanChooser)
check(ct['Count input is pending. Use Set for each edited count before opening a draft.'],'ENGLISH pending refusal not repeated')
check(c.SavePool()=='refused' and Texts(NexusFlexiblePlanChooser)['Not saved: Set each edited count first. Your pool is kept.'],'ENGLISH refusal template with its reason clause')
PoolRow(300002).action:Click()
check(Texts(NexusFlexiblePlanChooser)['1 / 256 alternatives     Chosen: 2 / 79 ordinary copies'],'ENGLISH budget after Set')
check(Nexus.FlexiblePlanChooser.Reason('NOT_A_CODE')=='This choice cannot be opened. Review the pool and exact counts.'
 and Nexus.FlexiblePlanChooser.Reason('STACK_LIMIT')=="That count exceeds this Echo's maximum stack.",'ENGLISH refusal reasons')
c.SavePool()
check(Texts(NexusFlexiblePlanChooser)['Saved on this character.'],'ENGLISH saved')
NexusFlexiblePlanReset:Click();CatalogAction(300001):Click();c.LoadPool()
p=H.popup
d=p and StaticPopupDialogs[p.which]
check(d and d.text=='Load the pool saved on this character?\nThis replaces the current pool, its counts and any pending count input. Cancel keeps them.'
 and d.button1=='Load saved' and d.button2=='Cancel','ENGLISH load dialog exact',d and d.text)
if p then d.OnCancel(p.frame,p.data);H.popup=nil end
check(L~=Nexus.Localization and Nexus.Localization.Format('journal.heading.missing_count',{count=Nexus.Localization.Count(nil)})=='Missing (?)'
 and Nexus.Localization.Format('plan.status.catalog_changed_many',{count=Nexus.Localization.Count(0)})
  =='0 Echoes in this pool no longer match the catalog; their saved details and counts are kept.','ENGLISH templates: unknown ?, zero 0')
c.Hide()

if #failures>0 then
 for _,f in ipairs(failures) do print('FAIL '..f) end
 error('l10n_ui_journal: '..#failures..' of '..checks..' checks failed')
end
print('PASS l10n_ui_journal checks='..checks..' (synthetic pseudo, long, missing-entry and English runs; native NOT_RUN)')
