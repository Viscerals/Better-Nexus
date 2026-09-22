-- A settled Orb run finishes at its approved limit: the last replacement is
-- confirmed, its durable receipt is cleared, nothing is pending, so the run
-- ends through its own owner, releases Orb-action ownership, keeps its
-- completed usage visible and needs no Stop before the next explicit Start.
-- An unsettled limit keeps its previous protections. The session-only run log
-- records the operations that actually happened, once each, for the current
-- run and at most the preceding one. Real runtime, real panel handlers, fake
-- game services, synthetic data.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function button(label,parent)
 for _,b in ipairs(H.frames)do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent)then return b end
 end
 error('button not found: '..label)
end

-- 1. A ten-Orb run that reaches its approved limit finishes when settled.
H.OrbPlan({{spellId=410002,quality=2,stacks=14}})
-- Twelve safe surplus copies, so ten replacements really have a source each.
H.granted={['Disposable A']={},['Disposable B']={}}
for _=1,6 do
 table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
 table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
end
O.charges=20
H.Notify();A.Poll()
H.Approve(10,false,false)
check(M.Status().limit==10 and M.Status().running,'ten Orbs approved and running')
-- One replacement per step, each waiting for the runtime to request its own
-- Orb first: an offer that arrives before the request is a different Echo
-- action, which the runtime correctly refuses to adopt.
local function replacement(step)
 for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
 check(M.Status().state=='WAIT_OFFER','step '..step..': the run requested its own Orb: '..M.Status().state)
 H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.Result(410002,2)
end
for step=1,10 do replacement(step) end
local s=M.Status()
check(s.state=='FINISHED','a settled run finishes at its limit: '..tostring(s.state))
check(s.spent==10 and s.limit==10 and not s.running,'the completed usage and approved limit stay visible: '
 ..s.spent..'/'..s.limit)
check(not s.pending and s.reserved==0,'nothing is pending or exposed')
check(not M.BlocksOrdinary(),'Orb-action ownership was released')
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary Automation stays off')
check(not M.Resume(),'a finished run cannot be resumed')

-- 2. The panel shows the finished state, offers a new run and disables Stop.
SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
Nexus.OrbPanel.Refresh()
check(f.status:GetText():find('Finished - limit reached',1,true),
 'the panel states the finished run: '..f.status:GetText())
check(f.start:GetText()=='Start new run','the primary control offers a new run')
check(not f.stop:IsEnabled(),'Stop is disabled for a finished run')
check(f.usage:GetText():find('10 / 10',1,true),'the completed usage stays visible: '..f.usage:GetText())

-- 3. The run log records every operation once, in order, with real fields.
local before=H.Count('orb-spend')
button('Run log',f):Click()
local log=assert(NexusOrbRunLog,'the run log window opens')
check(log:IsShown(),'the run log is shown')
check(H.Count('orb-spend')==before,'opening the log spends nothing')
local view=M.RunLog()
check(view.sessionOnly==true,'the log is session-only')
check(view.total==10,'ten operations are recorded: '..tostring(view.total))
check(#view.entries==10,'the full read returns them all: '..#view.entries)
check(view.limit==10 and view.spent==10,'the header carries the approved maximum and usage: '
 ..tostring(view.limit)..'/'..tostring(view.spent))
check(view.state=='FINISHED','the header carries the final state: '..tostring(view.state))
-- A bounded read returns only the rows the caller will render.
local page=M.RunLog('current',1,3)
check(#page.entries==3 and page.total==10,'a bounded read returns one page: '..#page.entries)
for index,entry in ipairs(view.entries)do
 check(entry.ordinal==index,'operation '..index..' keeps its order')
 check(entry.state=='confirmed','operation '..index..' is recorded as confirmed once')
 check(entry.sourceKey~=nil and entry.sourceQuality~=nil,'operation '..index..' records its actual source')
 check(entry.offered~=nil and #entry.offered==3,'operation '..index..' records the actual offer')
 check(entry.selectedKey~=nil and entry.selectionReason~=nil,
  'operation '..index..' records the selected Echo and its reason')
 check(entry.obtained~=nil,'operation '..index..' records the confirmed result')
end
check(NexusDB==nil or NexusDB.orbRunLog==nil,'no run history is written to saved data')

-- 4. Copy log produces the text on demand and changes nothing.
button('Copy log',log):Click()
check(log.copyBox:IsShown() and log.copyBox:GetText():find('Orb run log',1,true),
 'Copy log fills a copyable box')
check(log.copyBox:GetText():find('does not survive a reload',1,true),
 'the copied text states that the history is session-only')
check(H.Count('orb-spend')==before,'copying spends nothing')
button('Close',log):Click();check(not log:IsShown(),'the log closes')

-- 5. A new authorized run starts without Stop and keeps the previous log.
O.charges=10
H.Approve(2,false,false)
check(M.Status().spent==0 and M.Status().limit==2,'the new run starts its own counters')
local previous=M.RunLog('previous')
local current=M.RunLog('current')
check(previous.total==10,'the preceding run stays available: '..tostring(previous.total))
check(current.total<=1,'the new run logs only its own operations: '..tostring(current.total))
check(previous.runId~=current.runId,'the two runs are not combined')

-- 6. An unsettled limit keeps the previous protections: it does not finish.
replacement('new run 1')
for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}})
local pendingStatus=M.Status()
check(pendingStatus.pending==true,'the last operation is still unresolved')
check(pendingStatus.state~='FINISHED','an unresolved operation does not finish the run: '..pendingStatus.state)
check(M.BlocksOrdinary(),'the unresolved run still owns Orb actions')
-- 7. A refused submission is recorded truthfully as an attempt that was never
-- sent, and it never costs a later real operation its place in the log.
-- The operation left unresolved by section 6 is settled first, as an operator
-- would settle it, so the next fixture starts from a quiet runtime.
H.Result(410002,2)
M.Stop()
check(not M.Status().pending,'the unresolved operation was settled before the next fixture')
H.OrbPlan({{spellId=410002,quality=2,stacks=14}})
H.granted={['Disposable A']={},['Disposable B']={}}
for _=1,6 do
 table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
 table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
end
O.charges=20;H.Notify();A.Poll()
local spendsBefore=H.Count('orb-spend')
-- The service refuses this run's first submission.
O.mode='refuse'
H.Approve(2,false,false)
check(H.Count('orb-spend')==spendsBefore+1,'the refused submission really reached the service')
local refused=M.RunLog()
local notSent=0
for _,entry in ipairs(refused.entries)do if entry.state=='not sent' then notSent=notSent+1 end end
check(notSent==1,'the refused attempt is recorded as never sent: '..notSent)
check(M.Status().spent==0 and M.Status().reserved==0,'a refused attempt spends nothing')
O.mode='accept'
check(M.Resume(),'the run resumes after the refusal')
replacement('after refusal 1')
replacement('after refusal 2')
local finished=M.RunLog()
local confirmed=0
for _,entry in ipairs(finished.entries)do if entry.state=='confirmed' then confirmed=confirmed+1 end end
check(confirmed==2,'both real operations are recorded, not dropped: '..confirmed)
check(M.Status().spent==2,'the run really spent its two Orbs')
check(M.Status().state=='FINISHED','the run finished at its approved limit: '..M.Status().state)

-- 8. The limit reached on a later turn, not inside a settlement, finishes the
-- run through the same settled test.
H.OrbPlan({{spellId=410002,quality=2,stacks=14}})
H.granted={['Disposable A']={},['Disposable B']={}}
for _=1,6 do
 table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
 table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
end
O.charges=20;H.Notify();A.Poll()
H.Approve(1,false,false)
for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}})
check(M.Pause(),'the run is paused before its result arrives')
H.Result(410002,2)
check(M.Status().spent==1 and not M.Status().pending,'the result settled while the run was paused')
-- The approved maximum is reached and the result settled it, so there is
-- nothing to resume: the run finishes rather than asking for an increase.
check(M.Status().state=='FINISHED',
 'a settled result finishes the run even if the player had paused it: '..M.Status().state)
check(not M.BlocksOrdinary(),'that path also releases ownership')
local resumed,resumeWhy=M.Resume()
check(not resumed,'a finished run still cannot be resumed: '..tostring(resumeWhy))

print('PASS orb_finished_run_log: a settled limit finishes and releases ownership; the session-only log records ten operations once each and keeps the previous run checks='..checks)
