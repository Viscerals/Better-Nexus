-- Record linking reads same-loadout candidates from the exact-fingerprint
-- index, bounded: the index answers with the complete candidate set or an
-- explicit refusal (CURSOR_REQUIRED past the limit), never a truncated list.
-- A refused query creates no record page and attaches no wrong page; the
-- record is kept without a page. Within the bound, other owners' rows are
-- never a match and the owner gets its own page as before. Real boot, real
-- inbound DPS admission, 300 saved rows that share one loadout; synthetic.
local F=dofile('tests/prototype/format5_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local SHARED=300 -- above the controller's 256-candidate bound
local shared=L.OrdinaryRows(9,79);local fp=L.Fingerprint(shared)
local few=L.OrdinaryRows(10,79);local fp2=L.Fingerprint(few)
local function Row(id,i,rows,fingerprint)
 return {id=id,title='Loadout '..id,author='Peer'..i..'-Realm',ownerKey='peer'..i..'@realm',realm='realm',
  class='MAGE',postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,
  echoes=L.Copy(rows),fingerprint=fingerprint,lockedEchoes={},lockedComplete=true}
end
local db=F.Database({version=2})
db.communityBuilds={}
for i=1,SHARED do db.communityBuilds['same-'..i]=Row('same-'..i,i,shared,fp) end
for i=1,3 do db.communityBuilds['few-'..i]=Row('few-'..i,1000+i,few,fp2) end
local H=F.Boot(db)
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local C,D,CB=Nexus.BuildCatalog,Nexus.DpsCapture,Nexus.CommunityBuilds
local admitted=C.Status().availableCount
check(admitted==SHARED+3,'fixture: every row is admitted: '..tostring(admitted))
-- 1. The public index reader: complete within the bound, refused as a whole above it.
local ids,why=C.ExactFingerprintIds(fp2)
check(type(ids)=='table' and #ids==3 and why==nil,'a bucket within the default bound answers every id: '..tostring(ids and #ids))
local none=C.ExactFingerprintIds('no-such-loadout')
check(type(none)=='table' and #none==0,'an unknown loadout answers an empty list')
local refused,refusedWhy=C.ExactFingerprintIds(fp)
check(refused==nil and refusedWhy=='CURSOR_REQUIRED','a bucket above the default bound is refused as a whole: '..tostring(refusedWhy))
local two,twoWhy=C.ExactFingerprintIds(fp2,2)
check(two==nil and twoWhy=='CURSOR_REQUIRED','an explicit limit below the bucket refuses as a whole: '..tostring(twoWhy))
local all=C.ExactFingerprintIds(fp,SHARED)
check(type(all)=='table' and #all==SHARED,'an explicit limit at the bucket size answers every id: '..tostring(all and #all))
-- 2. Linking above the bound: an explicit refusal, no page, and the record is kept without a page.
local function Wire(name,rows,fingerprint,dps)
 return {v=7,c='dummy',d=dps,u=180,t=time()-100,p=name,l=80,k='MAGE',
  o=name:lower()..'@ebonhold',r='Ebonhold',e=L.DpsRows(rows),f=fingerprint}
end
local record={player='Alpha',ownerKey='alpha@ebonhold',realm='ebonhold',ownerVerified=true,class='MAGE',
 echoes=L.DpsRows(shared),fingerprint=fp}
local linkedId,linkedBuild,linkWhy=CB.EnsureDpsBuildForEchoes(L.DpsRows(shared),'dummy',record)
check(linkedId==nil and linkedBuild==nil and linkWhy=='CURSOR_REQUIRED',
 'linking refuses explicitly when the candidate set is incomplete: '..tostring(linkWhy))
check(C.Status().availableCount==admitted,'no record page was created on an incomplete query')
local before=C.DebugStats().cursorsBegun
local ok,receiveWhy=D.ReceiveRecord(Wire('Alpha',shared,fp,41000),'Alpha-Ebonhold')
check(ok==true,'the record itself is accepted: '..tostring(receiveWhy))
check(C.DebugStats().cursorsBegun-before==0,'and no whole-collection walk ran')
for _=1,200 do H.Advance(.05,.05) end
local alpha=D.GetCharacterBest('dummy','Alpha')
check(alpha and alpha.dps==41000 and alpha.buildId==nil,'the record is kept without a page rather than with a wrong one: '..tostring(alpha and alpha.buildId))
check(C.Status().availableCount==admitted,'still no page')
-- 3. Within the bound, linking behaves as before: three other owners' rows
-- are not a match, and the owner gets its own record page.
before=C.DebugStats().cursorsBegun
ok,receiveWhy=D.ReceiveRecord(Wire('Bravo',few,fp2,42000),'Bravo-Ebonhold')
check(ok==true and C.DebugStats().cursorsBegun-before==0,'a record within the bound is accepted without a walk: '..tostring(receiveWhy))
local bravo
for _=1,8000 do
 bravo=D.GetCharacterBest('dummy','Bravo')
 if bravo and bravo.buildId~=nil then break end
 H.Advance(.05,.05)
end
check(bravo and bravo.buildId~=nil,'the owner gets its own record page: '..tostring(bravo and bravo.buildId))
local page=bravo and C.Get(bravo.buildId)
check(page and page.autoDps==true and page.fingerprint==fp2,'the page is the owner\'s record loadout page')
check(C.Status().availableCount==admitted+1,'exactly one page was created')
for i=1,3 do check(C.Get('few-'..i)~=nil and C.Get('few-'..i).autoDps~=true,'few-'..i..': another owner\'s row is untouched') end
print('PASS dps_build_link_bounded checks='..checks)
