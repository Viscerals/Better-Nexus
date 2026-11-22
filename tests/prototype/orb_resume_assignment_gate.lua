-- Real writer/projection: paused pending Resume must reflect current assignment.
ORB_SUPPORT_ECHOES={}
for id=500101,500112 do ORB_SUPPORT_ECHOES[#ORB_SUPPORT_ECHOES+1]={id,2} end
local H=dofile('tests/prototype/orbs_support.lua')
local A,M=H.A,H.M;local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local original={{spellId=410002,quality=2,stacks=3}}
H.OrbPlan(original);check(M.Start(3),'original approved run starts');check(M.Pause(),'explicitly paused pending run')
check(M.Status().canResume and M.CompactStatus().canResume,'unchanged valid assignment can resume')
local receipt=F.Serialize(Nexus.Store.State().orbRefinement.pending);local actions=#H.actions
local changed={{spellId=410002,quality=2,stacks=2}};local sidecar={}
for id=500101,500106 do changed[#changed+1]={spellId=id,quality=2,stacks=1,locked=true} end
for id=500107,500112 do sidecar[id]=true end
check(A.SetFirstLoadoutWishlistIdentity('Changed independently valid inputs',changed,sidecar),'real assignment writer accepts valid separate inputs')
local a=A.AssignedWishlist();check(a.state=='ready' and Nexus.OrbPolicy.Normalize(a.entries)==nil,'real projection is ready but combined target invalid')
local full,compact=M.Status(),M.CompactStatus()
local resumed,why=M.Resume()
print('OBSERVED_INVALID_RESUME',tostring(full.canResume),tostring(compact.canResume),tostring(resumed),tostring(why))
check(not resumed,'actual fresh Resume refuses pending assignment change')
check(full.canResume==false and compact.canResume==false,'neither full nor compact read may advertise this immediately ineligible Resume')
check(full.pending and compact.pending and full.reserved==1 and compact.reserved==1 and full.limit==3,'pending exposure and approved maximum retained')
check(F.Serialize(Nexus.Store.State().orbRefinement.pending)==receipt and #H.actions==actions,'reads and refusal preserve exact receipt/actions')
check(pcall(Nexus.OrbPanel.Show),'real full window remains renderable')
local mini=Nexus.OrbPanel.ShowMini()
check(not NexusOrbPanel.start:IsEnabled() and not mini.resume:IsEnabled(),'real full and mini Resume controls withheld')
-- Start/Stop surfaces (2026-11-19, 9106 field report): the surfaces offer no Stop
-- for the earlier runtime's paused or held run (a recovery action that sent
-- nothing); its runtime Stop keeps the receipt as before.
check(not NexusOrbPanel.stop:IsEnabled() and not mini.stop:IsEnabled(),'neither view offers a Stop for that held run')
check(A.SetFirstLoadoutWishlistIdentity('Orb test',original),'real writer restores exact original assignment')
local restored=M.Status();check(not restored.canResume and not M.CompactStatus().canResume,'rewriting old content stamps a new assignment identity and cannot resume pending work')
check(restored.progress and restored.progress.rolledMissing==3,'original target display recovers')
check(F.Serialize(Nexus.Store.State().orbRefinement.pending)==receipt and #H.actions==actions,'restoration itself preserves exact pending receipt and sends nothing')
check(not M.Resume(),'fresh Resume also refuses new identity despite restored old content')
check(H.Count('orb-spend')==1,'Resume on this held request does not submit another spend')
check(M.Status().state=='PAUSED','refused Resume leaves explicit pause intact')
Nexus.OrbPanel.Show();Nexus.OrbPanel.ShowMini();mini.stop:Click()
check(M.Status().pending and M.Status().reserved==1 and not M.Status().running,'Stop retains the unresolved operation')
check(F.Serialize(Nexus.Store.State().orbRefinement.pending)==receipt and H.Count('orb-spend')==1,'Stop and display never settle or resubmit pending operation')
print('PASS orb_resume_assignment_gate checks='..checks)
