-- Issue #147, slice S1 and the R union: the runtime side of the shared
-- parity corpus tests/prototype/fixtures/l10n_parity. Each case's
-- english.lua and packs.lua bytes are read once, compiled in an empty
-- environment (the same bytes tools/tests/test_l10n_parity.py parses
-- without executing), injected into a fresh load of core/Localization.lua
-- with the case's language enum, and the Diagnostics() load facts, offered
-- languages and probe results must equal the case's runtime expectation.
-- The cases use test-only keys, so for them only the lines between the two
-- declaration marker lines are replaced, in memory, by a block declaring
-- each valid key of the case's decoded English (cases.lua states the rule);
-- every other byte is the real file. The bound registry rows R-P1 and R-P3
-- load the real file unchanged, with an in-memory edit of the real English
-- and the real packs. LF and CRLF variants are derived in memory and must
-- give equal data and outcomes.
-- Runtime cap (full visible-UI scope): the derived block holds at most the
-- loaded runtime's cap. Each case is checked against the real file (its
-- MAX_BASE_ENTRIES must equal cases.lua runtimeCap.current); the pilot cases
-- are also loaded by a legacy-cap loader, the same bytes with only that line
-- set to runtimeCap.pilot in memory, which must reproduce the historical
-- pilot expectation. runtimeCap.controls add the current 4096/4097 English,
-- declaration and pack boundaries in memory. A bound registry row checks its
-- change from the unedited real load, so no catalog count is fixed here.
-- That change is entry-level, so it holds where entries are judged one by
-- one: an edited input above the cap (a row that adds an entry while the real
-- English fills the budget) is checked against the whole-base refusal, and
-- the row's own prediction is then checked on the same edit at exactly the
-- cap (see "The entry budget of a bound row" below).
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

-- The declaration block of the real runtime: the real file split at its two
-- marker lines (kept), so a test block replaces only the lines between.
local RUNTIME='core/Localization.lua'
local MARK_OPEN,MARK_CLOSE='-- NEXUS-L10N-REGISTRY BEGIN','-- NEXUS-L10N-REGISTRY END'
local runtimeBytes=readBytes(RUNTIME)
local head,tail
do
 -- A whole marker line: plain search, then the line break after it.
 local function line(mark)
  local start,stop=runtimeBytes:find('\n'..mark,1,true)
  local after=stop and runtimeBytes:match('^\r?\n',stop+1)
  return after and start,after and stop+#after
 end
 local _,openEnd=line(MARK_OPEN)
 local closeStart=line(MARK_CLOSE)
 local _,count=runtimeBytes:gsub('NEXUS%-L10N%-REGISTRY','')
 check(openEnd and closeStart and openEnd<closeStart and count==2,'the runtime has exactly one declaration block between its two marker lines')
 head,tail=runtimeBytes:sub(1,openEnd),runtimeBytes:sub(closeStart+1)
end
-- The cap line of the real runtime, and the pilot (legacy-cap) variant of a
-- source: only that one line changes.
local CAP=corpus.runtimeCap
local CAP_LINE='local MAX_BASE_ENTRIES = '
do
 local value=runtimeBytes:match('\n'..CAP_LINE..'(%d+)\r?\n')
 local _,lines=runtimeBytes:gsub('\n'..CAP_LINE..'%d+','')
 check(lines==1 and tonumber(value)==CAP.current,'the real runtime cap is cases.lua runtimeCap.current: '..tostring(value))
 check(CAP.pilot<CAP.current,'the pilot cap is below the current cap')
end
local function legacy(source)
 local out,count=source:gsub('\n'..CAP_LINE..CAP.current..'(\r?\n)','\n'..CAP_LINE..CAP.pilot..'%1')
 check(count==1,'the legacy-cap loader changes exactly the cap line')
 return out
end
local CHARGE_KEY='readout.charge_counts'
local CHARGE_DECLARATION=runtimeBytes:match('%["readout%.charge_counts"%] = (%b{})')
check(CHARGE_DECLARATION and CHARGE_DECLARATION:find('kind = "format"',1,true),'the real charge-row format declaration is read from the real block')
-- The key contract of core/Localization.lua (ValidKey), restated for the rule.
local function validKey(key)
 return type(key)=='string' and #key>=3 and #key<=64 and key:find('^[a-z][a-z0-9_]*%.[a-z0-9_.]*[a-z0-9_]$')~=nil
  and not key:find('%.[^a-z]')
end
-- The case rule of cases.lua: each valid key of the decoded English, in byte
-- order, at most the loaded runtime's cap; the charge key with its real
-- declaration, others text. extra keys (declared without English) follow.
local function derivedKeys(english,cap,extra)
 local keys={}
 for key in pairs(english)do if validKey(key) then keys[#keys+1]=key end end
 table.sort(keys)
 while #keys>(cap or CAP.current) do keys[#keys]=nil end
 for _,key in ipairs(extra or {})do keys[#keys+1]=key end
 return keys
end
local function withDeclarations(keys,pilot)
 local lines={'local DECLARATIONS = {'}
 for _,key in ipairs(keys)do
  lines[#lines+1]=('    ["%s"] = %s,'):format(key,key==CHARGE_KEY and CHARGE_DECLARATION or '{kind = "text"}')
 end
 lines[#lines+1]='}'
 local source=head..table.concat(lines,'\n')..'\n'..tail
 check(source:sub(1,#head)==runtimeBytes:sub(1,#head) and source:sub(-#tail)==runtimeBytes:sub(-#tail),'a test block changes only the lines between the markers')
 return pilot and legacy(source) or source
end

local savedNexus=Nexus
-- A fresh load of the runtime with injected data and enum: the real file
-- unchanged (dofile), or the given source with a test declaration block.
local function boot(english,packs,enum,source)
 Nexus={LocalizationEnglish=english,LocalizationPacks=packs,DefaultProfile={uiLanguages={ids=enum}}}
 local ok,err
 if source then
  local chunk,cerr=compile(source,RUNTIME,_G)
  if chunk then ok,err=pcall(chunk) else ok,err=false,cerr end
 else
  ok,err=pcall(dofile,'core/Localization.lua')
 end
 local L=Nexus and Nexus.Localization
 Nexus=savedNexus
 assert(ok and L,'core/Localization.lua loads: '..tostring(err))
 return L
end

-- The observed runtime outcome: load facts, offered languages and, for
-- each probe, a fresh session with the probe's language selected once.
-- real=true loads the real file; otherwise the case's derived block is used
-- (opts.pilot: under the legacy-cap loader; opts.extra: extra declarations).
local function outcome(english,packs,case,real,want,opts)
 want=want or case.runtime
 opts=opts or {}
 local cap=opts.pilot and CAP.pilot or CAP.current
 local source=not real and withDeclarations(derivedKeys(english,cap,opts.extra),opts.pilot) or nil
 local L=boot(english,packs,case.enum,source)
 local d=L.Diagnostics()
 local o={base=d.base,packs=d.packs,languages={},probes={}}
 for _,row in ipairs(L.Languages())do o.languages[#o.languages+1]=row.id end
 for index,probe in ipairs(want and want.probes or {})do
  local P=boot(english,packs,case.enum,source)
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

local pilotCases={}
for _,id in ipairs(CAP.pilotCases)do pilotCases[id]=true end
local function sameOutcome(o,want,label,declared)
 check(same(o.base,want.base),'base load facts '..label..': '..show(o.base))
 -- Every derived declaration has an English entry, so outside the
 -- whole-base limit each rejected entry is undeclared or declared-invalid.
 check(o.base.missingDeclared==declared-o.base.accepted and (o.base.oversized
  or o.base.rejected==o.base.undeclared+o.base.missingDeclared),'derived block load facts reconcile '..label)
 check(same(o.packs,want.packs),'pack load facts '..label..': '..show(o.packs))
 check(same(o.languages,want.languages),'offered languages '..label..': '..show(o.languages))
 check(#o.probes==#want.probes,'probe count '..label)
 for i,p in ipairs(want.probes)do
  check(same(o.probes[i],{kind=p.kind,language=p.language,key=p.key,text=p.text,source=p.source,reason=p.reason}),
   'probe '..i..' '..label..': '..show(o.probes[i]))
 end
end

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
   sameOutcome(o,case.runtime,label,#derivedKeys(english))
   if pilotCases[case.id] then
    -- The historical pilot expectation under the legacy-cap loader.
    local want=case.pilotRuntime or case.runtime
    sameOutcome(outcome(english,packs,case,false,want,{pilot=true}),want,label..' (pilot cap)',#derivedKeys(english,CAP.pilot))
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

-- The current 4096/4097 boundaries, derived in memory from committed cases.
local controls=0
do
 local function grow(entries,count)
  local out,n={},0
  for key,value in pairs(entries)do out[key]=value;n=n+1 end
  local index=0
  while n<count do
   index=index+1
   local key=('parity.g%04d'):format(index)
   if out[key]==nil then out[key]=('Generated %04d'):format(index);n=n+1 end
  end
  return out
 end
 local seenPilot={}
 for _,id in ipairs(CAP.pilotCases)do check(byId[id] and not byId[id].derive,'pilot case is committed: '..id);seenPilot[id]=true end
 for _,control in ipairs(CAP.controls)do
  local source=byId[control.from]
  check(source and not source.derive and (control.file=='english' or control.file=='packs'),'cap control derives from a committed case: '..control.id)
  local dir=CORPUS..source.id..'/'
  local english=assert(loadData(readBytes(dir..'english.lua'),control.id,'LocalizationEnglish'))
  local packs=assert(loadData(readBytes(dir..'packs.lua'),control.id,'LocalizationPacks'))
  if control.file=='english' then english=grow(english,control.entries)
  else
   local id=source.enum[1]
   packs[id].entries=grow(packs[id].entries,control.entries)
  end
  local count,n=0,nil
  for _ in pairs(control.file=='english' and english or packs[source.enum[1]].entries)do count=count+1 end
  check(count==control.entries,'cap control holds its entry count: '..control.id)
  local o=outcome(english,packs,source,false,control.runtime,{extra=control.extraDeclarations})
  local declared=#derivedKeys(english,CAP.current,control.extraDeclarations)
  if control.extraDeclarations then
   -- Above the cap the block declares nothing: every entry is undeclared.
   check(declared>CAP.current,'the declaration control exceeds the cap: '..control.id)
   check(same(o.base,control.runtime.base),'base load facts '..control.id..': '..show(o.base))
   check(same(o.packs,control.runtime.packs) and same(o.languages,control.runtime.languages),'pack and language facts '..control.id)
   for i,p in ipairs(control.runtime.probes)do
    check(same(o.probes[i],{kind=p.kind,language=p.language,key=p.key,text=p.text,source=p.source,reason=p.reason}),'probe '..i..' '..control.id..': '..show(o.probes[i]))
   end
  else
   sameOutcome(o,control.runtime,control.id,declared)
  end
  controls=controls+1
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

-- The bound registry rows (R union): an in-memory edit of the real English,
-- loaded with the real packs into the real core/Localization.lua.
local registry=corpus.registry
local function edited(data,input)
 local lf=(data:gsub('\r\n','\n'))
 local lines,found={},0
 for line in (lf..'\n'):gmatch('([^\n]*)\n')do
  if line==input.remove then found=found+1
  else
   lines[#lines+1]=line
   if line==input.after then found=found+1;lines[#lines+1]=input.line end
  end
 end
 check(found==1,'the edit names exactly one line: '..tostring(input.after or input.remove))
 local text=table.concat(lines,'\n')
 if lf:sub(-1)=='\n' then text=text:sub(1,-2) end
 check(text~=lf,'the edit changes the source')
 return text
end
local bound=0
check(registry.parser=='parse_registry_declarations' and registry.marker.open==MARK_OPEN and registry.marker.close==MARK_CLOSE,'registry convention recorded once')
-- The unedited real load: its base facts, pack rows and, per probe, result.
local realEnglish=assert(loadData(readBytes('data/LocalizationEnglish.lua'),'english','LocalizationEnglish'))
local realPacks=assert(loadData(readBytes('data/LocalizationPacks.lua'),'packs','LocalizationPacks'))
local function realOutcome(probes)
 return outcome(realEnglish,realPacks,{enum=registry.enum},true,{probes=probes})
end
-- The pack rows a real load must show when the edit removes English keys:
-- each real pack entry of a removed key is rejected instead of copied.
local function packRowsAfter(rows,removed)
 local out={}
 for index,row in ipairs(rows)do
  local entries=realPacks[row.id].entries
  local lost=0
  for key in pairs(removed)do if entries[key]~=nil then lost=lost+1 end end
  out[index]={id=row.id,accepted=row.accepted-lost,rejected=row.rejected+lost}
 end
 return out
end
-- The entry budget of a bound row. What a row predicts (its change from the
-- unedited load, its pack rows, its probes) is entry-level: it holds where
-- the loader judges entries one by one, which is at most CAP.current English
-- entries. Above that the contract of core/Localization.lua decides alone
-- (English base: "above MAX_BASE_ENTRIES it adopts nothing, sets
-- oversized=true and rejected to the whole entry count"; every declared
-- meaning is then left without English and resolves as an unknown key; a pack
-- is still adopted, and none of its entries is copied). So the edited input
-- is counted before it is loaded:
--  * at most the cap: the row's own prediction, as before;
--  * above it: the refusal, predicted from that count, the declaration lines
--    of the real block and the contract (aboveCap), and then the row's own
--    prediction on the same edit at exactly the cap: the edit less as many
--    declared static entries as it is over (fitted). Those are the first
--    static-text declarations in byte order that the row does not name. Each
--    is one declared meaning left without English (one fewer accepted, one
--    more missing), its real pack entries are rejected as a removed key's
--    are, and nothing else of the row's prediction changes.
-- The safe status text is the documented one, stated here.
local UNAVAILABLE='This status cannot be shown right now.'
local staticText,declarationLines={},0
do
 local block=runtimeBytes:sub(#head+1,-#tail-1)
 for key in block:gmatch('\n    %["([^"]+)"%] = {kind = "text"},')do staticText[key]=true end
 local _,lines=block:gsub('\n    %["[^"]+"%] = {','')
 declarationLines=lines
end
local function aboveCap(o,supplied,want,label)
 check(declarationLines>0 and declarationLines<=CAP.current,'the real block declares at most the cap: '..declarationLines)
 local refused={present=true,oversized=true,accepted=0,rejected=supplied,formatted=0,undeclared=0,missingDeclared=declarationLines}
 check(same(o.base,refused),'registry base load facts above the cap '..label..': '..show(o.base)..' predicted '..show(refused))
 check(o.packs.present and o.packs.adopted==#registry.enum-1 and o.packs.refused==0,'every real pack stays adopted above the cap '..label)
 local rows={}
 for index=2,#registry.enum do
  local id,entries=registry.enum[index],0
  for _ in pairs(realPacks[id].entries)do entries=entries+1 end
  rows[#rows+1]={id=id,accepted=0,rejected=entries}
 end
 check(same(o.packs.rows,rows),'no real pack entry is copied above the cap '..label..': '..show(o.packs.rows))
 check(same(o.languages,registry.enum),'every enum language stays offered above the cap '..label..': '..show(o.languages))
 check(#o.probes==#want.probes,'registry probe count above the cap '..label)
 for i,p in ipairs(want.probes)do
  check(same(o.probes[i],{kind=p.kind,language=p.language,key=p.key,text=UNAVAILABLE,source='unavailable',reason=validKey(p.key) and 'unknown_key' or 'invalid_key'}),
   'registry probe '..i..' above the cap '..label..': '..show(o.probes[i]))
 end
end
-- The edit at exactly the cap, and every key it is then without (the row's
-- removed key and the entries left out here).
local function fitted(english,supplied,want,removed)
 local named,keys={},{}
 for key in pairs(removed)do named[key]=true end
 for _,p in ipairs(want.probes)do named[p.key]=true end
 for key in pairs(realEnglish)do
  if staticText[key] and english[key]~=nil and not named[key] then keys[#keys+1]=key end
 end
 table.sort(keys)
 local out,without,count={},{},0
 for key in pairs(removed)do without[key]=true end
 for index=1,supplied-CAP.current do without[assert(keys[index],'a declared static entry the row does not name')]=true end
 for key,value in pairs(english)do
  if not without[key] then out[key]=value;count=count+1 end
 end
 check(count==CAP.current,'the fitted edit holds exactly the cap: '..count)
 return out,without
end
for _,row in ipairs(registry.rows)do
 check(row.state==registry.bound,'registry row is bound: '..row.id)
 local want=row.expect and row.expect.runtime
 if row.input.file=='data/LocalizationEnglish.lua' then
  check(want~=nil,'an English registry row has a runtime expectation: '..row.id)
  local englishBytes=edited(readBytes(row.input.file),row.input)
  local packsBytes=readBytes('data/LocalizationPacks.lua')
  local unedited=realOutcome(want.probes)
  local removed={}
  if row.input.remove then removed[assert(row.input.remove:match('^%s*%["([^"]+)"%]'),'removed line names a key')]=true end
  local wantBase,change={},want.baseChange
  for name,value in pairs(unedited.base)do
   wantBase[name]=type(value)=='number' and value+(change.add[name] or 0)-(change.subtract[name] or 0) or value
  end
  for _,part in ipairs({change.add,change.subtract})do
   for name in pairs(part)do check(type(unedited.base[name])=='number','baseChange names a load fact: '..name)end
  end
  local wantRows=packRowsAfter(unedited.packs.rows,removed)
  local seen,seenFitted
  for _,ev in ipairs(variants(englishBytes,row.id..'/english'))do
   for _,pv in ipairs(variants(packsBytes,'data/LocalizationPacks.lua'))do
    local label=row.id..' english '..ev[1]..' packs '..pv[1]
    local english=assert(loadData(ev[2],row.id,'LocalizationEnglish'))
    local packs=assert(loadData(pv[2],'packs','LocalizationPacks'))
    local o=outcome(english,packs,{enum=registry.enum},true,want)
    if seen then check(same(seen,o),'LF and CRLF give equal registry outcomes: '..label) else seen=o end
    local expectBase,expectRows=wantBase,wantRows
    local supplied=0
    for _ in pairs(english)do supplied=supplied+1 end
    if supplied>CAP.current then
     aboveCap(o,supplied,want,label)
     local over=supplied-CAP.current
     local inside,without=fitted(english,supplied,want,removed)
     expectBase={}
     for name,value in pairs(wantBase)do expectBase[name]=value end
     expectBase.accepted,expectBase.missingDeclared=wantBase.accepted-over,wantBase.missingDeclared+over
     expectRows=packRowsAfter(unedited.packs.rows,without)
     label=label..' at exactly the cap'
     o=outcome(inside,packs,{enum=registry.enum},true,want)
     if seenFitted then check(same(seenFitted,o),'LF and CRLF give equal registry outcomes: '..label) else seenFitted=o end
    end
    check(same(o.base,expectBase),'registry base load facts '..label..': '..show(o.base)..' predicted '..show(expectBase))
    check(o.packs.present and o.packs.adopted==#registry.enum-1 and o.packs.refused==0,'every real pack stays adopted '..label)
    check(same(o.packs.rows,expectRows),'real pack copies change only by removed keys '..label..': '..show(o.packs.rows))
    check(same(o.languages,registry.enum),'every enum language stays offered '..label..': '..show(o.languages))
    check(#o.probes==#want.probes,'registry probe count '..label)
    for i,p in ipairs(want.probes)do
     local expected=p.unchanged and unedited.probes[i]
      or {kind=p.kind,language=p.language,key=p.key,text=p.text,source=p.source,reason=p.reason}
     check(not p.unchanged or (expected.text~=nil and not removed[p.key]),'an unchanged probe has an unedited result '..label)
     check(same(o.probes[i],expected),'registry probe '..i..' '..label..': '..show(o.probes[i]))
    end
   end
  end
  bound=bound+1
 else
  check(want==nil and row.runtime=='not applicable','a document-only registry row has no runtime expectation: '..row.id)
 end
end
-- The real file and data: the declarations admit exactly the whole real
-- English base, and every real pack entry is copied. The counts come from
-- the data and the declaration block text, not from the runtime.
do
 local count=0
 for _ in pairs(realEnglish)do count=count+1 end
 local block=runtimeBytes:sub(#head+1,-#tail-1)
 local _,formats=block:gsub('kind = "format"','')
 local _,templates=block:gsub('kind = "template"','')
 local _,declarations=block:gsub('\n    %["[^"]+"%] = {','')
 check(count>0 and declarations==count and count<=CAP.current,'one declaration line per real English key: '..declarations..' / '..count)
 local o=realOutcome({})
 check(same(o.base,{present=true,accepted=count,rejected=0,oversized=false,formatted=formats+templates,undeclared=0,missingDeclared=0}),'real declarations admit the whole real English base: '..show(o.base))
 for _,row in ipairs(o.packs.rows)do
  local entries=0
  for _ in pairs(realPacks[row.id].entries)do entries=entries+1 end
  check(row.accepted==entries and row.rejected==0,'every real pack entry is copied: '..row.id)
 end
end

check(Nexus==savedNexus,'the global Nexus is restored after every load')
print(('localization_parity: %d cases (%d also under the pilot cap %d), %d cap controls (cap %d), %d bound registry runtime rows, %d checks; harness P19=%s, P20=%s; native P19/P20 UNKNOWN')
 :format(#corpus.cases,#CAP.pilotCases,CAP.pilot,controls,CAP.current,bound,checks,tostring(harness.p19_ambiguous_escapes),tostring(harness.p20_bom)))
