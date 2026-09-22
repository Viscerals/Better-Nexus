-- NATIVE06: one actual Share must send during later ordinary catalog work.
-- Synthetic data/clock; real popup, controller, catalog, lifecycle and wire.
local S=dofile('tests/prototype/share_test_support.lua');local T=S.T
T.SingleSlicePacing()
for _,kind in ipairs({'put','retention'})do
local H,C=S.Boot();S.Incoming(H,C)
-- Hold the real wire guard during setup so frame timing cannot submit before
-- the later candidate exists. Release it before the behavior under test.
H.combat=true
local first=S.Post('NEXUS-TEST-SEND-LIVENESS');local id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
local queued=Nexus.Sync.GetShareStatus(id)
assert(queued.queueAdmitted and not queued.sendCompleted,'one actual Share admitted before any send')
local queuedAt=assert(queued.queuedAt)
local record=H.Clone((C.Get('synthetic-startup-2')))
record.title='Later ordinary incoming work';record.lastModified=3
local ok,why,ticket
if kind=='retention' then
 local maintenance,reason
 -- Background compaction may own an open maintenance walk. Let its normal
 -- lifecycle finish before requesting this real retention transaction.
 T.Until(H,function()
  maintenance,reason=C.BeginCatalogMaintenance({database=NexusDB,operation='retention'})
  return maintenance~=nil
 end,1000)
 assert(C.MaintenanceEvictOverlay(maintenance,'synthetic-startup-2'))
 ok,why,ticket=C.CommitMaintenance(maintenance)
else ok,why,ticket=C.Put(record,{source='sync'})end
assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket,'real later catalog write')
H.combat=false
local sendReadyAt=H.now
assert(not Nexus.Sync.GetShareStatus(id).terminal,'setup remains inside original Share lifetime')
local before=#H.sent;local updates,handshakes=0,0
local update=Nexus.Sync.OnUpdate
Nexus.Sync.OnUpdate=function(...)updates=updates+1;return update(...)end
local handshake=Nexus.SyncWire.PumpHandshake
Nexus.SyncWire.PumpHandshake=function(...)handshakes=handshakes+1;return handshake(...)end
Nexus.SyncWire.ObservePeer('WaitingPeer-Ebonhold')
H.Advance(8,.05)
local p=C.ManualPreparationStatus();local sent=Nexus.Sync.GetShareStatus(id)
assert(not p.ready and not ticket.committed,'catalog work is still genuinely pending')
assert(sent.sendCompleted and sent.attemptedAt and sent.sentAt,'prepared manual Share must send before catalog work completes')
assert(sent.attemptedAt-sendReadyAt<8 and sent.attemptedAt-queuedAt<120 and sent.queuedAt==queuedAt,'original admission sends promptly after wire readiness without an expiry extension')
assert(sent.terminal and sent.outcome=='sent-attempted','normal attribution-window settlement retains the original operation')
assert(sent.generation==queued.generation and sent.attempt==1,'no replacement operation or automatic Share retry')
assert(#H.sent==before+1 and updates==0 and handshakes==0,'only one prepared Share sends; full Sync and handshake stay gated')
local raw=H.sent[before+1].text:gsub('||','|')
local body=assert(raw:match('^WLBI|[^|]+|(.+)$'),'actual summary wire format')
local summary=assert(Nexus.Codec.JSONDecode(Nexus.Codec.Base64Decode(body)))
assert(summary.id==id and summary.t=='NEXUS-TEST-SEND-LIVENESS' and summary.n==3,'wire carries the approved ID, title and copies')
assert(H.putCalls[id]==1 and #H.shareCalls==1,'one controller save and one broadcast')
H.Advance(113,.05)
assert(not C.ManualPreparationStatus().ready,'the exact fixture lasts beyond the original 120-second lifetime')
local settled=Nexus.CommunityBuilds.ShareStatus(id)
assert(settled.localSaved and settled.sendCompleted and settled.outcome=='sent-attempted','later housekeeping cannot expire the completed Share')
assert(settled.confirmation=='unavailable' and settled.peerStored==nil,'API submission is not peer storage confirmation')
assert(#H.sent==before+1 and updates==0 and handshakes==0,'no duplicate packet or unrelated dispatch while blocked')
T.Until(H,function()return ticket.committed and C.ManualPreparationStatus().ready end)
T.Until(H,function()return updates>0 and handshakes>0 end)
assert(updates>0 and handshakes>0,'full Sync and handshake resume after catalog and hash readiness')
assert(Nexus.Sync.GetShareStatus(id).generation==queued.generation and H.putCalls[id]==1 and #H.shareCalls==1,'readiness never resubmits the original Share')
assert(C.Get(id).title=='NEXUS-TEST-SEND-LIVENESS' and #H.actions==0,'local record survives and no gameplay action occurs')
local orb=Nexus.OrbRuntime.Status()
assert(not orb.running and not orb.pending and orb.spent==0 and orb.reserved==0,'Orb mode remains idle')
print('PASS one prepared Share sends and settles during >120 seconds of real '..kind..' catalog work; normal Sync remains gated until ready')
end
