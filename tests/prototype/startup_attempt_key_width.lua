-- The startup reader refused a key its own producer writes.
--
-- core/AutomationRuntime.lua keys NexusDB.chars[<char>].autoLockAttempts.records
-- by AutoLockBaseKey(wishlistKey, spellId, replacementToken, copies). That key
-- EMBEDS a wishlist key, so it is routinely far wider than the general 183-byte
-- source rule, while the existing 2048-byte exception covers only the immediate
-- lockDesignTargetsBySlot map. A real profile therefore stopped start-up with
-- SOURCE_KEY_WIDTH_EXCEEDED on a 595-byte key this addon had itself written.
--
-- Everything here is SYNTHETIC. No player profile, character, realm or record
-- from the private report is used or reproduced: the wishlist key is generated
-- by the real producer from synthetic Echo ids, and the attempt record is
-- accepted or refused by the RUNTIME'S OWN validator, which recomputes
-- AutoLockBaseKey and AutoLockIdentity byte for byte. What that validator
-- accepts is, by construction, a key the producer would have written.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

-- The derivation the reader uses, restated here so a drift in either place is
-- a failing test rather than a silent disagreement:
--   KeyPart(v) = "<type>:<#text>:<text>"
--   baseKey    = KeyPart(wishlistKey).."|"..KeyPart(spellId).."|"
--                ..KeyPart(replacementToken)[.."|"..KeyPart(copies)]
local ATTEMPT_KEY_WIDTH=(6+1+4+1+2048)+1+(6+1+2+1+21)+1+(6+1+3+1+(6*21+5))+1+(6+1+2+1+21)
check(ATTEMPT_KEY_WIDTH==2267,'the derived attempt width is 2267 bytes: '..ATTEMPT_KEY_WIDTH)

local function KeyPart(value)
 local kind=type(value)
 local text=tostring(value==nil and '' or value)
 return kind..':'..tostring(#text)..':'..text
end
local function BaseKey(wishlistKey,spellId,replacementToken,copies)
 local parts={KeyPart(wishlistKey),KeyPart(spellId),KeyPart(replacementToken or false)}
 if tonumber(copies) and tonumber(copies)>1 then parts[#parts+1]=KeyPart(tonumber(copies)) end
 return table.concat(parts,'|')
end
local function Identity(baseKey,lockedRevision,lockedToken)
 return baseKey..'|locked='..KeyPart(lockedRevision)..'|state='..KeyPart(lockedToken)
end

-- A wishlist key of realistic width, from synthetic ids only.
local function WishlistKeyText(rows)
 local parts={}
 for index=1,rows do
  parts[#parts+1]=tostring(300000+index)..':'..tostring(1+(index%3))
 end
 return table.concat(parts,',')
end

local SPELL=201324
local LOCKED_TOKEN='200237x1,200583x1,200756x1,200960x1,201324x1'
local function Bucket(wishlistKey,state,copies)
 local baseKey=BaseKey(wishlistKey,SPELL,'',copies)
 return baseKey,{version=1,records={[baseKey]={
  baseKey=baseKey,wishlistKey=wishlistKey,spellId=SPELL,copies=copies or 1,
  replacementToken='',lockedRevision=1,lockedToken=LOCKED_TOKEN,
  identity=Identity(baseKey,1,LOCKED_TOKEN),
  state=state or 'confirmed',reason='locked_state_observed',
  adapterAttempts=1,preparedAt=100,expiresAt=200,submittedAt=100,resolvedAt=150,
 }}}
end

local WISHLIST_KEY=WishlistKeyText(56)
local BASE_KEY=Bucket(WISHLIST_KEY)
check(#WISHLIST_KEY>183,'fixture: the wishlist key alone is already over the general rule: '..#WISHLIST_KEY)
check(#BASE_KEY>183,'fixture: so is the compound attempt key: '..#BASE_KEY)
check(#BASE_KEY<ATTEMPT_KEY_WIDTH,'and it is inside the derived attempt width: '..#BASE_KEY)

-- 1. The producer's own validator accepts this record. It recomputes both
-- formulas, so acceptance here means the key is byte-identical to what
-- AutoLockBaseKey would have produced for these inputs.
local function Boot(mutate,expect)
 local db=F.Database({mutate=mutate})
 local H=F.Boot(db)
 local status=Nexus.StartupStatus()
 if expect=='ready' then
  check(status.coreReady==true and status.state~='failed',
   'start-up completes: '..tostring(status.state)..'/'..tostring(status.reason))
 elseif expect=='failed' then
  check(status.state=='failed' and status.reason=='SOURCE_KEY_WIDTH_EXCEEDED',
   'start-up stops on the width rule: '..tostring(status.reason))
 end
 return H,status
end

local expiredKey,expiredBucket=Bucket(WISHLIST_KEY,'expired')
Boot(function(db) db.chars[F.NAME].autoLockAttempts=expiredBucket end,'ready')
check(type(Nexus.RetryAutoLock)=='function','the retry entry the editor uses is reachable')
check(Nexus.RetryAutoLock()==true,
 'the producer validates the compound key it would have written itself')
-- The same record with ONE byte changed in the key is not a key the producer
-- would have written, and its own validator says so.
local broken={version=1,records={}}
for key,record in pairs(expiredBucket.records) do
 local bad=key:sub(1,#key-1)..'X'
 local copy={} ; for field,value in pairs(record) do copy[field]=value end
 copy.baseKey=bad;copy.identity=Identity(bad,1,LOCKED_TOKEN)
 broken.records[bad]=copy
end
Boot(function(db) db.chars[F.NAME].autoLockAttempts=broken end,'ready')
check(Nexus.RetryAutoLock()==false,
 'a key the producer would not have written is refused by the producer')

-- 2. The real start-up path admits the real shape, and the record survives a
-- reload byte for byte. This is the failure the reporter saw.
local saved
do
 local H=Boot(function(db)
  db.chars[F.NAME].autoLockAttempts=select(2,Bucket(WISHLIST_KEY,'confirmed'))
 end,'ready')
 local bucket=NexusDB.chars[F.NAME].autoLockAttempts
 check(type(bucket)=='table' and bucket.records[BASE_KEY]~=nil,
  'the record is still there after start-up')
 check(bucket.records[BASE_KEY].state=='confirmed'
  and bucket.records[BASE_KEY].reason=='locked_state_observed'
  and bucket.records[BASE_KEY].adapterAttempts==1,
  'with its confirmed state, reason and attempt count unchanged')
 saved=F.Serialize(NexusDB)
 check(#H.actions==0,'and start-up submitted no lock, unlock or other action')
end
do
 -- Reload of exactly those bytes.
 local H=F.Boot(assert(loadstring('return '..saved))())
 check(Nexus.StartupStatus().coreReady==true,'the reload completes as well')
 check(F.Serialize(NexusDB.chars[F.NAME].autoLockAttempts)
  ==F.Serialize(assert(loadstring('return '..saved))().chars[F.NAME].autoLockAttempts),
  'and the attempt bucket is byte-identical after the reload')
 check(#H.actions==0,'no lock, unlock or Orb action is replayed by the restart')
end

-- 3. The exception is path-specific and shape-specific. The SAME key is still
-- refused anywhere else, which is what makes this a compatibility correction
-- rather than a relaxed limit.
Boot(function(db) db.chars[F.NAME].recordedPicks={[BASE_KEY]=1} end,'failed')
Boot(function(db)
 db.chars[F.NAME].autoLockAttempts={version=1,records={[BASE_KEY]='not a record table'}}
end,'failed')
Boot(function(db)
 db.chars[F.NAME].autoLockAttempts={version=1,other={[BASE_KEY]={}}}
end,'failed')
Boot(function(db) db.settings.wide={[BASE_KEY]={}} end,'failed')

-- 4. The boundaries themselves, on the real walker.
local function KeyOfWidth(width)
 return string.rep('k',width)
end
Boot(function(db) db.chars[F.NAME].recordedPicks={[KeyOfWidth(183)]=1} end,'ready')
Boot(function(db) db.chars[F.NAME].recordedPicks={[KeyOfWidth(184)]=1} end,'failed')
Boot(function(db) db.chars[F.NAME].lockDesignTargetsBySlot[KeyOfWidth(2048)]={} end,'ready')
Boot(function(db) db.chars[F.NAME].lockDesignTargetsBySlot[KeyOfWidth(2049)]={} end,'failed')
Boot(function(db)
 db.chars[F.NAME].autoLockAttempts={version=1,records={[KeyOfWidth(ATTEMPT_KEY_WIDTH)]={}}}
end,'ready')
Boot(function(db)
 db.chars[F.NAME].autoLockAttempts={version=1,records={[KeyOfWidth(ATTEMPT_KEY_WIDTH+1)]={}}}
end,'failed')

-- 5. A key wider than the whole per-pump byte slice must still make progress.
-- The slice admits 2048 graph bytes; a 2267-byte key can never fit beside
-- anything, so it is charged alone instead of waiting for room that an empty
-- slice can never have. Without that, start-up pumps forever without failing.
do
 local wide=KeyOfWidth(ATTEMPT_KEY_WIDTH)
 local H=Boot(function(db)
  db.chars[F.NAME].autoLockAttempts={version=1,records={
   [wide]={}, [wide:sub(1,ATTEMPT_KEY_WIDTH-1)..'b']={}, [wide:sub(1,ATTEMPT_KEY_WIDTH-1)..'c']={},
  }}
  db.chars[F.NAME].lockDesignTargetsBySlot[KeyOfWidth(2048)]={}
 end,'ready')
 check(Nexus.StartupStatus().coreReady==true,
  'three keys wider than one slice each still complete the walk')
 check(#H.actions==0,'and nothing was submitted while they were charged')
end

-- 6. Bucket shapes the producer refuses are still the producer's business, not
-- a start-up failure: the reader checks widths, not record semantics.
Boot(function(db)
 db.chars[F.NAME].autoLockAttempts={version=2,records={}}
end,'ready')
check(Nexus.RetryAutoLock()==false,
 'an unknown bucket version is refused by the producer, not by start-up')

-- 7. The refusal reaches support. A start-up that stopped on the width rule
-- retains NO incident and NO Lua error - both histories are legitimately empty
-- - so the report must carry the failure itself, in both projections.
do
 local refused=KeyOfWidth(595)
 local H=Boot(function(db) db.chars[F.NAME].recordedPicks={[refused]=1} end,'failed')
 local report=assert(Nexus.SupportReport,'the report owner answers before initialization')
 check((Nexus.SupportIncidents and Nexus.SupportIncidents.Count() or 0)==0,
  'fixture: no incident was retained by a width refusal')
 local errors=Nexus.Errors and Nexus.Errors.History() or {}
 check(#errors==0,'fixture: and no Lua error either: '..#errors)
 local before=F.Serialize(NexusDB)
 local summary=report.Summary()
 check(summary:find('STARTUP FAILED',1,true)~=nil,'the summary leads with the failure: '..summary:sub(1,200))
 check(summary:find('SOURCE_KEY_WIDTH_EXCEEDED',1,true)~=nil,'and states the reason')
 check(summary:find('stage=',1,true)~=nil,'and the retained stage')
 check(summary:find('refused key: character.recordedPicks',1,true)~=nil,
  'and classifies the refused path')
 check(summary:find('595 bytes',1,true)~=nil and summary:find('limit 183',1,true)~=nil,
  'with the measured width and the rule that applied')
 check(summary:find('depth 2',1,true)~=nil and summary:find('path exception none',1,true)~=nil,
  'the nesting depth, and whether an exception matched')
 check(summary:find(refused,1,true)==nil,'the key itself is NOT in the report')
 check(summary:find(F.NAME,1,true)==nil,'and neither is the character name')
 check(summary:find('retained separately',1,true)==nil,
  'and it does not claim an incident is retained when none is')
 -- The prepared file carries the same facts through the same projection.
 local job=report.NewPreparation({extended=true})
 local guard=0
 while report.Step(job)=='pending' and guard<400 do guard=guard+1 end
 local payload=table.concat(job.chunks or {},'')
 check(payload:find('SOURCE_KEY_WIDTH_EXCEEDED',1,true)~=nil,'the prepared payload states the reason')
 check(payload:find('refused key: character.recordedPicks',1,true)~=nil
  and payload:find('595 bytes',1,true)~=nil,'and the same measured refusal')
 check(payload:find(refused,1,true)==nil,'without the key')
 -- Reading is passive: nothing initialized, nothing written, nothing released.
 check(F.Serialize(NexusDB)==before,'reading the report wrote nothing')
 check(Nexus.StartupStatus().coreReady~=true,'and did not complete start-up')
 check(Nexus.OrbRuntime.Start(1)==false or Nexus.OrbRuntime.Start(1)==nil,
  'dependent features stay refused')
 check(#H.actions==0,'and no action was submitted by any of it')
 -- A provider that raises cannot take the reason away.
 local realHistory=Nexus.Errors.History
 Nexus.Errors.History=function() error('synthetic provider failure') end
 local realIncidents=Nexus.SupportIncidents.History
 Nexus.SupportIncidents.History=function() error('synthetic incident failure') end
 local guarded=report.Summary()
 Nexus.Errors.History=realHistory;Nexus.SupportIncidents.History=realIncidents
 check(guarded:find('SOURCE_KEY_WIDTH_EXCEEDED',1,true)~=nil,
  'a throwing provider does not erase the retained reason')
 check(guarded:find('refused key:',1,true)~=nil,'or the measured refusal')
end

-- 8. The report route survives what it is FOR. It is the last route a player
-- has when start-up is broken, so no owner, no missing field and no hostile
-- value in a retained fact may take it away.
do
 Boot(function(db) db.chars[F.NAME].recordedPicks={[KeyOfWidth(595)]=1} end,'failed')
 local report=Nexus.SupportReport
 local realStatus=Nexus.StartupStatus
 -- A status table that states no state at all.
 Nexus.StartupStatus=function() return {coreReady=true} end
 local ok,summary=pcall(report.Summary)
 check(ok,'a status without a state does not take the summary away: '..tostring(summary))
 check(type(summary)=='string' and summary:find('Startup: state unknown',1,true)~=nil,
  'it says the state is unknown instead of raising')
 local okJob,job=pcall(report.NewPreparation,{extended=true})
 check(okJob,'and does not take the prepared file away either: '..tostring(job))
 -- A retained fact whose __tostring raises.
 Nexus.StartupStatus=function()
  return {state='failed',coreReady=false,reason='SOURCE_KEY_WIDTH_EXCEEDED',
   failure={stage=setmetatable({},{__tostring=function() error('hostile') end})}}
 end
 local okHostile,hostile=pcall(report.Summary)
 check(okHostile,'a hostile value in a retained fact does not raise: '..tostring(hostile))
 check(hostile:find('SOURCE_KEY_WIDTH_EXCEEDED',1,true)~=nil,
  'and the reason beside it still reaches the report')
 -- A missing owner entirely.
 Nexus.StartupStatus=nil
 check(pcall(report.Summary),'a missing start-up owner does not raise')
 Nexus.StartupStatus=function() error('synthetic status failure') end
 check(pcall(report.Summary),'and neither does a raising one')
 Nexus.StartupStatus=realStatus
 -- A raising incident owner takes NEITHER route away.
 local realHistory=Nexus.SupportIncidents.History
 Nexus.SupportIncidents.History=function() error('synthetic incident failure') end
 local okSummary=pcall(report.Summary)
 local okPrepare=pcall(report.NewPreparation,{})
 Nexus.SupportIncidents.History=realHistory
 check(okSummary,'a raising incident owner leaves the summary route')
 check(okPrepare,'and the prepared-file route')
end

-- 9. The settings graph is not the character graph. The new width applies only
-- once rows are being charged, and a settings map of the same two names gets
-- the general rule.
Boot(function(db)
 db.settings.autoLockAttempts={records={[KeyOfWidth(ATTEMPT_KEY_WIDTH)]={}}}
end,'failed')
do
 local H=Boot(function(db)
  db.settings.autoLockAttempts={records={[KeyOfWidth(ATTEMPT_KEY_WIDTH)]={}}}
 end,'failed')
 local summary=Nexus.SupportReport.Summary()
 check(summary:find('refused key: settings graph',1,true)~=nil,
  'and the refusal says which graph it was in: '..summary:sub(1,400))
 check(#H.actions==0,'no action followed any of it')
end

-- 10. A key a PLAYER chose never reaches the report, however much it looks
-- like a field name this addon owns.
do
 Boot(function(db)
  db.chars[F.NAME].lockDesignTargetsBySlot={Bloodhoof_Thrall={[KeyOfWidth(595)]='x'}}
 end,'failed')
 local summary=Nexus.SupportReport.Summary()
 check(summary:find('Bloodhoof_Thrall',1,true)==nil,
  'a name-shaped key is not printed: '..summary:sub(1,400))
 check(summary:find('refused key: character.lockDesignTargetsBySlot',1,true)~=nil,
  'the path stops at the last name this addon owns')
end

print('PASS startup_attempt_key_width: the reader accepts the compound attempt key its own producer writes, at a derived width, and refuses it everywhere else checks='..checks)
