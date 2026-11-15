-- Issue #171: Nexus.SessionPause is a memory-only session barrier. Its read
-- methods are pure, its transitions idempotent, its commands answer before
-- start-up completes, and it saves, creates and resumes nothing.
local function Serialize(v,seen)
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 seen=seen or {};if seen[v] then return 'cycle' end;seen[v]=true
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen) end
 seen[v]=nil
 return '{'..table.concat(out,',')..'}'
end
local function Keys(t)local n=0;for _ in pairs(t) do n=n+1 end;return n end

-- L1. The module alone: exact shape, detached tables, idempotent epoch.
do
 Nexus={}
 dofile('core/SessionPause.lua')
 local P=Nexus.SessionPause
 assert(P.IsPaused()==false,'false initially')
 local s=P.Status()
 assert(s.paused==false and s.epoch==0 and s.reason==nil and Keys(s)==2,'initial status')
 s.paused=true;s.epoch=99
 assert(P.IsPaused()==false and P.Status().epoch==0,'a returned table is a copy')
 assert(P.Status()~=P.Status(),'each status is a fresh table')
 local a=P.Pause()
 assert(a.paused==true and a.epoch==1 and a.reason=='session_pause' and Keys(a)==3,'pause returns its status')
 local b=P.Pause()
 assert(b.paused==true and b.epoch==1,'a repeated Pause does not count again')
 for _=1,5 do P.IsPaused();P.Status() end
 assert(P.Status().epoch==1,'reads do not count')
 local c=P.Resume()
 assert(c.paused==false and c.epoch==2 and c.reason==nil,'resume returns its status')
 assert(P.Resume().epoch==2,'a repeated Resume does not count again')
end

-- L2. Loaded but not started: the commands answer, prepare no saved data and
-- create no runtime owner. No ADDON_LOADED / world entry has happened.
do
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua')
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
  end
 end
 local created=0
 local factory=Nexus.MainInternals.AutomationRuntime;local new=factory.New
 factory.New=function(...)created=created+1;return new(...) end
 assert(SlashCmdList.NEXUS,'slash registered at load')
 local mark=#H.chat+1
 SlashCmdList.NEXUS('paused');SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('paused')
 local text=table.concat(H.chat,'\n',mark)
 assert(text:find('Nexus is not paused',1,true) and text:find('Nexus paused for this session',1,true),
  'commands answer before start-up: '..text)
 assert(not text:find('Preparing local saved data',1,true),'not sent to the start-up gate')
 assert(Nexus.SessionPause.IsPaused(),'paused before start-up')
 SlashCmdList.NEXUS('resume')
 assert(not Nexus.SessionPause.IsPaused(),'resumed before start-up')
 assert(NexusDB==nil and WishlistRealizerDB==nil,'no saved data prepared')
 assert(created==0,'no automation owner created')
end

-- L3. A started session: pausing changes no saved data, panel visibility or
-- Auto selection, adds no saved field, and Global Resume calls no Orb entry.
-- Its lifecycle holds the Share pump while paused (unpaused control).
local H
do
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 H=dofile('tests/prototype/harness.lua');H.Boot();H.Advance(2)
 Nexus.Panel.Show();H.Advance(.5)
 local shown=NexusPanel:IsShown()
 local orbCalls=0
 for _,name in ipairs({'Start','Resume','Confirm','ContinueConfirm'}) do
  local f=Nexus.OrbRuntime[name];Nexus.OrbRuntime[name]=function(...)orbCalls=orbCalls+1;return f(...) end
 end
 local community=Nexus.CommunityBuilds;local pump=community.PumpPendingShare;local pumps=0
 community.PumpPendingShare=function(...)pumps=pumps+1;return pump(...) end
 H.Advance(1)
 assert(pumps>0,'control: the lifecycle pumps the Share owner while not paused')
 local before=Serialize(NexusDB)
 SlashCmdList.NEXUS('pause')
 assert(Serialize(NexusDB)==before,'Pause writes no saved data')
 assert(NexusPanel:IsShown()==shown,'Pause leaves the HUD as it was')
 pumps=0;H.Advance(5)
 assert(pumps==0,'no Share pump while paused')
 assert(not Serialize(NexusDB):lower():find('pause',1,true),'no saved pause field')
 before=Serialize(NexusDB)
 SlashCmdList.NEXUS('resume')
 assert(Serialize(NexusDB)==before,'Resume writes no saved data')
 assert(orbCalls==0,'Global Resume calls no Orb Start, Resume, Confirm or Continue')
 Nexus.Panel.Hide();H.Advance(.5)
 SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('paused')
 assert(not NexusPanel:IsShown() and Nexus.SessionPause.IsPaused(),'hidden HUD: the commands still work')
 SlashCmdList.NEXUS('resume')
 assert(not Nexus.SessionPause.IsPaused() and not NexusPanel:IsShown(),'and Resume leaves it hidden')
end

-- L4. A reload starts unpaused.
do
 SlashCmdList.NEXUS('pause')
 local saved=NexusDB
 Nexus=nil;SlashCmdList=nil;NexusPanel=nil
 local J=dofile('tests/prototype/harness.lua');NexusDB=saved;J.Boot()
 local s=Nexus.SessionPause.Status()
 assert(s.paused==false and s.epoch==0,'a new UI session starts unpaused')
end

print('PASS session pause is memory-only, pure to read and recoverable before start-up')
