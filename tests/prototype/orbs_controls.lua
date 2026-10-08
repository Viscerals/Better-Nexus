local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=2}})
H.Approve(7,true,true)
check(M.Status().limit==1,'single-step always authorizes one Orb')
check(not M.Prepare(),'duplicate Start refuses')
check(not M.Confirm(H.lastApproval.token),'approval token is one-use')
check(M.Pause(),'pause accepted before offer')
H.Offer({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410008,quality=1}})
check(H.Count('take')==0 and M.Status().spent==1,'paused offer not selected; spend still reconciled')
check(M.Status().reserved==0,'spend reservation replaced not added')
check(M.Resume(),'explicit Resume accepts known waiting offer')
check(H.Count('take')==1,'one fallback selection after Resume')
H.Result(410001,1)
-- A settled completion at the approved limit ends the run through its owner:
-- the replacement is confirmed, the durable receipt is cleared and nothing is
-- pending, so ownership is released and no Stop is needed.
check(M.Status().state=='FINISHED' and H.Count('orb-spend')==1,
 'a settled single step finishes the run at its approved limit: '..M.Status().state)
check(M.Status().spent==1 and M.Status().limit==1 and not M.Status().running,
 'the completed usage and approved limit stay visible')
check(not M.Status().pending and M.Status().reserved==0,'nothing is pending or exposed')
check(not M.BlocksOrdinary(),'the finished run released Orb-action ownership')
check(not M.Resume(),'a finished run cannot be resumed')
check(M.Status().canStart==true,'a new run may be started without an intermediate Stop')
-- Finishing never turns ordinary Automation back on by itself.
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary Automation stays off after a finished run')
-- One deliberate Start authorizes the next run and only then resets counters.
H.Approve(3,true,false)
check(M.Status().spent==0 and M.Status().limit==3 and M.Status().running,
 'the next authorized run starts its own counters: '..M.Status().spent..'/'..M.Status().limit)
check(H.Count('orb-spend')==2,'the new run spends its own next Orb, not a duplicate of the first')
check(O.source==410001,'confirmed recyclable result prioritized')
check(M.Stop(),'Stop accepted with pending spend')
H.Offer();check(H.Count('take')==1,'Stop never auto-selects later offer')
-- Operator manually resolves the legitimate pending native offer.
H.service.SelectPerk(410002);H.Result(410002,2)
check(M.Status().state=='STOPPED' and not M.Status().pending,'passive result reconciled after Stop')
for i=1,5 do M.Pump()end
check(H.Count('orb-spend')==2 and not M.BlocksOrdinary(),'no auto-continuation after Stop')
check(not M.PrepareLimitIncrease(4),'stopped run cannot be resurrected by increasing its limit')
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary Auto not restarted by terminal cleanup')
print('PASS Orb pause/resume/stop, single-step and explicit limit controls='..checks)
