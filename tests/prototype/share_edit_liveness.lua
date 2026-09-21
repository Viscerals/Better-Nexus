local E=dofile('tests/prototype/share_edit_support.lua');local T=E.T
for _,kind in ipairs({'put','retention'})do
 local H,C,id,p,old=E.Begin();local restore=E.CapturePrint(H)
 local before=E.Submit(H,C,id,p,old);restore()
 local updated=E.AwaitCommit(H,C,id,old)
 assert(updated.id==old.id and updated.title=='NEXUS-TEST-EDIT-SAME-ID v2' and updated.description=='Approved updated description','exact approved same-ID text and new revision commit')
 assert(T.Equal(updated.echoes,old.echoes) and updated.fingerprint==old.fingerprint,'details edit preserves exact Echoes and fingerprint')
 local status=assert(Nexus.Sync.GetShareStatus(id))
 assert(status.version==tostring(updated.lastModified) and status.queueAdmitted and not status.sendCompleted,'committed Edit owns one prepared unsent operation')
 local ticket=E.LaterWork(H,C,kind);local updates=0;local update=Nexus.Sync.OnUpdate
 Nexus.Sync.OnUpdate=function(...)updates=updates+1;return update(...)end
 -- Delayed normal frame notifications keep the real candidate pending for
 -- the full expiry window. Each callback still uses the ordinary lifecycle.
 H.combat=false;H.Advance(8,.25)
 assert(not C.ManualPreparationStatus().ready and not ticket.committed and updates==0,'real later '..kind..' work still gates full Sync')
 local sent=assert(Nexus.Sync.GetShareStatus(id));local wire=E.Sends(H,id,updated.lastModified)
 assert(sent.sendCompleted and sent.terminal and sent.outcome=='sent-attempted' and #wire==1,'one approved Edit sends and settles before later catalog work finishes')
 assert(sent.generation==status.generation and sent.queuedAt==status.queuedAt and sent.attempt==status.attempt,'Edit sends the original admitted operation once')
 assert(wire[1].t==updated.title and wire[1].h==updated.fingerprintHash and wire[1].n==3 and wire[1].o==updated.ownerKey,'actual summary carries exact new revision, title, owner, fingerprint and copies')
 H.Advance(113,.25)
 assert(not C.ManualPreparationStatus().ready and #E.Sends(H,id,updated.lastModified)==1,'no duplicate during >120 seconds of real contention')
 assert(H.putCalls[id]==before.puts+1 and #H.shareCalls==before.broadcasts+1,'one Edit save and one broadcast; no new ID or retry')
 assert(sent.confirmation=='unavailable' and sent.peerStored==nil and #H.actions==0,'no peer confirmation or gameplay action invented')
 print('PASS actual same-ID Edit/Save during '..kind..': truthful pending UI, exact committed contents, one paced send and no duplicate')
end
