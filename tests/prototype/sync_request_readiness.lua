-- An explicit Sync Now request must reach its first transmission while valid
-- inbound records keep arriving. A direct inbound catalog write invalidates
-- the hash the request waits for, and the lifecycle withholds every full Sync
-- turn until the catalog and the hash are both ready. Real slash command,
-- session, lifecycle, hash cache, catalog and transport; synthetic data only.
local S=dofile('tests/prototype/sync_admission_support.lua');local T=S.T
local function Stats()return Nexus.Sync.Stats()end
local function Deferred()return Nexus.Sync.WorkState().deferredAdmissions end
local function Sent(H)
 local n=0
 for _,packet in ipairs(H.sent)do if packet.text:gsub('||','|'):gsub('^P%d+:',''):match('^WLRQ|')then n=n+1 end end
 return n
end
local function Accepted(H,prefix)
 local n=0
 for id,seen in pairs(H.puts)do if id:find(prefix,1,true)==1 then n=n+seen.accepted end end
 return n
end
local arrivals=0
local function Arrive(prefix,owner)
 arrivals=arrivals+1
 return S.Receive(prefix..arrivals,owner or ('Traffic'..((arrivals-1)%8+1)),S.base+arrivals,'Inbound during request '..arrivals)
end

-- 0. Controls: no traffic, and one transaction already in flight at the click.
local H,C=S.Boot(100)
SlashCmdList.NEXUS('sync')
T.Until(H,function()return Sent(H)==1 end,2000)
print('PASS control: no inbound traffic, request transmitted')
H,C=S.Boot(100);S.Hold(C)
local clicked=H.now;SlashCmdList.NEXUS('sync')
T.Until(H,function()return Sent(H)==1 end,8000)
assert(C.Get('admission-holder')~=nil,'the transaction in flight at the click committed first; it is never cancelled')
print(string.format('PASS control: one transaction in flight at the click, request transmitted after %.1fs',H.now-clicked))

-- 1. Saturating valid inbound summaries: one arrives whenever the catalog is
-- ready, the harshest case. Unheld, each takes the catalog and the request
-- expires unsent with no request ID.
H,C=S.Boot(100);arrivals=0
for i=1,40 do if C.ManualPreparationStatus().ready then Arrive('ready-a-')end;H.Advance(.05,.05)end
local directBefore=Accepted(H,'ready-a-')
assert(directBefore>=1,'fixture: before any request, a valid summary takes a ready catalog directly')
clicked=H.now;SlashCmdList.NEXUS('sync')
local sentAt
T.Until(H,function()
 -- The transmission is checked first: an arrival after it is no longer held.
 if Sent(H)>=1 then sentAt=H.now;return true end
 if Stats().terminalReason=='expired' or H.now-clicked>=305 then return true end
 if C.ManualPreparationStatus().ready then Arrive('ready-a-')end
end,12000)
print(string.format('OBSERVED sent=%s after=%.1fs requestId=%s terminal=%s queue=%s direct_writes_during_request=%d held=%s deferred=%d',
 tostring(sentAt~=nil),H.now-clicked,tostring(Stats().requestId),tostring(Stats().terminalReason),tostring(Stats().queueOutcome),
 Accepted(H,'ready-a-')-directBefore,tostring(Stats().admissionHeld),Deferred()))
assert(sentAt~=nil and Stats().requestId~='none' and Stats().queueOutcome=='sent','the explicit request reaches its first transmission under continuous valid inbound traffic')
assert(Accepted(H,'ready-a-')==directBefore,'no new inbound write took the catalog while the request was unsent')
assert(sentAt-clicked<=30,'the request waits for the one transaction in flight and the hash, not for a chain of writes: '..(sentAt-clicked))
local held=Stats().admissionHeld
assert(held>=1 and Deferred()==math.min(held,64)-Stats().admissionSuperseded,'every held item is retained in the bounded owner, none is dropped')
assert(Stats().storageRejected==Stats().admissionOverflow and Stats().malformedRejected==0,'a held item is refused only by the owner bound, and never as malformed')
-- The hold ends at the transmission: the next valid arrival is not held.
local heldAtSend=Stats().admissionHeld
T.Until(H,function()return C.ManualPreparationStatus().ready end,8000)
-- Deferred work resumes and exact retained records settle.
local id,owner,stamp
for i=directBefore+1,arrivals do
 if H.puts['ready-a-'..i] == nil or H.puts['ready-a-'..i].accepted==0 then id='ready-a-'..i;stamp=S.base+i;owner=Nexus.Identity.OwnerKey('Traffic'..((i-1)%8+1),'Ebonhold');break end
end
T.Until(H,function()return C.Get(id)~=nil end,20000)
local row=C.Get(id)
assert(row.ownerKey==owner and row.lastModified==stamp and row.title:find('Inbound during request',1,true)==1,'the first retained item settles with its exact owner, revision and title')
assert(H.puts[id].accepted==1 and Stats().admissionResolved>=1,'it was submitted exactly once, by the ordinary deferred pump')
assert(Sent(H)>=1 and #H.actions==0,'zero gameplay mutation')
print(string.format('PASS request transmitted after %.1fs under saturating inbound traffic; %d items held and retained; retained work resumed',sentAt-clicked,held))

-- 2. Owner bound: a full owner refuses a held item; it never takes the catalog.
H,C=S.Boot(100);arrivals=0
SlashCmdList.NEXUS('sync')
assert(Sent(H)==0,'fixture: the request is accepted and still unsent')
for i=1,17 do Arrive('bound-','OneSender')end
assert(Stats().admissionHeld==17 and Deferred()==16 and Stats().admissionOverflow==1 and Stats().storageRejected==1,'the seventeenth held item from one sender is a counted storage refusal')
assert(Accepted(H,'bound-')==0 and C.ManualPreparationStatus().ready,'no held item took the catalog, including the refused one')
T.Until(H,function()return Sent(H)==1 end,2000)
print('PASS owner bound holds during the request; refusal is counted, never a direct write')

-- 3. No hold for a transmission that cannot happen, and recovery.
for _,blocker in ipairs({'combat','suspended'})do
 H,C=S.Boot(100);arrivals=0
 if blocker=='combat' then H.combat=true else Nexus.SyncWire.suspended=true end
 SlashCmdList.NEXUS('sync')
 Arrive('blocked-')
 assert(Stats().admissionHeld==0 and Accepted(H,'blocked-')==1,'a blocked wire holds nothing; the valid item takes the catalog directly: '..blocker)
 T.Until(H,function()return C.Get('blocked-1')~=nil end,8000)
 assert(Sent(H)==0,'nothing is transmitted while blocked')
 if blocker=='combat' then H.combat=false else Nexus.SyncWire.suspended=false end
 T.Until(H,function()return Sent(H)==1 or Stats().terminalReason=='expired' end,8000)
 assert(Sent(H)==1,'after '..blocker..' clears, the same request is transmitted once')
 print('PASS '..blocker..': no hold while the wire cannot send; request transmitted after recovery')
end

-- 4. The hold is bounded by the request's own fixed lifetime.
H,C=S.Boot(100);arrivals=0;S.Hold(C)
SlashCmdList.NEXUS('sync')
Arrive('expiry-')
assert(Stats().admissionHeld==1 and Deferred()==1 and H.puts['expiry-1']==nil,'fixture: the item is held and retained before the catalog is asked')
H.now=H.now+301;H.Advance(.05,.05)
assert(Stats().terminalReason=='expired' and Stats().queueOutcome=='dropped','the request expires at its own unchanged 300-second lifetime')
T.Until(H,function()return C.ManualPreparationStatus().ready end,8000)
local before=Stats().admissionHeld
Arrive('expiry-')
assert(Stats().admissionHeld==before and Accepted(H,'expiry-')==1,'after the request expired nothing is held; a valid arrival takes the ready catalog directly')
print('PASS hold ends with the request lifetime; no lifetime was extended')
