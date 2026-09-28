-- Two isolated production runtimes in one process. Each peer has its own Lua
-- globals, harness, synthetic profile and player identity. The bridge carries
-- only packets captured from real SendChatMessage/SendAddonMessage calls into
-- the other peer's real receive events. It models no loss or throttling, and
-- no latency unless a test sets P.hold. It is not native evidence.
local P={}
-- A released peer runs the released test.9049 product files: verbatim copies
-- in the fixture, or unchanged current files. Every product file it loads is
-- checked against the fixture MANIFEST (length and FNV-1a 32 of the bytes
-- without carriage returns), so a stale fixture fails instead of passing on
-- newer code. Regenerate with: python tools/released_fixture.py build
P.RELEASED='tests/prototype/fixtures/released_9049'
local function Fnv1a(text)
 local h=2166136261
 for i=1,#text do
  local b=text:byte(i)
  if b~=13 then
   h=bit.bxor(h,b)%4294967296
   -- h * 16777619 mod 2^32 without leaving exact double arithmetic.
   h=((h%256)*16777216+h*403)%4294967296
  end
 end
 return string.format('%08x',h)
end
local manifest
local function Manifest()
 if manifest then return manifest end
 manifest={}
 for line in io.lines(P.RELEASED..'/MANIFEST.txt') do
  local path,size,digest=line:match('^([^#|][^|]*)|(%d+)|(%x+)|')
  if path then manifest[path]={size=tonumber(size),digest=digest} end
 end
 return manifest
end
function P.VerifyReleased(path,mapped)
 local entry=Manifest()[path]
 if not entry then return end
 local f=assert(io.open(mapped,'rb'));local text=f:read('*a');f:close()
 local plain=text:gsub('\r','')
 if #plain~=entry.size or Fnv1a(text)~=entry.digest then
  error('released peer file is not the released bytes: '..path..' (regenerate: python tools/released_fixture.py build)')
 end
end
-- configure(i,db), optional, adjusts peer i's synthetic profile before load.
-- opts, optional: opts.slots[i] replaces peer i's synthetic server Saved
-- Build slots; opts.roots[i] is a directory whose files replace the product
-- files of the same relative path for peer i (for example a released build's
-- files); opts.tocs[i] is the TOC that peer loads.
function P.Boot(names,rows,configure,opts)
 opts=opts or {}
 local peers={}
 for i,name in ipairs(names) do
  local e={};for k,v in pairs(_G)do e[k]=v end;e._G=e
  local released=opts.released and opts.released[i]
  local root=released and P.RELEASED or (opts.roots and opts.roots[i])
  local function Path(path)
   if root then
    local mapped=root..'/'..(path:gsub('\\','/'))
    local f=io.open(mapped,'rb');if f then f:close();return mapped end
   end
   return path
  end
  e.loadfile=function(path)
   local mapped=Path(path)
   if released then P.VerifyReleased((path:gsub('\\','/')),mapped) end
   local f,why=loadfile(mapped);if f then setfenv(f,e)end;return f,why
  end
  e.io={open=function(path,...)return io.open(Path(path),...)end,lines=function(path,...)return io.lines(Path(path),...)end,write=io.write,read=io.read,stdout=io.stdout,stderr=io.stderr}
  e.dofile=function(path)return assert(e.loadfile(path))()end
  local H=e.dofile('tests/prototype/harness.lua')
  e.UnitName=function()return name,'Ebonhold'end
  local T=e.dofile('tests/prototype/startup_support.lua')
  -- rows may be one size for both peers or one size per peer.
  e.NexusDB=T.Profile(type(rows)=='table' and rows[i] or rows or 5,0)
  if configure then configure(i,e.NexusDB) end
  H.perks.serverBuildSlots=opts.slots and opts.slots[i]
   or {[102]={name='NEXUS-TEST-'..name,verified=false,echoes={{spellId=200001,quality=1,stacks=3}}}}
  T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
  T.Until(H,function()return e.Nexus.StartupStatus().state=='ready' and e.Nexus.BuildCatalog.ManualPreparationStatus().ready end)
  peers[i]={e=e,H=H,T=T,name=name..'-Ebonhold',cursor=#H.sent}
 end
 P.A,P.B,P.trace,P.before,P.hold=peers[1],peers[2],{},nil,nil
 return peers[1],peers[2]
end
function P.Channel(q,text,sender)
 q.H.Fire('CHAT_MSG_CHANNEL',text,sender,nil,'1. '..q.e.Nexus.Sync.ChannelName(),nil,nil,nil,nil,q.e.Nexus.Sync.ChannelName())
end
local function Deliver(p,q)
 while p.cursor<#p.H.sent do
  local packet=p.H.sent[p.cursor+1]
  -- The addon route prefixes the same wire code with its protocol tag.
  local code=packet.text:gsub('||','|'):match('^([^|]+)'):gsub('^P%d+:','')
  -- Optional modelled delivery latency: a test may postpone the next packet of
  -- this sender. Order is kept, nothing is dropped, and the test bounds the delay.
  if P.hold and P.hold(p,q,code) then break end
  p.cursor=p.cursor+1
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
