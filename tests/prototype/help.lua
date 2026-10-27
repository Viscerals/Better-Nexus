local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local actions,sent=#H.actions,#H.sent
SlashCmdList.NEXUS('help')
local f=assert(NexusHelpWindow)
check(f:IsShown(),'help opens before addon initialization')
check(type(Nexus.StartupStatus)~='function' or not Nexus.StartupStatus().coreReady,'opening help cannot force readiness')
check(f:GetWidth()==660 and f:GetHeight()==540,'bounded help panel')
check(f:GetFrameStrata()=='DIALOG','normal parented dialog')
check(f.body:GetText():find('Wishlist is a desired plan',1,true),'explain desired versus owned')
check(#H.actions==actions and #H.sent==sent,'read-only early help has no gameplay or traffic')
check(#Nexus.Help.Pages==7,'seven complete guide pages')
local function b(label)
 for _,x in ipairs(H.frames)do if x:GetParent()==f and x.kind=='Button' and x:GetText()==label then return x end end
 error('missing help button '..label)
end
-- Getting started leads with the first task; page navigation and reference
-- follow it. Each setup route is named by the real Options menu path, whose
-- top level is Manage (ui/Panel.lua MoreMenuItems; ui_review_navigation V2
-- and guided_first_entry E14 check the labels against the real menu). Issue
-- #165: the panel's menu button reads Options (panel_options_label), so Help
-- names that visible control, never the retired bare ellipsis.
Nexus.Help.Show('start')
local start=f.body:GetText()
check(start:find('Start here: Setup / Welcome opens Guided setup',1,true)==1,'start page leads with the first task')
local first,pages=start:find('Setup / Welcome opens Guided setup',1,true),start:find('the page buttons above open any page directly',1,true)
check(first and pages and first<pages,'page navigation follows the first task')
for _,route in ipairs({'(Options > Manage > Setup / Welcome)','Setup information (read only), in the Options menu under Manage',
 'under Manage as Setup checklist and status','click Plan on the Nexus panel, then Wishlist Editor'})do
 check(start:find(route,1,true),'start page route: '..route)
end
local all='';for _,p in ipairs(Nexus.Help.Pages)do all=all..p.text..'\n' end
for _,stale in ipairs({'click ... on the Nexus panel, then Wishlist Editor','click ... on the Nexus panel, then Automation settings',
 '... > Automation settings','Hide Nexus Panel (... menu)','Setup information (read only), also under Manage'})do
 check(not all:find(stale,1,true),'no route that skips Manage: '..stale)
end
for _,stale in ipairs({'... menu','... > Manage','click ... on','the ... button','Menu and status'})do
 check(not all:find(stale,1,true),'#165: no page names the retired ellipsis control: '..stale)
end
check(all:find('click Options on the Nexus panel, then Manage, then Automation settings',1,true)
 and all:find('Options > Manage > Automation settings',1,true) and all:find('Hide Nexus Panel (Options > Manage)',1,true)
 and all:find('the Options button then reads ! Options',1,true),'#165: Help routes name the visible Options control and its notice mark')
check(Nexus.Panel==nil or type(Nexus.Panel.OptionsText)~='function'
 or (Nexus.Panel.OptionsText(nil)=='Options' and Nexus.Panel.OptionsText(true)=='! Options'),
 '#165: the words Help uses are the words the panel control shows')
-- A window that stepped aside for Help (the guided coach) is told once when
-- Help closes, and not when a Help route opens another window in its place.
local returned=0
Nexus.Help.Show('rolling',function() returned=returned+1 end)
b('Close'):Click()
check(returned==1 and not f:IsShown(),'closing Help tells the window that stepped aside')
Nexus.Help.Show('start');b('Close'):Click()
check(returned==1,'a later Help close tells it nothing again')
Nexus.Help.Show('start',function() returned=returned+1 end)
b('Setup checklist'):Click()
check(returned==1 and not f:IsShown() and NexusSetupChecklist and NexusSetupChecklist:IsShown(),
 'a Help route takes Help\'s place without bringing the window back')
NexusSetupChecklist:Hide()
Nexus.Help.Show('start')
b('Next'):Click();check(f.title:GetText():find('locked targets',1,true),'real next handler')
b('Previous'):Click();check(f.title:GetText():find('Getting started',1,true),'real previous handler')
Nexus.Help.Show('orbs');check(f.body:GetText():find('one Orb per replacement',1,true),'Orb instructions explain one-Orb boundary')
check(f.body:GetText():find('does not automatically re%-enable'),'no auto restart promise')
b('Close'):Click();check(not f:IsShown(),'close works')
-- The full-UI design's Help: each page leads with a short task topic (a few
-- lines and one Open action to the real screen); the page text stays below it
-- as the complete reference. One Open button serves every page, so no Help
-- control is ever hidden (orbs_help_layers needs every Help button visible).
local G=dofile('tests/prototype/layout_geometry_support.lua')
local DESIGN={start='Getting started',wishlists='Wishlists vs Saved Builds',rolling='Auto',sharing='Sync',
 orbs='Orbs',troubleshooting='Support'}
local function Card(tag,char,line)
 for _,p in ipairs(Nexus.Help.Pages)do
  Nexus.Help.Show(p.id)
  local t=Nexus.Help.Topics[p.id]
  check(t and (DESIGN[p.id]==nil or t.title==DESIGN[p.id]) and type(t.route)=='function','design topic for '..p.id)
  check(f.topicTitle:GetText()==t.title and f.topicOpen:GetText()==t.open and f.topicOpen:IsShown()
   and f.topicOpen:IsEnabled(),tag..': the topic card shows '..p.id)
  local len=0;for _,l in ipairs(t.lines)do len=len+#l end
  check(#t.lines>=1 and #t.lines<=3 and len<=400 and len*3<#p.text,tag..': a few short lines beside the reference: '..p.id)
  check(f.body:GetText()==p.text and f.body:IsShown(),tag..': the complete reference stays below the topic: '..p.id)
  check(f.reference:GetText():find('Reference',1,true)==1,tag..': the reference is labelled: '..p.id)
  for _,x in ipairs(H.frames)do
   if x:GetParent()==f and x.kind=='Button' then check(x:IsShown(),tag..': no hidden Help control on '..p.id) end
  end
  local root=G.Rect(f,f)
  local open,title,text,ref,scroll=G.Rect(f.topicOpen,f),G.Rect(f.topicTitle,f),G.Rect(f.topicText,f),G.Rect(f.reference,f),G.Rect(f.scroll,f)
  check(G.Inside(open,root) and G.Apart(open,title) and title[4]<=text[2] and open[4]<=text[2],tag..': title and Open sit above the lines: '..p.id)
  check(f.topicText:GetHeight()>=G.Rows(f.topicText:GetText(),f.topicText:GetWidth(),char)*line,tag..': the lines are tall enough: '..p.id)
  check(text[4]<=ref[2] and ref[4]<=scroll[2] and scroll[4]<=540-55 and scroll[4]-scroll[2]>=120,
   tag..': the reference scrolls below the card, above the bottom buttons: '..p.id,G.Text(scroll))
 end
end
Card('default',5.5,12)
G.UseFont({name='125%',char=8.75,line=15,size=15})
Card('125%',8.75,15)
G.UseFont(G.MODELS.default)
-- Each Open action is the real screen through its guarded route. During
-- loading the routes that need start-up say so in Help and open nothing.
local function Open(id) Nexus.Help.Show(id);f.topicOpen:Click() end
for _,id in ipairs({'wishlists','rolling','sharing','about'})do
 Open(id)
 check(f:IsShown() and f.note:GetText():find('after start-up finishes',1,true),'loading: the '..id..' topic waits for start-up and says so')
end
check(not (_G.NexusSettingsWindow and NexusSettingsWindow:IsShown()) and not (_G.NexusEditorFrame and NexusEditorFrame:IsShown()),
 'loading: no settings or editor window opened')
for _,route in ipairs({{'orbs','OrbPanel'},{'troubleshooting','SupportReportUI'}})do
 local owner=Nexus[route[2]]
 check(owner and type(owner.Show)=='function','fixture: '..route[2]..' is loaded')
 local real,calls=owner.Show,0
 owner.Show=function() calls=calls+1;return true end
 Open(route[1])
 owner.Show=real
 check(calls==1 and not f:IsShown(),'the '..route[1]..' topic opens its window in Help\'s place')
end
Open('start')
check(_G.NexusGuidedSetup and NexusGuidedSetup:IsShown() and not f:IsShown(),'Getting started opens the Setup guide')
NexusGuidedSetup:Hide()
check(#H.actions==actions and #H.sent==sent,'topic cards and their routes act and send nothing')
-- Both original designs: /nexus tutorial keeps opening Help (the full-UI
-- review's Help & onboarding; the guided design's "today opened by /nexus
-- tutorial"), and Setup / Welcome opens the coach. /nexus guide, which is
-- implemented, opens the coach. Both answer during loading; neither acts.
f:Hide()
SlashCmdList.NEXUS('tutorial')
check(f:IsShown(),'tutorial opens the reference Help during loading')
check(not (_G.NexusGuidedSetup and NexusGuidedSetup:IsShown()),'tutorial does not open the guided setup coach')
check(#H.actions==actions and #H.sent==sent,'tutorial opens Help without a game action or traffic')
f:Hide()
SlashCmdList.NEXUS('guide')
local coach=_G.NexusGuidedSetup
check(coach and coach:IsShown(),'guide opens the guided setup coach')
check(not f:IsShown(),'guide does not open the dense reference Help')
check(#H.actions==actions and #H.sent==sent,'guide opens the coach without a game action or traffic')
coach:Hide()
SlashCmdList.NEXUS('help');check(f:IsShown(),'help reopens the reference pages after the coach')
local commands=Nexus.Help.Pages[6].text
check(commands:find('/nexus help or /nexus tutorial - this guide',1,true) and commands:find('/nexus guide - Guided setup',1,true)
 and not commands:find('/nexus guide or /nexus tutorial',1,true),'the command list says tutorial opens Help and guide opens the coach')
b('Start page'):Click();check(f.title:GetText():find('Getting started',1,true),'home button')
Nexus.Help.Show('troubleshooting');local text=f.body:GetText()
check(text:find('Select this page',1,true) and text:find('copy pages in order',1,true),'copy pagination explained')
for _,command in ipairs({'reroll','freeze','currentlocks','prototype'})do
 local joined='';for _,p in ipairs(Nexus.Help.Pages)do joined=joined..p.text end
 check(joined:find('/nexus '..command,1,true),'document '..command)
end
check(#H.actions==actions and #H.sent==sent,'navigation through all guide pages stays passive')
print('PASS persistent pre-ready help and actual navigation handlers='..checks)
