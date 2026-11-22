-- Context changes are read directly through actual adapter, with no Pump needed.
local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}});check(M.Start(3) and M.Pause(),'paused original pending run')
local receipt=F.Serialize(Nexus.Store.State().orbRefinement.pending);local actions=#H.actions
local oldLevel=H.playerLevel;H.playerLevel=oldLevel+1
local full,compact=M.Status(),M.CompactStatus();local resumed,why=M.Resume()
print('OBSERVED_CONTEXT_RESUME',tostring(full.canResume),tostring(compact.canResume),tostring(resumed),tostring(why))
check(not resumed,'fresh Resume refuses different level/run context')
check(full.canResume==false and compact.canResume==false,'reads cannot offer Resume under the changed current context')
check(full.pending and full.reserved==1 and compact.reserved==1,'current context refusal retains pending exposure')
check(F.Serialize(Nexus.Store.State().orbRefinement.pending)==receipt and #H.actions==actions,'context reads/refusal send nothing and preserve exact receipt')
H.playerLevel=oldLevel
check(M.Status().canResume and M.CompactStatus().canResume,'original context restoration recovers legitimate Resume')
-- active reconciliation generation is display-only, not an action-context field.
local read=A.Orbs.Read
A.Orbs.Read=function(mode)local s,e,stage=read(mode);if s and mode=='display'then s.context.active=(s.context.active or 0)+999 end;return s,e,stage end
check(M.Status().canResume and M.CompactStatus().canResume,'unrelated display active-generation difference cannot suppress legitimate Resume')
A.Orbs.Read=read
check(M.Resume(),'fresh original context still resumes')
check(H.Count('orb-spend')==1,'no new spend while original receipt is held')
-- Start/Stop surfaces (2026-11-19, 9106 field report): the surfaces offer no Stop
-- for the earlier runtime's paused or held run (a recovery action that sent
-- nothing); its runtime Stop keeps the receipt as before.
M.Pause();local mini=Nexus.OrbPanel.ShowMini();H.Advance(.3);check(not mini.stop:IsEnabled() and not mini.pause:IsShown() and not mini.resume:IsShown(),'the mini offers no Stop, Pause or Resume for that run')
M.Stop();check(M.Status().pending and F.Serialize(Nexus.Store.State().orbRefinement.pending)==receipt,'Stop retains original pending evidence')
print('PASS orb_resume_context_gate checks='..checks)
