local H=dofile('tests/prototype/orbs_support.lua')
local M=H.M
local before=M.BoundaryDiagnostics()
assert(before.lifecycleObserved==true,'lifecycle initialization installs the orb observer before the first spend')
assert(type(before.epoch)=='number','the installed observer has a real epoch')
H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
local summary=Nexus.SupportReport.Summary()
assert(summary:find('current_epoch='..tostring(before.epoch+2),1,true),
 'a later zone is counted by the observer installed at startup')
assert(not summary:find('current_epoch=unknown',1,true),
 'an installed observer is not reported as an unknown epoch')
H.Advance(3.1)
H.OrbPlan();H.Approve(1,false);H.Offer();H.Result(410002,2)
local d=M.BoundaryDiagnostics()
assert(d.receiptPresent==false and d.snapshot~=nil,'fixture: completed fake operation retains comparisons')
H.now=H.now+120
d=M.BoundaryDiagnostics()
assert(type(d.snapshotAge)=='number' and d.snapshotAge>=120,'changed comparisons expose their sample age')
summary=Nexus.SupportReport.Summary()
assert(summary:find('scope=retained current=no',1,true)
 and summary:find('changed_age=120',1,true),'summary cannot imply old offer flags are current')
print('PASS orb_diagnostic_lifecycle_freshness')
