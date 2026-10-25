-- Preserve the original one-time welcome after new warning acknowledgment.
-- Real TOC/reload literal round-trip, synthetic saved data and game only.
local H=dofile('tests/prototype/harness.lua')
H.keepOverwriteWarningPrompts=true
H.Boot()
local f=NexusOverwriteWarning
assert(f and f:IsShown(),'first startup shows new warning')
assert(not NexusQuickStart or not NexusQuickStart:IsShown(),'welcome waits for reading')
-- Permanent real-control characterization: every check below is collected
-- (V.Checker) and reported before the final verdict. Captions and footers are
-- exact literals. Welcome buttons are found by their existing caption only.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('overwrite_warning_welcome')
local ONBOARDING_FOOTER='Choose Close to keep Auto OFF. Opening this warning does not enable Auto.'
local AUTO_FOOTER='Choose No to keep Auto OFF. Opening this warning does not enable Auto.'
local function Ends(win,tail)local text=tostring(win.body and win.body:GetText() or '');return text:sub(-#tail)==tail end
local function Captions(win,where)
 C.expect(win.yes:GetText()=='Continue \226\128\148 Auto stays OFF',where..': onboarding Yes reads Continue - Auto stays OFF',win.yes:GetText())
 C.expect(win.no:GetText()=='Close',where..': onboarding No reads Close',win.no:GetText())
 C.expect(Ends(win,ONBOARDING_FOOTER),where..': onboarding footer is exact Choose Close')
end
local function Child(parent,label)
 for _,c in ipairs(parent.children)do if c:IsObjectType('Button') and c:GetText()==label then return c end end
end
local function Dismiss(welcome,where)
 local close=Child(welcome,'Close')
 C.expect(close~=nil,where..' Welcome offers exact Close')
 C.expect(Child(welcome,'Later')==nil,where..' Welcome offers no Later')
 -- Real legacy Later: baseline-control fallback only while Close is missing.
 local button=close or Child(welcome,'Later')
 C.setup(button~=nil,where..' Welcome has a dismissal control')
 return button
end
-- Negative dependency injection: the public Readout is absent only inside fn.
local function Bare(fn,...)
 local readout=Nexus.Readout;Nexus.Readout=nil
 local ok,result=pcall(fn,...)
 Nexus.Readout=readout -- restored unconditionally
 return ok,result
end
Captions(f,'first launch with Readout')
local actions=#H.actions
H.Advance(5.01);f.yes:Click()
assert(NexusQuickStart and NexusQuickStart:IsShown(),'affirmation resumes existing first-time welcome')
assert(not Nexus.RecomputeStats().autoEnabled and #H.actions==actions,'reading enables no automation/action')
assert(NexusDB.overwriteWarnings==nil and not NexusDB.hasSeenQuickStart,'unchecked warning is not either saved acknowledgment')
local dismiss=Dismiss(NexusQuickStart,'first-time')
if dismiss then dismiss:Click() end
assert(NexusDB.hasSeenQuickStart and not NexusQuickStart:IsShown(),'existing first-time Welcome Close (formerly Later) Finish behavior is retained')
local F=dofile('tests/prototype/format5_support.lua')
H=F.Reload(function(h)h.keepOverwriteWarningPrompts=true end)
H.Advance(1,.05) -- allow the first decision/welcome check after startup readiness
f=NexusOverwriteWarning
assert(f:IsShown(),'old welcome acknowledgment cannot suppress warning after real module reload')
H.Advance(5.01);f.suppress:SetChecked(true);f.yes:Click()
assert(NexusDB.overwriteWarnings.onboarding.suppressed and not NexusDB.overwriteWarnings.auto,'only checked onboarding opt-out survives')
assert(not NexusQuickStart:IsShown() and not Nexus.RecomputeStats().autoEnabled,'old welcome stays seen and Auto stays OFF')
H=F.Reload(function(h)h.keepOverwriteWarningPrompts=true end)
H.Advance(1,.05)
assert(not NexusOverwriteWarning:IsShown(),'matching saved onboarding opt-out skips warning after reload')
SlashCmdList.NEXUS('auto');f=NexusOverwriteWarning
assert(f:IsShown() and f.yes:IsEnabled() and not f.suppress:GetChecked(),'Auto still has its own immediate unchecked warning')
f.no:Click()
assert(not Nexus.RecomputeStats().autoEnabled and #H.actions==0,'declining reload Auto submits nothing')
-- Declined first launch on a reloaded synthetic copy with neither saved
-- acknowledgment. The warning is opened through its public API while the
-- public Readout is absent, so its answers are still in the reading period.
H=F.Reload(function(h)h.keepOverwriteWarningPrompts=true;NexusDB.overwriteWarnings=nil;NexusDB.hasSeenQuickStart=nil end)
local w=Nexus.OverwriteWarning
local function Welcome()return NexusQuickStart and NexusQuickStart:IsShown() end
local function Snap()return {F.Serialize(NexusDB),#H.actions,#H.sent} end
local function Same(s)return F.Serialize(NexusDB)==s[1] and #H.actions==s[2] and #H.sent==s[3] and not Nexus.RecomputeStats().autoEnabled end
C.setup(not (NexusOverwriteWarning and NexusOverwriteWarning:IsShown()) and not Welcome(),'reload opens no warning or Welcome before the request')
local ok,outcome=Bare(w.EnsureOnboarding)
f=NexusOverwriteWarning
C.setup(ok and outcome=='pending' and f:IsShown(),'onboarding warning opened without Readout',outcome)
Captions(f,'onboarding without Readout')
C.guard(not f.yes:IsEnabled() and not f.no:IsEnabled() and not f.suppress:IsEnabled(),'onboarding answers are disabled while reading')
local s=Snap()
f.yes:GetScript('OnClick')(f.yes,'LeftButton');f.no:GetScript('OnClick')(f.no,'LeftButton')
C.guard(f:IsShown() and not f.yes:IsEnabled() and not f.no:IsEnabled() and not Welcome() and Same(s),'early Continue/Close handlers give no answer, consent or effect')
H.Advance(5.01)
C.setup(f.yes:IsEnabled() and f.no:IsEnabled(),'reading period ended')
s=Snap();f.no:Click()
local q=NexusQuickStart
C.guard(not f:IsShown() and Welcome() and q.title and q.title:GetText()=='Nexus setup (information only)','after reading, Close declines to the information-only Welcome')
C.guard(Same(s) and not NexusDB.hasSeenQuickStart and NexusDB.overwriteWarnings==nil,'Close saves no seen, suppression or other data; Auto, actions and sends unchanged')
local infoClose=Dismiss(q,'information-only')
s=Snap();if infoClose then infoClose:Click() end
C.guard(not q:IsShown() and not f:IsShown() and Same(s),'information-only Close writes nothing and reopens nothing')
H.Advance(1,.05)
C.guard(not q:IsShown() and not f:IsShown() and not NexusDB.hasSeenQuickStart and NexusDB.overwriteWarnings==nil,'information-only dismissal is not reopened or recorded at the next decision check')
-- Genuine public RequestAuto reuses the same frame; accept is a synthetic counter.
local owner,accepted={},0
local function accept()accepted=accepted+1;return true end
s=Snap()
w.RequestAuto(owner,accept)
C.guard(rawequal(NexusOverwriteWarning,f) and f:IsShown() and f.yes:IsEnabled() and f.yes:GetText()=='Yes' and f.no:GetText()=='No' and accepted==0,'genuine Auto rebinds the same warning to Yes/No')
C.guard(Ends(f,AUTO_FOOTER),'Auto footer with Readout is exact Choose No')
f.yes:Click();f.yes:Click()
C.guard(accepted==1 and not f:IsShown() and not Welcome(),'valid Auto Yes accepts once; repeated Yes accepts nothing')
local function Refused(route,shown)
 f.yes:Click() -- stale answer after the request closed
 C.guard(shown and not f:IsShown() and accepted==1 and not Welcome(),'Auto '..route..' grants nothing and opens no Welcome; stale Yes accepts nothing')
end
ok=Bare(w.RequestAuto,owner,accept)
C.guard(ok and f:IsShown() and Ends(f,AUTO_FOOTER),'Auto footer without Readout is exact Choose No')
local shown=f:IsShown();f.no:Click();Refused('No',shown)
w.RequestAuto(owner,accept);shown=f:IsShown();f.close:Click();Refused('close X',shown)
w.RequestAuto(owner,accept);shown=f:IsShown();shown=w.CancelAuto(owner)==true and shown;Refused('CancelAuto',shown)
C.guard(Same(s),'Auto answers save, act, send and enable nothing')
C.finish('real controls')
print('PASS real startup welcome continuation and independent reload suppression')
