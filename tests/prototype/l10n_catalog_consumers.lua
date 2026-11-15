-- Full UI localization: catalog and consumers agree. After the real TOC boot
-- every declaration has admitted English (no undeclared or missing meaning);
-- every key literal a Lua source passes to Text/Format (directly or through
-- a per-file T/TF helper) is a reviewed key of the matching kind; and every
-- reviewed key appears as a literal in some runtime source, so no key is an
-- orphan without a consumer. A typo would otherwise show the safe
-- "This status cannot be shown right now." text. Static source reading plus
-- the real seam; synthetic offline evidence, native NOT_RUN.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local L=assert(Nexus.Localization)
local base=L.Diagnostics().base
check(base.present and not base.oversized and base.undeclared==0 and base.missingDeclared==0 and base.rejected==0,
 ('every declaration has admitted English: accepted=%d rejected=%d undeclared=%d missing=%d'):format(base.accepted,base.rejected,base.undeclared,base.missingDeclared))
check(base.accepted==#L.Keys(),'admitted entries are the listed keys')

-- Runtime sources: every .lua line of Nexus.toc except the catalog itself and
-- third-party code.
local files={}
for line in io.lines('Nexus.toc') do
 line=line:gsub('\r','')
 if line~='' and not line:match('^#') then
  local path=line:gsub('\\','/')
  if path:match('%.lua$') and not path:match('^third_party/') and path~='data/LocalizationEnglish.lua'
   and path~='data/LocalizationPacks.lua' and path~='core/Localization.lua' then files[#files+1]=path end
 end
end
check(#files>50,'SETUP runtime source list from the TOC')

local used,static,formatted={}, {}, {}
local function read(path) local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
for _,path in ipairs(files) do
 local src=read(path)
 for key in src:gmatch('"([a-z][a-z0-9_]*%.[a-z0-9_.]*[a-z0-9_])"') do
  used[key]=used[key] or path
 end
 for key in src:gmatch("'([a-z][a-z0-9_]*%.[a-z0-9_.]*[a-z0-9_])'") do
  used[key]=used[key] or path
 end
 for key in src:gmatch('[Ll]ocalization%.Text%("([^"]+)"') do static[#static+1]={key,path} end
 local aliasL=src:find('local L = Nexus%.Localization')
 if aliasL then for key in src:gmatch('%f[%w_]L%.Text%("([^"]+)"') do static[#static+1]={key,path} end end
 -- Bare T/TF only in a file that defines them as the seam helpers.
 local helperT=src:find('local function T%(key%)%s*return %(Nexus%.Localization%.Text%(key%)%)')
 local helperTF=src:find('local function TF%(key, args%)%s*return %(Nexus%.Localization%.Format%(key, args%)%)')
 if helperT then for key in src:gmatch('%f[%w_]T%("([^"]+)"') do static[#static+1]={key,path} end end
 for key in src:gmatch('[Ll]ocalization%.Format%("([^"]+)"') do formatted[#formatted+1]={key,path} end
 if aliasL then for key in src:gmatch('%f[%w_]L%.Format%("([^"]+)"') do formatted[#formatted+1]={key,path} end end
 if helperTF then for key in src:gmatch('%f[%w_]TF%("([^"]+)"') do formatted[#formatted+1]={key,path} end end
end
for _,item in ipairs(static) do
 local kind=L.Kind(item[1])
 check(kind=='text' or kind=='block','static lookup of an unknown or formatted key: '..item[1]..' in '..item[2])
end
for _,item in ipairs(formatted) do
 local kind=L.Kind(item[1])
 check(kind=='format' or kind=='template','formatted lookup of an unknown or static key: '..item[1]..' in '..item[2])
end
check(#static+#formatted>=20,'SETUP consumer lookups found: '..(#static+#formatted))
-- Path-derived consumers: a module may list the keys it derives from code
-- identifiers at display time (ui/GuidedSetup.lua L10nDerivedKeys, the
-- coach's words). Each listed key must be reviewed, or its words would show
-- English; listed keys count as consumed.
-- A derived leaf may stay English only when it is named here with its reason.
-- (R5 Source86: guide.body.target_c_active is adopted with its traced wording,
-- so no derived leaf is pending any more.)
local DERIVED_PENDING={}
local derived,derivedCount,undeclaredDerived={},0,{}
for name,module in pairs(Nexus) do
 local list=type(module)=='table' and rawget(module,'L10nDerivedKeys')
 if type(list)=='function' then
  for _,key in ipairs(list()) do
   derived[key]=name;derivedCount=derivedCount+1
   if not L.Has(key) and not DERIVED_PENDING[key] then undeclaredDerived[#undeclaredDerived+1]=name..':'..key end
  end
 end
end
table.sort(undeclaredDerived)
for key in pairs(DERIVED_PENDING) do
 check(derived[key]~=nil and not L.Has(key),'a pending derived key is still derived and still unreviewed (remove it here once adopted): '..key)
end
check(#undeclaredDerived==0,'every path-derived key is a reviewed key: '..table.concat(undeclaredDerived,', '))
local orphans={}
for _,key in ipairs(L.Keys()) do if not used[key] and not derived[key] then orphans[#orphans+1]=key end end
check(#orphans==0,'every reviewed key has a runtime consumer literal; orphans: '..table.concat(orphans,', '))
print(('PASS l10n_catalog_consumers keys=%d lookups=%d derived=%d checks=%d (static source + real seam; native NOT_RUN)'):format(#L.Keys(),#static+#formatted,derivedCount,checks))
