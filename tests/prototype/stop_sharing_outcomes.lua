local D=dofile('tests/prototype/stop_sharing_support.lua');local T=D.T
-- Compatibility outcomes at the Sync boundary. The renderer, controller,
-- catalog ticket and normal completion lifecycle remain the real modules.
for _,kind in ipairs({'queued','retry','unavailable'})do
 local H,C,id,button,restore=D.Begin();local wireBefore=#H.sent
 if kind=='unavailable' then Nexus.Sync.BroadcastDelete=nil
 else Nexus.Sync.BroadcastDelete=function()
  H.deleteCalls=H.deleteCalls+1
  if kind=='queued' then return true end
  return false,'queued for retry'
 end end
 local message=D.Confirm(H,id,button)
 assert(message:find('Waiting for local removal',1,true) and not message:find('stopped sharing locally',1,true),'queue result alone cannot claim local removal: '..kind)
 assert(C.Get(id) and #H.tombstoneTickets==1,'fallback owns one real pending local ticket')
 local tombs,calls=H.tombstoneCalls,H.deleteCalls
 T.Until(H,function()return H.tombstoneTickets[1].committed end)
 assert(C.Get(id)==nil,'original fallback ticket commits local removal')
 local terminal=H.stopMessages[#H.stopMessages]
 assert(terminal:find('stopped sharing locally',1,true) and terminal:find('Peer removal is not confirmed',1,true),'only committed local removal gets success text')
 if kind=='queued' then assert(terminal:find('withdrawal queued',1,true))
 elseif kind=='retry' then assert(terminal:find('retry is pending',1,true))
 else assert(terminal:find('withdrawal not queued: Sync unavailable',1,true))end
 H.Advance(5,.05);D.NoTable(H.stopMessages)
 assert(H.tombstoneCalls==tombs and H.deleteCalls==calls and #H.sent==wireBefore and #H.actions==0,'display does not create an automatic retry, wire call, or game mutation')
 restore();print('PASS actual pending/committed Stop Sharing renderer with Sync compatibility outcome '..kind)
end
for _,kind in ipairs({'cancel'})do
 local H,C,id,button,restore=D.Begin();local database=NexusDB;local old=H.Clone(database.authorityBundle.communityBuilds[id]);local wireBefore=#H.sent
 local message=D.Confirm(H,id,button)
 assert(message:find('Waiting for local removal',1,true) and #H.tombstoneTickets==1)
 local calls,tombs=H.deleteCalls,H.tombstoneCalls
 C.CancelRootAdmission()
 local ticket=H.tombstoneTickets[1]
 assert(ticket.state~='pending' and not ticket.committed,'real ticket failure settles without local removal')
 assert(T.Equal(database.authorityBundle.communityBuilds[id],old),'failed approval preserves the original synthetic durable row')
 D.NoTable(H.stopMessages)
 for _,text in ipairs(H.stopMessages)do assert(not text:find('stopped sharing locally',1,true),'failed pending operation never claims removal')end
 assert(H.stopMessages[#H.stopMessages]:find('Stop Sharing refused',1,true),'terminal failure is visible through real completion callback')
 H.Advance(1,.05)
 assert(H.deleteCalls==calls and H.tombstoneCalls==tombs and #H.sent==wireBefore and #H.actions==0,'failure does not retry or submit anything')
 restore();print('PASS actual Stop Sharing pending failure on '..kind)
end
-- An already accepted local transaction may complete after the character
-- changes. It must affect only its original target and keep the original owner.
local H,C,id,button,restore=D.Begin();local database=NexusDB
local old=H.Clone(database.authorityBundle.communityBuilds[id])
local unrelated=H.Clone(database.authorityBundle.communityBuilds['synthetic-startup-2']);local wireBefore=#H.sent
D.Confirm(H,id,button);local calls,tombs=H.deleteCalls,H.tombstoneCalls
UnitName=function()return 'DifferentPlayer','Ebonhold' end
T.Until(H,function()return H.tombstoneTickets[1].state~='pending' end)
assert(H.tombstoneTickets[1].committed and database.authorityBundle.communityBuilds[id]==nil,'the original approved ticket, not the later character, owns completion')
assert(database.authorityBundle.syncTombstones[id].ownerKey==old.ownerKey,'committed removal retains the approved original owner')
assert(T.Equal(database.authorityBundle.communityBuilds['synthetic-startup-2'],unrelated),'original ticket does not change an unrelated record')
assert(H.stopMessages[#H.stopMessages]:find('stopped sharing locally',1,true),'terminal result reports actual committed removal')
assert(H.deleteCalls==calls and H.tombstoneCalls==tombs and #H.sent==wireBefore and #H.actions==0,'owner change cannot submit a new removal or withdrawal')
restore();print('PASS accepted local removal keeps its original owner and target after character change')
-- The exact confirmation still rechecks ownership before calling Sync.
H,C,id,button,restore=D.Begin()
button:Click();assert(H.popup and H.popup.data.id==id)
UnitName=function()return 'DifferentPlayer','Ebonhold' end
H.AcceptPopup()
assert(H.deleteCalls==0 and H.tombstoneCalls==0,'changed owner cannot submit the old confirmation')
assert(H.stopMessages[#H.stopMessages]:find('not your shared build',1,true))
restore();print('PASS Stop Sharing confirmation preserves the owner guard')
