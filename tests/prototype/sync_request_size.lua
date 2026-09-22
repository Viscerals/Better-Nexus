-- Sync request size (WLRQ). Native test.9028: Sync Now ended queue_rejected /
-- queue=dropped. Cause reproduced offline (2026-09-22): since the release-identity
-- work the request's version field carries build metadata (+internal, +test.N,
-- +dev). With full-width build and DPS bucket hashes and a longer character name
-- the escaped request exceeded the 255-byte chat limit, and the transport refused
-- it as "invalid packet" before sending. Manual and automatic requests share the
-- one builder. Correction: the builder measures the escaped request with the
-- transport's own measure and limit BEFORE admission, uses the full version when
-- it fits, else the plain release version once; a request that still does not
-- fit is refused with its measured length. Sender, hashes, request ID, fields and
-- separators never change.
-- Real TOC, Sync session, transport admission and inbound decoder. Hash values are
-- produced by the production LibraryHash over synthetic records, or are the
-- widest values it can produce ("%x" of a value below 2^31). No network.
local T=dofile('tests/prototype/startup_support.lua')
local H
local LIMIT=255
local function Esc(text)return #text+select(2,text:gsub('|',''))end
local function Upvalue(field)
 local seen={}
 local function search(fn,depth)
  if type(fn)~='function' or seen[fn] or depth>6 then return nil end
  seen[fn]=true
  for i=1,200 do
   local name,value=debug.getupvalue(fn,i)
   if not name then break end
   if type(value)=='table' and type(rawget(value,field))=='function' then return value end
   if type(value)=='function' then local found=search(value,depth+1);if found then return found end end
  end
 end
 for _,fn in pairs(Nexus.Sync)do local found=search(fn,0);if found then return found end end
end
-- The widest DPS/build bucket hash the production format allows, per bucket width.
local function Buckets(widths)
 local parts={}
 for i,w in ipairs(widths)do parts[i]=string.sub('7fffffff',1,w)end
 return table.concat(parts,',')
end
local FULL={8,8,8,8,8,8,8,8}
local state
local function Boot(opts)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 H=dofile('tests/prototype/harness.lua');NexusDB=T.Profile(3,0)
 local name=opts.name or 'PrototypeTester'
 UnitName=function()return name,'Ebonhold' end
 T.Load()
 Nexus.Release.buildLabel=opts.label or 'source'
 Nexus.Release.channel=opts.channel or 'development'
 if opts.version then Nexus.Release.version=opts.version;Nexus.VERSION=opts.version end
 state={build=opts.build,dps=opts.dps or Buckets(FULL),calls={},fullQueue=opts.fullQueue}
 if opts.build then Nexus.BuildHashCache.Delta=function()return state.build end end
 Nexus.DpsCapture.GetSyncHash=function()return state.dps end
 if opts.catalogVersion then Nexus.BuildCatalog.CatalogVersion=function()return opts.catalogVersion end end
 if opts.now then H.now=opts.now end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 local transport=assert(Upvalue('EnqueueControl'),'fixture: the real transport instance')
 local real=transport.EnqueueControl
 transport.EnqueueControl=function(payload,metadata)
  if type(metadata)=='table' and metadata.queueClass=='request' then
   state.calls[#state.calls+1]={payload=payload,requestId=metadata.requestId}
   if state.fullQueue then return false,'sync queue full' end
  end
  return real(payload,metadata)
 end
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end,60000)
 return transport
end
local function Sent()
 local out={}
 for _,p in ipairs(H.sent)do
  local wire=p.text:gsub('^P%d+:','')
  if wire:find('^WLRQ||') then out[#out+1]=wire end
 end
 return out
end
local function Fields(text)local f={};for part in (text..'|'):gmatch('([^|]*)|')do f[#f+1]=part end;return f end
local function Manual()
 local before=#state.calls
 local ok,why=Nexus.Sync.RequestSync()
 H.Advance(2,.1)
 return ok,why,state.calls[before+1],#state.calls-before
end
local function Outcome()return Nexus.Sync.Stats()end
local function LogCount(text)
 local n=0
 for _,row in ipairs(Nexus.Sync.EventLog() or {})do if tostring(row.text or ''):find(text,1,true)then n=n+1 end end
 return n
end
-- The request field that carries the build hash: delta buckets, then the hex catalog token.
local function ExpectedBuild(delta)
 local version=tostring(Nexus.BuildCatalog.CatalogVersion())
 return delta..','..(version:gsub('.',function(c)return string.format('%02x',c:byte())end))
end
-- The full-form request, built independently from its parts.
local function FullForm(name,build,dps,requestId)
 return string.format('WLRQ|%s|%s|%s|%s|%s',name,build,dps,requestId,Nexus.ReleaseIdentity().announce)
end

-- The installed identity: full announced version and the plain release version.
local PUBLIC={label='test.9032-abcdef0',channel='public-test'}
local INTERNAL={label='test.9032-abcdef0',channel='internal'}

-- 1. Reproduction (preserved): full-width hashes, 10-letter main character, internal package.
--    The full request is over the limit; the compact request is sent once.
f=nil
local function Case(name,identity,build,expectForm,extra)
 local opts={name=name,label=identity.label,channel=identity.channel,build=build,now=extra and extra.now}
 for k,v in pairs(extra or {})do opts[k]=v end
 Boot(opts);T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,60000)
 H.Advance(20,.1)                                 -- the automatic login pass has run
 local auto=state.calls[1]
 assert(auto,name..': the automatic login request reached the builder')
 local ok,why,call,count=Manual()
 return auto,ok,why,call,count
end
local fullBuild=Buckets(FULL)
local auto,ok,why,call,count=Case('Valentinew',INTERNAL,fullBuild,'plain')
local id=Nexus.ReleaseIdentity()
local fullText=string.format('WLRQ|Valentinew|%s|%s|%s|%s',Fields(call.payload)[3],Fields(call.payload)[4],call.requestId,id.announce)
assert(id.announce=='1.20.0-beta.1+internal' and Esc(fullText)>LIMIT,'fixture: the full internal request is over the limit ('..Esc(fullText)..')')
for _,c in ipairs({auto,call})do
 local full=FullForm('Valentinew',ExpectedBuild(fullBuild),Buckets(FULL),c.requestId)
 assert(Esc(full)==256,'the independently built full form is 256 bytes: '..Esc(full))
 -- Exactly the full form with only the version field replaced by the plain release version.
 assert(c.payload==full:gsub('|1%.20%.0%-beta%.1%+internal$','|1.20.0-beta.1'),'only the version field differs: '..c.payload)
 assert(Fields(c.payload)[6]=='1.20.0-beta.1' and Esc(c.payload)<=LIMIT,'plain release version, prerelease kept, fits')
end
assert(ok==true and count==1,'manual Sync: one admission ('..tostring(why)..')')
local wire=Sent()
assert(#wire>=2,'both requests were sent on the wire')
for _,w in ipairs(wire)do assert(#w<=LIMIT,'wire length within the chat limit: '..#w)end
local s=Outcome()
assert(s.oversizeDropped==nil or s.oversizeDropped==0,'the transport refused nothing as oversize')
assert(s.requestVersionForm=='plain' and s.requestLength==Esc(call.payload) and s.requestLimit==LIMIT,'diagnostics state the measured length, limit and form')
print(string.format('PASS reproduction 10-letter name, internal: full %d > %d, sent plain %d (automatic and manual)',Esc(fullText),LIMIT,Esc(call.payload)))

-- 2. 12-letter name and the 15-letter harness control, public-test, widest hashes and a long request ID.
-- 12 letters is the longest character name; 9999999 s (115 days) of client uptime gives an 11-digit request clock.
auto,ok,why,call,count=Case('Abcdefghijkl',PUBLIC,fullBuild,'plain',{now=9999999.5})
f=Fields(call.payload)
assert(ok and count==1 and f[2]=='Abcdefghijkl' and f[6]=='1.20.0-beta.1' and Esc(call.payload)<=LIMIT,'12 letters: sent with the plain version: '..call.payload)
assert(#f[5]>=#'c1-9999999500-1000','fixture: a long request ID from a long client uptime: '..f[5])
print(string.format('PASS 12-letter name, public-test, widest hashes, request ID %s: sent plain %d',f[5],Esc(call.payload)))
-- The 15-letter harness name (longer than any real name) is the control: with the ordinary clock the plain
-- request fits; with the 11-digit clock it does not, and it is refused with its measured length (section 6 rule).
auto,ok,why,call,count=Case('PrototypeTester',PUBLIC,fullBuild,'plain')
f=Fields(call.payload)
assert(ok and f[6]=='1.20.0-beta.1' and Esc(call.payload)<=LIMIT,'15-letter control, ordinary clock: sent plain '..Esc(call.payload))
print(string.format('PASS 15-letter control, ordinary clock: sent plain %d',Esc(call.payload)))
Boot({name='PrototypeTester',label=PUBLIC.label,channel=PUBLIC.channel,build=fullBuild,now=9999999.5})
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,60000);H.Advance(20,.1)
assert(#state.calls==0,'15-letter control, 11-digit clock: the automatic request never reached admission')
local st=Outcome()
assert(st.queueOutcome=='oversize' and st.requestLength==256 and st.requestVersionForm=='plain','measured refusal of the compact request: '..tostring(st.requestLength))
-- Review P2: the automatic pass does not retry the same refusal every second.
H.Advance(120,.5)
assert(LogCount('refused before sending')==1 and LogCount('automatic login convergence stopped')==1,'one automatic attempt, then stopped: '..LogCount('refused before sending'))
assert(#state.calls==0,'still nothing admitted')
-- A manual click is one more attempt, refused the same way.
local okManual,whyManual=Nexus.Sync.RequestSync();H.Advance(30,.5)
assert(okManual==false and tostring(whyManual)=='sync request too long (256>255 bytes)' and LogCount('refused before sending')==2 and #state.calls==0,'manual: one measured refusal')
print('PASS 15-letter control, 11-digit clock: compact 256 > 255 refused before admission')

-- 3. Short requests keep the full advertised version (production-generated hashes of a small library).
auto,ok,why,call,count=Case('Bo',PUBLIC,nil,'full')
local f=Fields(call.payload)
assert(ok and f[6]=='1.20.0-beta.1+test.9032' and Outcome().requestVersionForm=='full','a request that fits keeps +test.9032: '..call.payload)
auto,ok,why,call,count=Case('Valentinew',INTERNAL,nil,'full')
assert(Fields(call.payload)[6]=='1.20.0-beta.1+internal','internal full version kept when it fits')
-- Development source (+dev): the same rule. It keeps +dev when the request fits and uses the plain version when not.
auto,ok,why,call,count=Case('Valentinew',{label='source',channel='development'},fullBuild,'full')
local devFull=FullForm('Valentinew',ExpectedBuild(fullBuild),Buckets(FULL),call.requestId)
assert(Nexus.ReleaseIdentity().announce=='1.20.0-beta.1+dev' and Esc(devFull)==251 and call.payload==devFull,'+dev at 251 bytes is kept: '..call.payload)
auto,ok,why,call,count=Case('Abcdefghijkl',{label='source',channel='development'},fullBuild,'plain',{now=9999999.5})
devFull=FullForm('Abcdefghijkl',ExpectedBuild(fullBuild),Buckets(FULL),call.requestId)
assert(Esc(devFull)>LIMIT and call.payload==devFull:gsub('|1%.20%.0%-beta%.1%+dev$','|1.20.0-beta.1'),'+dev over the limit: plain form, other fields identical ('..Esc(devFull)..')')
print('PASS short requests keep the full version; +dev follows the same rule')

-- 4. Exact boundary: 255 escaped bytes keep the full version; 256 use the plain version.
local function Boundary(target)
 -- Choose DPS bucket widths so that the full request is exactly `target` bytes.
 Boot({name='Valentinew',label=PUBLIC.label,channel=PUBLIC.channel,build=fullBuild,dps=Buckets(FULL)})
 T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,60000);H.Advance(20,.1)
 H.now=H.now+60                                 -- past the request cooldown
 local probe=state.calls[#state.calls]
 local pf=Fields(probe.payload)
 local announce=Nexus.ReleaseIdentity().announce
 local widths={8,8,8,8,8,8,8,8}
 local function Full(dps,requestId)return string.format('WLRQ|%s|%s|%s|%s|%s',pf[2],pf[3],dps,requestId,announce)end
 -- The request ID of the next request has the same width as the last one here (same clock digits).
 local base=Esc(Full(Buckets(widths),pf[5]))
 local cut=base-target
 assert(cut>=0 and cut<=8*7,'fixture: the boundary is reachable by bucket width ('..base..')')
 local i=1
 while cut>0 do local take=math.min(cut,widths[i]-1);widths[i]=widths[i]-take;cut=cut-take;i=i+1 end
 state.dps=Buckets(widths)
 local ok2,why2,c2=Manual()
 assert(ok2,'boundary '..target..': '..tostring(why2))
 local fullLen=Esc(Full(state.dps,c2.requestId))
 return fullLen,c2
end
local len255,c255=Boundary(255)
assert(len255==255 and Fields(c255.payload)[6]=='1.20.0-beta.1+test.9032' and Esc(c255.payload)==255,'255 bytes: full version kept ('..len255..')')
local len256,c256=Boundary(256)
assert(len256==256 and Fields(c256.payload)[6]=='1.20.0-beta.1' and Esc(c256.payload)==256-#'+test.9032','256 bytes: plain version ('..Esc(c256.payload)..')')
for _,w in ipairs(Sent())do assert(#w<=LIMIT,'wire within limit')end
print('PASS exact boundary: 255 full, 256 plain ('..Esc(c256.payload)..')')

-- 5. Pipe escaping is counted: the real wire text is exactly the measured length.
for _,w in ipairs(Sent())do
 local unescaped=w:gsub('||','|')
 assert(#w==Esc(unescaped),'wire length equals the escaped measure')
end
print('PASS escaped measure equals the real wire length')

-- 6. A compact request that is still too long is refused before admission, with its measured length;
--    nothing is truncated and nothing is retried in another form.
Boot({name='Valentinew',label=PUBLIC.label,channel=PUBLIC.channel,build=fullBuild,catalogVersion=string.rep('x',40)})
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,60000);H.Advance(20,.1)
local before=#state.calls
H.now=H.now+60
ok,why=Nexus.Sync.RequestSync();H.Advance(2,.1)
assert(ok==false and tostring(why):match('^sync request too long %(%d+>255 bytes%)$'),'measured refusal: '..tostring(why))
assert(#state.calls==before,'nothing reached queue admission')
s=Outcome()
assert(s.queueOutcome=='oversize' and s.terminalReason=='queue_rejected' and s.requestVersionForm=='plain' and s.requestLength>LIMIT and s.requestLimit==LIMIT,'diagnostics: oversize, not "full" or "dropped"')
for _,w in ipairs(Sent())do assert(not w:find('^WLRQ'),'no request on the wire')end
local refusals=LogCount('refused before sending')
H.Advance(120,.5)
assert(LogCount('refused before sending')==refusals,'no automatic retry of the refused request')
print('PASS compact still too long: refused before admission ('..tostring(why)..')')

-- 7. A full queue stays "full": one admission attempt per request, never a second form of the same request.
Boot({name='Valentinew',label=PUBLIC.label,channel=PUBLIC.channel,build=fullBuild,fullQueue=true})
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,60000);H.Advance(20,.1)
H.now=H.now+60
ok,why=Nexus.Sync.RequestSync();H.Advance(2,.1)
s=Outcome()
assert(ok==false and s.queueOutcome=='full' and s.terminalReason=='queue_rejected','queue full stays distinct: '..tostring(why))
local perRequest={}
for _,c in ipairs(state.calls)do
 perRequest[c.requestId]=(perRequest[c.requestId] or 0)+1
 assert(Fields(c.payload)[6]=='1.20.0-beta.1','each attempt uses the one chosen form')
end
for rid,n in pairs(perRequest)do assert(n==1,'request '..rid..' was submitted '..n..' times')end
print('PASS queue full: one attempt per request, no alternate-version retry')

-- 8. The peer decoder accepts the plain-version request; its fields keep their meaning.
Boot({name='Valentinew',label=PUBLIC.label,channel=PUBLIC.channel,build=fullBuild})
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,60000);H.Advance(20,.1)
local sent=assert(state.calls[1],'fixture: a request was built').payload
local text=sent:gsub('^WLRQ|[^|]+|','WLRQ|DecoderPeer|'):gsub('c1%-[%d]+%-[%d]+','c1-424242-4242')
local rejected=Nexus.Sync.Stats().malformedRejected or 0
H.Fire('CHAT_MSG_CHANNEL',text,'DecoderPeer-Ebonhold',nil,'1. '..Nexus.Sync.ChannelName(),nil,nil,nil,nil,Nexus.Sync.ChannelName())
assert((Nexus.Sync.Stats().malformedRejected or 0)==rejected,'the inbound decoder accepts the plain-version request')
local observed
for _,row in ipairs(Nexus.Updates.PeerObservations())do if row.source:find('^DecoderPeer')then observed=row end end
assert(observed and observed.version=='1.20.0-beta.1' and observed.reported==nil,'decoded version is the plain release version; no update notice')
assert(Nexus.Updates.Status().state=='unknown','update status unaffected')
print('PASS peer decoder accepts the plain-version request')

-- 9. The installed identity is unchanged: status label, channel and the full announced version.
id=Nexus.ReleaseIdentity()
assert(id.channel=='public-test' and id.label=='test.9032-abcdef0' and id.announce=='1.20.0-beta.1+test.9032' and id.display=='1.20.0-beta.1 test.9032','the installed identity keeps its full version')
assert(Nexus.RuntimeBuildLabel()=='test.9032-abcdef0')
-- The request cooldown is unchanged.
H.now=H.now+60;assert(Nexus.Sync.RequestSync())
local admitted=#state.calls
local okAgain,whyAgain=Nexus.Sync.RequestSync();H.Advance(1,.1)
assert(tostring(whyAgain)=='already syncing' and #state.calls==admitted,'a second click while syncing admits nothing: '..tostring(okAgain)..' '..tostring(whyAgain))
assert(#H.actions==0,'no gameplay action')
print('PASS sync_request_size')
