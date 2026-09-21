local D=dofile('tests/prototype/stop_sharing_support.lua');local T=D.T
-- A busy catalog no longer refuses the approval. One exact-ID approval is
-- retained, nothing is removed or sent while it waits, and it is submitted
-- exactly once when ordinary admission returns.
local H,C,id,button,restore=D.Begin();local old=H.Clone((C.Get(id)))
local busy=D.Busy(H,C);local wireBefore=#H.sent
local message=D.Confirm(H,id,button)
D.NoTable(H.stopMessages)
assert(message:find('Waiting for local removal',1,true) and message:find('still present',1,true),'waiting approval reports pending local work and the still-present record')
assert(not message:find('stopped sharing locally',1,true) and not message:find('refused',1,true),'waiting approval is neither a completed removal nor a refusal')
assert(H.deleteCalls==0 and H.tombstoneCalls==0 and #H.tombstoneTickets==0,'nothing is submitted while another transaction owns admission')
assert(T.Equal(C.Get(id),old),'waiting approval preserves the exact record')
local again,repeated=Nexus.CommunityBuilds.DeleteBuild(id)
assert(again==true and repeated.localPending==true and H.deleteCalls==0,'a repeated request joins the one retained approval')
T.Until(H,function()return busy.committed end)
T.Until(H,function()return #H.tombstoneTickets==1 end)
assert(H.deleteCalls==1 and H.tombstoneCalls==1 and T.Equal(C.Get(id),old),'one submission owns one real ticket; the row remains until it commits')
T.Until(H,function()return H.tombstoneTickets[1].committed end)
assert(C.Get(id)==nil,'only the committed ticket removes the local row')
H.Advance(5,.05)
local status=assert(Nexus.Sync.GetDeleteStatus(id))
assert(status.terminal and status.reason=='REMOTE_TOMBSTONE_ORDER_UNPROVEN','remote withdrawal limitation remains explicit')
local terminal=H.stopMessages[#H.stopMessages]
assert(terminal:find('stopped sharing locally',1,true) and terminal:find('remote withdrawal is not supported',1,true) and terminal:find('Peer removal is not confirmed',1,true),'terminal UI reports the committed local result and the remote limitation')
assert(H.deleteCalls==1 and H.tombstoneCalls==1,'no resubmission after the terminal commit')
assert(#H.sent==wireBefore and #H.actions==0,'deferred cleanup sends no withdrawal and makes no gameplay call')
restore();print('PASS busy Stop Sharing waits, submits once, commits, and keeps the zero-wire limitation')

-- Every scope or target change while waiting is a terminal refusal.
for _,change in ipairs({'owner','database','binding','revision'})do
 H,C,id,button,restore=D.Begin();old=H.Clone((C.Get(id)));wireBefore=#H.sent
 if change=='revision' then
  local ok,why=Nexus.CommunityBuilds.EditBuild(id,'NEXUS-TEST-EDITED-WHILE-WAITING','Edited after approval')
  assert(ok and why=='ROOT_MUTATION_PENDING','fixture: a real pending edit of the same build owns admission')
 else D.Busy(H,C) end
 message=D.Confirm(H,id,button)
 assert(message:find('Waiting for local removal',1,true) and H.deleteCalls==0)
 if change=='owner' then UnitName=function()return 'DifferentPlayer','Ebonhold' end
 elseif change=='database' then NexusDB=H.Clone(NexusDB)
 elseif change=='binding' then C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds) end
 if change=='revision' then
  T.Until(H,function()return H.stopMessages[#H.stopMessages]:find('refused',1,true) end)
 else Nexus.CommunityBuilds.PumpPendingShare() end
 local refused=H.stopMessages[#H.stopMessages]
 D.NoTable(H.stopMessages)
 assert(refused:find('Stop Sharing refused',1,true),'change while waiting is a visible terminal refusal: '..change)
 assert(refused:find(change=='revision' and 'changed after approval' or 'player or catalog changed',1,true),'refusal names its cause: '..change)
 for i=1,5 do Nexus.CommunityBuilds.PumpPendingShare()end
 if change~='database' and change~='binding' then H.Advance(5,.05) end
 assert(H.deleteCalls==0 and H.tombstoneCalls==0 and #H.tombstoneTickets==0,'cancelled approval is never submitted: '..change)
 for _,text in ipairs(H.stopMessages)do assert(not text:find('stopped sharing locally',1,true),'cancelled approval never claims removal')end
 for i=wireBefore+1,#H.sent do assert(not H.sent[i].text:find('WLRD',1,true),'cancellation sends no withdrawal')end
 assert((change=='revision' or #H.sent==wireBefore) and #H.actions==0,'cancellation sends nothing of its own and makes no gameplay call')
 if change=='revision' then assert(C.Get(id).title=='NEXUS-TEST-EDITED-WHILE-WAITING','the edited record remains shared')end
 restore();print('PASS waiting Stop Sharing cancelled on '..change..' change')
end
