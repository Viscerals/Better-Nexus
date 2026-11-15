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

-- A-STATE-03: the public typed identity of integral numbers. Expectations are
-- literal decimal text, never computed by the formatter under test.
local I=assert(Nexus.Identity,'the identity owner is loaded')
local INTEGRAL={
 {0,'n:0'},{1,'n:1'},{-1,'n:-1'},{2147483647,'n:2147483647'},{-2147483648,'n:-2147483648'},
 {2147483648,'n:2147483648'},{-2147483649,'n:-2147483649'},{4294967296,'n:4294967296'},
 {9007199254740991,'n:9007199254740991'},{-9007199254740991,'n:-9007199254740991'},
}
for _,case in ipairs(INTEGRAL) do
 check(I.TypedIdentity(case[1])==case[2],'integral identity '..case[2]..': '..tostring(I.TypedIdentity(case[1])))
end
-- Negative zero made at run time (a signed floating-point underflow), so no
-- constant folding or integer representation can turn it into 0.
local function Negate(v) return -v end
local negativeZero=Negate(1e-300)*1e-300
check(1/negativeZero==-math.huge,'fixture: negative zero is negative zero')
check(I.TypedIdentity(negativeZero)=='n:0','negative zero stays the canonical n:0: '..tostring(I.TypedIdentity(negativeZero)))
-- Every other kind keeps its existing identity.
check(I.TypedIdentity(1)~=I.TypedIdentity('1') and I.TypedIdentity('1')=='s:1:1','number 1 and string "1" stay distinct')
check(I.TypedIdentity('')=='s:0:' and I.TypedIdentity('\195\169')=='s:2:\195\169','strings are byte-counted, empty and non-ASCII included')
check(I.TypedIdentity(true)=='b:1' and I.TypedIdentity(false)=='b:0' and I.TypedIdentity(nil)=='z:','booleans and nil')
check(I.TypedIdentity(0/0)=='n:nan' and I.TypedIdentity(math.huge)=='n:inf' and I.TypedIdentity(-math.huge)=='n:-inf','NaN and infinities')
check(I.TypedIdentity(1.5)=='n:1.5','a fraction keeps %.17g: '..tostring(I.TypedIdentity(1.5)))
check(I.TypedIdentity({})=='x:table' and I.TypedIdentity(print)=='x:function','other kinds keep their markers')

-- The declared CONDITIONAL model: a "%d" conversion of a value outside the
-- signed 32-bit range yields the signed 32-bit minimum; every other format is
-- delegated unchanged. A test-local seam only; it does not show that any
-- native client truncates. A repaired source need not call "%d" at all, so
-- zero modified calls is a valid outcome. The real string.format is restored
-- before any identity is asserted, on success and on failure.
local realFormat=string.format
local modified=0
local okModel,modelled=pcall(function()
 string.format=function(fmt,...)
  local value=...
  if fmt=='%d' and type(value)=='number' and (value<-2147483648 or value>2147483647) then
   modified=modified+1
   return realFormat('%d',-2147483648)
  end
  return realFormat(fmt,...)
 end
 check(string.format('%d',7)=='7' and string.format('%d',2147483647)=='2147483647'
  and string.format('%d',-2147483648)=='-2147483648','model: an in-range %d is delegated unchanged')
 check(string.format('%.0f',9007199254740991)=='9007199254740991' and string.format('%x',255)=='ff'
  and string.format('%.17g',1.5)=='1.5','model: every other format is delegated unchanged')
 local out={}
 for index,case in ipairs(INTEGRAL) do out[index]=I.TypedIdentity(case[1]) end
 return out
end)
string.format=realFormat
check(string.format==realFormat,'the format seam is restored')
assert(okModel,modelled)
for index,case in ipairs(INTEGRAL) do
 check(modelled[index]==case[2],'model: '..case[2]..' keeps its exact identity: '..tostring(modelled[index])..' (modified %d calls: '..modified..')')
end
local seen={}
for index=1,#modelled do
 check(not seen[modelled[index]],'model: no two integral inputs share one identity: '..tostring(modelled[index]))
 seen[modelled[index]]=true
end
-- After restoration the ordinary fixture behavior still holds.
check(string.format('%x',255)=='ff' and I.TypedIdentity(2147483648)=='n:2147483648','after restoration: formatting and identity are ordinary')
check(C.LibraryHash({[1]=row})~=C.LibraryHash({['1']=row}),'after restoration: typed build material')
check(C.LibraryHash({[1]=row,['1']=row},{['1']={stamp=9,author='A'}})==table.concat(expected,','),'after restoration: cache/fallback identical canonical material')
print('PASS typed identity/cache/fallback controls='..checks)
