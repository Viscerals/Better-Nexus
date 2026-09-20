-- Two isolated production runtimes in one process. Each peer has its own Lua
-- globals, harness, synthetic profile and player identity. The bridge carries
-- only packets captured from real SendChatMessage/SendAddonMessage calls into
-- the other peer's real receive events. It models no latency, loss or
-- throttling, and it is not native evidence.
local P={}
function P.Boot(names,rows)
 local peers={}
 for i,name in ipairs(names) do
  local e={};for k,v in pairs(_G)do e[k]=v end;e._G=e
  e.loadfile=function(path)local f,why=loadfile(path);if f then setfenv(f,e)end;return f,why end
  e.dofile=function(path)return assert(e.loadfile(path))()end
  local H=e.dofile('tests/prototype/harness.lua')
  e.UnitName=function()return name,'Ebonhold'end
  local T=e.dofile('tests/prototype/startup_support.lua')
  -- rows may be one size for both peers or one size per peer.
  e.NexusDB=T.Profile(type(rows)=='table' and rows[i] or rows or 5,0)
  H.perks.serverBuildSlots={[102]={name='NEXUS-TEST-'..name,verified=false,echoes={{spellId=200001,quality=1,stacks=3}}}}
  T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
  T.Until(H,function()return e.Nexus.StartupStatus().state=='ready' and e.Nexus.BuildCatalog.ManualPreparationStatus().ready end)
  peers[i]={e=e,H=H,T=T,name=name..'-Ebonhold',cursor=#H.sent}
 end
 P.A,P.B,P.trace,P.before=peers[1],peers[2],{},nil
 return peers[1],peers[2]
end
function P.Channel(q,text,sender)
 q.H.Fire('CHAT_MSG_CHANNEL',text,sender,nil,'1. '..q.e.Nexus.Sync.ChannelName(),nil,nil,nil,nil,q.e.Nexus.Sync.ChannelName())
end
local function Deliver(p,q)
 while p.cursor<#p.H.sent do
  p.cursor=p.cursor+1;local packet=p.H.sent[p.cursor]
  -- The addon route prefixes the same wire code with its protocol tag.
  local code=packet.text:gsub('||','|'):match('^([^|]+)'):gsub('^P%d+:','')
  P.trace[#P.trace+1]={from=p.name,to=q.name,code=code,text=packet.text}
  if P.before then P.before(p,q,code) end
  if packet.route=='chat' and packet.kind=='CHANNEL' then P.Channel(q,packet.text,p.name)
  elseif packet.route=='addon' then q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,p.name)
  else error('unmodelled captured route '..tostring(packet.route)..'/'..tostring(packet.kind))end
 end
end
function P.Step()P.A.H.Advance(.05,.05);P.B.H.Advance(.05,.05);Deliver(P.A,P.B);Deliver(P.B,P.A)end
function P.Advance(seconds)for i=1,math.floor(seconds/.05+.5)do P.Step()end end
function P.Until(predicate,limit)
 for i=1,limit or 12000 do P.Step();if predicate()then return i end end
 error('bounded paired test did not reach its condition')
end
function P.Count(code)
 local n=0;for _,packet in ipairs(P.trace)do if packet.code==code then n=n+1 end end;return n
end
-- Actual Share controls on one peer.
function P.Post(p,title)
 p.e.Nexus.CommunityBuilds.ShowPostBuild();local f=assert(p.e.NexusPostPopup)
 f._postTitleBox:_NexusSetRawText(title)
 f._postDescBox:_NexusSetRawText('Isolated synthetic paired transfer')
 assert(f._postGoBtn:IsEnabled());f._postGoBtn:Click()
 return assert(p.e.Nexus.CommunityBuilds.ShareStatus()).id
end
function P.Full(p,id)
 local row=p.e.Nexus.BuildCatalog.Get(id)
 return row and type(row.echoes)=='table' and #row.echoes>0 and row or nil
end
function P.Ready(p)return p.e.Nexus.BuildCatalog.ManualPreparationStatus().ready end
return P
