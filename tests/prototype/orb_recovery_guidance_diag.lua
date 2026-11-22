-- Truthful explanation never turns missing client evidence into server proof.
-- Real addon / synthetic services. No native performance/recovery claim.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local H,M,A,O=R.Class({latch=false,edit=function(row,state)row.spendConfirmed=false;state.spendConfirmed=false end})
S.Pass(H,M,A,1)
H.granted[H.names[500001]]={{spellId=500001,quality=1}};H.Notify();A.Poll();M.Pump()
check(M.RecoveryView().recovery=='UNOBSERVABLE','unlinked no-offer ownership reaches the reported class')
check(M.Status().reason:find('does not prove that the server spent nothing',1,true)
 and not M.Status().reason:find('only exit',1,true),'UNOBSERVABLE guidance does not promise an unavailable exit')
local saved=H.Clone(R.Saved());local sends=#H.sent;local requests=O.requests
local v=M.ContinueView()
check(v.reason=='spend_unconfirmed' and not v.eligible and v.explanation,'unobserved spend explains refusal')
check(v.text:find('does not prove that the server spent nothing',1,true),'no invented no-spend conclusion')
check(v.text:find('no retained observation',1,true) and not v.text:find('never observed',1,true),'missing saved history is not proof the client never observed it')
check(v.text:find('Start, Resume and reload cannot reconstruct',1,true),'repeat actions cannot reconstruct history')
Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
-- Start/Stop rework (2026-11-19): no recovery UI or buttons on the run page.
check(not NexusOrbPanel.cont:IsShown(),'no Continue opener for the record')
check(#H.sent==sends and O.requests==requests and R.Same(R.Saved(),saved),'opening the window sends and saves nothing')
local ok,why=M.ContinueBegin()
check(not ok and why=='spend_unconfirmed','API still refuses the original gate')
check(M.Status().pending and M.Status().reserved==1 and M.BlocksOrdinary(),'uncertain exposure and block retained')
local H2,M2,A2,O2=R.Class({latch=false});R.Server(H2);S.Pass(H2,M2,A2,1)
check(M2.ContinueView().eligible,'client-observed spend retains the original eligibility (runtime view)')
Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
check(not NexusOrbPanel.cont:IsShown(),'an eligible record has no Continue opener either')
-- Offered/named choice class must not acquire an archive consent either.
local H3,M3,A3,O3=R.Class({latch=false})
H3.Board({{spellId=500037,quality=1},{spellId=500001,quality=1},{spellId=500038,quality=1}});O3.offer=true
S.Pass(H3,M3,A3,1);Nexus.OrbPanel.Show();NexusOrbPanel.Refresh()
check(M3.ContinueView().reason=='offer_open','open offer still refuses')
check(not NexusOrbPanel.cont:IsShown(),'no Continue opener with an open offer')
-- Instrumentation availability is optional and disabled dispatch preserves results.
local raw=Nexus.Performance;local labels={}
Nexus.Performance={MeasureDiagnostic=function(label,fn,...)labels[label]=(labels[label]or 0)+1;return fn(...)end}
local before=M3.Status(false);Nexus.OrbPanel.Refresh()
Nexus.GameAdapter.Orbs.Read()
check(labels['orb.status'] and labels['orb.read'] and labels['orb.panel'],'all three approved labels dispatch: '..tostring(labels['orb.status'])..'/'..tostring(labels['orb.read'])..'/'..tostring(labels['orb.panel']))
check(M3.Status(false).spent==before.spent,'timing dispatch changes no usage')
Nexus.Performance=raw
local H4,M4=S.Fresh();Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
check(not NexusOrbPanel.cont:IsShown(),'no receipt has no recovery explanation')
print('PASS orb_recovery_guidance_diag checks='..checks..'; offline only; spending and Continue eligibility unchanged')
