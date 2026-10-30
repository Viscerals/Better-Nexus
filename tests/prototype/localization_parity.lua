-- Issue #147, slice S1: the runtime side of the shared parity corpus
-- tests/prototype/fixtures/l10n_parity. Each case's english.lua and
-- packs.lua bytes are read once, compiled in an empty environment (the same
-- bytes tools/tests/test_l10n_parity.py parses without executing), injected
-- into a fresh load of the unchanged core/Localization.lua with the case's
-- language enum, and the Diagnostics() load facts, offered languages and
-- probe results must equal the case's runtime expectation. LF and CRLF
-- variants are derived in memory and must give equal data and outcomes.
-- P8 is the intended divergence: a Lua constructor keeps the last duplicate
-- value. P19 (Lua 5.1 versus LuaJIT escapes) and P20 (UTF-8 BOM) native WoW
-- behaviour is UNKNOWN: their controls only record the harness fact and
-- check that it is one of the declared readings. Synthetic offline evidence,
-- not native evidence; no product, data or package file is changed.
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local CORPUS='tests/prototype/fixtures/l10n_parity/'

local function readBytes(path)
 local file=assert(io.open(path,'rb'));local data=file:read('*a');file:close();return data
end
local function compile(bytes,name,env)
 if setfenv then
  local chunk,err=loadstring(bytes,'='..name)
  if chunk then setfenv(chunk,env) end
  return chunk,err
 end
 return load(bytes,'='..name,'t',env)
end
-- Both line-break variants of a source. A lone CR is refused (C11), and the
-- checkout must be exactly one of the two variants.
local function variants(data,name)
 check(not (data:gsub('\r\n','')):find('\r',1,true),'no lone CR in '..name)
 local lf=(data:gsub('\r\n','\n'));local crlf=(lf:gsub('\n','\r\n'))
 check(data==lf or data==crlf,'checkout is the LF or CRLF variant: '..name)
 return {{'lf',lf},{'crlf',crlf}}
end
local function same(a,b)
 if type(a)~='table' or type(b)~='table' then return a==b end
 for k,v in pairs(a)do if not same(v,b[k]) then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function show(v)
 if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(x,y)return tostring(x)<tostring(y)end)
 local out={};for _,k in ipairs(keys)do out[#out+1]=tostring(k)..'='..show(v[k])end
 return '{'..table.concat(out,',')..'}'
end

-- The case table: a restricted literal table run in an empty environment.
local casesChunk=assert(compile(readBytes(CORPUS..'cases.lua'),'cases.lua',{}))
local corpus=casesChunk()
check(type(corpus)=='table' and corpus.schema=='nexus.l10n.parity_cases' and corpus.schemaVersion==1,'parity corpus schema')
check(#corpus.shippedProductIds==0 and next(corpus.shippedProductIds)==nil,'fixtures add no shipped product')

-- The English and packs tables a data source assigns, or nil and the error.
local function loadData(bytes,name,field)
 local env={}
 local chunk,err=compile(bytes,name,env)
 if not chunk then return nil,err end
 local ok,run=pcall(chunk)
 if not ok then return nil,run end
 return env.Nexus and env.Nexus[field],nil
end

local savedNexus=Nexus
-- A fresh load of the unchanged runtime with injected data and enum.
local function boot(english,packs,enum)
 Nexus={LocalizationEnglish=english,LocalizationPacks=packs,DefaultProfile={uiLanguages={ids=enum}}}
 local ok,err=pcall(dofile,'core/Localization.lua')
 local L=Nexus and Nexus.Localization
 Nexus=savedNexus
 assert(ok and L,'core/Localization.lua loads: '..tostring(err))
 return L
end

-- The observed runtime outcome: load facts, offered languages and, for
-- each probe, a fresh session with the probe's language selected once.
local function outcome(english,packs,case)
 local L=boot(english,packs,case.enum)
 local d=L.Diagnostics()
 local o={base=d.base,packs=d.packs,languages={},probes={}}
 for _,row in ipairs(L.Languages())do o.languages[#o.languages+1]=row.id end
 for index,probe in ipairs(case.runtime and case.runtime.probes or {})do
  local P=boot(english,packs,case.enum)
  if probe.language then P.InitializeActiveLanguage(probe.language) end
  local text,source,reason
  if probe.kind=='format' then text,source,reason=P.Format(probe.key,corpus.formatArguments)
  else text,source,reason=P.Text(probe.key) end
  o.probes[index]={kind=probe.kind,language=probe.language,key=probe.key,text=text,source=source,reason=reason}
 end
 return o
end

local covered,ids={},{}
local byId={}
for _,case in ipairs(corpus.cases)do
 check(type(case.id)=='string' and not ids[case.id],'unique case id '..tostring(case.id))
 ids[case.id]=true;byId[case.id]=case
 for _,row in ipairs(case.rows)do covered[row]=true end
end
for _,row in ipairs(corpus.mappedRows)do check(covered[row],'mapped row covered by a case: '..row)end
for _,row in ipairs(corpus.unknownRows)do check(covered[row],'UNKNOWN row has a control: '..row)end

-- Every committed case: both variants load equal data and give the expected outcome.
local harness={}
local function runCase(case,englishBytes,packsBytes)
 local seen
 for _,ev in ipairs(variants(englishBytes,case.id..'/english.lua'))do
  for _,pv in ipairs(variants(packsBytes,case.id..'/packs.lua'))do
   local label=case.id..' english '..ev[1]..' packs '..pv[1]
   local english,ee=loadData(ev[2],case.id..'/english.lua','LocalizationEnglish')
   local packs,pe=loadData(pv[2],case.id..'/packs.lua','LocalizationPacks')
   check(type(english)=='table' and type(packs)=='table','LuaJIT loads both sources: '..label..' '..tostring(ee or pe))
   local o=outcome(english,packs,case)
   if seen then
    check(same(seen.english,english) and same(seen.packs,packs),'LF and CRLF give equal decoded data: '..label)
    check(same(seen.outcome,o),'LF and CRLF give equal runtime outcomes: '..label)
   else seen={english=english,packs=packs,outcome=o} end
   local want=case.runtime
   check(same(o.base,want.base),'base load facts '..label..': '..show(o.base))
   check(same(o.packs,want.packs),'pack load facts '..label..': '..show(o.packs))
   check(same(o.languages,want.languages),'offered languages '..label..': '..show(o.languages))
   check(#o.probes==#want.probes,'probe count '..label)
   for i,p in ipairs(want.probes)do
    check(same(o.probes[i],{kind=p.kind,language=p.language,key=p.key,text=p.text,source=p.source,reason=p.reason}),
     'probe '..i..' '..label..': '..show(o.probes[i]))
   end
  end
 end
 return seen
end

for _,case in ipairs(corpus.cases)do
 if case.derive then
  check(case.native=='UNKNOWN','a derived representation control keeps native UNKNOWN: '..case.id)
 else
  local dir=CORPUS..case.id..'/'
  local seen=runCase(case,readBytes(dir..'english.lua'),readBytes(dir..'packs.lua'))
  if case.decoded then
   -- P19: the harness reading must be one whole declared reading.
   check(case.native=='UNKNOWN','P19 native behaviour stays UNKNOWN')
   local reading
   for _,name in ipairs({'lua51','luajit'})do
    local all=true
    for key,value in pairs(case.decoded[name])do if seen.english[key]~=value then all=false end end
    if all then reading=name end
   end
   check(reading~=nil,'P19 harness decodes one declared reading: '..show(seen.english))
   check(not same(case.decoded.lua51,case.decoded.luajit),'P19 readings differ, so the row stays UNKNOWN')
   harness[case.id]=reading
  end
 end
end

-- P8: the Lua constructor keeps the last duplicate value (offline rejects it).
do
 local english=assert(loadData(readBytes(CORPUS..'p08_duplicate_english/english.lua'),'p08','LocalizationEnglish'))
 local count=0;for _ in pairs(english)do count=count+1 end
 check(english['parity.alpha']=='Second' and count==3,'P8 duplicate English key: the last value is kept, invisible at runtime')
 local packs=assert(loadData(readBytes(CORPUS..'p08_duplicate_pack_entry/packs.lua'),'p08p','LocalizationPacks'))
 check(packs.qaQA.entries['parity.alpha']=='Deux','P8 duplicate pack entry: the last value is kept')
end
-- P13: decimal escapes and literal UTF-8 decode to the same bytes.
do
 local dir=CORPUS..'p13_escape_equivalence/'
 local english=assert(loadData(readBytes(dir..'english.lua'),'p13','LocalizationEnglish'))
 local packs=assert(loadData(readBytes(dir..'packs.lua'),'p13p','LocalizationPacks'))
 check(english['parity.ru']==packs.qaQA.entries['parity.ru'] and #english['parity.ru']==14,'P13 escaped and literal UTF-8 are equal bytes')
end

-- P20: a UTF-8 BOM before a committed source, derived in memory.
for _,case in ipairs(corpus.cases)do
 if case.derive then
  local source=byId[case.derive.from]
  check(source and not source.derive and case.derive.file=='english','P20 derives from a committed case')
  local dir=CORPUS..source.id..'/'
  local englishBytes=case.derive.prefix..readBytes(dir..'english.lua')
  check(englishBytes:sub(1,3)=='\239\187\191','P20 prefix is the UTF-8 BOM')
  local english=loadData(englishBytes,case.id,'LocalizationEnglish')
  local reading
  if english==nil then reading='refused'
  else
   local packs=assert(loadData(readBytes(dir..'packs.lua'),case.id,'LocalizationPacks'))
   local plain=assert(loadData(readBytes(dir..'english.lua'),source.id,'LocalizationEnglish'))
   if same(english,plain) and same(outcome(english,packs,source),outcome(plain,packs,source)) then reading='same_as_source' end
  end
  local declared=false
  for _,name in ipairs(case.harness)do if name==reading then declared=true end end
  check(declared,'P20 harness reading is declared: '..tostring(reading))
  harness[case.id]=reading
 end
end

check(Nexus==savedNexus,'the global Nexus is restored after every load')
print(('localization_parity: %d cases, %d checks; harness P19=%s, P20=%s; native P19/P20 UNKNOWN')
 :format(#corpus.cases,checks,tostring(harness.p19_ambiguous_escapes),tostring(harness.p20_bom)))
