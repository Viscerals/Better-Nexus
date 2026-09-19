-- Real Orb Help entry path, including simultaneous Advanced controls.
-- This checks the observed native ordering mechanism, not native pixel output.
local H=dofile('tests/prototype/orbs_support.lua');local M,O=H.M,H.O
local function button(parent,label)
 for _,f in ipairs(H.frames)do if f.kind=='Button'and f:GetParent()==parent and f:GetText()==label then return f end end
 error('missing button: '..label)
end
local function descendant(f,parent)
 while f do if f==parent then return true end;f=f:GetParent()end
 return false
end
local function foreground(orb,help)
 assert(orb:IsShown()and help:IsShown(),'both windows must retain their intended visible state')
 assert(help:GetFrameStrata()==orb:GetFrameStrata(),'test models the actual concurrent dialog strata')
 local highest=orb:GetFrameLevel()
 for _,f in ipairs(H.frames)do
  if f:IsVisible()and descendant(f,orb)then highest=math.max(highest,f:GetFrameLevel())end
 end
 assert(help:GetFrameLevel()>highest,'Help backdrop must be above every visible Orb frame/control; Help='..help:GetFrameLevel()..' Orb max='..highest)
 assert(NexusHelpScroll:GetFrameLevel()>help:GetFrameLevel()and help.content:GetFrameLevel()>=NexusHelpScroll:GetFrameLevel(),'Help content stays above its own opaque backdrop')
 assert(help.content:GetFrameLevel()<128 and help:GetFrameLevel()<100,'keep the corrected band below the earlier high-level Help failure')
 assert(help.body:IsVisible()and #help.body:GetText()>300,'complete body remains visible')
 for _,f in ipairs(H.frames)do
  if f.kind=='Button'and f:GetParent()==help then assert(f:IsVisible()and f:GetFrameLevel()>help:GetFrameLevel(),'Help navigation stays above its backdrop')end
 end
end
local function snapshot()
 local s=M.Status()
 return {running=s.running,pending=s.pending~=nil,spent=s.spent,reserved=s.reserved,limit=s.limit,actions=#H.actions,sent=#H.sent}
end
local function unchanged(before,reason)
 local after=snapshot()
 for k,v in pairs(before)do assert(after[k]==v,reason..' changed '..k)end
end
local function open(orb)
 local before=snapshot();button(orb,'Help'):Click();local help=assert(NexusHelpWindow)
 assert(help.page:GetText()=='Page 5 / 7','actual Orb Help button opens the Orb topic')
 foreground(orb,help);unchanged(before,'Help opening');return help
end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}});O.charges=0
local orb=Nexus.OrbPanel.Show();button(orb,'Advanced'):Click();assert(orb.advanced:IsShown())
local help=open(orb);local before=snapshot()
button(help,'Next'):Click();button(help,'Previous'):Click();button(help,'Start page'):Click()
foreground(orb,help);unchanged(before,'Help navigation')
button(help,'Close'):Click();assert(not help:IsShown()and orb:IsShown(),'Help Close leaves the Orb panel available')
-- Reopen in both orders; creation order must not decide the window layers.
Nexus.OrbPanel.Hide();Nexus.Help.Show('orbs');Nexus.OrbPanel.Show();foreground(orb,help)
button(help,'Close'):Click();Nexus.Help.Show('orbs');foreground(orb,help);button(help,'Close'):Click()
O.charges=10;assert(M.Start(2));assert(H.Count('orb-spend')==1)
help=open(orb);before=snapshot();button(orb,'Close'):Click()
assert(not orb:IsShown()and help:IsShown()and M.Status().running,'Orb Close still hides an approved run without stopping it')
unchanged(before,'Orb Close under Help');button(help,'Close'):Click();unchanged(before,'Help Close during run')
Nexus.OrbPanel.Show();M.Pause();H.Offer();assert(H.Count('take')==0,'paused ready offer remains unselected')
Nexus.OrbPanel.Refresh();help=open(orb);before=snapshot();H.Advance(.6)
foreground(orb,help);unchanged(before,'Help and Orb timer reads with a paused ready offer')
button(help,'Close'):Click();button(orb.advanced,'Recheck'):Click();unchanged(before,'actual Recheck after Help')
M.Stop();assert(M.Status().pending and H.Count('orb-spend')==1 and H.Count('take')==0,'pending exposure retained without an extra mutation')
print('PASS actual Orb Help layering/Advanced/reopen/navigation/running Close/paused ready offer/passive Recheck')
