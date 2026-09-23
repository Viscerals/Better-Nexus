-- At the moment an approved run reaches its maximum, the Orb panel's primary
-- control changes under the player: it was Pause while the run was going and
-- Resume while the run was paused, and at FINISHED it offers a new run with
-- the configured maximum already filled in. One press there starts real
-- spending. The first press must only arm that control, and only a deliberate
-- second press may start the run. Real runtime, real panel handlers, fake
-- game services, synthetic data.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=14}})
H.granted={['Disposable A']={},['Disposable B']={}}
for _=1,6 do
 table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
 table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
end
O.charges=20
H.Notify();A.Poll()
H.Approve(3,false,false)
for step=1,3 do
 for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
 check(M.Status().state=='WAIT_OFFER','step '..step..': the run requested its own Orb')
 H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.Result(410002,2)
end
check(M.Status().state=='FINISHED','the settled run finished at its limit: '..tostring(M.Status().state))

SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
Nexus.OrbPanel.Refresh()
check(f.start:GetText()=='Start new run','the primary control offers a new run')
local spends=H.Count('orb-spend')
f.start:Click()
local s=M.Status()
check(s.state=='FINISHED' and not s.running,'the first press starts nothing: '..tostring(s.state))
check(H.Count('orb-spend')==spends,'the first press spends nothing: '..H.Count('orb-spend')..' of '..spends)
check(f.start:GetText()=='Confirm new run','the control now says which press starts the run')
check(f.status:GetText():find('Confirm new run',1,true)~=nil,
 'the panel states what the second press approves: '..f.status:GetText())

-- A closed window is not an armed one.
f:Hide();f:Show();Nexus.OrbPanel.Refresh()
check(f.start:GetText()=='Start new run','closing the window disarms the control')
check(not M.Status().running,'and nothing was started by closing it')

f.start:Click()
check(f.start:GetText()=='Confirm new run','it arms again on the next press')
check(not M.Status().running,'still nothing is running after the arming press')
f.start:Click()
check(M.Status().running==true,'the second, deliberate press starts the new run')
check(M.Status().spent==0,'the new run starts its own counters: '..tostring(M.Status().spent))
print('PASS orb_finished_new_run_confirm: a finished run needs a deliberate second press before it spends again checks='..checks)
