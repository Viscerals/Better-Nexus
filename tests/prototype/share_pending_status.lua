-- A Share that waits keeps one truthful, build-specific sentence on screen.
-- test.9027 printed one chat line and closed the form; nothing stated the wait
-- afterwards, and a failed local save dropped the typed draft.
-- Real form, controller, Community window, catalog and Sync operation status.
-- The sentence is read from the existing Share outcome and the existing Sync
-- operation; this test adds no second owner. Synthetic data only.
local S=dofile('tests/prototype/share_test_support.lua');local T=S.T
local NAME='NEXUS-TEST-SHARE-GUARDS'
-- The controller keeps the print it saw at creation, so the sink is installed first.
local realPrint,sink=print,nil
print=function(...)
 if not sink then return realPrint(...) end
 local t={};for i=1,select('#',...)do t[#t+1]=tostring((select(i,...)))end;sink[#sink+1]=table.concat(t,' ')
end
local function Captured(fn)
 sink={};local lines=sink
 local ok,err=pcall(fn);sink=nil;assert(ok,err)
 return lines
end
local function Truthful(text,where)
 assert(type(text)=='string' and text:find(NAME,1,true),where..': names the build: '..tostring(text))
 assert(not text:find('%%',1,true) and not text:find('%d+ ?s[%s%.]') and not text:find('seconds',1,true),where..': no percentage and no timing promise: '..text)
 assert(not text:find('Cancel',1,true) and not text:find('Retry',1,true),where..': offers no unsafe Cancel or Retry: '..text)
end
local function WindowLine()
 local frame=assert(NexusCommunityBuildsFrame)
 return frame._syncStatusText:GetText() or ''
end

-- 1. Waiting for the catalog: not submitted yet.
local H,C=S.Boot();local incoming=S.Incoming(H,C)
local first,p
local lines=Captured(function()first,p=S.Post()end)
local id=first.id
assert(first.localPending and first.localStage=='waiting-catalog' and not H.putCalls[id],'fixture: one retained Share, not yet submitted')
local state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='preparing' and text:find('Preparing "'..NAME..'" to share — not sent yet.',1,true),'waiting state: '..tostring(text))
assert(text:find('finishing earlier work',1,true) and not text:find('is submitted',1,true),'a waiting Share is not described as a submitted write: '..text)
assert(not text:lower():find('fail',1,true) and not text:find('Not shared',1,true),'retained work is never called failed')
Truthful(text,'waiting')
assert(#lines==1 and lines[1]:find(text,1,true),'the click states the same sentence once: '..tostring(lines[1]))
assert(not p:IsShown(),'the accepted form closes')

-- The sentence persists: Community window opened later, closed and reopened; form reopened.
Nexus.CommunityBuilds.Show()
assert(WindowLine():find(text,1,true),'Community window states the pending Share: '..WindowLine())
Nexus.CommunityBuilds.Hide();Nexus.CommunityBuilds.Show()
assert(WindowLine():find(text,1,true),'still stated after close and reopen')
Nexus.CommunityBuilds.ShowPostBuild()
assert(p:IsShown() and p._shareStatus:GetText():find(text,1,true),'the reopened form states it too')

-- Repeat clicks: same identity, no second record, no failure wording.
for click=1,3 do
 p._postTitleBox:_NexusSetRawText('Another title '..click)
 lines=Captured(function()p._postGoBtn:Click()end)
 local again=Nexus.CommunityBuilds.ShareStatus()
 assert(again.id==id and again.localPending and not H.putCalls[id] and #H.shareCalls==0,'repeat click '..click..' keeps the one operation')
 assert(#lines==1 and lines[1]:find('Preparing "'..NAME..'"',1,true) and not lines[1]:lower():find('fail',1,true),'repeat click restates the wait: '..tostring(lines[1]))
 assert(p:IsShown() and p._postTitleBox:_NexusRawText()=='Another title '..click,'the later draft stays in the form')
 assert(p._shareStatus:GetText():find('Preparing "'..NAME..'"',1,true),'form status is the retained Share, not an error')
end

-- 2. Submitted local write, not settled: a different, equally truthful wait.
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localStage=='saving' end)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='preparing' and text:find('Preparing "'..NAME..'" to share — not sent yet.',1,true) and text:find('local save is submitted',1,true),'submitted-write state: '..tostring(text))
Truthful(text,'saving');assert(H.putCalls[id]==1 and #H.shareCalls==0)

-- 3. Delayed completion through the existing completion owner: queued, then sent.
lines=Captured(function()T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)end)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(incoming.committed,'the earlier incoming write settled first, unforced')
local completion;for _,l in ipairs(lines)do if l:find(NAME,1,true)then completion=l end end
assert(completion and completion:find('Saved "'..NAME..'" locally',1,true),'the existing completion notice fires once the save settles: '..tostring(completion))
assert(H.putCalls[id]==1 and #H.shareCalls==1 and C.Get(id).title==NAME,'one record, one hand-off, the first approved title')
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).sendCompleted end,8000)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='sent' and text=='Sent "'..NAME..'" — peer receipt not confirmed.','sent state: '..tostring(text))
T.Until(H,function()return WindowLine():find(text,1,true)~=nil end,2000)
assert(not text:find('stored',1,true) and Nexus.CommunityBuilds.ShareStatus(id).confirmation=='unavailable','a send is not a claim of remote storage')
print('PASS pending Share: waiting -> submitted -> saved -> sent, one sentence, persistent, one record')

-- The queued sentence, before the send turn.
H,C=S.Boot()
first=S.Post();id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='queued' or state=='sent','after the local save: '..tostring(state))
if state=='queued' then assert(text=='Saved "'..NAME..'" locally — queued for sharing.',text) end
print('PASS queued sentence: '..text)

-- 4. A real failed local save: actual reason, no false success, draft offered back.
H,C=S.Boot();S.Incoming(H,C);first,p=S.Post();id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localStage=='saving' end)
lines=Captured(function()C.CancelRootAdmission()end)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='refused' and text:find('Not shared: "'..NAME..'" — CANCELLED',1,true) and text:find('Nothing was saved or sent',1,true),'refusal states the actual reason: '..tostring(text))
local notice;for _,l in ipairs(lines)do if l:find('Not shared',1,true)then notice=l end end
assert(notice and notice:find('CANCELLED',1,true),'the existing completion owner reports the refusal')
assert(select(1,Nexus.CommunityBuilds.CanRetryShare(id))==false,'no Retry is offered for a record that was never saved')
Nexus.CommunityBuilds.Show()
assert(WindowLine():find('Not shared: "'..NAME..'"',1,true),'refusal persists in the window')
Nexus.CommunityBuilds.ShowPostBuild()
assert(p:IsShown() and p._postTitleBox:_NexusRawText()==NAME and p._postDescBox:_NexusRawText()=='Approved immutable test description','the approved draft returns to the form')

assert(H.putCalls[id]==1 and #H.shareCalls==0 and C.Get(id)==nil,'no resubmission, no send, no record')
-- The returned draft can be shared again as a new explicit request.
T.Until(H,function()return C.ManualPreparationStatus().ready end)
p._postGoBtn:Click()
local second=Nexus.CommunityBuilds.ShareStatus()
assert(second.id~=id,'an explicit new click is a new request')
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(second.id).localSaved end)
Nexus.CommunityBuilds.ShowPostBuild();Nexus.CommunityBuilds.ShowPostBuild()
assert(p._postDescBox:_NexusRawText()=='','after a saved Share the old failed draft is not offered again')
assert(#H.actions==0,'no gameplay action')
print('PASS refusal: actual reason, persistent, draft kept, no misleading Retry')

-- 5. Saved but never sent (the unchanged 120-second expiry under a blocked wire):
-- stated as stopped, not as sent; the explicit Retry Share keeps the build name.
H,C=S.Boot();H.combat=true;first=S.Post();id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='queued' and text=='Saved "'..NAME..'" locally — queued for sharing.','queued and unsent: '..tostring(text))
H.Advance(121,.05)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='stopped' and text:find('Saved "'..NAME..'" locally — not sent: expired',1,true) and not text:find('Sent',1,true),'expiry is not a send: '..tostring(text))
H.combat=false
assert(Nexus.CommunityBuilds.CanRetryShare(id)==true,'fixture: the existing owner offers Retry Share')
assert(Nexus.CommunityBuilds.RetryShare(id)==true,'explicit retry starts')
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert((state=='queued' or state=='sent') and text:find('"'..NAME..'"',1,true),'the retried Share is still named: '..tostring(text))
assert(H.putCalls[id]==1,'a retry sends the saved record; it writes no second record')
print('PASS stopped and retried Share: truthful and build-specific')

-- 6. Review F1/F2: an earlier Share of the session was sent. Sync answers an unknown ID
-- with its latest Share of any build; that must never describe a later build.
H,C=S.Boot()
first=S.Post('EARLIER-SENT');local earlier=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(earlier).sendCompleted end,8000)
S.Incoming(H,C)
first,p=S.Post('LATER-REFUSED');id=first.id
assert(id~=earlier and first.localPending,'the new request keeps its own identity while an earlier Share exists')
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='preparing' and text:find('"LATER-REFUSED"',1,true),'pending sentence is the new build: '..tostring(text))
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localStage=='saving' end)
C.CancelRootAdmission()
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='refused' and text:find('Not shared: "LATER-REFUSED" — CANCELLED',1,true),'the actual refusal reason, not the earlier build: '..tostring(text))
local merged=Nexus.CommunityBuilds.ShareStatus(id)
assert(merged.id==id and not merged.sendCompleted and not merged.sent and merged.queueReason=='CANCELLED','no field of the earlier Share is laid over this one')
-- The same earlier Share, then a later Share that commits after the player changed: never "Sent".
H,C=S.Boot()
first=S.Post('EARLIER-SENT-2');earlier=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(earlier).sendCompleted end,8000)
local handoffs=#H.shareCalls
S.Incoming(H,C);first=S.Post('LATER-OWNER-CHANGED');id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localStage=='saving' end)
local realUnitName=UnitName
UnitName=function()return 'DifferentPlayer','Ebonhold' end
T.Until(H,function()return not Nexus.CommunityBuilds.ShareStatus(id).localPending end)
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(#H.shareCalls==handoffs,'fixture: zero transport hand-offs for the later Share')
assert(state=='saved' and text:find('not queued: Share stopped: the player or catalog changed.',1,true) and not text:find('Sent',1,true) and not text:find('..',1,true),'a Share with no hand-off is never stated as sent: '..tostring(text))
UnitName=realUnitName
print('PASS an earlier Share never describes a later one')

-- 7. Review F14: a Share stopped for a player change gives no draft to the other player.
H,C=S.Boot();S.Incoming(H,C);first,p=S.Post();id=first.id
UnitName=function()return 'DifferentPlayer','Ebonhold' end
Nexus.CommunityBuilds.PumpPendingShare()
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='refused' and text:find('player or catalog changed. Nothing was saved or sent.',1,true) and not text:find('form keeps',1,true),'no doubled full stop and no draft claim: '..tostring(text))
Nexus.CommunityBuilds.ShowPostBuild();if not p:IsShown()then Nexus.CommunityBuilds.ShowPostBuild()end
assert(p._postDescBox:_NexusRawText()=='','the earlier player\'s draft is not offered')
UnitName=realUnitName
print('PASS no draft crosses a player change')

-- 8. Review F5: an explicit Retry Share of an older build does not take the sentence of a retained Share.
H,C=S.Boot();H.combat=true
first=S.Post('OLDER-STOPPED');local older=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(older).localSaved end)
H.Advance(121,.05);H.combat=false
T.Until(H,function()return C.ManualPreparationStatus().ready end)
assert(Nexus.CommunityBuilds.CanRetryShare(older)==true,'fixture: the older Share is retryable')
state,text=Nexus.CommunityBuilds.ShareStatusText(older)
assert(state=='stopped' and text:find('Open the build to use Retry Share.',1,true),'Retry is named only when the existing owner offers it: '..tostring(text))
S.Incoming(H,C);first,p=S.Post('RETAINED-A');id=first.id
assert(first.localPending and id~=older)
assert(Nexus.CommunityBuilds.RetryShare(older)==true,'the retry itself starts')
state,text=Nexus.CommunityBuilds.ShareStatusText()
assert(state=='preparing' and text:find('"RETAINED-A"',1,true),'the retained Share keeps its sentence: '..tostring(text))
Nexus.CommunityBuilds.ShowPostBuild();if not p:IsShown()then Nexus.CommunityBuilds.ShowPostBuild()end
lines=Captured(function()p._postGoBtn:Click()end)
assert(#lines==1 and lines[1]:find('Preparing "RETAINED-A"',1,true),'a repeat click restates the retained Share, not the retried build: '..tostring(lines[1]))

-- 9. Review F4: the open form follows its Share when that settles, with the Community window closed.
assert(p:IsShown() and p._shareStatus:GetText():find('Preparing "RETAINED-A"',1,true))
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
assert(not p._shareStatus:GetText():find('Preparing',1,true) and p._shareStatus:GetText():find('"RETAINED-A"',1,true),'the form no longer says Preparing after the save settled: '..p._shareStatus:GetText())
assert(H.putCalls[id]==1,'one record')
-- Review N5: the open form also follows the send, not only the local save.
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).sendCompleted end,8000)
Nexus.CommunityBuilds.Hide()                              -- the Community window is closed: no view refresh reaches the form
for i=1,20 do H.Advance(.05,.05)end                       -- one second of frames
assert(p:IsShown() and p._shareStatus:GetText():find('Sent "RETAINED-A"',1,true) and not p._shareStatus:GetText():find('queued for sharing',1,true),'within one second the open form says Sent, with the Community window closed: '..p._shareStatus:GetText())
print('PASS retry beside a retained Share; open form follows the settlement')

-- 10. Review N1 (P2): the refusal of the user's own click stays in the form through ordinary refreshes,
-- with or without an earlier Share in the session, until a legitimate next action replaces it.
H,C=S.Boot()
first=S.Post('EARLIER-SENT-3');T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(first.id).sendCompleted end,8000)
H.perks.serverBuildSlots[103]={name='TOO-MANY',verified=false,echoes={}}
for i=1,86 do H.perks.serverBuildSlots[103].echoes[i]={spellId=200000+((i-1)%90)+1,quality=i%4,stacks=1,locked=false}end
H.Notify();Nexus.GameAdapter.Poll()
Nexus.CommunityBuilds.ShowPostBuild();p=assert(NexusPostPopup);if not p:IsShown()then Nexus.CommunityBuilds.ShowPostBuild()end   -- the form of THIS boot
p._postWishlistBtn:Click()
local chosenSource
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible()then for _,r in ipairs({f:GetRegions()})do if r.GetText and tostring(r:GetText()):find('TOO-MANY',1,true)then chosenSource=f end end end end
assert(chosenSource,'fixture: the oversized source is listed');chosenSource:Click()
p._postTitleBox:_NexusSetRawText('REFUSED-CLICK')
lines=Captured(function()p._postGoBtn:Click()end)
local refusal=p._shareStatus:GetText()
assert(refusal:find('86 ordinary and 0 permanent',1,true) and lines[1]:find('86 ordinary',1,true),'fixture: a click-time refusal is shown in the form: '..tostring(refusal))
-- Ordinary refreshes of every kind: explicit refresh, window open/close, frames, an incoming catalog commit.
Nexus.CommunityBuilds.Refresh();Nexus.CommunityBuilds.Show();Nexus.CommunityBuilds.Hide();Nexus.CommunityBuilds.Refresh()
local ticket=S.Incoming(H,C);T.Until(H,function()return ticket.committed end)
for i=1,40 do H.Advance(.05,.05)end;Nexus.CommunityBuilds.Refresh()
assert(p:IsShown() and p._shareStatus:GetText()==refusal,'the refusal survives ordinary refreshes and is not replaced by the earlier Share: '..tostring(p._shareStatus:GetText()))
assert(not p._shareStatus:GetText():find('EARLIER-SENT-3',1,true))
-- Legitimate replacement 1: the user chooses another source.
p._postWishlistBtn:Click()
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible()then for _,r in ipairs({f:GetRegions()})do if r.GetText and tostring(r:GetText()):find(NAME,1,true)then chosenSource=f end end end end
chosenSource:Click()
assert(not p._shareStatus:GetText():find('86 ordinary',1,true),'choosing another source replaces the refusal')
-- Legitimate replacement 2: a new click that is accepted.
p._postTitleBox:_NexusSetRawText('ACCEPTED-AFTER-REFUSAL');lines=Captured(function()p._postGoBtn:Click()end)
local accepted=Nexus.CommunityBuilds.ShareStatus();assert(accepted.title=='ACCEPTED-AFTER-REFUSAL','the new click is accepted: '..tostring(lines[1])..' / '..tostring(accepted.title))
Nexus.CommunityBuilds.ShowPostBuild();if not p:IsShown()then Nexus.CommunityBuilds.ShowPostBuild()end
assert(p._shareStatus:GetText():find('ACCEPTED-AFTER-REFUSAL',1,true) and not p._shareStatus:GetText():find('86 ordinary',1,true),'the next result replaces it')
print('PASS a click-time refusal stays until a legitimate next action')

-- 11. Review N8 / mutants n14, n19: Retry is named and offered only when a retry can change the result; the reason is shown.
H,C=S.Boot();H.combat=true;first=S.Post('RETRY-WORDING');id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
local realStatus=Nexus.Sync.GetShareStatus
Nexus.Sync.GetShareStatus=function(wanted)local s=realStatus(wanted);if s and s.id==id then s.terminal,s.outcome,s.reason,s.sendCompleted,s.sent=true,'rejected','summary too large',false,false;s.version=tostring(C.Get(id).lastModified)end;return s end
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='stopped' and text:find('not sent: rejected (summary too large)',1,true) and not text:find('Retry',1,true),'a size rejection names its reason and no Retry: '..tostring(text))
assert(select(1,Nexus.CommunityBuilds.CanRetryShare(id))==false,'and the existing owner does not offer a retry that cannot succeed')
Nexus.Sync.GetShareStatus=function(wanted)local s=realStatus(wanted);if s and s.id==id then s.terminal,s.outcome,s.reason,s.sendCompleted,s.sent=true,'expired','expired',false,false;s.version=tostring(C.Get(id).lastModified)end;return s end
state,text=Nexus.CommunityBuilds.ShareStatusText(id)
assert(state=='stopped' and text:find('Open the build to use Retry Share.',1,true) and select(1,Nexus.CommunityBuilds.CanRetryShare(id))==true,'an expiry still offers Retry: '..tostring(text))
Nexus.Sync.GetShareStatus=realStatus
print('PASS Retry wording and action follow what a retry can change')
