-- The adaptive rolling policy and the automatic local roll recorder inside the REAL
-- runtime: real TOC boot, real Store, real automation step, real action submission,
-- mocked game services. Covers: shipped defaults, decision/outcome/after linkage with
-- Freeze survival and ownership change, the selector changing only at a safe action
-- boundary (never clearing or replaying an unresolved intent), loading uncertainty,
-- recorder-off, recorder-failure and recorder-absent equivalence of every action, the
-- commands and the report page, and the read-only saved root. No native evidence.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Boot(pending)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=pending or 30;H.Boot()
 return H
end
local function Plan(entries)
 assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic recorder plan',entries or {{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}),'plan set')
end
local TWO={{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200020,quality=0}}
local function Trace() return Nexus.DiagnosticLogs.Snapshot('rollTrace') end
local function Decisions() local out={};for _,r in ipairs(Trace())do if r.k=='D' then out[#out+1]=r end end return out end
local function Kinds(H) local out={};for _,a in ipairs(H.actions)do out[#out+1]=a[1]..':'..tostring(a[2]) end return table.concat(out,',') end

-- 1. Shipped defaults: adaptive strategy and local recording are ON without any setting.
local H=Boot()
local settings=Nexus.Store.Settings()
check(settings.rollingPolicy=='adaptive' and settings.rollTrace==true,'defaults: adaptive strategy, recording on')
check(Nexus.DefaultProfile.defaultSettings.rollingPolicy=='adaptive' and Nexus.DefaultProfile.defaultSettings.rollTrace==true,'shipped default profile')
Plan();H.Board(TWO);H.Notify();H.Advance(.5)
SlashCmdList.NEXUS('auto');H.Advance(1.5)
check(H.actions[1] and H.actions[1][1]=='freeze' and H.actions[1][2]==0,'the default strategy Freezes the first of two needed offers (zero-based wire index)')
local lines=Nexus.RollingStatusLines()
check(lines[1]=='rolling strategy: adaptive' and lines[2]:find('adaptive-0-settle-live1',1,true) and lines[3]:find('roll recording: on (local only)',1,true),'status lines: '..table.concat(lines,' | '))
-- Server answers the Freeze: the held offer returns carried; then the Take; ownership grows.
H.perks.pendingFreezeIndex=nil
H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200030,quality=0}});H.Notify();H.Advance(1.5)
check(H.actions[2] and H.actions[2][1]=='take' and H.actions[2][2]==200002,'the unheld needed offer is taken next')
H.perks.pendingSelectSpellId=nil
H.granted[H.names[200002]]={{spellId=200002,quality=2}}
H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200031,quality=0},{spellId=200032,quality=0}});H.Notify();H.Advance(1.5)
local d=Decisions()
check(#d==3,'one decision record per fresh board: '..#d)
check(d[1].pol=='adaptive-0-settle-live1' and d[1].prof=='group-protected-neutral-1' and d[1].req=='adaptive' and d[1].fb==nil,'policy, profile and requested selector are recorded')
check(d[1].pr=='freeze:1:200001:PAIR_FREEZE_SECOND_NEEDED' and d[1].of=='200001.1.;200002.2.;200020.0.' and d[1].tn==2,'proposal, ordered offers and target count')
check(d[1].lvl==40 and d[1].cls=='MAGE' and d[1].hz==30 and d[1].ch=='20.20.10.1','level, class, horizon and trusted charges')
local all=Trace()
local first=d[1]
-- Auto was switched on after the first decision, so its outcomes arrive as linked late records.
local lifecycle,afterRecord='',first
for _,r in ipairs(all)do
 if r.ref==first.n and r.io then lifecycle=lifecycle..r.io..',' end
 if r.ref==first.n and r.af then afterRecord=r end
end
check(lifecycle:find('prepared:intent_beat',1,true) and lifecycle:find('submitted:adapter_accepted',1,true) and lifecycle:find('confirmed:board_transition',1,true),'the action lifecycle is linked to the decision: '..lifecycle)
check(afterRecord.af=='200001.1.F;200002.2.;200030.0.' and afterRecord.fz=='set:kept','the board after the Freeze shows the held offer: Freeze survival is recorded')
check((afterRecord.cb or ''):find('next_board:board_transition',1,true),'the confirmation basis is recorded: '..tostring(afterRecord.cb))
check(afterRecord.ac=='20.20.9.1','charges after: one Freeze consumed')
check(d[2].pr=='take:2:200002:SELECT_OUTSTANDING_WISHLIST' and d[2].of:find('F',1,true) and d[2].fz=='held:kept' and d[2].ao=='200002:+1','Take: held offer survived, ordinary ownership +1: '..tostring(d[2].fz)..' '..tostring(d[2].ao))
check(d[3].tg:find('200002,1,0,1,0,',1,true),'the next decision sees the new ordinary copy')
check(d[1].s==d[2].s and d[1].n<d[2].n and d[2].n<d[3].n and d[1].run==d[3].run,'ids are opaque, ordered and share a run')
local text=Nexus.RollRecorder.Export()
for _,secret in ipairs({'Synthetic recorder plan','Echo 1','Echo 2'})do check(not text:find(secret,1,true),'no Wishlist or Echo name in the export: '..secret)end
check(not text:find('Valentine',1,true),'no character name in the export')

-- 2. The selector changes only at a safe action boundary and never clears or replays an intent.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5)
SlashCmdList.NEXUS('auto');H.Advance(1.5)
local sent=#H.actions
check(sent==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','precondition: a Freeze is submitted and unresolved')
SlashCmdList.NEXUS('policy released');H.Advance(3)
local current
for _,line in ipairs(Nexus.RollingStatusLines())do current=(current or '')..line..' | ' end
check(Nexus.Store.Settings().rollingPolicy=='released','the saved setting changes at once')
check(current:find('rolling strategy: adaptive (selected: released, applies at the next safe action boundary)',1,true),'the strategy in force stays adaptive while the intent is unresolved: '..current)
local held=Nexus.RecomputeStats().lastActionLifecycle.state
check(held=='submitted' or held=='uncertain' or held=='expired','the unresolved intent is not cleared: '..tostring(held))
check(#H.actions==sent,'nothing is replayed or re-decided while it is unresolved: '..Kinds(H))
-- The server answers: the intent resolves; the next decision runs the selected strategy.
H.perks.pendingFreezeIndex=nil
H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200030,quality=0}});H.Notify();H.Advance(1.5)
current=''
for _,line in ipairs(Nexus.RollingStatusLines())do current=current..line..' | ' end
check(current:find('rolling strategy: released |',1,true),'after the intent resolved the selected strategy is in force: '..current)
local latest=Decisions();latest=latest[#latest]
check(latest.pol=='released-nexus-1' and latest.req=='released' and latest.fb==nil,'the next decision is recorded as the released policy, selected and not a fallback')
local seenBoundary=false
for _,r in ipairs(Trace())do if r.k=='B' and r.kind=='policy' and r.d=='adaptive>released' then seenBoundary=true end end
check(seenBoundary,'the switch is a recorded boundary')
SlashCmdList.NEXUS('policy adaptive');H.Advance(1.5)
check(Nexus.Store.Settings().rollingPolicy=='adaptive','selecting adaptive again')
-- A selector fallback is shown in the status lines.
Nexus.Store.Settings().rollingPolicy='banana'
H.perks.pendingSelectSpellId=nil;H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200034,quality=0}});H.Notify();H.Advance(2)
local fallbackLines=table.concat(Nexus.RollingStatusLines(),' | ')
check(fallbackLines:find('fell back to the released policy: SELECTOR_UNKNOWN',1,true),'the status lines show the fallback reason: '..fallbackLines)
Nexus.Store.Settings().rollingPolicy='adaptive'
SlashCmdList.NEXUS('policy banana')
check(Nexus.Store.Settings().rollingPolicy=='adaptive','an invalid value changes nothing')
-- A garbage SAVED value runs the released policy and says so.
Nexus.Store.Settings().rollingPolicy=42
H.perks.pendingSelectSpellId=nil;H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200033,quality=0}});H.Notify();H.Advance(2)
latest=Decisions();latest=latest[#latest]
check(latest.pol=='released-nexus-1' and latest.fb=='SELECTOR_UNKNOWN','an unknown saved selector is a diagnosed fallback to the released policy: '..tostring(latest.pol)..' '..tostring(latest.fb))

-- 3. Loading uncertainty: a Freeze sent before a loading screen stays unresolved; no replay; the record ends it.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5)
SlashCmdList.NEXUS('auto');H.Advance(1.5)
sent=#H.actions
H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(5)
check(#H.actions==sent,'no action is replayed across the loading screen: '..Kinds(H))
local rows=Trace();local fate,leave,enter
for _,r in ipairs(rows)do
 if r.fate then fate=r.fate end -- on the decision, or on a late record that names it
 if r.k=='B' and r.kind=='world_leave' then leave=true end
 if r.k=='B' and r.kind=='world_enter' then enter=true end
end
check(fate=='interrupted:world_leave' and leave and enter,'loading boundaries are recorded and the open decision is marked interrupted: '..tostring(fate))
local uncertain=false
for _,r in ipairs(rows)do if (r.io or ''):find('uncertain:world_transition',1,true) then uncertain=true end end
check(uncertain,'the unresolved sent action is recorded as uncertain, never as confirmed')
SlashCmdList.NEXUS('policy released');H.Advance(5)
check(Nexus.RollingStatusLines()[1]:find('applies at the next safe action boundary',1,true),'the selector waits while the crossed intent is unresolved: '..Nexus.RollingStatusLines()[1])
check(#H.actions==sent,'and nothing is replayed after the selector change')

-- 3b. A stale assignment: the Wishlist changes after the board was first decided. The record
-- keeps the plan the decision saw, names the action actually prepared, and the stale action is not sent.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5)
local staleBefore=Decisions()[1]
check(staleBefore.pr:find('freeze:1:200001',1,true),'precondition: the first plan proposes a Freeze of 200001')
Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic new plan',{{spellId=200020,quality=0,stacks=1}})
H.Notify();H.Advance(.5)
SlashCmdList.NEXUS('auto');H.Advance(1.5)
check(H.actions[1] and H.actions[1][1]=='take' and H.actions[1][2]==200020 and #H.actions==1,'the action follows the new plan; the stale Freeze is never sent: '..Kinds(H))
local staleRows=Trace();local staleD,submittedActual,lifecycle
lifecycle=''
for _,r in ipairs(staleRows)do
 if r.k=='D' and not staleD then staleD=r end
 if r.sa then submittedActual=r.sa end
 if r.io then lifecycle=lifecycle..r.io..',' end
end
check(staleD.tg:find('200001,1,0',1,true) and not staleD.tg:find('200020',1,true),'the decision record keeps the plan it saw: '..tostring(staleD.tg))
check(submittedActual=='t3.200020','the record names the action actually submitted: '..tostring(submittedActual))
check(lifecycle:find('prepared:intent_beat@0.0=t3.200020',1,true),'the lifecycle names the prepared action: '..lifecycle)

-- 3c. The real runtime, one unchanged board: proposal A (Freeze), prepared B (the Wishlist changes),
-- superseded, prepared A again (the Wishlist changes back), submitted A. The record names A as submitted.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5)
SlashCmdList.NEXUS('auto');H.Advance(.25)
Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic B plan',{{spellId=200020,quality=0,stacks=1}})
H.Notify();H.Advance(.3)
Plan();H.Notify();H.Advance(1.5)
check(#H.actions==1 and H.actions[1][1]=='freeze' and H.actions[1][2]==0,'only the final Freeze was sent: '..Kinds(H))
H.perks.pendingFreezeIndex=nil
H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200035,quality=0}});H.Notify();H.Advance(1.5)
local sequence,submitted,survival='',nil,nil
for _,r in ipairs(Trace())do
 if r.io then sequence=sequence..r.io..',' end
 if r.sa and not submitted then submitted=r.sa end
 if r.fz and r.fz:find('set:',1,true) and not survival then survival=r.fz end
end
check(submitted=='f1.200001','the submitted action is the Freeze of 200001: '..tostring(submitted))
check(sequence:find('=t3.200020',1,true) and sequence:find('superseded:decision_changed',1,true),'the superseded intent B is named in the lifecycle: '..sequence)
check(survival=='set:kept','the Freeze outcome follows the submitted Freeze: '..tostring(survival))

-- 4a. A run boundary (the level returning from 80 to 1) ends the open decision and starts a new run id.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5)
SlashCmdList.NEXUS('auto');H.Advance(1.5)
local runBefore=Decisions()[1].run
H.playerLevel=80;H.Advance(1);H.playerLevel=1;H.Advance(2)
local boundary,fateRun
for _,r in ipairs(Trace())do
 if r.k=='B' and r.kind=='run' then boundary=r end
 if r.fate=='interrupted:run' then fateRun=true end
end
check(boundary and boundary.run~=runBefore,'a run boundary is recorded with a new run id')
check(fateRun,'the open decision of the dead run is marked interrupted')

-- 4. Reload linkage.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5)
local sessions=0
for _,r in ipairs(Trace())do if r.k=='B' and r.kind=='session' then sessions=sessions+1 end end
check(sessions==1,'a session boundary is written before the first decision')

-- 5. The recorder changes no action: on, off, failing and absent give the same actions.
local function Script(setup)
 local h=Boot();Plan({{spellId=200001,quality=1,stacks=2},{spellId=200002,quality=2,stacks=1}})
 if setup then setup(h) end
 local boards={
  TWO,
  {{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200030,quality=0}},
  {{spellId=200040,quality=0},{spellId=200041,quality=0},{spellId=200042,quality=0}},
  {{spellId=200001,quality=1},{spellId=200001,quality=1},{spellId=200043,quality=0}},
 }
 h.Board(boards[1]);h.Notify();h.Advance(.5);SlashCmdList.NEXUS('auto');h.Advance(1.5)
 for i=2,#boards do
  -- The server answers the previous action: a Take is granted, every latch clears.
  local last=h.actions[#h.actions]
  if last and last[1]=='take' then h.granted[h.names[last[2]]]={{spellId=last[2],quality=h.db[last[2]].quality}} end
  h.perks.pendingFreezeIndex,h.perks.pendingSelectSpellId,h.perks.pendingBanishIndex,h.perks.pendingReroll=nil,nil,nil,nil
  h.Board(boards[i]);h.Notify();h.Advance(1.5)
 end
 return Kinds(h),#Nexus.DiagnosticLogs.Snapshot('decision')
end
local withRecorder,decisionLog=Script()
local reference=withRecorder
local off,offLog=Script(function()Nexus.Store.Settings().rollTrace=false end)
check(off==reference and offLog==decisionLog,'recording off: the same actions and decision log: '..off..' vs '..reference)
local absent=Script(function()Nexus.RollRecorder=nil end)
check(absent==reference,'no recorder module: the same actions: '..absent..' vs '..reference)
local failing=Script(function()Nexus.DiagnosticLogs.Append=function()error('simulated storage failure')end end)
check(failing==reference,'a failing recorder: the same actions: '..failing..' vs '..reference)
check(reference:find('freeze',1,true) and reference:find('take',1,true) and reference:find('banish',1,true),'the script exercises Freeze, Take and Banish: '..reference)

-- 5b. The prepared support report carries the record (one private file for a tester).
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(1.5)
local report,why=Nexus.SupportReport.Prepare({})
check(report~=nil,'the support report prepares: '..tostring(why))
local whole=table.concat(report.chunks)
check(whole:find('-- local roll record (local only; no names; not a draw model) --',1,true) and whole:find('NEXUS_ROLL_TRACE_1',1,true),'the report holds the roll record section')
check(whole:find('PAIR_FREEZE_SECOND_NEEDED',1,true),'the report holds the recorded decision')
check(report.meta.omissions=='none' and not report.meta.partial,'no section is omitted: '..tostring(report.meta.omissions))
for _,chunk in ipairs(report.chunks)do check(#chunk<=Nexus.SupportReport.CHUNK_BYTES,'every report chunk stays within its bound')end
check(not whole:find('Synthetic recorder plan',1,true) and not whole:find('Echo 1',1,true),'no Wishlist or Echo name in the report')
-- A record whose text is full of escaped separators is not cut by the report.
local manyTargets={}
for i=1,32 do manyTargets[1230000+i]=85 end
local escapeId=Nexus.RollRecorder.Decision({state={},action={type='take',index=1,spellId=200001,reasonCode=string.rep('|%',48),policyId='adaptive-0-settle-live1'},
 board={cards={{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200020,quality=0}},signature='escape-check'},
 owned={synced=true,bySpell={}},plan={requestedCounts=manyTargets},catalog={rows={},playerMask=1},level=20,horizon=5,
 charges={banish=1,reroll=1,freeze=1,trustworthy=true}})
for i=1,12 do Nexus.RollRecorder.Intent(escapeId,'uncertain',string.rep('|%',20),{elapsed=1}) end
Nexus.RollRecorder.After({basis=string.rep('|',32),board={cards={}}})
local escapedLine
for line in Nexus.RollRecorder.Export():gmatch('[^\n]+')do if line:find('%7C%25%7C',1,true) then escapedLine=line end end
check(escapedLine and #escapedLine>1900,'precondition: a long escaped record line exists: '..tostring(escapedLine and #escapedLine))
report=Nexus.SupportReport.Prepare({})
check(table.concat(report.chunks):find(escapedLine,1,true),'the report holds the whole escaped record line, not a cut one')
Nexus.RollRecorder=nil
report=Nexus.SupportReport.Prepare({})
check(table.concat(report.chunks):find('local roll record: not available',1,true) and report.meta.omissions=='none','a missing recorder is stated, not an error')

-- 6. Commands: switch, clear, report page; Clear Log leaves the record alone.
H=Boot();Plan();H.Board(TWO);H.Notify();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(1.5)
local said={}
local realPrint=print
print=function(...)local p={};for i=1,select('#',...)do p[i]=tostring((select(i,...)))end;said[#said+1]=table.concat(p,' ')end
local function Said(text)for _,line in ipairs(said)do if line:find(text,1,true)then return true end end for _,line in ipairs(H.chat)do if line:find(text,1,true)then return true end end return false end
SlashCmdList.NEXUS('trace')
print=realPrint
check(Said('roll recording: on (local only)') and Said('Roll trace tab'),'/nexus trace reports and points to the tab')
check(NexusLogViewer~=nil,'/nexus trace opens the log viewer')
local page=Nexus.GetDiagnosticPageText('trace')
check(page:sub(1,18)=='NEXUS_ROLL_TRACE_1' and page:find('NOT A DRAW MODEL',1,true),'the Roll trace page is the export')
local retained=#Trace()
SlashCmdList.NEXUS('logclear')
check(#Trace()==retained and retained>0,'Clear Log leaves the roll record alone')
Nexus.DiagnosticLogs.ClearAll()
check(#Trace()==retained,'ClearAll leaves the roll record alone')
-- Status shows the strategy and the recording.
local mark=#H.chat
SlashCmdList.NEXUS('status')
local statusText=''
for i=mark+1,#H.chat do statusText=statusText..H.chat[i]..' ' end
check(statusText:find('rolling strategy: adaptive',1,true) and statusText:find('roll recording: on (local only)',1,true),'/nexus status shows the strategy in force and the recording state')
-- Clear Log on the Roll trace tab clears only the roll record; on another tab it leaves it alone.
local clearButton
for _,f in ipairs(H.frames)do if f.GetText and f:GetText()=='Clear Log' then clearButton=f end end
check(clearButton~=nil,'the viewer has a Clear Log button')
SlashCmdList.NEXUS('trace')
clearButton:Click();H.Advance(.2)
check(#Trace()==0,'Clear Log on the Roll trace tab clears the roll record')
-- records again for the rest
H.perks.pendingFreezeIndex=nil;H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200051,quality=0}});H.Notify();H.Advance(1.5)
retained=#Trace();check(retained>0,'recording continues after a clear')
SlashCmdList.NEXUS('trace off')
H.perks.pendingFreezeIndex=nil;H.Board({{spellId=200001,quality=1,isFrozen=true},{spellId=200002,quality=2},{spellId=200050,quality=0}});H.Notify();H.Advance(1.5)
check(Nexus.Store.Settings().rollTrace==false and #Trace()==retained,'/nexus trace off stops new records')
SlashCmdList.NEXUS('trace on');check(Nexus.Store.Settings().rollTrace==true,'/nexus trace on')
SlashCmdList.NEXUS('trace clear');check(#Trace()==0,'/nexus trace clear deletes the record')
SlashCmdList.NEXUS('trace sideways')
check(Nexus.Store.Settings().rollTrace==true,'an unknown trace argument changes nothing')

-- 7. Read-only saved root: nothing is written into the saved data; the session still records.
local F=dofile('tests/prototype/format5_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local db=F.Database({version=6,mutate=function(d)d.settingsVersion=6;d.settings.autoPick=true;d.settings.autoFreeze=true;d.settings.autoBanish=true;d.settings.autoReroll=true end})
H=F.Boot(db,function(h)h.pendingRolls=30 end)
local before=F.Serialize(db)
Plan();H.Board(TWO);H.Notify();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(1.5)
check(Nexus.MainInternals.SavedFormatClassV1()=='future','the saved root is read-only (future format)')
check(rawget(db,'rollTraceLog')==nil and F.Serialize(db)==before,'no roll record is written into a read-only saved root')
check(#Nexus.DiagnosticLogs.Snapshot('rollTrace')>=2,'the session still keeps its own record')
check(Nexus.Store.Settings().rollingPolicy=='adaptive','the read-only session runs the shipped default strategy')
-- A valid saved choice is honored in a read-only session; an invalid one is not copied; a saved recording-off is honored.
for _,case in ipairs({{'released','released',true},{'banana','adaptive',true},{'adaptive','adaptive',false}})do
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local d2=F.Database({version=6,mutate=function(d)d.settingsVersion=6;d.settings.rollingPolicy=case[1];if not case[3] then d.settings.rollTrace=false end end})
 local h2=F.Boot(d2,function(h)h.pendingRolls=30 end)
 check(Nexus.Store.Settings().rollingPolicy==case[2],'read-only root: saved selector '..case[1]..' -> '..tostring(Nexus.Store.Settings().rollingPolicy))
 check(Nexus.Store.Settings().rollTrace==(case[3] and true or false),'read-only root: saved recording switch '..tostring(case[3]))
end
-- A read-only root with a saved recording-off writes and keeps nothing.
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local offDb=F.Database({version=6,mutate=function(d)d.settingsVersion=6;d.settings.rollTrace=false;d.settings.autoPick=true;d.settings.autoFreeze=true end})
H=F.Boot(offDb,function(h)h.pendingRolls=30 end);Plan();H.Board(TWO);H.Notify();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(1.5)
check(#Nexus.DiagnosticLogs.Snapshot('rollTrace')==0 and rawget(offDb,'rollTraceLog')==nil,'saved recording-off in a read-only root: nothing is recorded anywhere')

print('PASS roll recorder runtime checks='..checks)
