-- Community list walk and hash warm-up read the catalog through independent
-- named summary cursors. One active cursor per family made them supersede
-- each other on every restart: on a catalog that needs several frames (657
-- builds in the reported profile) neither finished, the list stayed
-- "Updating results" and Open Build showed a blank detail. Other callers keep
-- the shared summary slot unchanged. A selected build that cannot be shown
-- gets an explicit loading or refusal state instead of a blank panel.
--
-- Real TOC boot, catalog, hash cache, projections and the Community window;
-- 700 synthetic builds. Frame counts are bounded harness turns, not timing.
local F=dofile('tests/prototype/format5_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local N=700

local H,C,CB
local function Boot(mapNamedToShared,mutate)
 local db=F.Database()
 local profile=T.Profile(N,0)
 db.communityBuilds,db.loadoutEvidence=profile.communityBuilds,profile.loadoutEvidence
 if mutate then mutate(db) end
 -- The reported profile's saved filters: every build, page 1 of 20 rows.
 db.buildFilters={currentClassOnly=false,qualifiedOnly=false,scope='all',page=1,pageSize=20,search=''}
 H=F.Boot(db)
 C,CB=Nexus.BuildCatalog,Nexus.CommunityBuilds
 if mapNamedToShared then
  -- Control: the earlier behavior, every reader in the one shared slot.
  local begin=C.BeginSummaryCursor
  C.BeginSummaryCursor=function() return begin() end
 end
end
local function Put(rec)
 local ok,why,ticket=C.Put(rec,{source='remote',sender='Other-Realm'})
 if ok==nil and type(ticket)=='table' then
  for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
  ok=ticket.committed==true
 end
 return ok
end
local function NewBuild(id,title)
 local echoes={}
 for j=1,79 do echoes[j]={spellId=200001+((j+7)%84),quality=j%4,stacks=1} end
 return {id=id,title=title,author='Other-Realm',class='MAGE',postedAt=2,lastModified=2,
  description='Synthetic',echoes=echoes,loadoutAvailable=true}
end
local function Published()
 local d=CB.DiagnosticSnapshot()
 return d.projectionCurrent and not d.projectionPending and (d.publishedRows or 0)>0
end
local function HashReady()
 local s=Nexus.BuildHashCache.Stats()
 return s.phase=='ready',s
end
local function Panel()
 local frame=NexusCommunityBuildsFrame
 local p=frame and frame._detailPanel
 local status=p and p._nexusStatus
 return p,status
end
local function Shown(id)
 local p,status=Panel()
 local sel=CB.GetSelectedBuildForPanel()
 return p and p:IsShown() and not (status and status:IsShown()) and sel and sel.id==id
end
local function Status(kind)
 local p,status=Panel()
 return status and status:IsShown() and status.kind==kind and not p:IsShown()
end
local function Settle(limit)
 for i=1,limit do
  if Published() and HashReady() then return i end
  H.Advance(.05,.05)
 end
end
-- The real search box (its handler sets the filter and refreshes).
local function Search(text) NexusBuildsSearch:SetText(text) end

-- 1. The cursor API: named readers own independent slots; the shared slot
-- keeps its semantics; a catalog change refuses each named reader once.
do
 Boot()
 Settle(4000)
 local t1=C.BeginSummaryCursor();local t2=C.BeginSummaryCursor()
 local _,_,e1=C.SummaryCursorNext(t1)
 local s2,_,e2=C.SummaryCursorNext(t2)
 check(e1=='invalid cursor' and e2==nil and s2~=nil,'shared slot: a second cursor supersedes the first: '..tostring(e1))
 local c=C.BeginSummaryCursor('community')
 local d=C.BeginSummaryCursor()
 local h=C.BeginSummaryCursor('build-hash-cache')
 local o=C.BeginSummaryCursor('unknown-reader')
 local sc,_,ec=C.SummaryCursorNext(c)
 local sh,_,eh=C.SummaryCursorNext(h)
 local _,_,ed=C.SummaryCursorNext(d)
 local so,_,eo=C.SummaryCursorNext(o)
 check(sc~=nil and ec==nil and sh~=nil and eh==nil,'named readers are not superseded by shared-slot or other named cursors')
 check(ed=='invalid cursor' and so~=nil and eo==nil,'an unknown reader name uses the shared slot: '..tostring(ed))
 local c2=C.BeginSummaryCursor('community')
 local _,_,ec1=C.SummaryCursorNext(c)
 check(ec1=='invalid cursor' and select(3,C.SummaryCursorNext(c2))==nil,'a named reader supersedes only its own earlier cursor')
 check(Put(NewBuild('cursor-change-1','Cursor change one')),'fixture: a catalog change')
 local _,doneC,errC=C.SummaryCursorNext(c2)
 local _,doneH,errH=C.SummaryCursorNext(h)
 check(doneC==true and errC=='catalog changed' and doneH==true and errH=='catalog changed',
  'after a change each named reader is refused once as changed: '..tostring(errC)..' / '..tostring(errH))
 check(select(3,C.SummaryCursorNext(c2))=='invalid cursor','and then the old cursor is invalid')
end

-- 2. Interleaved readers on a multi-frame catalog: the Community list and the
-- hash warm-up both finish. Control: in one shared slot neither finishes.
local function Interleaved(control)
 Boot(control)
 -- Open the browser while the first warm-up after login walks the catalog
 -- (as in the reported session).
 for _=1,400 do
  if Nexus.BuildHashCache.Stats().phase=='summary' then break end
  H.Advance(.05,.05)
 end
 local walking=Nexus.BuildHashCache.Stats().phase=='summary'
 CB.ShowBuild('synthetic-startup-650')
 local frames=Settle(3000)
 return frames,walking
end
do
 local frames,walking=Interleaved(false)
 check(walking,'fixture: the warm-up was walking the catalog when the browser opened')
 check(frames~=nil,'both walks finish while interleaved (frames: '..tostring(frames)..')')
 check(Shown('synthetic-startup-650'),'and the opened build is shown')
 local s=select(2,HashReady())
 check((s.warmRestarts or 0)<=2,'the warm-up did not restart repeatedly: '..tostring(s.warmRestarts))
 local cframes,cwalking=Interleaved(true)
 check(cwalking and cframes==nil,'control: in one shared slot the walks never finish (the reported failure)')
end

-- 3. Navigation: a build outside the filtered list and outside page 1 shows
-- its detail; repeated navigation follows the selection; a missing build
-- states why instead of a blank panel.
do
 Boot()
 CB.ShowBuild('missing-build-id')
 check(Status('pending'),'before the list is ready: the selected missing build reads as loading')
 Settle(4000)
 CB.Refresh();H.Advance(.05,.05)
 check(Status('unavailable'),'after the list is ready: the missing build is refused in words')
 local _,status=Panel()
 check(status.title:GetText()=='Build not available' and tostring(status.text:GetText()):find('not in your build library',1,true),
  'refusal text: '..tostring(status.text:GetText()))
 CB.ShowBuild('synthetic-startup-650')
 for _=1,40 do H.Advance(.05,.05) end
 local v=CB.VirtualStats();local d=CB.DiagnosticSnapshot()
 check(Shown('synthetic-startup-650') and d.requestedPage==1 and v.selectedVisible==false,
  'a build outside page 1 shows its detail; the list stays on page 1')
 Search('no build matches this text')
 for _=1,400 do if Published() or (CB.DiagnosticSnapshot().projectionCurrent) then break end;H.Advance(.05,.05) end
 for _=1,40 do H.Advance(.05,.05) end
 check(CB.VirtualStats().results==0 and Shown('synthetic-startup-650'),'a search that hides the build keeps its detail')
 Search('')
 for _,id in ipairs({'synthetic-startup-3','synthetic-startup-650','synthetic-startup-3','missing-build-id','synthetic-startup-7'}) do
  CB.ShowBuild(id)
  for _=1,40 do H.Advance(.05,.05) end
  if id=='missing-build-id' then
   check(Status('unavailable'),'repeated navigation: the missing build is refused')
  else
   check(Shown(id),'repeated navigation shows '..id)
  end
 end
end

-- 4. Each distinct refusal reads as its own state, with its own words.
do
 Boot(false,function(db)
  -- A summary without its Echo list (an older peer's summary).
  db.communityBuilds['summary-only']={id='summary-only',title='Summary only',author='Other-Realm',class='MAGE',
   postedAt=1,lastModified=1,needsFullBuild=true,loadoutAvailable=false,echoCount=79,fingerprintHash='abcd1234'}
  -- A malformed saved-mirror marker: admission refuses the row.
  db.communityBuilds['bad-mirror']={id='bad-mirror',title='Bad mirror',author='Other-Realm',class='MAGE',
   postedAt=1,lastModified=1,echoes=db.communityBuilds['synthetic-startup-1'].echoes,importedSavedBuild='bogus'}
 end)
 Settle(4000)
 local function Text() local _,status=Panel();return status.title:GetText(),tostring(status.text:GetText()) end
 -- Bounded: until the list is published again after the navigation.
 local function Open(id)
  CB.ShowBuild(id)
  for _=1,400 do
   H.Advance(.05,.05)
   if not Status('pending') and CB.DiagnosticSnapshot().projectionCurrent then break end
  end
 end
 Open('summary-only')
 local title,text=Text()
 check(C.Get('summary-only')~=nil and Status('incomplete') and title=='Build not available yet'
  and text:find('still arriving',1,true),'a build without its Echo list: incomplete, stated: '..text)
 Open('bad-mirror')
 check(C.Get('bad-mirror')==nil and Status('unavailable'),'a row admission refused is unavailable')
 -- An invalid saved-mirror marker cannot be admitted (above), and the
 -- controller's projection refuses one that a read returned: the view states
 -- it as unavailable, never shown and never blank. The projection's own
 -- defensive branch names it invalid for any other reader.
 local Projection=Nexus.CommunityInternals.Projection
 local direct=Projection.New({builds=function() return {} end,buildsCurrent=function() return false end,
  loadBuild=function(id)
   local b=C.Get('synthetic-startup-2');local copy={};for k,v in pairs(b) do copy[k]=v end
   copy.id,copy.importedSavedBuild=id,'bogus';return copy
  end})
 local none,err,why=direct.Detail('injected-invalid',{})
 check(none==nil and err==nil and why=='invalid','the projection names an invalid marker: '..tostring(why))
 local missing,_,missingWhy=Projection.New({builds=function() return {} end,buildsCurrent=function() return false end,
  loadBuild=function() return nil end}).Detail('absent',{})
 check(missing==nil and missingWhy=='unavailable','and an absent build as unavailable: '..tostring(missingWhy))
 local get=C.Get
 C.Get=function(id,...)
  if id=='injected-invalid' then
   local b=get('synthetic-startup-2')
   local copy={};for k,v in pairs(b) do copy[k]=v end
   copy.id,copy.importedSavedBuild='injected-invalid','bogus'
   return copy,'overlay'
  end
  return get(id,...)
 end
 Open('injected-invalid')
 title,text=Text()
 check(Status('unavailable') and title=='Build not available' and text:find('not in your build library',1,true),
  'an invalid record from a read: refused in words: '..text)
 C.Get=get
 Open('synthetic-startup-2')
 check(Shown('synthetic-startup-2') and not Status('unavailable'),'a valid build after a refusal shows its detail; the state is cleared')
end

print('PASS community_cursor_readers checks='..checks)
