-- Full-UI localization: an Auto hold reason is presented once.
-- core/AutomationRuntime.lua SelectPoll keeps this poll's pause in
-- sel.blocked; Effective's reason carries it to the support report ("Auto
-- reason: ...") and to the displays, which say it through
-- Readout.AutoHoldText -> UserText.Message. The runtime keeps the English
-- wording (UserText.EnglishMessage) whatever the language, so the report's
-- bytes never depend on the language; the display says it once, in the
-- active language. Real TOC boot (harness.lua), real Auto, real Orb gate:
--  1. English: the wording and the report line are the exact English shown
--     before (reasons table: "orb state not yet known").
--  2. Pseudo pack: the same runtime reason and report line stay English
--     byte for byte; the HUD's held line says it through the seam, once.
--  3. The Orb block sentence (Orb runtime owns the action) through the same
--     path: English kept by the runtime; the display shows it translated.
--  4. EnglishMessage equals Message in an English session for every reason
--     of the reasons table and the Orb hold words; it changes no language.
-- Synthetic offline evidence only: no native client claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local PLAN={}
for i=1,12 do PLAN[#PLAN+1]={spellId=200000+i,quality=i%4,stacks=1} end
local NOT_KNOWN="Ordinary rolling paused: the server's Orb state is not confirmed yet"

local H
local function Boot(mode)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil;NexusQuickStart=nil
 if mode then S.InstallBootHook(mode) end
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Synthetic plan',verified=true,echoes=PLAN}}
 H.Boot()
 assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Synthetic plan',PLAN),'assign the plan')
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 Nexus.Panel.Show();H.Advance(.5)
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 assert(Nexus.RecomputeStats().autoEnabled==true,'Auto is ON')
end
-- An Orb service whose state the server has not confirmed yet: the ordinary
-- gate holds with the reasons-table code "orb state not yet known".
local function OrbStateNotKnown()
 ProjectEbonhold.OrbService={IsStateKnown=function() return false end,IsOfferPending=function() return false end,
  GetCharges=function() return 0 end,RequestCharges=function() return true end}
 Nexus.RequestRecompute();H.Advance(1)
end
local function ReportLine()
 local report=Nexus.SupportReport.Prepare({})
 for line in table.concat(report and report.chunks or {}):gmatch('[^\n]+') do
  if line:sub(1,13)=='Auto reason: ' then return line end
 end
end
-- v3: every runtime status line of Main's status source, rebuilt as
-- core/AutomationRuntime.lua builds it (colour codes as written).
local function StatusLines()
 local book=Nexus.MainRuntimeStatusBook()
 local out={}
 for raw in pairs(book.exact) do out[#out+1]=raw end
 for _,entry in ipairs(book.formats) do
  local args={}
  for n,slot in ipairs(entry.slots) do args[n]=slot=='count' and 7 or 'Qv' end
  if entry.key=='automation.status.banished_echo' then args[1],args[2]='|cffff6666','|r' end
  if entry.key=='automation.status.froze_echo' then args[1],args[2]='|cff66aaff ','|r' end
  out[#out+1]=string.format(entry.format,unpack(args))
 end
 out[#out+1]='auto paused: user acting'
 return out,book
end
local function Held()
 local model=Nexus.Panel._lastModel
 return type(model)=='table' and model.auto==true and type(model.paused)=='string' and model.paused or nil
end

------------------------------------------------------------------------------
-- 1. English
------------------------------------------------------------------------------
Boot(nil)
OrbStateNotKnown()
local e=Nexus.AutomationEffectiveState()
check(e.state=='paused' and e.reason:sub(1,#NOT_KNOWN)==NOT_KNOWN,'English: the runtime reason is the English wording: '..tostring(e.reason))
local englishReason=e.reason
local englishLine=ReportLine()
check(englishLine=='Auto reason: '..englishReason,'English: the report line carries it: '..tostring(englishLine))
local held=Held()
-- The HUD's held value is the gate's own raw code (AutoAllowed); the display
-- presents it once.
check(held=='orb state not yet known','English: the HUD holds on the raw gate code: '..tostring(held))
check(Nexus.Readout.AutoHoldText(held)==englishReason,'English: the display says the same bytes (presented once)')

do
 local G=Nexus.OrbGuidance
 local g=Nexus.Panel._lastModel.orbGuidance
 check(g.text==NOT_KNOWN..'. Open Orbs to inspect it.' and G.Shown(g.text)==g.text,'English: the guidance shows its exact bytes: '..tostring(g.text))
 check(NexusPanel._rollRec:GetText():find(g.text,1,true)==1,'English: the HUD roll body shows the exact guidance: '..NexusPanel._rollRec:GetText())
 for raw,key in pairs(G.SHOWN_KEYS) do check(G.Shown(raw)==raw,'English: '..key..' is the exact producer text') end
 local history=Nexus.OrbHistory
 for state,key in pairs(history.RUN_STATE_KEYS) do
  check(Nexus.Localization.Text(key)==history.RUN_STATES[state],'English: run state '..state..' keeps its English label')
 end
end

do
 local lines,book=StatusLines()
 local n=0
 for _ in pairs(book.exact) do n=n+1 end
 check(n==26 and #book.formats==8,'English: the runtime status book is admitted whole: '..n..'/'..#book.formats)
 for _,line in ipairs(lines) do
  check(Nexus.UserText.Message(line)==Nexus.UserText.EnglishMessage(line),'English: runtime status line unchanged: '..line)
 end
 Nexus.Panel.SetStatus('waiting for slot data')
 check(Nexus.Panel._lastModel.status=='waiting for slot data','English: the panel shows the exact status bytes')
end

------------------------------------------------------------------------------
-- 4. EnglishMessage equals Message in English (same session)
------------------------------------------------------------------------------
do
 local U=Nexus.UserText
 local src=S.readFile('core/UserText.lua')
 local block=assert(src:match('\nlocal reasons=(%b{})'),'reasons table')
 local reasons=assert(loadstring('return '..block))()
 local n=0
 for raw,english in pairs(reasons) do
  n=n+1
  check(U.EnglishMessage(raw)==U.Message(raw),'EnglishMessage equals Message in English: '..raw)
  check(U.Message(english)==english,'the English wording is recognized as itself in English: '..english)
 end
 for _,raw in ipairs({'user acting','client auto-accept re-enabled','Another Echo automation addon is loaded -- disable it',
  'the game has not finished loading the character'}) do
  check(U.EnglishMessage(raw)==U.Message(raw) and U.Message(raw)==raw,'hold words stay raw English: '..raw)
 end
 check(n>30,'reasons covered: '..n)
end

------------------------------------------------------------------------------
-- 2. Pseudo pack: the runtime keeps English; the display says it once
------------------------------------------------------------------------------
Boot('wrap')
check(Nexus.Localization.ActiveLanguage()=='frFR','pseudo pack active')
OrbStateNotKnown()
e=Nexus.AutomationEffectiveState()
check(e.reason==englishReason,'pseudo: the runtime reason stays the English bytes: '..tostring(e.reason))
check(ReportLine()==englishLine,'pseudo: the support report line is byte-identical to English: '..tostring(ReportLine()))
held=Held()
check(held=='orb state not yet known','pseudo: the HUD model holds the same raw gate code: '..tostring(held))
check(Nexus.Readout.AutoHoldText(e.reason)==S.OPEN..NOT_KNOWN..S.CLOSE,'pseudo: the kept English wording is also said once at display: '..Nexus.Readout.AutoHoldText(e.reason))
local shown=Nexus.Readout.AutoHoldText(held)
check(shown==S.OPEN..NOT_KNOWN..S.CLOSE,'pseudo: the display says it through the seam, once: '..tostring(shown))
check(not S.Unmarked(shown):find('%a'),'pseudo: no English word is left in the held line: '..tostring(shown))
local note=Nexus.Readout.AutoHoldNote(held)
check(note:find(S.OPEN..NOT_KNOWN..S.CLOSE,1,true)~=nil,'pseudo: the inline held note carries it once: '..note)
-- English in, active language out: EnglishMessage never follows the pack.
check(Nexus.UserText.EnglishMessage('orb state not yet known')==NOT_KNOWN,'pseudo: EnglishMessage stays English')
check(Nexus.UserText.Message('orb state not yet known')==S.OPEN..NOT_KNOWN..S.CLOSE,'pseudo: Message follows the pack')
check(Nexus.Localization.ActiveLanguage()=='frFR','EnglishMessage leaves the active language unchanged')

------------------------------------------------------------------------------
-- 3. The Orb block sentence through the same path
------------------------------------------------------------------------------
do
 local raw='Ordinary rolling is paused: Orb refinement owns the current action.'
 local english=Nexus.UserText.EnglishMessage(raw)
 check(english==raw,'pseudo: the Orb block sentence stays English for the record: '..english)
 local display=Nexus.UserText.Message(raw)
 check(display==S.OPEN..S.OPEN..'Ordinary rolling'..S.CLOSE..' is paused: Orb refinement owns the current action.'..S.CLOSE,
  'pseudo: the display says the Orb sentence and its subject through the Orb book: '..display)
 check(Nexus.Readout.AutoHoldText(raw)==display,'pseudo: AutoHoldText shows the same single presentation')
 local unknown='Ordinary rolling is paused: '..'Zażółć'
 check(Nexus.UserText.Message(unknown)==unknown,'pseudo: an unknown text keeps its existing presentation')
end

------------------------------------------------------------------------------
-- 5. Orb guidance (logic/OrbGuidance.lua) at the panel: English model,
--    said once at the display (roll body and the Open Orbs hover)
------------------------------------------------------------------------------
do
 local G=Nexus.OrbGuidance
 local g=Nexus.Panel._lastModel.orbGuidance
 local OPEN_TAIL='. Open Orbs to inspect it.'
 check(type(g)=='table' and g.state=='orb-state','pseudo: the guidance holds on the Orb state: '..tostring(g and g.state))
 check(g.text==NOT_KNOWN..OPEN_TAIL,'pseudo: the guidance model keeps the English: '..tostring(g.text))
 check(g.blockers[1] and g.blockers[1].text==NOT_KNOWN,'pseudo: its blocker keeps the English: '..tostring(g.blockers[1] and g.blockers[1].text))
 local shown=G.Shown(g.text)
 check(shown==S.OPEN..S.OPEN..NOT_KNOWN..S.CLOSE..OPEN_TAIL..S.CLOSE,'pseudo: the guidance is said once with its reason: '..shown)
 local button=NexusPanel._orbsBtn
 button.blockers=g.blockers
 local lines=S.CaptureTooltip(button:GetScript('OnEnter'),button)
 local found=false
 for _,line in ipairs(lines) do if line==S.OPEN..NOT_KNOWN..S.CLOSE then found=true end end
 check(found,'pseudo: the Open Orbs hover says the blocker through the seam: '..table.concat(lines,' | '))
 for raw,key in pairs(G.SHOWN_KEYS) do
  check(G.Shown(raw)==S.OPEN..raw..S.CLOSE,'pseudo: guidance text said through '..key)
 end
 check(G.Shown('Zażółć')=='Zażółć','pseudo: an unknown guidance text is shown unchanged')
 check(NexusPanel._rollRec:GetText():find(shown,1,true)==1,'pseudo: the HUD roll body says the guidance once: '..NexusPanel._rollRec:GetText())
 -- The Orb run line of the hub: the run state's meaning through its key.
 local history=Nexus.OrbHistory
 for state,key in pairs(history.RUN_STATE_KEYS) do
  check(Nexus.Localization.Text(key)==S.OPEN..history.RUN_STATES[state]..S.CLOSE,'pseudo: run state '..state..' has its keyed meaning')
 end
end

-- v3: the runtime status lines are said through the seam at the panel.
do
 local lines=StatusLines()
 for _,line in ipairs(lines) do
  local shown=Nexus.UserText.Message(line)
  check(S.IsPseudo(shown) and S.LooksUntranslated(shown,function(w) return w=='Qv' end)==nil,'pseudo: runtime status line said through the seam: '..shown)
 end
 Nexus.Panel.SetStatus('waiting for slot data')
 check(Nexus.Panel._lastModel.status==S.OPEN..'waiting for slot data'..S.CLOSE,'pseudo: the panel status receiver says it once: '..tostring(Nexus.Panel._lastModel.status))
 check(Nexus.UserText.Message('|cffff6666Banished|r echo #3')==S.OPEN..'|cffff6666Banished|r echo #3'..S.CLOSE,'pseudo: the colour codes stay around the action word')
end
-- The Options hover's status when the Identity gate refuses the status text:
-- its stand-in is said through its key (only the gate is stubbed).
do
 local identity=Nexus.Identity
 local real=identity.DisplaySafeText
 local model=Nexus.Panel._lastModel
 local status=model.status
 model.status='unreviewed status'
 identity.DisplaySafeText=function() return nil end
 local shown=Nexus.Panel.StatusTooltipText()
 identity.DisplaySafeText=real
 model.status=status
 check(shown==S.OPEN..'status unavailable'..S.CLOSE,'pseudo: the status stand-in is said through its key: '..tostring(shown))
end
print('l10n_hold_presentation: '..checks..' checks')
