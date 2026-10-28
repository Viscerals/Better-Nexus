local H=dofile('tests/prototype/orbs_support.lua');local M,O=H.M,H.O
dofile('tests/prototype/legacy_editbox_support.lua')(H)
H.OrbPlan();O.charges=0
local count=#H.actions
local ok,f=pcall(Nexus.OrbPanel.Show)
assert(ok,'legacy idle Orb render failed: '..tostring(f))
assert(f.limit.Enable==nil and f.limit.Disable==nil and f.limit.IsEnabled==nil,'fixture must not supply Button methods')
assert(f.limit.UnknownCapitalizedMethod==nil,'fixture must not invent unknown methods')
assert(f.limit.mouseEnabled and f.limit.keyboardEnabled,'idle maximum must be editable')
-- No saved maximum: the draft follows the confirmed balance, here zero (not 1 or 10).
assert(f.limit:GetText()=='0' and f.usage:GetText()=='Orbs used: 0 / 0','actual maximum and usage must render: '..f.limit:GetText()..' / '..f.usage:GetText())
assert(f.status:GetText():find('No confirmed Orbs are available.',1,true),'zero balance explanation must render')
assert(not f.start:IsEnabled() and not f.stop:IsEnabled(),'zero balance cannot start a run')
-- Closed size: measured rows, at most the former 445 (stale exact-445/660 pins
-- updated by the finish pass, item D; OrbPanel flowBands). Advanced adds its
-- whole 205-unit box below the buttons, inside the window.
local closedH=f:GetHeight()
local function AdvancedInside()
 local _,_,_,_,y=f.advanced:GetPoint()
 return f.advanced:IsShown() and f:GetHeight()<=660 and -(tonumber(y) or 0)+f.advanced:GetHeight()<=f:GetHeight()
end
assert(not f.advanced:IsShown() and closedH<=445 and f._bandsBottom<=closedH,'Advanced starts hidden in the closed-size panel')
f.limit:SetFocus();assert(H.TypeLimit(f,'3'))
Nexus.OrbPanel.Refresh()
assert(f.limit:HasFocus() and f.limit:GetText()=='3','passive refresh must preserve idle typing')
f.limit:GetScript('OnEnterPressed')(f.limit)
assert(not f.limit:HasFocus() and M.Status().config.maxOrbs==3,'Enter saves the idle maximum and releases focus')
f.limit:SetFocus();assert(H.TypeLimit(f,'9'));f.limit:GetScript('OnEscapePressed')(f.limit)
assert(not f.limit:HasFocus() and f.limit:GetText()=='3','Escape restores the saved maximum')
closedH=f:GetHeight()
assert(closedH<=445,'the closed-size panel after editing')
H.OrbButton('Advanced',f):Click();assert(AdvancedInside() and f:GetHeight()>closedH,'Advanced shows its whole box inside the taller window')
H.OrbButton('Advanced',f):Click();assert(not f.advanced:IsShown() and f:GetHeight()==closedH,'closing Advanced gives back exactly its height')
f.limit:SetFocus();H.OrbButton('Close',f):Click()
assert(not f:IsShown() and not f.limit:HasFocus(),'Close releases the hidden input focus')
assert(#H.actions==count,'opening/editing/closing the zero-balance panel submits no gameplay action')
print('PASS strict legacy EditBox idle/zero balance/max usage/status/focus/Advanced/Close')
