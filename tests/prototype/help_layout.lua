-- Structural rendering checks; native text fit/clicks remain a separate gate.
local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
SlashCmdList.NEXUS('help');local f=assert(NexusHelpWindow)
local scroll=assert(NexusHelpScroll);local child=assert(f.content)
assert(scroll:GetFrameLevel()>f:GetFrameLevel(),'Help scroll must render above its opaque parent')
assert(f:GetFrameLevel()<100 and child:GetFrameLevel()<128,'keep every Help layer below the observed native clamping boundary')
assert(child:GetFrameLevel()>=scroll:GetFrameLevel(),'Help body must render above its scroll viewport')
assert(child:GetNumPoints()>0,'Help body needs an explicit viewport anchor')
local navigation={}
for _,b in ipairs(H.frames)do if b.kind=='Button' and b:GetParent()==f then
 assert(b:GetFrameLevel()>f:GetFrameLevel(),'Help navigation must render and receive clicks above the parent')
 navigation[b:GetText()]=b
end end
for i=1,7 do
 assert(f.body:IsVisible() and #f.body:GetText()>300,'complete Help body visible on page '..i)
 assert(f.body:GetWidth()>400 and f.body:GetHeight()>0,'Help body has explicit dimensions')
 assert(child:GetHeight()>=f.body:GetHeight(),'scroll child cannot clip its text')
 navigation.Next:Click()
end
navigation.Previous:Click();navigation.Close:Click();assert(not f:IsShown())
SlashCmdList.NEXUS('help');assert(f:IsShown() and f.body:IsVisible())
assert(#H.actions==0 and #H.sent==0,'Help is passive before readiness')
print('PASS explicit Help layering, anchors, text dimensions, seven-page navigation and passive reopen')
