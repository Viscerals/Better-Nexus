-- Synthetic profiles only. Shared by startup regressions and measured probes.
local T={}
function T.Load()
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','');if line~='' and not line:match('^#') then
   local path=line:gsub('\\','/');assert(loadfile(path))('Nexus',{})
  end
 end
end
function T.Profile(n,pool)
 local db={communityBuilds={},loadoutEvidence={schemaVersion=1,entries={}},
  settings={autoPick=false},chars={}}
 for i=1,n do
  local id='synthetic-startup-'..i;local echoes={}
  for j=1,79 do echoes[j]={spellId=200000+j,quality=j%4,stacks=1}end
  db.communityBuilds[id]={id=id,title='Synthetic '..i,author='Other-Realm',class='MAGE',
   postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,echoes=echoes,
   lockedEchoes={},lockedComplete=true,customUnknown={keep=i}}
 end
 -- Preserved opaque evidence entries exercise real graph-copy/validation work;
 -- they are not used to claim a proven Echo reference for any build.
 for i=1,pool do db.loadoutEvidence.entries['synthetic-preserved-'..i]={keep=i}end
 return db
end
function T.Count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
function T.Equal(a,b,seen)
 if type(a)~=type(b) then return false end
 if type(a)~='table'then return a==b end
 seen=seen or {};if seen[a]then return seen[a]==b end;seen[a]=b
 for k,v in pairs(a)do if not T.Equal(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function T.Until(H,predicate,limit)
 for i=1,limit or 20000 do
  H.Advance(.05,.05)
  if predicate() then return i end
 end
 error('bounded startup test did not reach its condition')
end
return T
