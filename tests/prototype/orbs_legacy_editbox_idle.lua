-- Start/Stop rework (2026-11-19). The idle Orb window has no maximum box, Max
-- button, usage line or Advanced exclusions: Start and Stop only. At zero
-- balance Start is unavailable and says why; the window keeps its closed size;
-- Close still releases a stale input focus. Nothing is sent.
-- (Replaces the strict legacy maximum EditBox idle pin.)
local H=dofile('tests/prototype/orbs_support.lua');local M,O=H.M,H.O
dofile('tests/prototype/legacy_editbox_support.lua')(H)
H.OrbPlan();O.charges=0
local count=#H.actions
local ok,f=pcall(Nexus.OrbPanel.Show)
assert(ok,'idle Orb render failed: '..tostring(f))
assert(f.limit.Enable==nil and f.limit.Disable==nil and f.limit.IsEnabled==nil,'fixture must not supply Button methods')
assert(f.limit.UnknownCapitalizedMethod==nil,'fixture must not invent unknown methods')
for _,k in ipairs({'limit','max','usage','approval','advancedToggle','advanced'}) do
 assert(not f[k]:IsShown(),'idle: no '..k)
end
assert(f.balance:GetText():find('^Confirmed Orb balance: 0'),'the balance line still renders: '..tostring(f.balance:GetText()))
assert(not f.start:IsEnabled() and not f.stop:IsEnabled(),'zero balance cannot start a run')
assert(f.startWhy:GetText():find('No confirmed Orbs',1,true),'zero balance: Start says why: '..tostring(f.startWhy:GetText()))
local closedH=f:GetHeight()
assert(closedH<=445 and f._bandsBottom<=closedH,'the closed-size panel')
O.charges=3;Nexus.OrbPanel.Refresh()
assert(f.start:IsEnabled() and not f.stop:IsEnabled() and f:GetHeight()<=445,'with Orbs Start is offered in the same window')
f.limit:SetFocus();H.OrbButton('Close',f):Click()
assert(not f:IsShown() and not f.limit:HasFocus(),'Close releases the hidden input focus')
assert(#H.actions==count,'opening/refreshing/closing the panel submits no gameplay action')
print('PASS idle Orb window: Start/Stop only, zero balance, closed size, Close')
