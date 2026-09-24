-- Leaderboard fixture support. Synthetic data only; no player data.
--
-- Builds saved data for the REAL Leaderboard path: Community builds, DPS
-- character-best rows, removal markers and retention markers, in the legacy
-- saved locations that the real start-up admits and moves into the authority
-- bundle (communityBuilds, syncTombstones, communityRetentionEvictions,
-- dpsCapture). Nothing here injects rows into a view, forces a readiness flag
-- or replaces a production function.
--
-- Shapes follow the addon's own writers:
--  * a build is the record a direct owner shares (core/Sync.lua passes it to
--    BuildCatalog.Put with source "remote"; the owner is verified there by
--    Identity.TransportOwns) as it is stored: ownerVerified=true, a coherent
--    name@realm owner tuple, ordinary rows in `echoes` and locked rows in
--    `lockedEchoes`, both {spellId, quality, stacks};
--  * a DPS row is what DpsCapture.ReceiveRecord stores for a direct owner:
--    echoes/lockedEchoes as {spellId, count}, fingerprint "<id>x<count>,...",
--    loadoutHash, evidenceKey/lockedEvidenceKey, protocolVersion 7,
--    ownerVerified=true, keyed by the canonical owner key in
--    dpsCapture.characterBest[category];
--  * the content keys (evidenceKey, loadoutHash) are computed by the
--    product's own core/LoadoutEvidence.lua, loaded into a private sandbox
--    (no second implementation).
-- The same builds and records can also be fed through the real inbound
-- functions (Fixture:Inbound), so a test can compare both routes.
--
-- Sizes are parameters; every generator is O(n) in the number of keys.
local L={}
L.REALM='Ebonhold'
L.ORDINARY_POOL_FIRST,L.ORDINARY_POOL_SIZE=200001,84 -- harness Echoes 200001..200084
L.LOCKED_POOL_FIRST,L.LOCKED_POOL_SIZE=200085,6      -- harness Echoes 200085..200090
L.MAX_ORDINARY,L.MAX_LOCKED=79,6                     -- LoadoutEvidence.SemanticLimits
L.STAMP=1700000000                                   -- harness time() at boot is 1700001000

-- Product content-key functions, loaded once from the product file into a
-- sandbox so no global state of a later boot is touched.
local evidence
local function Evidence()
 if evidence then return evidence end
 local chunk=assert(loadfile('core/LoadoutEvidence.lua'))
 local env=setmetatable({Nexus={}},{__index=_G})
 setfenv(chunk,env);chunk('Nexus',{})
 evidence=assert(env.Nexus.LoadoutEvidence,'LoadoutEvidence did not load')
 return evidence
end
L.Evidence=Evidence

local function Quality(spellId) return (spellId-200000)%4 end

-- Ordinary evidence for one variant: a cyclic window of the 84-Echo pool,
-- the first `doubles` Echoes with two copies. Variants 0..2519 give distinct
-- fingerprints (84 windows x 30 double counts).
function L.OrdinaryRows(variant,copies)
 copies=copies or L.MAX_ORDINARY
 assert(copies>=1 and copies<=L.MAX_ORDINARY,'ordinary copies must fit the 79-copy envelope')
 local doubles=math.floor(variant/L.ORDINARY_POOL_SIZE)%30
 if doubles*2>copies then doubles=math.floor(copies/2) end
 local distinct=copies-doubles
 assert(distinct<=L.ORDINARY_POOL_SIZE,'ordinary pool too small')
 local offset=variant%L.ORDINARY_POOL_SIZE
 local rows={}
 for k=0,distinct-1 do
  local id=L.ORDINARY_POOL_FIRST+(offset+k)%L.ORDINARY_POOL_SIZE
  rows[#rows+1]={spellId=id,quality=Quality(id),stacks=k<doubles and 2 or 1}
 end
 table.sort(rows,function(a,b)return a.spellId<b.spellId end)
 return rows
end

-- Locked evidence: `copies` (0..6) copies from the six-Echo locked pool; an
-- odd variant stacks two copies on the first Echo. `shared` names an
-- ordinary Echo that is also held as a locked copy (roles stay separate).
function L.LockedRows(variant,copies,shared)
 copies=copies==nil and L.MAX_LOCKED or copies
 assert(copies>=0 and copies<=L.MAX_LOCKED,'locked copies must fit the six-copy envelope')
 local rows,left={},copies
 if shared and left>0 then rows[#rows+1]={spellId=shared,quality=Quality(shared),stacks=1};left=left-1 end
 local i=0
 while left>0 do
  local id=L.LOCKED_POOL_FIRST+i
  local stacks=(i==0 and variant%2==1 and left>=2) and 2 or 1
  rows[#rows+1]={spellId=id,quality=Quality(id),stacks=stacks}
  left=left-stacks;i=i+1
 end
 table.sort(rows,function(a,b)return a.spellId<b.spellId end)
 return rows
end

function L.Copies(rows)local n=0;for _,r in ipairs(rows or {})do n=n+(r.stacks or r.count)end;return n end

-- DpsCapture's stored echo shape: {spellId, count}, one row per spell,
-- sorted by spell ID (NormalizeEchoes).
function L.DpsRows(rows)
 local counts,ids={},{}
 for _,r in ipairs(rows or {})do
  if counts[r.spellId]==nil then ids[#ids+1]=r.spellId end
  counts[r.spellId]=(counts[r.spellId] or 0)+(r.stacks or r.count)
 end
 table.sort(ids)
 local out={}
 for i,id in ipairs(ids)do out[i]={spellId=id,count=counts[id]} end
 return #out>0 and out or nil
end
function L.Fingerprint(rows)
 local out={}
 for _,r in ipairs(L.DpsRows(rows) or {})do out[#out+1]=r.spellId..'x'..r.count end
 return table.concat(out,',')
end

local function Copy(v)
 if type(v)~='table' then return v end
 local t={};for k,x in pairs(v)do t[k]=Copy(x)end;return t
end
L.Copy=Copy

-- Player entry fields (all optional except name/class):
--  name, class, dps={lk=,dummy=}, ts={lk=,dummy=}, duration={lk=,dummy=},
--  level, variant, ordinary (copies), locked (copies), sharedLocked (bool),
--  build = 'present' (default) | 'missing' | 'tombstone' | 'retention',
--  buildId, title, isLocal (the harness character, PrototypeTester; its
--  name must then be 'PrototypeTester').
--  A player without dps gets a build and no DPS row.
-- Spec fields: players, extraBuilds (unrelated builds, other owners, no DPS
--  rows), extraLocked (their locked copies, default 6), removalMarkers and
--  retentionMarkers (marker-only IDs), markerShape ('legacy' default: the
--  older retention owner's shapes {stamp,author} and a number; 'v1': the
--  current exact shapes), idPrefix, realm (one realm for all players).
function L.New(spec)
 spec=spec or {}
 local E=Evidence()
 local fx={spec=spec,realm=spec.realm or L.REALM,prefix=spec.idPrefix or 'lbfx-',
  players={},builds={},buildOrder={},rows={dummy={},lk={}},
  removal={},retention={},markerIds={},markerOrder={},extraIds={}}
 local realmKey=fx.realm:lower()
 fx.realmKey=realmKey
 local variant=0
 local function NextVariant(explicit)
  if explicit then return explicit end
  local v=variant;variant=variant+1;return v
 end
 local function MakeBuild(id,name,owner,class,ord,locked,title,isLocal,stamp)
  local ordinaryKey=E.Fingerprint(ord)
  local lockedKey=#locked>0 and E.Fingerprint(locked,{forceLocked=true}) or nil
  local fp=L.Fingerprint(ord)
  local b={id=id,title=title,author=name,ownerKey=owner,realm=realmKey,ownerVerified=true,
   isMine=isLocal==true,class=class,postedAt=stamp,lastModified=stamp,
   description='Synthetic Leaderboard fixture build '..id,
   echoes=Copy(ord),lockedEchoes=#locked>0 and Copy(locked) or nil,
   fingerprint=fp,fingerprintHash=E.CompatibilityHash(fp),echoCount=L.Copies(ord),
   evidenceKey=ordinaryKey,lockedEvidenceKey=lockedKey,
   loadoutAvailable=true,needsFullBuild=false}
  return b
 end
 local function AddMarker(kind,id,owner,name,i)
  local shape=spec.markerShape or 'legacy'
  local stamp=L.STAMP-3600-i
  local value
  if kind=='removal' then
   if shape=='v1' then
    value={schemaVersion=1,typedId={luaType='string',exactValue=id},ownerKey=owner,
     sourceKind='local',sourceIdentity='local',targetRowGeneration=1,
     targetRowProvenance={author=name,ownerKey=owner,realm=realmKey,ownerVerified=true},
     receiptRevision=i,receiptAtServerTime=stamp,remoteStampEvidence=stamp}
   else value={stamp=stamp,author=name} end
   fx.removal[id]=value
  else
   if shape=='v1' then
    value={schemaVersion=1,typedId={luaType='string',exactValue=id},evictedCatalogGeneration=1,
     evictedSourceIdentity='overlay',evictedProvenanceIdentity=owner,
     receiptRevision=i,receiptAtServerTime=stamp}
   else value=stamp end
   fx.retention[id]=value
  end
  assert(not fx.markerIds[id],'duplicate marker id '..id)
  fx.markerIds[id]=kind;fx.markerOrder[#fx.markerOrder+1]=id
 end
 for i,p in ipairs(spec.players or {})do
  local name=assert(p.name,'player name');local class=assert(p.class,'player class')
  local owner=name:lower()..'@'..realmKey
  local v=NextVariant(p.variant)
  local ord=L.OrdinaryRows(v,p.ordinary)
  local shared=p.sharedLocked and ord[1].spellId or nil
  local locked=L.LockedRows(v,p.locked,shared)
  local mode=p.build or 'present'
  local buildId=p.buildId or (fx.prefix..(mode=='present' and 'b-' or mode..'-')..i)
  local player={index=i,name=name,class=class,owner=owner,buildId=buildId,build=mode,
   isLocal=p.isLocal==true,ordinary=ord,locked=locked,fingerprint=L.Fingerprint(ord),
   dpsOrdinary=L.DpsRows(ord),dpsLocked=L.DpsRows(locked),
   lockedFingerprint=#locked>0 and L.Fingerprint(locked) or '0',
   displayPlayer=name..'-'..realmKey,title=p.title or ('Leaderboard fixture build of '..name),
   dps={},ts={},duration={},level=p.level or 80}
  fx.players[#fx.players+1]=player
  if mode=='present' then
   local b=MakeBuild(buildId,name,owner,class,ord,locked,player.title,p.isLocal,L.STAMP+i)
   assert(not fx.builds[buildId],'duplicate build id '..buildId)
   fx.builds[buildId]=b;fx.buildOrder[#fx.buildOrder+1]=buildId
  elseif mode=='tombstone' then AddMarker('removal',buildId,owner,name,i)
  elseif mode=='retention' then AddMarker('retention',buildId,owner,name,i)
  else assert(mode=='missing','unknown build mode '..tostring(mode)) end
  for _,category in ipairs({'lk','dummy'})do
   local dps=p.dps and p.dps[category]
   if dps then
    local ts=(p.ts and p.ts[category]) or (L.STAMP+100+i)
    local duration=(p.duration and p.duration[category]) or (category=='lk' and 120 or 180)
    player.dps[category],player.ts[category],player.duration[category]=dps,ts,duration
    local row={dps=dps,level=player.level,ts=ts,duration=duration,player=name,class=class,
     ownerKey=owner,realm=realmKey,buildId=buildId,echoes=Copy(player.dpsOrdinary),
     fingerprint=player.fingerprint,loadoutHash=E.CompatibilityHash(player.fingerprint),
     lockedEchoes=Copy(player.dpsLocked),evidenceKey=E.Fingerprint(player.dpsOrdinary),
     lockedEvidenceKey=player.dpsLocked and E.Fingerprint(player.dpsLocked,{forceLocked=true}) or nil,
     protocolVersion=7,ownerVerified=true}
    assert(fx.rows[category][owner]==nil,'one row per character and category: '..owner)
    fx.rows[category][owner]=row
   end
  end
 end
 -- Unrelated builds: other owners, no DPS rows.
 for i=1,spec.extraBuilds or 0 do
  local id=fx.prefix..'x-'..i
  local name='Peer'..i
  local classes={'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','DEATHKNIGHT','SHAMAN','MAGE','WARLOCK','DRUID'}
  local v=NextVariant()
  local b=MakeBuild(id,name,name:lower()..'@'..realmKey,classes[(i-1)%10+1],
   L.OrdinaryRows(v),L.LockedRows(v,spec.extraLocked),'Unrelated fixture build '..i,false,L.STAMP-i)
  fx.builds[id]=b;fx.buildOrder[#fx.buildOrder+1]=id;fx.extraIds[#fx.extraIds+1]=id
 end
 -- Marker-only IDs: no build, no DPS row references them.
 for i=1,spec.removalMarkers or 0 do
  local id=fx.prefix..'gone-'..i
  AddMarker('removal',id,'goneowner'..i..'@'..realmKey,'GoneOwner'..i,1000+i)
 end
 for i=1,spec.retentionMarkers or 0 do
  local id=fx.prefix..'evicted-'..i
  AddMarker('retention',id,'evictedowner'..i..'@'..realmKey,'EvictedOwner'..i,2000+i)
 end
 setmetatable(fx,{__index=L.Fixture})
 return fx
end

L.Fixture={}
local Fixture=L.Fixture

-- Distinct catalog keys the saved maps occupy (builds + marker-only IDs).
function Fixture:DistinctKeys()
 return #self.buildOrder+#self.markerOrder
end

-- Write the fixture into the legacy saved locations of `db` (a table from
-- format5_support F.Database or any saved table without an authority bundle).
-- Existing entries in those maps are kept; fixture keys must not collide.
function Fixture:Install(db)
 assert(rawget(db,'authorityBundle')==nil,'install into the legacy locations before the first start-up')
 db.communityBuilds=db.communityBuilds or {}
 db.syncTombstones=db.syncTombstones or {}
 db.communityRetentionEvictions=db.communityRetentionEvictions or {}
 db.dpsCapture=db.dpsCapture or {}
 local dps=db.dpsCapture
 dps.characterBest=dps.characterBest or {dummy={},lk={}}
 dps.characterBest.dummy=dps.characterBest.dummy or {}
 dps.characterBest.lk=dps.characterBest.lk or {}
 for _,id in ipairs(self.buildOrder)do
  assert(db.communityBuilds[id]==nil,'build id already present: '..id)
  db.communityBuilds[id]=Copy(self.builds[id])
 end
 for id,v in pairs(self.removal)do assert(db.syncTombstones[id]==nil);db.syncTombstones[id]=Copy(v) end
 for id,v in pairs(self.retention)do assert(db.communityRetentionEvictions[id]==nil);db.communityRetentionEvictions[id]=Copy(v) end
 for _,category in ipairs({'lk','dummy'})do
  for owner,row in pairs(self.rows[category])do
   assert(dps.characterBest[category][owner]==nil,'DPS row already present: '..owner)
   dps.characterBest[category][owner]=Copy(row)
  end
 end
 return db
end

-- The ranked order the product defines. lk/dummy (DpsCapture.GetDpsBoard and
-- ViewProjections.LeaderboardBefore): DPS descending, then earlier ts, then
-- player name, then public identity key. Both records
-- (CandidateEvidence.RealDpsPairs + LeaderboardBefore): only characters
-- with a Dummy AND a Lich King record on the same ordinary and locked
-- evidence; ranked by the higher of the two, then player name.
function Fixture:Expected(category)
 local out={}
 for _,p in ipairs(self.players)do
  if category=='combined' then
   if p.dps.lk and p.dps.dummy then
    out[#out+1]={player=p,dps=math.max(p.dps.lk,p.dps.dummy),average=(p.dps.lk+p.dps.dummy)/2,ts=0}
   end
  elseif p.dps[category] then
   out[#out+1]={player=p,dps=p.dps[category],ts=p.ts[category]}
  end
 end
 table.sort(out,function(a,b)
  if a.dps~=b.dps then return a.dps>b.dps end
  if category~='combined' and a.ts~=b.ts then return a.ts<b.ts end
  local an,bn=a.player.name:lower(),b.player.name:lower()
  if an~=bn then return an<bn end
  return a.player.owner<b.player.owner
 end)
 return out
end

-- The same builds and DPS records through the real inbound functions the
-- Sync receiver calls: BuildCatalog.Put(record, {source='remote', sender})
-- (core/Sync.lua full-build admission) and DpsCapture.ReceiveRecord(record,
-- sender) (Sync commitDps). Only remote players whose build is present are
-- fed; the local character's records are written by combat capture, not by
-- an inbound path. Returns per-call outcomes.
function Fixture:Inbound(H,advance)
 advance=advance or function(n)for _=1,n do H.Advance(.05,.05)end end
 local C,D=Nexus.BuildCatalog,Nexus.DpsCapture
 local out={builds={},records={}}
 for _,p in ipairs(self.players)do
  if p.build=='present' and not p.isLocal then
   local b=self.builds[p.buildId]
   local sender=p.name..'-'..self.realm
   local record={id=b.id,title=b.title,author=b.author,ownerKey=b.ownerKey,realm=b.realm,class=b.class,
    postedAt=b.postedAt,lastModified=b.lastModified,description=b.description,
    echoes=Copy(b.echoes),lockedEchoes=Copy(b.lockedEchoes)}
   local ok,why,ticket=C.Put(record,{source='remote',sender=sender})
   if ok==nil and type(ticket)=='table' then
    for _=1,4000 do if ticket.state~='pending' then break end;advance(1) end
    ok,why=ticket.committed==true,ticket.reason or ticket.state
   end
   out.builds[#out.builds+1]={id=b.id,ok=ok,why=why}
   for _,category in ipairs({'lk','dummy'})do
    if p.dps[category] then
     local wire={v=7,c=category,d=p.dps[category],u=p.duration[category],t=p.ts[category],
      p=p.name,l=p.level,k=p.class,o=p.owner,r=self.realm,b=p.buildId,
      e=Copy(p.dpsOrdinary),f=p.fingerprint,lk=Copy(p.dpsLocked)}
     local accepted,reason=D.ReceiveRecord(wire,sender)
     out.records[#out.records+1]={owner=p.owner,category=category,ok=accepted,why=reason}
    end
   end
  end
 end
 advance(20)
 return out
end

-- One more DPS record for a fixture player, through the real inbound
-- function (DpsCapture.ReceiveRecord from the player's own sender). The
-- fixture's expectation for that player is updated to the new record.
-- A received record also requests the real retention run.
function Fixture:Receive(name,category,values)
 local p
 for _,x in ipairs(self.players)do if x.name==name then p=x end end
 assert(p and not p.isLocal,'a remote fixture player is required: '..tostring(name))
 p.dps[category]=values.dps
 p.ts[category]=values.ts or (L.STAMP+500+p.index)
 p.duration[category]=values.duration or (category=='lk' and 120 or 180)
 local wire={v=7,c=category,d=p.dps[category],u=p.duration[category],t=p.ts[category],
  p=p.name,l=p.level,k=p.class,o=p.owner,r=self.realm,b=p.build=='present' and p.buildId or nil,
  e=Copy(p.dpsOrdinary),f=p.fingerprint,lk=Copy(p.dpsLocked)}
 return Nexus.DpsCapture.ReceiveRecord(wire,p.name..'-'..self.realm)
end

------------------------------------------------------------------------
-- Real view readers (read only; they click real widgets where a user would)
------------------------------------------------------------------------

-- Show the Leaderboard through Nexus.Leaderboard.Show and advance the
-- harness until the view has published a current projection.
function L.Open(H,category,limit)
 local LB=Nexus.Leaderboard
 if LB.IsShown() then LB.SetCategory(category) else LB.Show(category) end
 for i=1,limit or 2000 do
  H.Advance(.05,.05)
  local v,d=LB.VirtualStats(),LB.DiagnosticSnapshot()
  if v.dataReady and d.projectionCurrent and not d.projectionPending
   and v.category==category and d.blockedReason=='none' then return i end
 end
 local d=LB.DiagnosticSnapshot()
 error('Leaderboard did not publish '..category..': '..tostring(d.blockedReason)
  ..' '..tostring(LB.VirtualStats().lastDataError))
end

local function Frame() return assert(NexusLeaderboardFrame,'Leaderboard frame') end
local function ListChild()
 local scroll=assert(Frame()._virtualListScrollFrame,'Leaderboard list')
 return assert(scroll.scrollChild,'Leaderboard list child')
end
local function RankOf(button)
 local digits=tostring(button.rank:GetText() or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 return tonumber(digits)
end

-- Every rendered row, scrolling the real virtual list window by window.
-- Each entry: {index, rank, player, dps, build, extra, data, button}.
function L.RenderedRows(H)
 local LB=Nexus.Leaderboard
 local total=LB.VirtualStats().publishedRows
 local byIndex,count={},0
 local offset=0
 for _=1,total+2 do
  LB.ScrollTo(offset)
  local v=LB.VirtualStats()
  for _,button in ipairs(ListChild().children)do
   if button:IsShown() and button.data~=nil and button.rank then
    local index=RankOf(button)
    if index and not byIndex[index] then
     count=count+1
     byIndex[index]={index=index,rank=index,player=button.player:GetText(),dps=button.dps:GetText(),
      build=button.build:GetText(),extra=button.extra:GetText(),data=button.data,button=button}
    end
   end
  end
  if count>=total or v.last>=total then break end
  offset=offset+math.max(1,(v.last-v.first))*40
 end
 LB.ScrollTo(0)
 local out={}
 for i=1,total do out[i]=byIndex[i] end
 return out,total
end

-- Click one rendered row (scrolling it into the window first) and read the
-- detail pane the view rendered for it.
function L.Select(H,index)
 local LB=Nexus.Leaderboard
 LB.ScrollTo((index-1)*40)
 local target
 for _,button in ipairs(ListChild().children)do
  if button:IsShown() and button.data~=nil and RankOf(button)==index then target=button end
 end
 assert(target,'rendered row '..index..' is not in the window')
 target:Click()
 H.Advance(.05,.05)
 return L.Detail()
end

function L.Detail()
 local d=assert(Frame()._leaderboardDetail,'Leaderboard detail')
 local ordinary,locked={},{}
 for _,b in ipairs(d.icons)do
  if b:IsShown() then ordinary[#ordinary+1]={spellId=b.tip,count=tonumber(b.count:GetText()) or 1} end
 end
 for _,b in ipairs(d.lockedIcons)do if b:IsShown() then locked[#locked+1]={spellId=b.tip} end end
 return {row=d.row,title=d.title:GetText(),owner=d.owner:GetText(),record=d.record:GetText(),
  more=d.more:GetText(),ordinary=ordinary,locked=locked,copyCandidate=d.copyCandidate,
  copyReason=d.copyReason,openBuildId=d.openBuildId,openReason=d.openReason,
  copyEnabled=d.copy:IsEnabled(),openEnabled=d.open:IsEnabled(),lockedTitle=d.lockedTitle:IsShown(),
  openButton=d.open,copyButton=d.copy}
end

-- Walk every page of the real Community Builds projection with no class or
-- qualification filter; returns the set of build IDs it lists. Scope 'all'
-- (default) lists ordinary builds; scope 'mine' lists the local character's
-- own builds and saved-loadout mirrors (ViewProjections PumpBuildJob).
function L.CommunityIds(H,scope,limit)
 local P=Nexus.ViewProjections
 local ids,page,pages={},1,1
 local filters={currentClassOnly=false,qualifiedOnly=false,scope=scope or 'all',sortMode='title'}
 repeat
  filters.page=page
  local rows,summary
  for _=1,limit or 4000 do
   rows,summary=P.RequestBuilds(filters)
   if rows then break end
   P.PumpBuilds();H.Advance(.05,.05)
  end
  assert(rows,'Community projection did not publish')
  for _,b in ipairs(rows)do ids[b.id]=true end
  pages=summary.pageCount or 1
  page=page+1
 until page>pages
 return ids
end

function L.Count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end

------------------------------------------------------------------------
-- Offline module reload for large saved tables
------------------------------------------------------------------------

-- format5_support F.Reload round-trips NexusDB as ONE table literal. A saved
-- table with about 2000 full builds exceeds LuaJIT's limit of 65536
-- constants per function, so that literal no longer compiles. L.Reload uses
-- F.Reload unchanged whenever the single literal compiles. Otherwise it
-- round-trips the same literal text in bounded pieces, one compiled function
-- per piece, checks that the result serializes to exactly the same bytes,
-- and boots it the same way. Offline module reload only, not a client reload.
L.PIECE_BYTES=60000
function L.RoundTrip(F,value)
 local pieces={}
 local function Walk(v,path)
  local text=F.Serialize(v)
  if type(v)~='table' or #text<=L.PIECE_BYTES then pieces[#pieces+1]={path=path,text=text};return end
  pieces[#pieces+1]={path=path,text='{}'}
  local keys={};for k in pairs(v)do keys[#keys+1]=k end
  table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
  for _,k in ipairs(keys)do
   local child={};for i,p in ipairs(path)do child[i]=p end
   child[#child+1]=F.Serialize(k)
   Walk(v[k],child)
  end
 end
 Walk(value,{})
 local root
 for _,piece in ipairs(pieces)do
  if #piece.path==0 then
   root=assert(loadstring('return '..piece.text))()
  else
   local target='R'
   for i=1,#piece.path-1 do target=target..'['..piece.path[i]..']' end
   assert(loadstring('local R=...;'..target..'['..piece.path[#piece.path]..']='..piece.text))(root)
  end
 end
 return root,#pieces
end

function L.Reload(F,before)
 local saved=F.Serialize(NexusDB)
 if loadstring('return '..saved) then return F.Reload(before) end
 local copy,pieces=L.RoundTrip(F,NexusDB)
 assert(F.Serialize(copy)==saved,'the chunked round trip reproduces the saved bytes exactly')
 L.lastReloadPieces=pieces
 return F.Boot(copy,before),saved
end

return L
