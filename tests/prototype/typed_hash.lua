local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local C=Nexus.SyncInternals.Compatibility.New({buckets=8,getCatalog=function()return Nexus.BuildCatalog end,
 getBuildHashCache=function()return Nexus.BuildHashCache end,getBuildRevision=function()return 1 end,
 getDpsCapture=function()return Nexus.DpsCapture end,getTombstones=function()return {} end,
 localOwnsTomb=function()return true end,relayEligible=function()return true end,myName=function()return 'Tester'end,
 currentOwnerKey=function()return 'Tester-Realm'end,now=GetTime,getCodec=function()return Nexus.Codec end,
 validIdentifier=function(id)return type(id)=='string'end,validHash=function()return true end,
 escapedLen=function(s)return #s end,codeIndex='IDX',maxBuildIdBytes=96,chatLimit=254,chatSafety=5})
local row={lastModified=1,ordinaryComplete=true,loadoutAvailable=true,echoes={{spellId=200001}},fingerprintHash='abc'}
check(C.BuildBucket(1)==C.BuildBucket('1'),'stable bucket assignment')
check(C.LibraryHash({[1]=row})~=C.LibraryHash({['1']=row}),'typed build material')
check(C.LibraryHash({}, {[1]={stamp=9,author='A'}})~=C.LibraryHash({}, {['1']={stamp=9,author='A'}}),'typed tombstone material')
local a={[1]=row,['1']=H.Clone(row),['other']=H.Clone(row)};local b={other=H.Clone(row),['1']=H.Clone(row),[1]=H.Clone(row)}
check(C.LibraryHash(a)==C.LibraryHash(b),'iteration-independent mixed typed collection')
check(C.LibraryHash({['ordinary']=row})==C.LibraryHash({ordinary=H.Clone(row)}),'equal typed records equal')
-- Compare the actual cache's material builders to fallback hashes, not a copy.
local function find(f,needle,seen)
 if type(f)~='function' or seen[f] then return end;seen[f]=true
 for i=1,100 do local n,v=debug.getupvalue(f,i);if not n then break end
  if n==needle then return v end
  if n~='_ENV' and type(v)=='function' then local got=find(v,needle,seen);if got then return got end end
 end
end
local build=assert(find(Nexus.BuildHashCache.Pump,'BuildEntry',{}),'actual cache BuildEntry')
local tomb=assert(find(Nexus.BuildHashCache.Pump,'TombstoneEntry',{}),'actual cache TombstoneEntry')
check(build(1,row)~=build('1',row),'cache typed build')
check(tomb(1,{stamp=9,author='A'})~=tomb('1',{stamp=9,author='A'}),'cache typed tomb')
local function hash(entries)
 table.sort(entries);local v=5381
 for _,s in ipairs(entries)do for i=1,#s do v=((v*33)+s:byte(i))%2147483648 end end
 return #entries>0 and string.format('%x',v) or '0'
end
local expected={};for i=1,8 do expected[i]='0'end
expected[C.BuildBucket(1)]=hash({build(1,row),build('1',row),tomb('1',{stamp=9,author='A'})})
check(C.LibraryHash({[1]=row,['1']=row},{['1']={stamp=9,author='A'}})==table.concat(expected,','),'cache/fallback identical canonical material')
print('PASS typed identity/cache/fallback controls='..checks)
