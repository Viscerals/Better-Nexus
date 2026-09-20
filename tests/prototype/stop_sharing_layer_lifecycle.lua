local L=dofile('tests/prototype/stop_sharing_layer_support.lua');local T=L.T
local H,C,id,button,restore,p,library,close=L.Begin()
local wire=#H.sent;local old=H.Clone((C.Get(id)))
local submitted={};local broadcast=Nexus.Sync.BroadcastDelete
Nexus.Sync.BroadcastDelete=function(build,...)
 submitted[#submitted+1]=build.id;return broadcast(build,...)
end
local other=H.Clone((C.Get('synthetic-startup-2')))
L.Open(H,id,button,p,library)
close:Click()
assert(not library:IsShown() and p:IsShown(),'normal Library X keeps the existing confirmation')
assert(p.data.id==id,'Library Close preserves original confirmation identity')
Nexus.CommunityBuilds.ShowBuild('synthetic-startup-2')
assert(library:IsShown(),'normal Library reopen')
L.Above(p,library)
assert(p.data.id==id and H.deleteCalls==0,'reopen and changed selection do not replace approval or submit')
local foreign=L.D.Busy(H,C)
p.button1:Click();L.Restored(p,'DIALOG',1)
L.D.NoTable(H.stopMessages)
-- The busy catalog retains this one original-ID approval instead of refusing
-- it. Nothing is submitted until ordinary admission returns.
assert(H.deleteCalls==0 and H.tombstoneCalls==0 and #H.tombstoneTickets==0,'busy acceptance submits nothing and owns no removal ticket yet')
assert(H.stopMessages[#H.stopMessages]:find('Waiting for local removal',1,true),'busy acceptance after closing/reopening under confirmation reports pending local work')
assert(T.Equal(C.Get(id),old) and T.Equal(C.Get('synthetic-startup-2'),other),'waiting approval preserves original and newly selected record')
T.Until(H,function()return foreign.committed end)
T.Until(H,function()return #H.tombstoneTickets==1 end)
assert(H.deleteCalls==1 and submitted[1]==id and H.tombstoneCalls==1,'later admission submits the original approved ID exactly once')
T.Until(H,function()return H.tombstoneTickets[1].committed end)
H.Advance(2,.05)
assert(H.deleteCalls==1 and H.tombstoneCalls==1,'dismissal and terminal completion do not resubmit')
assert(C.Get(id)==nil and T.Equal(C.Get('synthetic-startup-2'),other),'only the originally approved record is removed; the newly selected record is unchanged')
assert(H.stopMessages[#H.stopMessages]:find('stopped sharing locally',1,true) and H.stopMessages[#H.stopMessages]:find('remote withdrawal is not supported',1,true),'terminal result and remote limitation are reported')
assert(#H.sent==wire and #H.actions==0,'waiting lifecycle sends no wire or resource action')
restore()
-- A separate ready fixture covers accepted removal. The preserved baseline
-- also hides the old detail button after the mixed busy/selection sequence;
-- changing that unrelated projection behavior is outside this layer fix.
H,C,id,button,restore,p,library,close=L.Begin()
wire=#H.sent;old=H.Clone((C.Get(id)));other=H.Clone((C.Get('synthetic-startup-2')))
submitted={};broadcast=Nexus.Sync.BroadcastDelete
Nexus.Sync.BroadcastDelete=function(build,...)
 submitted[#submitted+1]=build.id;return broadcast(build,...)
end
L.Open(H,id,button,p,library)
close:Click();Nexus.CommunityBuilds.ShowBuild('synthetic-startup-2')
L.Above(p,library)
assert(p.data.id==id and H.deleteCalls==0,'ready confirmation keeps its original ID through Library Close/reopen and changed selection')
p.button1:Click();L.Restored(p,'DIALOG',1)
assert(H.deleteCalls==1 and submitted[1]==id and #H.tombstoneTickets==1,'deliberate confirmation admits one original-ID local ticket')
assert(H.stopMessages[#H.stopMessages]:find('Waiting for local removal',1,true) and T.Equal(C.Get(id),old),'NATIVE07 pending result remains exact')
T.Until(H,function()return H.tombstoneTickets[1].committed end)
H.Advance(2,.05)
local message=H.stopMessages[#H.stopMessages]
assert(message:find('stopped sharing locally',1,true) and message:find('remote withdrawal is not supported',1,true) and message:find('Peer removal is not confirmed',1,true),'NATIVE07 terminal result and limitation retained')
assert(C.Get(id)==nil and T.Equal(C.Get('synthetic-startup-2'),other),'only originally approved shared record removed')
assert(H.deleteCalls==1 and H.tombstoneCalls==1,'terminal callback and popup hide do not repeat deletion')
assert(#H.sent==wire and #H.actions==0,'popup lifecycle sends no unsupported wire or gameplay action')
restore();print('PASS actual Stop Sharing Close/reopen, original-ID acceptance, busy waiting with one submission, pending and committed result lifecycle')
