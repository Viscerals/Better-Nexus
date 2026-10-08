-- A completed build or DPS transfer whose JSON root is a valid scalar
-- (number, true, string) is a malformed record, not a handler error
-- (BN-FULL-REVIEW-PRIVATE-BUILD-003, audit F1). The real receiver gets the
-- real wire text; nothing is stored and the ordinary rejection is counted.
-- Control: a decoded table without a record takes the same ordinary rejection.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local S,Codec,C=Nexus.Sync,Nexus.Codec,Nexus.BuildCatalog
check(S and type(S.HandleIncoming)=='function','receiver present')
local function Stats() return S.Stats() or {} end
local function Rejections()
 local n=0;for k,v in pairs(Stats()) do if type(k)=='string' and k:lower():find('reject',1,true) and type(v)=='number' then n=n+v end end
 return n
end
local before=C.Count()
local transfer=0
local function Build(root)
 transfer=transfer+1
 local id='saved-scalar_'..transfer
 return 'WLRB|PeerOne|'..id..'|1700000000|1/1|'..Codec.Base64Encode(root),id
end
local function Dps(root)
 transfer=transfer+1
 return 'WLD2|PeerOne|t'..string.format('%07d',transfer)..'|1/1|'..Codec.Base64Encode(root)
end

for _,root in ipairs({'5','true','-0.5','"text"'}) do
 local text,id=Build(root)
 local r0=Rejections()
 local ok,err=pcall(S.HandleIncoming,text,'PeerOne')
 check(ok,'build root '..root..': no handler error ('..tostring(err)..')')
 check(err~=true,'build root '..root..': not accepted')
 check(Rejections()>r0,'build root '..root..': ordinary rejection counted')
 check(C.Get(id)==nil,'build root '..root..': nothing stored')
 r0=Rejections()
 ok,err=pcall(S.HandleIncoming,Dps(root),'PeerOne')
 check(ok,'DPS root '..root..': no handler error ('..tostring(err)..')')
 check(err~=true,'DPS root '..root..': not accepted')
 check(Rejections()>r0,'DPS root '..root..': ordinary rejection counted')
end
check(C.Count()==before,'no catalog change from scalar roots')

-- Control: a decoded table that fails the schema is the ordinary schema
-- rejection (the same route the scalar roots now take), not an error.
do
 local text,id=Build('{"x":1}')
 local r0=Rejections()
 local ok,err=pcall(S.HandleIncoming,text,'PeerOne')
 check(ok and err~=true,'table root without a record: ordinary rejection ('..tostring(err)..')')
 check(Rejections()>r0,'table root: rejection counted')
 check(C.Get(id)==nil,'table root: nothing stored')
end
print('sync_scalar_root_reject ok',checks)
