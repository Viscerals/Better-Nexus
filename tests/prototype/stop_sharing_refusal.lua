local D=dofile('tests/prototype/stop_sharing_support.lua');local T=D.T
local H,C,id,button,restore=D.Begin();local old=H.Clone((C.Get(id)))
local busy=D.Busy(H,C);local wireBefore=#H.sent
local message=D.Confirm(H,id,button)
D.NoTable(H.stopMessages)
assert(message:find('Stop Sharing refused',1,true) and message:find('catalog',1,true),'busy refusal must explain catalog preparation')
assert(not message:find('stopped sharing locally',1,true),'refused local removal must not claim success')
assert(T.Equal(C.Get(id),old) and #H.tombstoneTickets==0,'busy refusal owns no removal ticket and preserves the exact record')
local status=Nexus.Sync.GetDeleteStatus(id)
assert(status and status.reason=='ROOT_MUTATION_PENDING','raw refusal reason remains in the operation receipt')
local calls,tombs=H.deleteCalls,H.tombstoneCalls
T.Until(H,function()return busy.committed and C.ManualPreparationStatus().ready end)
H.Advance(5,.05)
assert(H.deleteCalls==calls and H.tombstoneCalls==tombs and calls==1,'no automatic Stop Sharing resubmission')
assert(T.Equal(C.Get(id),old) and #H.sent==wireBefore and #H.actions==0,'refused cleanup changes no record, wire, or gameplay resource')
restore();print('PASS actual Stop Sharing structured busy refusal; readable result, preserved record, no retry')
