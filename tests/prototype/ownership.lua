local H=dofile('tests/prototype/harness.lua');H.Boot()
local A=Nexus.GameAdapter
local checks=0;local function check(v,msg) assert(v,msg);checks=checks+1 end
-- Reach the existing runtime's private projection-cache functions for an
-- offline white-box regression. No production test/debug export is added.
local seen={}
local function find(value,wanted,depth)
 if type(value)~='function' or seen[value] or depth>15 then return end
 seen[value]=true
 for i=1,100 do
  local name,v=debug.getupvalue(value,i);if not name then break end
  if name==wanted then return v end
  if name~='_ENV' then
   if type(v)=='function' then local got=find(v,wanted,depth+1);if got then return got end
   elseif type(v)=='table' and (name=='AutomationRuntime' or name=='M') then
    for _,fn in pairs(v) do local got=find(fn,wanted,depth+1);if got then return got end end
   end
  end
 end
end
local function resolve(name) seen={};return assert(find(Nexus.RequestRecompute,name,0),'runtime upvalue '..name) end
local read=resolve('ReadProjection');local update=resolve('UpdateProjectionRevisions')
local function revisions()
 local r={A.PresentationRevisions()}
 update(r[1],r[2],r[3],r[4],r[7],r[8],r[9],r[10]);return r
end
H.holdGrantedResponse=true;H.granted={};A.RunBoundaryReset();A.Poll()
local before=revisions()
local first=read('owned',1,H.playerLevel,A.Owned)
check(first.synced==false,'pre-response empty is untrusted')
-- Notify using the same pre-request reference: no fabricated trust.
H.Notify();A.Poll();revisions()
check(read('owned',1,H.playerLevel,A.Owned).synced==false,'notification alone is not authority')
-- A real completed response replaces the table, even when it remains empty.
H.granted={};H.Notify();A.Poll()
local after=revisions()
check(after[3]~=before[3] or after[4]~=before[4],'empty confirmation invalidates cache revisions')
local confirmed=read('owned',1,H.playerLevel,A.Owned)
check(confirmed~=first and confirmed.synced==true,'actual runtime cache observes confirmed empty')
local settled=revisions();H.Notify();A.Poll();local duplicate=revisions()
check(settled[3]==duplicate[3] and settled[4]==duplicate[4],'duplicate response does not churn')
H.granted={['Echo 1']={{spellId=200001}}};H.Notify();A.Poll();revisions()
check(read('owned',1,H.playerLevel,A.Owned).bySpell[200001]==1,'real content change refreshes counts')
A.RunBoundaryReset();A.Poll();revisions()
check(read('owned',1,H.playerLevel,A.Owned).synced==false,'new generation does not trust previous data')
print('PASS ownership notification -> revisions -> real cache checks='..checks)
