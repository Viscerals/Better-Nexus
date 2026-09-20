-- The existing Advanced peer report shows, read-only, why the full Sync turn is
-- withheld: the last observed lifecycle gate reason, owner and the booleans the
-- gate actually decided with, the catalog preparation phase and progress, the
-- hash walk, the manual preparation scalars and the pending Sync owners. Read
-- through the real diagnostic consumer (log viewer, "Advanced peer" tab) and
-- bound to the phases the real catalog reports at the same moment. Reading it
-- must never pump, initialize, submit, reconcile or create a transaction.
-- Diagnostic only: no Sync behavior is changed or claimed. Synthetic data only.
local S=dofile('tests/prototype/sync_admission_support.lua');local T=S.T
local function Line(text,name)return ('\n'..text):match('\n('..name..' [^\n]*)') end
local function Field(line,key)return line and line:match('%f[%w_]'..key..'=(%S+)') end

-- 0. Before the gate is reached nothing is inferred: unknown, then the
-- community start-up early return with its three booleans still unknown.
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(100,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
local first=Nexus.StartupStatus()
assert(first.syncGate=='unknown' and first.syncGateOwner=='unknown' and first.syncGateCatalogReady==nil,'unknown before any observation')
T.Until(H,function()return Nexus.StartupStatus().syncGate=='community-startup' end,400000)
assert(Nexus.PeerDebug.Start('')~=false)
local gate=Line(Nexus.PeerDebug.Report(),'lifecycle_gate')
assert(Field(gate,'last_observed')=='community-startup' and Field(gate,'adapter_ready')=='unknown' and Field(gate,'catalog_ready')=='unknown'
 and Field(gate,'hashes_ready')=='unknown' and Field(gate,'startup')=='pending','community start-up is distinguished from the later gates: '..tostring(gate))
Nexus.PeerDebug.Stop()

local C;H,C=S.Boot(100)
local D,V=Nexus.PeerDebug,Nexus.LogViewer
-- The same call the tab's Start button makes, then the real viewer.
assert(D.Start('')~=false,'bounded peer test session started')
V.Show('peer')
-- The tab repaints once per second while active. Every frame's real catalog
-- status is sampled, so the rendered text can be bound to a real moment.
local hashGate
local function Panel()
 local samples={}
 for i=1,24 do
  H.Advance(.05,.05);local p=C.ManualPreparationStatus();samples[#samples+1]={phase=tostring(p.phase),pumps=p.pumps,ready=p.ready}
  -- The hash gate can be short; its report line is read at the frame it is first observed.
  if not hashGate and Nexus.StartupStatus().syncGate=='hashes-not-ready' then hashGate=Line(D.Report(),'lifecycle_gate') end
 end
 return (NexusLogScroll.scrollChild:GetText():gsub('||','|')),samples
end

-- 1. Idle and ready: the gate is open and nothing is in preparation.
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,20000)
local text=Panel()
local prep,walk
gate,prep,walk=Line(text,'lifecycle_gate'),Line(text,'catalog_preparation'),Line(text,'hash_walk')
assert(gate and prep and walk and Line(text,'manual_preparation') and Line(text,'sync_pending'),'the five lines are in the rendered Advanced peer report')
assert(Field(gate,'last_observed')=='open' and Field(gate,'owner')=='none' and Field(gate,'startup')=='ready' and Field(gate,'sync_ready')=='true','idle: gate open, no owner')
assert(Field(gate,'adapter_ready')=='true' and Field(gate,'catalog_ready')=='true' and Field(gate,'hashes_ready')=='true','idle: the three decided booleans are true')
assert(Field(prep,'ready')=='true' and Field(prep,'reason')=='ROOT_ADMITTED' and Field(prep,'phase')=='none' and Field(prep,'kind')=='none','idle: no catalog candidate')
assert(Field(walk,'phase')=='ready' and Field(walk,'pending')=='false','idle: hash walk finished')

-- 2. Reading is passive. Every owner that could pump, admit, invalidate, submit
-- or reconcile is observed; the report must call none of them and change nothing.
local calls={}
local function Watch(owner,name)local real=owner[name];owner[name]=function(...)calls[#calls+1]=name;return real(...)end;return function()owner[name]=real end end
local restore={Watch(C,'PumpRootAdmission'),Watch(C,'Put'),Watch(C,'Status'),Watch(C,'RootState'),Watch(C,'BeginRootAdmission'),
 Watch(Nexus.BuildHashCache,'Pump'),Watch(Nexus.Sync,'OnUpdate'),Watch(Nexus.Sync,'Housekeep'),Watch(Nexus.Sync,'UpdatePendingRequestStatus'),
 Watch(Nexus.CommunityBuilds,'PumpPendingShare'),Watch(Nexus.CommunityBuilds,'DiagnosticSnapshot')}
S.Hold(C)                                  -- a real inbound summary owns the catalog
local function State()
 local p,h,s=C.ManualPreparationStatus(),Nexus.BuildHashCache.Stats(),Nexus.Sync.Stats()
 return table.concat({tostring(p.ready),tostring(p.phase),p.pumps,p.totalPumps,p.work,p.generation,p.binding,tostring(h.phase),tostring(h.preparedRows),
  tostring(h.revision),tostring(s.sent),tostring(s.received),tostring(s.admissionDeferred),Nexus.Sync.WorkState().deferredAdmissions,#H.sent,#H.actions,
  tostring(Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)),tostring(Nexus.StartupStatus().syncGate)},'|')
end
local before=State();calls={}
for i=1,40 do assert(type(D.Report())=='string') end
assert(#calls==0,'the report calls no pumping, admitting, invalidating, submitting or reconciling owner: '..table.concat(calls,','))
assert(State()==before,'forty reads changed no catalog, hash, Sync, wire or gate state')
for _,undo in ipairs(restore)do undo()end

-- 3. Bound to the real phases while that one transaction runs.
--  a) The provider the tab renders, read at one instant, equals the catalog's
--     own status at that instant: phase, reason, kind, progress.
--  b) The text the real viewer rendered shows a phase and a progress count
--     that the catalog really had during that repaint second.
local seen,count,lastPumps={},0,-1
for i=1,400 do
 local samples;text,samples=Panel()
 local p=C.ManualPreparationStatus()
 if p.ready then break end
 local now=D.Report();gate,prep=Line(now,'lifecycle_gate'),Line(now,'catalog_preparation')
 assert(Field(prep,'phase')==tostring(p.phase) and Field(prep,'reason')==p.reason and Field(prep,'kind')==tostring(p.kind),'phase, reason and kind are the catalog\'s own: '..tostring(prep))
 assert(Field(prep,'ready')=='false' and Field(prep,'relevant')=='true' and Field(prep,'reason')=='CATALOG_COMMIT_PENDING' and Field(prep,'owner_agrees')=='true','an inbound record in preparation')
 assert(tonumber(Field(prep,'pumps'))==p.pumps and p.pumps>lastPumps,'progress count is the candidate\'s own and rises');lastPumps=p.pumps
 assert(Field(gate,'last_observed')=='catalog-not-ready' and Field(gate,'catalog_ready')=='false' and Field(gate,'adapter_ready')=='true','the gate names the catalog while it is busy: '..tostring(gate))
 local shown=Line(text,'catalog_preparation');local matched=false
 for _,s in ipairs(samples)do matched=matched or (Field(shown,'phase')==s.phase and tonumber(Field(shown,'pumps'))==s.pumps) end
 assert(matched,'the viewer rendered a phase and progress the catalog really had in that second: '..tostring(shown))
 if not seen[p.phase] then seen[p.phase]=true;count=count+1 end
end
assert(count>=4 and seen['rows'] and seen['index'],'several distinct useful phases were shown, including rows and index: '..count)

-- 4. After the commit the hash walk is the withholding boundary, then the gate opens.
T.Until(H,function()if not hashGate and Nexus.StartupStatus().syncGate=='hashes-not-ready' then hashGate=Line(D.Report(),'lifecycle_gate') end;return Nexus.StartupStatus().syncGate=='open' end,4000)
assert(hashGate and Field(hashGate,'last_observed')=='hashes-not-ready' and Field(hashGate,'catalog_ready')=='true' and Field(hashGate,'hashes_ready')=='false','catalog ready, hashes not ready: '..tostring(hashGate))
assert(Field(Line(D.Report(),'lifecycle_gate'),'last_observed')=='open','then the gate opened')

-- 5. A manual request owns the preparation of a busy catalog, and retained
-- inbound items are counted from the existing owner.
-- The first holder's commit queued its own recovery request; while that is owed a
-- new arrival is retained instead of taking the catalog, so it drains first.
T.Until(H,function()local w=Nexus.Sync.WorkState();return C.ManualPreparationStatus().ready and w.recovery==0 and w.outbound==0 and w.deferredAdmissions==0 end,12000)
S.Hold(C,'gate-holder-2','HolderTwo',S.base+50)
SlashCmdList.NEXUS('sync')
S.Receive('gate-arrival-1','Peer',S.base+60,'Arrives during the request')
H.Advance(.5,.05)
text=D.Report();gate=Line(text,'lifecycle_gate')
local manual,pending=Line(text,'manual_preparation'),Line(text,'sync_pending')
assert(Field(gate,'owner')=='manual-request' and Field(gate,'last_observed')=='catalog-not-ready','the manual request owns this preparation: '..tostring(gate))
assert(tonumber(Field(manual,'updates'))>0 and tonumber(Field(manual,'slices'))>=tonumber(Field(manual,'updates')) and Field(manual,'wait_reason')=='CATALOG_COMMIT_PENDING','manual preparation updates, slices and wait reason are shown: '..tostring(manual))
assert(tonumber(Field(pending,'retained_inbound'))==Nexus.Sync.WorkState().deferredAdmissions and tonumber(Field(pending,'retained_inbound'))>=1,'retained inbound count is the existing owner\'s')
assert(#H.actions==0,'zero gameplay mutation')
print(string.format('PASS read-only gate status in the Advanced peer report: unknown and community start-up distinguished, %d catalog phases bound, hash gate and open gate named, manual owner shown, 40 passive reads',count))
