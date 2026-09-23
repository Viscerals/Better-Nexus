-- The reported native maximum was "sync.update 751.090 ms". That path wraps
-- every synchronous step of one Sync update, so the number says one update was
-- long and nothing about WHICH step was long. The admission drive's slice
-- allowance covers only the preparation slices inside its own pump; transport
-- preparation, inbound decoding and the view refresh are outside it.
--
-- These phase scalars answer that question the next time it happens, and they
-- are armed only AFTER an update actually crossed the threshold, so an ordinary
-- update pays two clock reads. Offline timing here is the harness clock: it
-- proves the attribution mechanism, NOT any native duration or frame rate.
local A=dofile('tests/prototype/sync_admission_support.lua');local T=A.T
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,C=A.Boot(20)
local S=assert(Nexus.Sync,'sync is loaded')
check(type(S.PhaseStats)=='function','the owner reports its own phases')
S.ResetPhaseStats()
local stats=S.PhaseStats()
check(stats.thresholdMs>0,'a slow update has a stated threshold: '..stats.thresholdMs)
check(stats.slowUpdates==0,'no slow update has happened yet')
check(next(stats.phases)==nil,'and nothing is measured per phase until one does')

-- An ordinary update measures the update only, never the fourteen steps.
S.OnUpdate(0.05)
stats=S.PhaseStats()
check(next(stats.phases)==nil,'an ordinary update stays un-instrumented')
check(stats.lastUpdateMs~=nil,'while the update itself is still measured: '
 ..tostring(stats.lastUpdateMs))

-- Make one update genuinely slow through a real step, not by writing counters.
local realClock=debugprofilestop
local offset,stepping=0,false
debugprofilestop=function()
 local base=realClock and realClock() or 0
 -- Each reading advances past the slow-update threshold, so one update
 -- really is slow by the owner's own test.
 if stepping then offset=offset+60 end
 return base+offset
end
stepping=true
S.OnUpdate(0.05)
stepping=false
stats=S.PhaseStats()
check(stats.slowUpdates>=1,'the slow update is counted: '..stats.slowUpdates)
check(stats.armed>0,'and per-phase timing is armed for the updates after it: '..stats.armed)
check(stats.maxUpdateMs>=stats.thresholdMs,
 'the update maximum is retained: '..tostring(stats.maxUpdateMs))

-- The next updates attribute their time to named phases.
stepping=true
S.OnUpdate(0.05)
S.OnUpdate(0.05)
stepping=false
stats=S.PhaseStats()
local named=0
for name,row in pairs(stats.phases) do
 named=named+1
 check(row.count>=1,'phase '..name..' was measured: '..row.count)
 check(row.maxMs>=0,'and carries its own maximum: '..row.maxMs)
end
check(named>=6,'the update is attributed to several named phases: '..named)
check(stats.phases['admission.pump']~=nil,
 'including the admission drive, which owns the slice allowance')
check(stats.phases['transport.prepare']~=nil,
 'and transport preparation, which is outside that allowance')
debugprofilestop=realClock

-- Arming decays, so a single slow update does not instrument the session.
S.ResetPhaseStats()
stats=S.PhaseStats()
check(stats.armed==0 and stats.slowUpdates==0,'a reset clears the attribution')
check(next(stats.phases)==nil,'including the per-phase rows')
for _=1,3 do S.OnUpdate(0.05) end
check(next(S.PhaseStats().phases)==nil,
 'and ordinary updates after a reset stay un-instrumented')

-- The phase state sits on the module table because this file is at the Lua
-- local limit, so it is writable from outside. Measurement must never be able
-- to stop the update: every step still runs whatever is done to that table.
local ranSteps=0
local realPump=Nexus.Sync.RequestDataViewRefresh
for _,broken in ipairs({'not a table',{},{clock=1},false}) do
 Nexus.Sync._phases=broken
 local ok,err=pcall(Nexus.Sync.OnUpdate,0.05)
 check(ok,'a broken phase table does not stop the update ('..tostring(broken)..'): '..tostring(err))
 ranSteps=ranSteps+1
end
Nexus.Sync._phases=nil
local ok,err=pcall(Nexus.Sync.OnUpdate,0.05)
check(ok,'and neither does removing it entirely: '..tostring(err))
check(type(Nexus.Sync.PhaseStats())=='table','the reader survives it too')
-- Put a working owner back for the rest of the checks.
Nexus.Sync._phases={thresholdMs=50,window=20,stats={},armed=0,slowUpdates=0,
 steps=Nexus.Sync._defaultSteps,
 clock=function() return debugprofilestop and debugprofilestop() or nil end,
 record=function() end}
check(ranSteps==4,'every broken shape was exercised: '..ranSteps)

-- No clock, no claims: the update still runs and nothing is invented.
local saved=debugprofilestop
debugprofilestop=nil
S.ResetPhaseStats()
S.OnUpdate(0.05)
stats=S.PhaseStats()
check(stats.lastUpdateMs==nil,'without a clock no duration is reported')
check(next(stats.phases)==nil,'and no phase is invented')
debugprofilestop=saved
A.Settled(H,C)
print('PASS sync_phase_attribution: a long Sync update attributes itself to named phases, armed only after one happens checks='..checks)
