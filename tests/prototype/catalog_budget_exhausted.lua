-- Catalog slice check (Echo-roll lag report, 2026-09-30). A catalog pump
-- stops before the first unit of work after any counter reaches its slice.
-- Exhausted runs before every unit and scanned all 24 counters: about 16% of
-- the admission CPU on the reporter's 756-build catalog. It now reads a flag
-- that Charge sets at the first crossing.
--
-- Required: at every Exhausted call of a startup admission and of one catalog
-- write through the real modules, the answer equals the full scan of the same
-- budget; both answers occur (the run cannot pass vacuously); the write
-- commits the same record. The full-scan rule and its constants are the
-- module's own SLICE and COUNTER_KEYS.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
local restore=T.SingleSlicePacing()
NexusDB=T.Profile(40,60);T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local C=Nexus.BuildCatalog

-- Find the module's upvalues by name, from its public functions.
local function findUpvalue(name)
 local queue,seen={},{}
 for _,f in pairs(C) do if type(f)=='function' then queue[#queue+1]=f end end
 local i=1
 while i<=#queue do
  local f=queue[i];i=i+1
  if not seen[f] then
   seen[f]=true
   for u=1,255 do
    local n,v=debug.getupvalue(f,u)
    if not n then break end
    if n==name then return f,u,v end
    if type(v)=='function' then queue[#queue+1]=v
    elseif type(v)=='table' then for _,x in pairs(v) do if type(x)=='function' then queue[#queue+1]=x end end end
   end
  end
 end
end
local holder,index,exhausted=findUpvalue('Exhausted')
local _,_,SLICE=findUpvalue('SLICE')
local _,_,KEYS=findUpvalue('COUNTER_KEYS')
check(holder and type(exhausted)=='function','the catalog slice check is found')
check(type(SLICE)=='table' and type(KEYS)=='table' and #KEYS==24,'the slice limits and the 24 counters are found')

local function fullScan(budget)
 for _,key in ipairs(KEYS) do
  local slice=SLICE[key]
  if slice and budget[key]>=slice then return true end
 end
 return false
end
local calls,yes,no,disagree,first=0,0,0,0,nil
local reached,reachedCount={},0
debug.setupvalue(holder,index,function(budget)
 local answer=exhausted(budget)
 local expected=fullScan(budget)
 calls=calls+1
 if expected then
  yes=yes+1
  for _,key in ipairs(KEYS) do
   if not reached[key] and budget[key]>=SLICE[key] then reached[key]=true;reachedCount=reachedCount+1 end
  end
 else no=no+1 end
 if (answer and true or false)~=expected then
  disagree=disagree+1
  first=first or ('call '..calls..': '..tostring(answer)..' vs '..tostring(expected))
 end
 return answer
end)

-- 1. Startup admission of the saved catalog.
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end,200000)
check(C.Count()==40,'the saved catalog is admitted: '..C.Count())
check(disagree==0,'startup: every slice decision equals the full scan: '..tostring(first))
check(yes>=20 and no>yes,'startup: pumps ended on exhausted slices '..yes..' times in '..calls..' checks')
local startupYes=yes

-- 2. One catalog write, as a received build.
local donor=C.Get('synthetic-startup-7')
check(type(donor)=='table' and type(donor.echoes)=='table' and #donor.echoes==79,'a stored build to copy')
local record=H.Clone(donor);record.id='synthetic-received-1';record.title='Received 1';record.author='Remote-Realm'
local ok,why,ticket=C.Put(record)
check(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table','the write starts a catalog mutation: '..tostring(why))
T.Until(H,function()return ticket.state~='pending'end,200000)
check(ticket.state=='committed' and C.Count()==41,'the write commits: '..tostring(ticket.state)..' count '..C.Count())
local stored=C.Get('synthetic-received-1')
check(stored and T.Equal(stored.echoes,donor.echoes),'the committed record keeps the same Echoes')
check(disagree==0,'write: every slice decision equals the full scan: '..tostring(first))
check(yes-startupYes>=20,'write: pumps ended on exhausted slices '..(yes-startupYes)..' times')
-- Several different counters ended slices (the flag is set the same way for
-- every counter). The counts in the PASS line vary between runs, because the
-- admission's work order does; the checks above do not depend on them.
local names={};for _,key in ipairs(KEYS) do if reached[key] then names[#names+1]=key end end
check(reachedCount>=5,'slices ended on several counters: '..table.concat(names,','))
restore()
print('PASS catalog slice decisions equal the full scan ('..calls..' checks, '..yes..' exhausted; counters '..table.concat(names,',')..'); '..checks..' checks')
