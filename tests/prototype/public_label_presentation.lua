-- Readable public names (BN-OWNER-LEADERBOARD-LABEL-001). A record whose
-- owner is not established shows its readable name (with the realm it states)
-- on Community bylines and detail headings, without the
-- generated "(legacy/unverified ...)" tuple of raw typed tokens. The tuple
-- stays in publicIdentityKey; the detail views say in plain words that the
-- owner is not established. Identity, shadowing, selection, DPS, ranking and
-- actions are unchanged.
-- Leaderboard rows and their detail heading show the character name only
-- (owner decision of 2026-10-04, superseding the realm in those names): the
-- realm stays in the identity key, the record fields and the row tooltip.
--
-- Real TOC boot, catalog, DpsCapture relay admission, projections and the
-- Leaderboard and Community windows; synthetic players only. Expected names
-- and identity keys are written here from the stated format, not read back.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local NOTE='|cff999999Owner identity not established.|r'
-- No generated provenance decoration in a readable name.
local function Clean(text)
 return type(text)=='string' and not text:find('legacy/unverified',1,true)
  and not text:find('string:',1,true) and not text:find('nil:0:',1,true)
  and not text:find('Relayer',1,true)
end
-- No active WoW formatting: every "|" is an escaped "||".
local function Inert(text) return type(text)=='string' and text:gsub('||',''):find('|',1,true)==nil end
-- Conservative fit (the 7.0 px per character, 17 px per line model of
-- quickstart_layout_fit.lua): the note takes one line of a description box
-- and at least one line of the description stays visible, at the box's
-- current width and at its narrowest layout width (minWidth).
local function NoteFits(box,label,minWidth)
 local visible=#NOTE:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 local h=box:GetHeight()
 for _,w in ipairs({box:GetWidth(),minWidth or box:GetWidth()}) do
  local lines=math.ceil(visible*7.0/w)
  check(w>0 and lines==1 and lines*17+17<=h,label..': the note fits on one line and leaves a description line ('
   ..visible..' characters, '..lines..' line(s) in '..w..'x'..h..')')
 end
end

local fx,H
local function Boot()
 fx=L.New({players={
  {name='PrototypeTester',class='MAGE',isLocal=true,variant=30,ordinary=60},
  {name='Alpha',class='MAGE',variant=1,dps={dummy=61000,lk=62000}},
  {name='Bravo',class='PRIEST',variant=2,dps={dummy=51000}},
 }})
 H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
 for _=1,400 do H.Advance(.05,.05) end
end
Boot()
local I=Nexus.Identity

-- 1. The presentation policy (real Identity module, synthetic records).
do
 local function Row(t) t.ownerVerified=t.ownerVerified==true;return t end
 local verified=Row({player='Alpha',realm='ebonhold',ownerKey='alpha@ebonhold',ownerVerified=true})
 local kiralyl=Row({player='Kiralyl',realm='ebonhold',ownerKey='kiralyl@ebonhold',relaySender='Relayer-Ebonhold'})
 local mengooE=Row({player='Mengoo',realm='ebonhold',ownerKey='mengoo@ebonhold',relaySender='Relayer-Ebonhold'})
 local mengooF=Row({player='Mengoo',realm='frostmourne',ownerKey='mengoo@frostmourne',relaySender='Relayer-Ebonhold'})
 local alphaF=Row({player='Alpha',realm='frostmourne',ownerKey='alpha@frostmourne',relaySender='Relayer-Ebonhold'})
 local full=Row({player='Kiralyl-Ebonhold'})
 local unicode=Row({player='Ærøn',realm='ebonhold',ownerKey='ærøn@ebonhold',relaySender='Relayer-Ebonhold'})
 local hostile=Row({player='Ev|cffff0000il|r',realm='ebonhold',relaySender='Relayer-Ebonhold'})
 local missing=Row({realm='ebonhold',relaySender='Relayer-Ebonhold'})
 -- A stored realm with whitespace: OwnerKey accepts it (whitespace removed),
 -- but the name must not carry the raw control character.
 local tabRealm=Row({player='Tabby',realm='Ebon\thold',relaySender='Relayer-Ebonhold'})
 local rows,summary=I.PresentPublicRecords({verified,kiralyl,mengooE,mengooF,alphaF,full,unicode,hostile,missing,tabRealm},'player')
 check(summary.shadowed==0 and #rows==10,'without shadowing every record is presented: '..#rows)
 check(verified.displayPlayer=='Alpha-ebonhold' and verified.publicIdentityKey=='verified:alpha@ebonhold'
  and verified.publicIdentityVerified==true,'established owner: readable label, exact identity: '..tostring(verified.displayPlayer))
 check(kiralyl.displayPlayer=='Kiralyl-ebonhold','owner not established: the readable name and realm only: '..tostring(kiralyl.displayPlayer))
 check(kiralyl.publicIdentityKey=='legacy|string:7:Kiralyl|string:8:ebonhold|string:16:kiralyl@ebonhold|nil:0:|string:16:Relayer-Ebonhold'
  and kiralyl.publicIdentityVerified==false,'the complete provenance tuple stays in the identity key: '..tostring(kiralyl.publicIdentityKey))
 check(mengooE.displayPlayer=='Mengoo-ebonhold' and mengooF.displayPlayer=='Mengoo-frostmourne'
  and mengooE.publicIdentityKey~=mengooF.publicIdentityKey,'same short name, different realms: distinct records, each realm shown')
 check(alphaF.displayPlayer=='Alpha-frostmourne' and alphaF.publicIdentityVerified==false
  and alphaF.publicIdentityKey~=verified.publicIdentityKey,'a relayed record never takes the verified identity of the same short name')
 check(full.displayPlayer=='Kiralyl-Ebonhold','a stated full player name is shown as stated: '..tostring(full.displayPlayer))
 check(unicode.displayPlayer=='Ærøn-ebonhold','UTF-8 names are kept: '..tostring(unicode.displayPlayer))
 check(hostile.displayPlayer=='Unknown-ebonhold' and Inert(hostile.displayPlayer),'hostile name: the safe fallback, no active formatting: '..tostring(hostile.displayPlayer))
 check(tabRealm.displayPlayer=='Unknown','a realm with a control character never reaches the name (display escaping refuses it): '..tostring(tabRealm.displayPlayer))
 check(missing.displayPlayer==nil and missing.publicIdentityKey:find('^legacy|nil:0:|') ~= nil,'missing name: no label (the view falls back), no raw key printed')
 -- The character-name-only label (Leaderboard): the same records, no realm.
 check(verified.displayName=='Alpha' and kiralyl.displayName=='Kiralyl'
  and mengooE.displayName=='Mengoo' and mengooF.displayName=='Mengoo'
  and mengooE.publicIdentityKey~=mengooF.publicIdentityKey,'character names: same short name stays two records')
 check(full.displayName=='Kiralyl','a stated full player name shows its character name: '..tostring(full.displayName))
 check(unicode.displayName=='Ærøn','UTF-8 character names are kept: '..tostring(unicode.displayName))
 check(hostile.displayName=='Unknown' and Inert(hostile.displayName),'hostile name: the safe fallback: '..tostring(hostile.displayName))
 check(tabRealm.displayName=='Tabby','the character name does not depend on a bad realm: '..tostring(tabRealm.displayName))
 check(missing.displayName==nil,'missing name: no character label either')
 for _,r in ipairs({verified,kiralyl,mengooE,mengooF,alphaF,full,unicode,hostile}) do
  check(Clean(r.displayPlayer) and Inert(r.displayPlayer),'no generated decoration: '..tostring(r.displayPlayer))
 end
 -- Shadowing rule unchanged: an ambiguous row with a verified short name is
 -- hidden from ordinary public rows; other ambiguous rows stay.
 local again={} for _,r in ipairs({verified,kiralyl,alphaF}) do local c={} for k,v in pairs(r) do c[k]=v end again[#again+1]=c end
 local shown,s2=I.PresentPublicRecords(again,'player',{shadowAmbiguous=true})
 check(s2.shadowed==1 and #shown==2 and shown[1].publicIdentityKey=='verified:alpha@ebonhold'
  and shown[2].player=='Kiralyl','shadowing: the relayed Alpha is hidden by the verified Alpha, Kiralyl stays')
 -- Community rows are records: two builds by the same unestablished author
 -- show the same readable byline and keep distinct identities. Player-authored
 -- titles are not changed, also when they contain "Legacy".
 local b1={id='saved-kiralyl_rogue_lite_live_-1',author='Kiralyl',realm='ebonhold',claimedOwnerKey='kiralyl@ebonhold',
  relaySender='Relayer-Ebonhold',ownerVerified=false,title='Legacy (unverified) raid build'}
 local b2={id='relay-kiralyl-2',author='Kiralyl',realm='ebonhold',claimedOwnerKey='kiralyl@ebonhold',
  relaySender='Relayer-Ebonhold',ownerVerified=false,title='Second build'}
 local builds=I.PresentPublicRecords({b1,b2},'author')
 check(#builds==2 and b1.displayAuthor=='Kiralyl-ebonhold' and b2.displayAuthor=='Kiralyl-ebonhold','same readable byline for both builds')
 check(b1.publicIdentityKey~=b2.publicIdentityKey and b1.publicIdentityKey:find('string:32:saved-kiralyl_rogue_lite_live_-1',1,true),
  'the build identity stays in the key, not in the byline')
 check(b1.displayTitle=='Legacy (unverified) raid build','a player-authored title is kept as written: '..tostring(b1.displayTitle))
 -- Player-authored text stays escaped (names and realms cannot carry "|":
 -- the validators refuse it, so a name falls back instead).
 local b3={id='hostile-title',author='Kiralyl',realm='ebonhold',claimedOwnerKey='kiralyl@ebonhold',
  relaySender='Relayer-Ebonhold',ownerVerified=false,title='|cffff0000Red|r |Hitem:1|h[x]|h'}
 I.PresentPublicRecords({b3},'author')
 check(b3.displayTitle=='||cffff0000Red||r ||Hitem:1||h[x]||h' and Inert(b3.displayTitle),'a hostile title is shown inert: '..tostring(b3.displayTitle))
 check(b3.displayAuthor=='Kiralyl-ebonhold','and its byline is the readable name: '..tostring(b3.displayAuthor))
end

-- Records received through a relay (the real relay admission): three
-- characters whose owner is not established, one sharing a verified short
-- name, and two relayed builds by the same author.
local function Receive()
 local D,C=Nexus.DpsCapture,Nexus.BuildCatalog
 local function Relay(name,realm,dps,variant)
  local ord=L.OrdinaryRows(variant,40)
  local wire={v=7,c='dummy',d=dps,u=150,t=L.STAMP+700+variant,p=name,l=60,k='MAGE',
   o=name:lower()..'@'..realm:lower(),r=realm,e=L.DpsRows(ord),f=L.Fingerprint(ord)}
  check(D.ReceiveRelayedRecord(wire,'Relayer-Ebonhold')==true,'fixture: relayed record for '..name..'@'..realm..' admitted')
 end
 Relay('Kiralyl','Ebonhold',40000,11)
 Relay('Mengoo','Ebonhold',39000,12)
 Relay('Mengoo','Frostmourne',38000,13)
 Relay('Alpha','Frostmourne',37000,14)
 local function Put(id,variant)
  local rec={id=id,title='Relayed build '..id,author='Kiralyl',ownerKey='kiralyl@ebonhold',realm='ebonhold',class='MAGE',
   postedAt=L.STAMP+800,lastModified=L.STAMP+800,description='Synthetic relayed build',echoes=L.OrdinaryRows(variant,30)}
  local ok,why,ticket
  for _=1,400 do
   ok,why,ticket=C.Put(rec,{source='remote',sender='Relayer-Ebonhold'})
   if ok==nil and type(ticket)=='table' then
    for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
    ok,why=ticket.committed==true,ticket.reason or ticket.state
   end
   if why~='ROOT_MUTATION_PENDING' and why~='ROOT_ADMISSION_PENDING' then break end
   for _=1,20 do H.Advance(.05,.05) end
  end
  local stored=C.Get(id)
  check(ok==true and stored and stored.ownerVerified==false and stored.relaySender=='Relayer-Ebonhold',
   'fixture: relayed build '..id..' stored without an established owner')
 end
 Put('saved-kiralyl_rogue_lite_live_-1',21)
 Put('relay-kiralyl-2',22)
 for _=1,200 do H.Advance(.05,.05) end
end
Receive()

-- Side-effect baseline: durable data and outgoing requests before navigation.
local bundleBefore=F.Serialize(NexusDB.authorityBundle)
local sentBefore,startedAt=#H.sent,H.now

-- 2. Leaderboard rows and detail (real window). Expected order: DPS
-- descending; the relayed Alpha is shadowed by the verified Alpha.
do
 local K='legacy|string:%d:%s|string:%d:%s|string:%d:%s|nil:0:|string:16:Relayer-Ebonhold'
 local function Key(name,realm) local owner=name:lower()..'@'..realm
  return K:format(#name,name,#realm,realm,#owner,owner) end
 local want={
  {label='Alpha',realm='Realm: ebonhold',key='verified:alpha@ebonhold',dps=61000,verified=true,actions=true},
  {label='Bravo',realm='Realm: ebonhold',key='verified:bravo@ebonhold',dps=51000,verified=true,actions=true},
  {label='Kiralyl',realm='Realm stated: ebonhold',key=Key('Kiralyl','ebonhold'),dps=40000,verified=false,actions=false},
  {label='Mengoo',realm='Realm stated: ebonhold',key=Key('Mengoo','ebonhold'),dps=39000,verified=false,actions=false},
  {label='Mengoo',realm='Realm stated: frostmourne',key=Key('Mengoo','frostmourne'),dps=38000,verified=false,actions=false},
 }
 L.Open(H,'dummy')
 local rows,total=L.RenderedRows(H)
 check(total==#want,'dummy board: exactly the expected rows (the relayed Alpha stays shadowed): '..total)
 -- The row tooltip tells same-name characters apart (recorded lines only).
 local lines
 local tip=GameTooltip
 local saved={SetText=tip.SetText,AddLine=tip.AddLine,Hide=tip.Hide,IsOwned=tip.IsOwned}
 tip.SetText=function(self,t) lines={tostring(t)};self.tipShown=true end
 tip.AddLine=function(self,t) lines[#lines+1]=tostring(t) end
 tip.IsOwned=function() return true end
 tip.Hide=function(self) self.tipShown=false end
 for i,w in ipairs(want) do
  local r=rows[i]
  check(r.player==w.label and Clean(r.player),'row '..i..' shows '..w.label..': '..tostring(r.player))
  check(r.data.publicIdentityKey==w.key and r.data.dps==w.dps and r.data.publicIdentityVerified==w.verified,
   'row '..i..' is the record '..w.key..' at '..w.dps)
  -- Pooled buttons are rebound while scrolling: hover the one bound now.
  Nexus.Leaderboard.ScrollTo((i-1)*40);H.Advance(.05,.05)
  local button
  for _,b in ipairs(NexusLeaderboardFrame._virtualListScrollFrame.scrollChild.children) do
   if b:IsShown() and b.data==r.data then button=b end
  end
  assert(button,'row '..i..' is bound')
  lines=nil
  button:GetScript('OnEnter')(button)
  check(lines and lines[1]==w.label and lines[2]==w.realm
   and lines[3]==(w.verified and 'Owner verified' or 'Owner identity not established'),
   'row '..i..' tooltip: '..table.concat(lines or {},' / '))
  button:GetScript('OnLeave')(button)
  check(tip.tipShown==false,'row '..i..': leaving the row hides its tooltip')
 end
 for k,v in pairs(saved) do tip[k]=v end
 -- Detail, selected out of order: the detail is the clicked record's.
 for _,i in ipairs({5,4,3,1,2}) do
  local w=want[i]
  local det=L.Select(H,i)
  local desc=NexusLeaderboardFrame._leaderboardDetail.desc:GetText()
  check(det.row and det.row.publicIdentityKey==w.key,'detail '..i..' shows the record '..w.key)
  check(det.owner=='by '..w.label,'detail heading '..i..': '..tostring(det.owner))
  if w.verified then
   check(not desc:find(NOTE,1,true),'detail '..i..': no provenance note for an established owner')
  else
   check(desc:sub(1,#NOTE)==NOTE,'detail '..i..': the owner-not-established note leads the description: '..tostring(desc))
  end
  check(det.openEnabled==w.actions and det.copyEnabled==w.actions,'detail '..i..': Open/Copy availability unchanged ('..tostring(w.actions)..')')
 end
 NoteFits(NexusLeaderboardFrame._leaderboardDetail.desc,'Leaderboard detail')
 -- The two Mengoo rows stay independent after a refresh.
 L.Open(H,'lk');L.Open(H,'dummy')
 local again=L.RenderedRows(H)
 check(again[4].data.publicIdentityKey==want[4].key and again[5].data.publicIdentityKey==want[5].key,'after a refresh the same-name rows keep their records')
 Nexus.Leaderboard.Hide()
end

-- 3. Community cards and detail (real window).
do
 Nexus.CommunityBuilds.Show()
 for _=1,200 do H.Advance(.05,.05) end
 local frame=assert(NexusCommunityBuildsFrame)
 local box=frame._qualifiedBtn
 if box:GetChecked() then box:SetChecked(false);box:Click() end
 -- Wait for the projection of the new filter (bounded).
 local settled=false
 for _=1,4000 do
  local d=Nexus.CommunityBuilds.DiagnosticSnapshot()
  if d.filterQualifiedOnly==false and d.projectionCurrent and not d.projectionPending and not d.projectionDirty then settled=true;break end
  H.Advance(.05,.05)
 end
 check(settled,'fixture: the Community list shows builds without DPS records')
 local cards={}
 for step=0,20 do
  Nexus.CommunityBuilds.ScrollTo(step*92);for _=1,3 do H.Advance(.05,.05) end
  for _,f in ipairs(H.frames) do
   if f.buildId and f:IsVisible() and f.author and not cards[f.buildId] then cards[f.buildId]={step=step,text=f.author:GetText()} end
  end
 end
 local function Open(id)
  Nexus.CommunityBuilds.ScrollTo(cards[id].step*92);for _=1,3 do H.Advance(.05,.05) end
  local target
  for _,f in ipairs(H.frames) do if f.buildId==id and f:IsVisible() and f.addBtn then target=f end end
  assert(target,'card '..id..' is bound')
  target.addBtn:Click();for _=1,5 do H.Advance(.05,.05) end
  local p=frame._detailPanel
  return Nexus.CommunityBuilds.GetSelectedBuildForPanel(),p.author:GetText(),p.desc:GetText()
 end
 for _,id in ipairs({'saved-kiralyl_rogue_lite_live_-1','relay-kiralyl-2'}) do
  check(cards[id] and cards[id].text:sub(1,#'by Kiralyl-ebonhold  ')=='by Kiralyl-ebonhold  ' and Clean(cards[id].text),
   'card '..id..' byline: '..tostring(cards[id] and cards[id].text))
 end
 for _,id in ipairs({'relay-kiralyl-2','saved-kiralyl_rogue_lite_live_-1'}) do
  local sel,author,desc=Open(id)
  check(sel and sel.id==id,'the same byline, and the clicked card selects its own build '..id..': '..tostring(sel and sel.id))
  check(author=='by Kiralyl-ebonhold','detail heading for '..id..': '..tostring(author))
  check(desc:sub(1,#NOTE)==NOTE and desc:find('Synthetic relayed build',1,true),'detail for '..id..': the note, then the description')
 end
 -- Narrowest Community detail: 290 px (ui/LayoutMetrics.lua) less 20 px of padding (RefreshLayout).
 NoteFits(frame._detailPanel.desc,'Community detail',270)
 local alpha
 for id in pairs(cards) do if id==fx.players[2].buildId then alpha=id end end
 local sel,author,desc=Open(alpha)
 check(sel and sel.id==alpha and author=='by Alpha-ebonhold' and not desc:find(NOTE,1,true),'established owner: plain byline and no note')
 local own=cards[fx.players[1].buildId]
 check(own and own.text:find('Your build',1,true),'the local build keeps its owner tag')
 Nexus.CommunityBuilds.Hide()
end

-- 4. Rendering and navigation change no durable data and start no Sync
-- traffic. Background Sync may send its own requests on its own schedule, so
-- a matched run (same boot, same received records, the same simulated time,
-- no window opened) must send exactly the same requests.
check(F.Serialize(NexusDB.authorityBundle)==bundleBefore,'catalog, DPS and all bundled saved data are unchanged by rendering and navigation')
local function Codes(from)
 local out={}
 for i=from+1,#H.sent do
  local code=(tostring(H.sent[i].text or ''):gsub('||','|'):match('^([^|]+)') or ''):gsub('^P%d+:','')
  if code=='WLRQ' or code=='WLLQ' or code=='WLCP' or code=='WLRB' then out[#out+1]=code end
 end
 return table.concat(out,',')
end
local navigated,elapsed=Codes(sentBefore),H.now-startedAt
Boot();Receive()
local idleFrom,idleStart=#H.sent,H.now
while H.now-idleStart<elapsed do H.Advance(.05,.05) end
check(navigated==Codes(idleFrom),'navigation sends the same requests as the matched idle run: ['..navigated..'] vs ['..Codes(idleFrom)..']')
print('PASS public_label_presentation checks='..checks)
