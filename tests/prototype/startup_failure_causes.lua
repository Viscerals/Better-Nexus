-- A failed Store start-up keeps its original failure code, but distinct causes
-- must stay distinct in the read-only status: stage, cause, detail, owner, a
-- bounded error, the selection row and the saved-format verdict. Reading the
-- status never binds, pumps or writes; dependent features stay blocked.
-- Real TOC boot, Store, lifecycle, /nexus status and Orb runtime; synthetic data.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

-- A real saved database with a committed bundle (format 2), then edited.
local base
do
 local db=F.Database({version=2})
 F.Boot(db)
 check(Nexus.StartupStatus().coreReady,'fixture: the base profile starts')
 base=F.Serialize(NexusDB)
end
local function Copy()return assert(loadstring('return '..base))()end

local function Failed(label,db,expect,prepare)
 local initCalls=0
 local charsBefore=F.Serialize(db.chars or {})
 F.fileHooks={[ [[core\Store.lua]] ]=function()
  local init=Nexus.Store.Init
  Nexus.Store.Init=function(...)initCalls=initCalls+1;return init(...)end
 end}
 local H=F.Boot(db,prepare)
 F.fileHooks=nil
 local s=Nexus.StartupStatus()
 check(s.state=='failed' and not s.coreReady,label..': start-up failed')
 check(s.reason==expect.reason,label..': the original failure code is kept: '..tostring(s.reason))
 local f=s.failure or {}
 for key,value in pairs(expect.facts)do
  check(f[key]==value,label..': failure.'..key..' = '..tostring(value)..' (got '..tostring(f[key])..')')
 end
 if expect.errorPrefix then
  check(type(f.error)=='string' and f.error:find(expect.errorPrefix,1,true) and #f.error<=163
   and not f.error:find('[%c|]'),label..': the error is bounded and one line: '..tostring(f.error))
 end
 -- Reading the status and the commands is passive.
 local saved=F.Serialize(NexusDB);local calls=initCalls
 for i=1,20 do Nexus.StartupStatus() end
 local chat=#H.chat
 SlashCmdList.NEXUS('status')
 local said=table.concat(H.chat,'\n',chat+1)
 check(said:find('Startup stopped: '..expect.reason,1,true) and said:find('Startup failure:',1,true),
  label..': /nexus status states the code and the retained facts: '..said)
 check(initCalls>0,label..': fixture: the lifecycle Store.Init calls are counted')
 check(F.Serialize(NexusDB)==saved and initCalls==calls,label..': status reads write nothing and never call Store.Init')
 -- Dependent features stay blocked.
 local w=Nexus.Store.StateWriteStatus()
 check(w.mode~='durable',label..': no durable write eligibility: '..tostring(w.mode))
 H.Advance(10,.05)
 check(F.Serialize(NexusDB.chars or {})==charsBefore,label..': no dependent writes character data while start-up has failed')
 local ok=Nexus.OrbRuntime.Start(1)
 check(not ok,label..': Orb Start refuses')
 return f
end

-- 1. The saved Store data in the bundle has an unknown key.
local db=Copy();db.authorityBundle.storeData.unexpected=true
Failed('store data unknown key',db,{reason='STORE_INVALID',facts={cause='STORE_DATA_UNKNOWN_KEY',
 stage='STORE_DURABLE_BUNDLE_ADMISSION_PENDING',formatClass='supported',formatVersion=2}})
-- 2. The empty placeholder, for a format this build writes itself: no first
-- admission there (that is only for accepted formats 3-5); it stays invalid.
db=Copy();db.authorityBundle.storeData={}
Failed('store data empty, format 2',db,{reason='STORE_INVALID',facts={cause='STORE_DATA_EMPTY',formatClass='supported'}})
-- 3. A dependent owner raises an error.
db=Copy()
Failed('owner error',db,{reason='STORE_INVALID',facts={owner='LoadoutEvidence.Init',stage='STORE_AUTHORITY_PENDING'},
 errorPrefix='synthetic evidence failure'},function(H)
 -- Replaced after load, before start-up: the owner raises a multi-line error.
 F.fileHooks[ [[core\LoadoutEvidence.lua]] ]=function()
  Nexus.LoadoutEvidence.Init=function()error('synthetic evidence failure\nsecond line|pipe '..string.rep('x',300),0)end
 end
end)
-- 4. The initial selection refuses a malformed migration marker (selection row 5).
db=F.Database({version=2});db.nexusStoreMigrations={wishlistRealizerDB={version=1,completed='yes'}}
Failed('selection row',db,{reason='STORE_INVALID',facts={row=5,stage='STORE_UNBOUND'}})
-- 5. The bounded character check fails: its detail stays the displayed reason.
db=F.Database({version=2});local shared={x=1};db.chars[F.NAME].a=shared;db.chars[F.NAME].b=shared
Failed('character check',db,{reason='SOURCE_ALIAS_OR_CYCLE',facts={detail='SOURCE_ALIAS_OR_CYCLE',stage='STORE_CHAR_MIGRATION_PENDING'}})
print('PASS startup_failure_causes: store-data, placeholder, owner, selection and character causes stay distinct; reads passive; dependents blocked checks='..checks)
