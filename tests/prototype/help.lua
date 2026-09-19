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
b('Next'):Click();check(f.title:GetText():find('permanent targets',1,true),'real next handler')
b('Previous'):Click();check(f.title:GetText():find('Getting started',1,true),'real previous handler')
Nexus.Help.Show('orbs');check(f.body:GetText():find('one Orb per replacement',1,true),'Orb instructions explain one-Orb boundary')
check(f.body:GetText():find('does not automatically re%-enable'),'no auto restart promise')
b('Close'):Click();check(not f:IsShown(),'close works')
SlashCmdList.NEXUS('guide');check(f:IsShown(),'guide alias reopens after close')
SlashCmdList.NEXUS('tutorial');check(f:IsShown(),'tutorial alias is persistent guide, no forced walkthrough')
b('Start page'):Click();check(f.title:GetText():find('Getting started',1,true),'home button')
Nexus.Help.Show('troubleshooting');local text=f.body:GetText()
check(text:find('Select this page',1,true) and text:find('copy pages in order',1,true),'copy pagination explained')
for _,command in ipairs({'reroll','freeze','currentlocks','prototype'})do
 local joined='';for _,p in ipairs(Nexus.Help.Pages)do joined=joined..p.text end
 check(joined:find('/nexus '..command,1,true),'document '..command)
end
check(#H.actions==actions and #H.sent==sent,'navigation through all guide pages stays passive')
print('PASS persistent pre-ready help and actual navigation handlers='..checks)
