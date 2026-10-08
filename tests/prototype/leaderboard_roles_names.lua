-- Leaderboard Copy keeps strict current locked-role authority; a verified
-- remote build whose roles were never received offers one deliberate
-- "Request full build" action instead (docs/P1_7_LOCKED_ROLE_WIRE.md). The
-- main names of rows and detail headings are character names only, while
-- the realm and owner stay in the identity fields and the row tooltip.
--
-- Real TOC boot, catalog, DpsCapture, projections and the Leaderboard window.
-- The Sync request functions are replaced by counting stubs (the paired
-- transport is covered by sync_locked_roles_request). Synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local HISTORICAL='historical locked evidence is not current copy authority'
local VAL='Valentin\195\169' -- UTF-8 "Valentine" with an accent

local fx=L.New({players={
 {name=VAL,class='MAGE',variant=1,dps={dummy=61000},locked=6},       -- roles unknown
 {name='Twin',class='PRIEST',variant=2,dps={dummy=52000},locked=2},  -- roles known
 {name='Kilo',class='MAGE',variant=3,dps={dummy=43000},locked=3},    -- roles unknown, owner not established on the build
 {name='Mismatch',class='MAGE',variant=4,dps={dummy=34000},locked=3},-- record names another build
 {name='PrototypeTester',class='MAGE',isLocal=true,variant=5,dps={dummy=25000},locked=1}, -- own build, roles unknown
 {name='Partial',class='MAGE',variant=9,dps={dummy=24000},locked=2}, -- roles unknown, record no longer matches its list
 {name='Rho',class='MAGE',variant=10,dps={dummy=23000},locked=2},     -- roles unknown (real Sync section)
}})
local fy=L.New({realm='Frostmourne',idPrefix='lbfy-',players={
 {name='Twin',class='ROGUE',variant=6,dps={dummy=51000},locked=2},   -- same name, other realm
 {name='Qual',class='ROGUE',variant=7,dps={dummy=20000},locked=0},   -- player field states the realm
 {name='Nilly',class='ROGUE',variant=8,dps={dummy=15000},locked=0},  -- legacy row without a player field
}})
local function Player(f,name) for _,p in ipairs(f.players) do if p.name==name then return p end end end
local val,twin,kilo,mis,me=Player(fx,VAL),Player(fx,'Twin'),Player(fx,'Kilo'),Player(fx,'Mismatch'),Player(fx,'PrototypeTester')
local partial,rho=Player(fx,'Partial'),Player(fx,'Rho')
local twinF,qual,nilly=Player(fy,'Twin'),Player(fy,'Qual'),Player(fy,'Nilly')
local db=F.Database({version=2})
fx:Install(db);fy:Install(db)
local function RolesUnknown(p)
 local b=db.communityBuilds[p.buildId]
 b.lockedEchoes,b.lockedEvidenceKey,b.lockedAuthorityProven=nil,nil,nil
end
RolesUnknown(val);RolesUnknown(kilo);RolesUnknown(mis);RolesUnknown(me);RolesUnknown(partial);RolesUnknown(rho)
do
 local b=db.communityBuilds[kilo.buildId]
 b.claimedOwnerKey,b.ownerKey,b.ownerVerified,b.relaySender=b.ownerKey,nil,false,'Relayer-Ebonhold'
end
db.dpsCapture.characterBest.dummy[mis.owner].buildId=val.buildId
db.dpsCapture.characterBest.dummy[qual.owner].player='Qual-Frostmourne'
db.dpsCapture.characterBest.dummy[nilly.owner].player=nil
local H=F.Boot(db,function(h) h.playerLevel=60 end)
for _=1,400 do H.Advance(.05,.05) end

-- Counting stubs: the view may read the state; only a click may request.
local S=Nexus.Sync
local realRequest,realStatus=S.RequestLockedRoles,S.LockedRolesRequestStatus
local calls,reads,script={},0,{}
S.RequestLockedRoles=function(id) calls[#calls+1]=id;return script.request(id) end
S.LockedRolesRequestStatus=function(id) reads=reads+1;return script.status(id) end
script.request=function() return true,'pending' end
script.status=function() return nil end

L.Open(H,'dummy')
local rows,total=L.RenderedRows(H)
local byOwner={}
for i,r in ipairs(rows) do byOwner[r.data.ownerKey]={index=i,row=r} end
local function Detail(p) return L.Select(H,assert(byOwner[p.owner],'row of '..p.owner).index) end
local function ButtonText(det) return det.copyButton:GetText() end

-- 1. Names: the character name only, capitals and accents kept; the
-- identity (owner, realm, key, build) unchanged and distinct per character.
do
 check(total==10,'fixture: ten rows: '..total)
 local want={[val.owner]=VAL,[twin.owner]='Twin',[kilo.owner]='Kilo',[mis.owner]='Mismatch',
  [me.owner]='PrototypeTester',[partial.owner]='Partial',[rho.owner]='Rho',[twinF.owner]='Twin',[qual.owner]='Qual',[nilly.owner]='Unknown'}
 for owner,name in pairs(want) do
  local r=byOwner[owner]
  check(r and r.row.player==name,'row '..owner..' shows '..name..': '..tostring(r and r.row.player))
  check(not tostring(r.row.player):find('-',1,true),'no realm suffix in '..tostring(r.row.player))
 end
 local a,b=byOwner[twin.owner].row.data,byOwner[twinF.owner].row.data
 check(a.publicIdentityKey~=b.publicIdentityKey and a.ownerKey=='twin@ebonhold' and b.ownerKey=='twin@frostmourne'
  and a.buildId~=b.buildId and a.realm~=b.realm,'same name, two characters: distinct identity, owner, realm and build')
 check(a.displayPlayer=='Twin-ebonhold' and b.displayPlayer=='Twin-frostmourne','the full public label stays in the identity fields')
 check(byOwner[qual.owner].row.data.player=='Qual-Frostmourne','fixture: the stored player field keeps its stated realm')
 check(byOwner[nilly.owner].row.data.publicIdentityVerified==false,'a legacy row without a name stays unverified')
 check(Detail(nilly).owner=='by Unknown','legacy row without a name: the safe fallback: '..tostring(Detail(nilly).owner))
 check(Detail(val).owner=='by '..VAL,'detail heading: '..tostring(Detail(val).owner))
 -- The row tooltip tells same-name characters apart, and closes with the
 -- row: on leave and when a hovered pooled row is hidden.
 local tip=GameTooltip
 local saved={SetText=tip.SetText,AddLine=tip.AddLine,Hide=tip.Hide,IsOwned=tip.IsOwned}
 local lines
 tip.SetText=function(self,t) lines={tostring(t)};self.tipShown=true end
 tip.AddLine=function(self,t) lines[#lines+1]=tostring(t) end
 tip.IsOwned=function() return true end
 tip.Hide=function(self) self.tipShown=false end
 local function Hover(p)
  local index=byOwner[p.owner].index
  Nexus.Leaderboard.ScrollTo((index-1)*40);H.Advance(.05,.05)
  local button
  for _,b in ipairs(NexusLeaderboardFrame._virtualListScrollFrame.scrollChild.children) do
   if b:IsShown() and b.data and b.data.ownerKey==p.owner then button=b end
  end
  assert(button,'row of '..p.owner..' is bound')
  lines=nil;button:GetScript('OnEnter')(button)
  return button,table.concat(lines or {},' / ')
 end
 local button,text=Hover(twin)
 check(text=='Twin / Realm: ebonhold / Owner verified','verified row tooltip: '..text)
 button:GetScript('OnLeave')(button)
 check(tip.tipShown==false,'leaving the row hides its tooltip')
 button,text=Hover(twinF)
 check(text=='Twin / Realm: frostmourne / Owner verified','the same name on another realm: '..text)
 button,text=Hover(nilly)
 check(text=='Unknown / Realm stated: frostmourne / Owner identity not established','a row without an established owner: '..text)
 button:Hide()
 check(tip.tipShown==false,'hiding a hovered pooled row hides its tooltip')
 button:Show()
 for k,v in pairs(saved) do tip[k]=v end
 check(Detail(twinF).owner=='by Twin' and Detail(twin).owner=='by Twin','same-name detail headings')
end

-- 2. Strict authority: roles unknown on the current build, six locked rows
-- only on the DPS record. Copy stays unavailable; the action is offered.
local det=Detail(val)
do
 check(det.copyCandidate==nil and det.copyReason==HISTORICAL,'the historical record rows never prove Copy: '..tostring(det.copyReason))
 check(Nexus.CandidateEvidence.Validate(det.copyCandidate)==nil,'no candidate validates')
 check(ButtonText(det)=='Request full build' and det.copyEnabled,'the action is offered: '..tostring(ButtonText(det)))
 check(tostring(det.more):find('were not received',1,true),'the reason is stated: '..tostring(det.more))
 check(#det.locked==#val.dpsLocked and L.Copies(val.locked)==6,'fixture: the detail shows the record rows of six locked copies')
 -- Rendering, re-selection and frames never request.
 for _=1,3 do Detail(twin);det=Detail(val) end
 for _=1,100 do H.Advance(.05,.05) end
 check(#calls==0 and reads>0,'rendering reads the state only: '..#calls..' requests, '..reads..' reads')
end

-- 3. Other refusals never offer the action.
do
 local function NoAction(p,label)
  local d=Detail(p)
  check(d.copyCandidate==nil and not d.copyEnabled and ButtonText(d)=='Copy into Editor',
   label..': Copy unavailable and no request action: '..tostring(d.copyReason))
 end
 NoAction(kilo,'owner not established on the current build')
 NoAction(mis,'record names another build')
 NoAction(me,'own build')
 -- The projection marks a record whose evidence no longer matches its
 -- Echo list; Copy refuses for that reason, which a roles request cannot fix.
 byOwner[partial.owner].row.data.recordIdentityMismatch=true
 NoAction(partial,'record evidence mismatch (a roles request cannot fix it)')
 local d=Detail(twin)
 local v=Nexus.CandidateEvidence.Validate(d.copyCandidate)
 check(v and d.copyEnabled and ButtonText(d)=='Copy into Editor' and #v.lockedEchoes==2,'known current roles: Copy with exactly their locked rows')
 check(#calls==0,'no request from any of these')
end

-- 4. The states of one deliberate request. Each click requests once; the
-- ticker only re-reads the state.
do
 det=Detail(val)
 local state='pending'
 script.request=function() return true,'pending' end
 script.status=function() return state,state=='timeout' and 'no reply with the locked Echo roles arrived' or nil end
 det.copyButton:Click()
 local d=L.Detail()
 check(#calls==1 and calls[1]==val.buildId,'one click, one request for the exact build')
 check(d.copyButton:GetText()=='Requesting...' and not d.copyEnabled,'pending: the button waits')
 check(tostring(d.more):find("Waiting for the owner's reply",1,true) and tostring(d.more):find(VAL,1,true),'pending text names the owner: '..tostring(d.more))
 for _=1,60 do H.Advance(.05,.05) end
 check(#calls==1,'waiting sends nothing more')
 state='timeout'
 for _=1,30 do H.Advance(.05,.05) end
 d=L.Detail()
 check(d.copyButton:GetText()=='Request full build' and d.copyEnabled,'timeout: the action is offered again')
 check(tostring(d.more):find('No reply',1,true),'timeout text: '..tostring(d.more))
 for _=1,200 do H.Advance(.05,.05) end
 check(#calls==1,'no automatic retry after a timeout')
 script.request=function() return false,'offline','not connected to the Nexus sync channel' end
 d.copyButton:Click();d=L.Detail()
 check(#calls==2 and tostring(d.more):find('Request not sent: not connected',1,true) and d.copyEnabled,'offline: stated, not sent: '..tostring(d.more))
 script.request=function() return false,'refused','Sync is Off' end
 d.copyButton:Click();d=L.Detail()
 check(#calls==3 and tostring(d.more):find('Request not sent: Sync is Off',1,true),'refused: stated: '..tostring(d.more))
 script.request=function() return false,'refused','the build owner is not verified' end
 d.copyButton:Click();d=L.Detail()
 check(#calls==4 and tostring(d.more):find('Request not sent: the build owner is not verified',1,true) and d.copyEnabled,
  'an authority refusal from Sync: stated, nothing promoted: '..tostring(d.more))
 check(d.copyCandidate==nil,'still no Copy candidate')
 script.request=function() return true,'pending' end
end

-- 5. The owner's answer completes the current build: Copy then uses the
-- build's own stated roles (here deliberately not the record's six rows).
do
 local stated=L.LockedRows(40,2)
 local C=Nexus.BuildCatalog
 local current=C.Get(val.buildId)
 local rec={}
 for k,v in pairs(current) do rec[k]=v end
 rec.lockedEchoes={}
 for i,e in ipairs(stated) do rec.lockedEchoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=true} end
 rec.lockedAuthorityProven=true
 local ok,why,ticket=C.Put(rec,{source='remote',sender=VAL..'-Ebonhold'})
 if ok==nil and type(ticket)=='table' then
  for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
  ok=ticket.committed==true
 end
 local after=C.Get(val.buildId)
 check(ok and after.lockedAuthorityProven==true and #after.lockedEchoes==2 and after.fingerprint==current.fingerprint
  and after.lastModified==current.lastModified,'fixture: the same revision now states its roles')
 script.status=function() return 'complete' end
 det=Detail(val)
 local v=Nexus.CandidateEvidence.Validate(det.copyCandidate)
 check(v and det.copyEnabled and det.copyButton:GetText()=='Copy into Editor','Copy is available from the current build')
 local function Ids(list) local t={} for _,e in ipairs(list) do t[#t+1]=tostring(e.spellId) end table.sort(t) return table.concat(t,',') end
 check(Ids(v.lockedEchoes)==Ids(stated) and #v.lockedEchoes==2,'Copy carries the build stated locked rows, not the record rows: '..Ids(v.lockedEchoes))
 check(#calls==4,'no further request')
end

-- 6. The real Sync request through the real button: the saved mode is
-- honored, one click sends once, repeated clicks (also ones that bypass the
-- disabled button) and rendering send nothing more.
do
 S.RequestLockedRoles,S.LockedRolesRequestStatus=realRequest,realStatus
 local function Count(code)
  local n=0
  for _,packet in ipairs(H.sent) do
   local c=tostring(packet.text or ''):gsub('||','|'):match('^([^|]+)')
   if c and c:gsub('^P%d+:','')==code then n=n+1 end
  end
  return n
 end
 local q0=Count('WLLQ')
 local d=Detail(rho)
 local policy=Nexus.SyncModePolicy;local mode=policy.Mode
 policy.Mode=function() return 'manual' end
 d.copyButton:Click();d=L.Detail()
 check(tostring(d.more):find('Request not sent: Sync is in Manual mode',1,true) and d.copyEnabled,'Manual mode: refused in words: '..tostring(d.more))
 for _=1,100 do H.Advance(.05,.05) end
 check(Count('WLLQ')==q0,'a refused click sends nothing')
 policy.Mode=function() return 'automatic' end
 local connected=S.IsConnected
 S.IsConnected=function() return true end
 d=Detail(rho)
 d.copyButton:Click();d=L.Detail()
 check(d.copyButton:GetText()=='Requesting...' and not d.copyEnabled,'automatic: pending')
 for _=1,5 do d.copyButton:Click() end
 local click=d.copyButton:GetScript('OnClick')
 for _=1,5 do click(d.copyButton) end
 for _=1,200 do H.Advance(.05,.05) end
 check(Count('WLLQ')-q0==1,'one request for many clicks: '..(Count('WLLQ')-q0))
 for _=1,5 do Detail(twin);Detail(rho) end
 for _=1,400 do H.Advance(.05,.05) end
 check(Count('WLLQ')-q0==1 and S.LockedRolesRequestStatus(rho.buildId)=='pending','rendering sends nothing; still pending')
 policy.Mode,S.IsConnected=mode,connected
end

print('PASS leaderboard_roles_names checks='..checks)
