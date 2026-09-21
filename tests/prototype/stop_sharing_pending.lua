local D=dofile('tests/prototype/stop_sharing_support.lua');local T=D.T
local H,C,id,button,restore=D.Begin();local old=H.Clone((C.Get(id)));local wireBefore=#H.sent
local message=D.Confirm(H,id,button)
D.NoTable(H.stopMessages)
assert(message:find('Waiting for local removal',1,true),'accepted real Sync-owned removal must report pending local work')
assert(not message:find('stopped sharing locally',1,true) and not message:find('refused',1,true),'pending local ticket is neither a completed removal nor a refused approval')
assert(T.Equal(C.Get(id),old) and #H.tombstoneTickets==1,'pending removal retains the old row and one real ticket')
local calls,tombs=H.deleteCalls,H.tombstoneCalls
T.Until(H,function()return H.tombstoneTickets[1].committed end)
assert(C.Get(id)==nil,'only the original committed ticket removes the local row')
H.Advance(5,.05)
local status=assert(Nexus.Sync.GetDeleteStatus(id))
assert(status.terminal and status.reason=='REMOTE_TOMBSTONE_ORDER_UNPROVEN','existing remote withdrawal limitation remains explicit')
local terminal=H.stopMessages[#H.stopMessages]
assert(terminal:find('stopped sharing locally',1,true) and terminal:find('remote withdrawal is not supported',1,true) and terminal:find('Peer removal is not confirmed',1,true),'terminal UI reports the committed local result and actual remote limitation')
assert(not status.queueAdmitted and not status.retryPending and Nexus.Sync.WorkState().pendingDeletes==0,'unsupported remote withdrawal has no admitted or retry-owned operation')
assert(H.deleteCalls==calls and H.tombstoneCalls==tombs and calls==1,'terminal completion never retries removal')
assert(#H.sent==wireBefore and #H.actions==0,'local removal sends no unsupported withdrawal or gameplay action')
restore();print('PASS actual Stop Sharing pending local removal, committed tombstone, retained zero-wire limitation')
