local L=dofile('tests/prototype/stop_sharing_layer_support.lua')
local H,C,id,button,restore,p,library,close,untouched=L.Begin()
local wire=#H.sent;local old=H.Clone((C.Get(id)))
assert(library:GetFrameStrata()=='DIALOG' and library:GetFrameLevel()==50,'exact reported Library layer')
assert(p:GetFrameStrata()=='DIALOG' and p:GetFrameLevel()==1,'exact reported native popup layer before display')
L.Open(H,id,button,p,library)
assert(p:GetFrameLevel()==1,'foregrounding must not introduce high frame levels')
-- Repeated display of an already-visible named dialog must not overwrite
-- the saved original layer with the temporary one.
StaticPopup_Show('NEXUS_STOP_SHARING_BUILD','same record',nil,{id=id})
L.Above(p,library);p.button2:Click();L.Restored(p,'DIALOG',1)
assert(untouched:GetFrameStrata()=='DIALOG' and untouched:GetFrameLevel()==1,'other popup slots unchanged')
local unrelatedShows,unrelatedHides=0,0
StaticPopupDialogs.NEXUS_TEST_UNRELATED={button1='OK',button2='Cancel',hideOnEscape=true,
 OnShow=function()unrelatedShows=unrelatedShows+1 end,
 OnHide=function()unrelatedHides=unrelatedHides+1 end}
StaticPopup_Show('NEXUS_TEST_UNRELATED')
assert(p:GetFrameStrata()=='DIALOG' and p:GetFrameLevel()==1,'reused slot has no Stop Sharing layer leak')
p.button2:Click()
assert(unrelatedShows==1 and unrelatedHides==1,'unrelated dialog callbacks remain intact')
L.Open(H,id,button,p,library)
StaticPopup_Show('NEXUS_TEST_UNRELATED')
assert(p:GetFrameStrata()=='DIALOG' and p:GetFrameLevel()==1,'replacing a visible Stop Sharing dialog also restores the shared slot')
p.button2:Click()
assert(unrelatedShows==2 and unrelatedHides==2,'visible replacement retains unrelated callbacks')
L.Open(H,id,button,p,library)
StaticPopup_Hide('NEXUS_STOP_SHARING_BUILD');L.Restored(p,'DIALOG',1)
-- Restore the actual preexisting stratum, rather than a hardcoded default.
p:SetFrameStrata('FULLSCREEN');p:SetFrameLevel(4)
L.Open(H,id,button,p,library);H.EscapePopup();L.Restored(p,'FULLSCREEN',4)
assert(library:GetFrameStrata()=='DIALOG' and library:GetFrameLevel()==50,'Library layer untouched')
assert(H.deleteCalls==0 and H.tombstoneCalls==0 and #H.stopMessages==0,'display, Cancel, Escape and reuse submit no deletion or result')
assert(L.T.Equal(C.Get(id),old) and #H.sent==wire and #H.actions==0,'layer handling preserves data and sends no wire or resource action')
restore();print('PASS actual Stop Sharing foreground/buttons, repeated display, Cancel/Escape, restored slot and unrelated popup reuse')
