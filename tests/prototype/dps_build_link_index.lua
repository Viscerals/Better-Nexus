-- Linking a DPS record to its exact loadout page goes through the catalog's
-- exact-fingerprint index. It never walks the whole collection through the
-- record cursor (a synchronous deep copy of every row, which also stopped at
-- a fixed step budget and returned a prefix as if complete). The browser's
-- whole-collection read states whether it is complete. Real boot, a 700-row
-- catalog, real inbound DPS admission; synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local N=700
local db=F.Database({version=2})
local profile=T.Profile(N,0)
db.communityBuilds,db.loadoutEvidence=profile.communityBuilds,profile.loadoutEvidence
local H=F.Boot(db)
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local C,D,CB=Nexus.BuildCatalog,Nexus.DpsCapture,Nexus.CommunityBuilds
check(C.Status().availableCount==N,'fixture: '..N..' builds admitted: '..tostring(C.Status().availableCount))
local function Wire(name,variant,dps)
 local rows=L.OrdinaryRows(variant,79)
 return {v=7,c='dummy',d=dps,u=180,t=time()-100+variant,p=name,l=80,k='MAGE',
  o=name:lower()..'@ebonhold',r='Ebonhold',e=L.DpsRows(rows),f=L.Fingerprint(rows)}
end
local function Cursors() return C.DebugStats().cursorsBegun end
-- A record page is one retained catalog mutation on a 700-row root: wait,
-- bounded, until the record carries its page.
local function Settle(name)
 for _=1,8000 do
  local row=D.GetCharacterBest('dummy',name)
  if row and row.buildId~=nil then return end
  H.Advance(.05,.05)
 end
end
-- 1. A record for a loadout no stored build has, with no build id, is linked
-- to a new record page without a whole-collection walk.
local before=Cursors()
local ok,why=D.ReceiveRecord(Wire('Alpha',5,41000),'Alpha-Ebonhold')
local begun=Cursors()-before
check(ok==true,'the record is accepted: '..tostring(why))
check(begun==0,'linking an unknown loadout begins no catalog cursor (no whole-collection walk): '..begun)
Settle('Alpha')
local row=D.GetCharacterBest('dummy','Alpha')
check(row and row.buildId~=nil,'the record is linked to a build page: '..tostring(row and row.buildId))
local page=row and C.Get(row.buildId)
check(page and page.autoDps==true and page.fingerprint==row.fingerprint,'the page is the record loadout page with the same fingerprint')
-- 2. The same owner again with the same loadout: the existing page is
-- found through the index and reused.
before=Cursors()
ok,why=D.ReceiveRecord(Wire('Alpha',5,43000),'Alpha-Ebonhold')
begun=Cursors()-before
check(ok==true and begun==0,'a better record for the same loadout is accepted without a collection walk: '..tostring(why)..' cursors='..begun)
Settle('Alpha')
local again=D.GetCharacterBest('dummy','Alpha')
check(again and again.buildId==row.buildId and again.dps==43000,'the existing page is reused: '..tostring(again and again.buildId))
check(C.Status().availableCount==N+1,'one page was created in all: '..tostring(C.Status().availableCount))
-- 3. Another owner with the same loadout gets its own record page (pages are
-- owner-specific), again without a walk.
before=Cursors()
ok,why=D.ReceiveRecord(Wire('Bravo',5,42000),'Bravo-Ebonhold')
begun=Cursors()-before
check(ok==true and begun==0,'another owner with the same loadout: accepted without a collection walk: '..tostring(why)..' cursors='..begun)
Settle('Bravo')
local bravo=D.GetCharacterBest('dummy','Bravo')
check(bravo and bravo.buildId~=nil and bravo.buildId~=row.buildId,'the other owner gets its own record page: '..tostring(bravo and bravo.buildId))
-- 4. The browser's whole-collection read states its completeness.
local map,complete=CB.Builds()
local count=0;for _ in pairs(map or {})do count=count+1 end
local available=C.Status().availableCount
check(type(map)=='table' and ((complete==true and count==available) or (complete==false and count<available)),
 'a bounded whole-collection read states whether it is complete: entries='..count..' of '..available..' complete='..tostring(complete))
print('PASS dps_build_link_index checks='..checks)
