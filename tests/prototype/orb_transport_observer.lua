-- 035 part 2a: the passive transport observer for the Orb charge reply (opcode 1220).
--
-- The audited client (the owner's installed bytes only) keeps ONE handler per opcode, and
-- its dispatcher checks the prefix and the framing, not the sender or the channel. So the
-- observer must not register a competing opcode handler. It listens to the same
-- CHAT_MSG_ADDON event in its own frame, which leaves the game's frame, handlers, payloads,
-- order, errors and behavior alone, and it sends nothing.
--
-- Raw observations stay separate from accepted protocol evidence. A reply is QUALIFYING
-- (class Q) only when every one of these holds: the exact prefix, the whisper channel, a
-- sender equal to the player's own exact name (a known identity; no cross-realm or short-name
-- alias), opcode 1220 with a tab and a non-empty body, no segmentation, exactly three fields
-- and canonical bounded integers. A relevant packet that the game's dispatcher would still
-- accept but the observer rejects (class R) may have changed the game's cache; so may an
-- admitted but unqualifiable packet (class A of opcode 1220). Both mark the opcode as
-- tainted until a later qualifying (or, for the other opcodes, admitted) packet.
-- The observer records arrival ordinals and a local lifecycle epoch. It never says a reply
-- belongs to a request: the protocol carries no correlation, so "observed after refresh
-- began" is all that can be said, and a local epoch rejects only local work.
-- Native server sender and channel are NOT TESTED here.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local H,M,A,O=S.Fresh()
local B=Nexus.GameAdapter.Orbs
local ME='PrototypeTester'
local PREFIX='AAM0x9'
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function Send(payload,dist,sender,prefix)
 H.Fire('CHAT_MSG_ADDON',prefix or PREFIX,payload,dist,sender)
end
local function Last(since)
 local list=B.TransportSince(since or 0)
 return list and list[#list] or nil
end

-- A synthetic stand-in for the game's own dispatcher, written to the audited contract (not
-- copied from it): one frame, one handler per opcode that a later registration replaces, a
-- prefix and framing check, bounded segment assembly, errors caught and not rethrown.
local function GameDispatcher()
 local g={handlers={},log={},errors=0,replaced=0}
 function g.on(op,fn) if g.handlers[op] then g.replaced=g.replaced+1 end g.handlers[op]=fn end
 local inflight={}
 local f=CreateFrame('Frame')
 f:RegisterEvent('CHAT_MSG_ADDON')
 f:SetScript('OnEvent',function(_,e,prefix,payload,dist,sender)
  if e~='CHAT_MSG_ADDON' or prefix~=PREFIX or type(payload)~='string' or payload=='' then return end
  local evt,rest=payload:match('^(%d+)\t(.*)$')
  if not evt then return end
  evt=tonumber(evt)
  local mid,idx,tot,slice=rest:match('^@(%x%x%x%x)\t(%x%x%x)/(%x%x%x)\t(.*)$')
  if mid then
   local rec=inflight[evt..':'..mid] or {total=tonumber(tot,16),got=0,parts={}}
   inflight[evt..':'..mid]=rec
   local i=tonumber(idx,16)
   if i>=1 and i<=rec.total and not rec.parts[i] then rec.parts[i]=slice;rec.got=rec.got+1 end
   if rec.got~=rec.total then return end
   inflight[evt..':'..mid]=nil
   rest=table.concat(rec.parts,'',1,rec.total)
  end
  local h=g.handlers[evt]
  if h then
   g.log[#g.log+1]={evt,rest,dist,sender}
   local ok=pcall(h,rest,dist,sender,evt)
   if not ok then g.errors=g.errors+1 end
  end
 end)
 return g
end

-- 1. Passive: the game's frame, handlers, payloads, order and errors are untouched, in
-- either registration order, and the observer sends nothing.
section('1 passive observation',function()
 local function Run(observerFirst)
  local H2,M2,A2,O2=S.Fresh();H=H2
  local B2=Nexus.GameAdapter.Orbs
  local g
  if observerFirst then assert(B2.TransportStart());g=GameDispatcher() else g=GameDispatcher();assert(B2.TransportStart()) end
  local seen={}
  g.on(1220,function(body,dist,sender,evt) seen[#seen+1]='1220:'..body..':'..tostring(dist)..':'..tostring(sender)..':'..tostring(evt) end)
  g.on(16,function() error('game handler boom',0) end)
  g.on(18,function(body) seen[#seen+1]='18:'..body end)
  local sentBefore=#H.sent
  Send('1220\t49,0,0','WHISPER',ME)
  Send('16\tx','WHISPER',ME)
  Send('18\ty','WHISPER',ME)
  Send('1220\t48,-1,1','WHISPER','Other')
  Send('1220\t@ABCD\t001/002\t49,','WHISPER',ME);Send('1220\t@ABCD\t002/002\t0,0','WHISPER',ME)
  return seen,g,#H.sent-sentBefore,B2
 end
 local a,ga,sa=Run(true);local b,gb,sb=Run(false)
 local want={'1220:49,0,0:WHISPER:'..ME..':1220','18:y','1220:48,-1,1:WHISPER:Other:1220','1220:49,0,0:WHISPER:'..ME..':1220'}
 check(table.concat(a,'|')==table.concat(want,'|'),'handlers saw exactly the payloads, in order: '..table.concat(a,'|'))
 check(table.concat(a,'|')==table.concat(b,'|'),'the same with the observer registered after the game frame')
 check(ga.errors==1 and gb.errors==1,'a throwing game handler is isolated: the game keeps its own error behavior')
 check(ga.replaced==0 and gb.replaced==0,'no handler was replaced')
 check(sa==0 and sb==0,'the observer sent nothing')
 check(#ga.log==#gb.log and #ga.log==5,'the game dispatched once per message in both orders')
end)

-- 2. The admission matrix of opcode 1220.
local CASES={
 {'valid',        '1220\t49,0,0','WHISPER',ME,'Q',nil,{charges=49,delta=0,pending=0}},
 {'known positive','1220\t49,0,2','WHISPER',ME,'Q',nil,{charges=49,delta=0,pending=2}},
 {'signed delta', '1220\t48,-1,0','WHISPER',ME,'Q',nil,{charges=48,delta=-1,pending=0}},
 {'zero charges', '1220\t0,0,0','WHISPER',ME,'Q',nil,{charges=0,delta=0,pending=0}},
 {'wrong sender', '1220\t49,0,0','WHISPER','Other','R','sender'},
 {'nil sender',   '1220\t49,0,0','WHISPER',nil,'R','sender'},
 {'empty sender', '1220\t49,0,0','WHISPER','','R','sender'},
 {'cross-realm alias','1220\t49,0,0','WHISPER',ME..'-Ebonhold','R','sender'},
 {'case differs', '1220\t49,0,0','WHISPER',ME:upper(),'R','sender'},
 {'wrong channel','1220\t49,0,0','PARTY',ME,'R','channel'},
 {'guild channel','1220\t49,0,0','GUILD',ME,'R','channel'},
 {'nil channel',  '1220\t49,0,0',nil,ME,'R','channel'},
 {'lower whisper','1220\t49,0,0','whisper',ME,'R','channel'},
 {'third absent', '1220\t49,0','WHISPER',ME,'A','third_absent'},
 {'one field',    '1220\t49','WHISPER',ME,'A','third_absent'},
 {'empty third',  '1220\t49,0,','WHISPER',ME,'A','malformed'},
 {'extra field',  '1220\t49,0,0,1','WHISPER',ME,'A','fields_extra'},
 {'non digit',    '1220\t49,0,x','WHISPER',ME,'A','malformed'},
 {'negative charges','1220\t-1,0,0','WHISPER',ME,'A','malformed'},
 {'negative pending','1220\t49,0,-1','WHISPER',ME,'A','malformed'},
 {'leading zero', '1220\t049,0,0','WHISPER',ME,'A','malformed'},
 {'leading zero 3','1220\t49,0,00','WHISPER',ME,'A','malformed'},
 {'minus zero',   '1220\t49,-0,0','WHISPER',ME,'A','malformed'},
 {'space before', '1220\t 49,0,0','WHISPER',ME,'A','malformed'},
 {'space inside', '1220\t49, 0,0','WHISPER',ME,'A','malformed'},
 {'trailing space','1220\t49,0,0 ','WHISPER',ME,'A','malformed'},
 {'exponent',     '1220\t1e2,0,0','WHISPER',ME,'A','malformed'},
 {'hex',          '1220\t0x31,0,0','WHISPER',ME,'A','malformed'},
 {'decimal',      '1220\t49.5,0,0','WHISPER',ME,'A','malformed'},
 {'seven digits', '1220\t1234567,0,0','WHISPER',ME,'A','range'},
 {'huge',         '1220\t99999999999999999999,0,0','WHISPER',ME,'A','range'},
 {'segmented tiny','1220\t@ABCD\t001/001\t49,0,0','WHISPER',ME,'A','segmented'},
 {'segmented wrong sender','1220\t@ABCD\t001/001\t49,0,0','WHISPER','Other','R','sender'},
}
section('2 admission matrix',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs
 assert(B.TransportStart())
 local g=GameDispatcher();g.on(1220,function() end)
 for _,c in ipairs(CASES) do
  local name,payload,dist,sender,cls,why,want=c[1],c[2],c[3],c[4],c[5],c[6],c[7]
  local before=B.TransportStatus().ord
  Send(payload,dist,sender)
  local list=B.TransportSince(before)
  check(#list==1,name..': one relevant record')
  local r=list[1]
  check(r.op==1220 and r.cls==cls and r.why==why,name..': class '..tostring(r.cls)..'/'..tostring(r.why)..' expected '..cls..'/'..tostring(why))
  if want then check(r.charges==want.charges and r.delta==want.delta and r.pending==want.pending,name..': parsed values') end
  if cls~='Q' then check(r.charges==nil and r.pending==nil,name..': no value is taken from an unqualified packet') end
  check(R.Plain(r,16),name..': the record is plain data')
  for k,v in pairs(r) do check(v~=sender or sender==nil or type(v)~='string','the record keeps no sender text') end
 end
end)

-- 3. Identity: an unknown player identity can never qualify.
section('3 identity',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 local rawName=UnitName
 for _,name in ipairs({false,'','Unknown','unknown'}) do
  UnitName=function() if name==false then return nil end return name end
  local before=B.TransportStatus().ord
  Send('1220\t49,0,0','WHISPER',name==false and nil or name)
  Send('1220\t49,0,0','WHISPER',ME)
  local list=B.TransportSince(before)
  check(#list==2 and list[1].cls=='R' and list[1].why=='identity' and list[2].cls=='R' and list[2].why=='identity',
   'identity '..tostring(name)..': both rejected as identity: '..tostring(list[1] and list[1].why))
 end
 -- the short name that the client reports with a realm: the plain sender does not match
 UnitName=function() return ME..'-Ebonhold' end
 local before=B.TransportStatus().ord
 Send('1220\t49,0,0','WHISPER',ME)
 check(Last(before).cls=='R' and Last(before).why=='sender','a short-name sender is no alias for a name with a realm')
 UnitName=rawName
 before=B.TransportStatus().ord
 Send('1220\t49,0,0','WHISPER',ME)
 check(Last(before).cls=='Q','with a known identity the same packet qualifies')
end)

-- 4. What is not a reply is not counted as one.
section('4 echo, framing and prefix',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 local s0=B.TransportStatus()
 Send('1220','WHISPER',ME)                       -- the client's own empty request, as an echo
 Send('1220\t','WHISPER',ME)                     -- an empty body
 Send('hello','WHISPER',ME)                      -- not the game's framing
 Send('1220\t49,0,0','WHISPER',ME,'AAM0x8')      -- another prefix
 Send('1220\t49,0,0','WHISPER',ME,'')            -- no prefix
 Send(nil,'WHISPER',ME);Send('','WHISPER',ME);Send(1220,'WHISPER',ME)
 Send('1221\t3|410002','WHISPER',ME)             -- an opcode the observer does not follow
 local s1=B.TransportStatus()
 check(s1.ord==s0.ord and s1.counts.Q==0 and s1.counts.A==0 and s1.counts.R==0,'none of these is a relevant record')
 check(s1.counts.echo==1 and s1.counts.drop>=2 and s1.counts.other==1,'they are counted apart: echo '..s1.counts.echo..' drop '..s1.counts.drop..' other '..s1.counts.other)
end)

-- 5. The other relevant packets: admitted or rejected, never parsed.
section('5 other opcodes',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 for _,op in ipairs({16,18,1000,540,542}) do
  local b0=B.TransportStatus().ord
  Send(op..'\tpayload text','WHISPER',ME)
  local ok=Last(b0)
  check(ok.op==op and ok.cls=='A' and ok.why==nil and ok.charges==nil,'op '..op..' admitted')
  Send(op..'\t','WHISPER',ME)
  check(Last(b0).cls=='A','op '..op..' with an empty body is still an arrival the game acts on')
  local b1=B.TransportStatus().ord
  Send(op..'\tforged','WHISPER','Other')
  local bad=Last(b1)
  check(bad.cls=='R' and bad.why=='sender','op '..op..' from another sender is rejected')
  local st=B.TransportStatus()
  check(st.bad[op]==bad.ord,'op '..op..' is tainted at that ordinal')
  Send(op..'\tgood','WHISPER',ME)
  st=B.TransportStatus()
  check(st.good[op]>st.bad[op],'op '..op..': a later admitted packet replaces what the game cached')
 end
end)

-- 6. Taint of the charge reply, including an admitted but unqualified packet.
section('6 taint of 1220',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 Send('1220\t49,0,0','WHISPER',ME)
 local st=B.TransportStatus()
 check(st.good[1220]==1 and st.bad[1220]==nil,'a qualifying reply is good')
 Send('1220\t49,0','WHISPER',ME)
 st=B.TransportStatus()
 check(st.bad[1220]==2,'an admitted reply without the third field is tainted: the game keeps its old count')
 Send('1220\t49,0,0','WHISPER','Other')
 check(B.TransportStatus().bad[1220]==3,'a rejected sender is tainted')
 Send('1220\t49,0,0','WHISPER',ME)
 st=B.TransportStatus()
 check(st.good[1220]==4 and st.bad[1220]==3,'only a later qualifying reply clears it')
 -- an empty body changes nothing in the game and taints nothing
 Send('1220\t','WHISPER','Other')
 check(B.TransportStatus().bad[1220]==3,'an empty body from a rejected sender taints nothing')
end)

-- 7. Epochs and ordinals: a loading screen is a local transition, nothing more.
section('7 epoch',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 local e0=B.TransportStatus().epoch
 Send('1220\t49,0,0','WHISPER',ME)
 H.Fire('PLAYER_LEAVING_WORLD')
 local e1=B.TransportStatus().epoch
 Send('1220\t49,0,0','WHISPER',ME)
 H.Fire('PLAYER_ENTERING_WORLD')
 local e2=B.TransportStatus().epoch
 Send('1220\t49,0,0','WHISPER',ME)
 check(e1==e0+1 and e2==e1+1,'each leave and enter is one epoch step')
 local list=B.TransportSince(0)
 check(#list==3 and list[1].epoch==e0 and list[2].epoch==e1 and list[3].epoch==e2,'each record carries the epoch in which it arrived')
 check(list[1].ord<list[2].ord and list[2].ord<list[3].ord,'ordinals follow arrival order')
end)

-- 8. Bounded ring and counters; an old ordinal that the ring no longer covers is refused.
section('8 bounds',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 Send('1220\t49,0,0','WHISPER',ME)
 for i=1,300 do Send('1220\t49,0,0','WHISPER',ME) end
 local list,why=B.TransportSince(0)
 check(list==nil and why=='overflow','a request for records older than the ring refuses')
 local top=B.TransportStatus().ord
 list=B.TransportSince(top-10)
 check(#list==10,'the recent records are returned')
 check(#(B.TransportSince(top-48) or {})<=48,'the ring is bounded')
 check(B.TransportStatus().counts.Q==301,'the counters keep counting')
 check(B.TransportStatus().retained==48,'and the ring holds 48 records, not 301: '..tostring(B.TransportStatus().retained))
 check(R.Plain(B.TransportStatus(),24),'the status holds only numbers, booleans and short names')
end)

-- 9. The status carries no identity.
section('9 privacy',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 Send('1220\t49,0,0','WHISPER',ME);Send('1220\t49,0,0','WHISPER','SecretPlayer-Realm')
 local function Scan(t,path)
  for k,v in pairs(t) do
   check(tostring(k)~=ME and tostring(k)~='SecretPlayer-Realm','no identity as a key')
   if type(v)=='string' then check(not v:find(ME,1,true) and not v:find('SecretPlayer',1,true),'no identity in '..path..tostring(k)) end
   if type(v)=='table' then Scan(v,path..tostring(k)..'.') end
  end
 end
 Scan(B.TransportStatus(),'status.');Scan(B.TransportSince(0),'since.')
end)

-- 10. A request is marked with the arrival ordinal at that moment, and is never a claim of
-- correlation. Starting twice is one observer.
section('10 request mark and start',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs
 check(B.TransportStatus().started==false,'not started before it is asked')
 check(B.TransportStart()==true and B.TransportStart()==true,'start is idempotent')
 local frames=0;for _,f in ipairs(H.frames) do if f.events and f.events.CHAT_MSG_ADDON then frames=frames+1 end end
 local before=frames
 B.TransportStart()
 frames=0;for _,f in ipairs(H.frames) do if f.events and f.events.CHAT_MSG_ADDON then frames=frames+1 end end
 check(frames==before,'a second start adds no frame')
 Send('1220\t49,0,0','WHISPER',ME)
 local ok,why,mark=B.RequestRefresh()
 check(ok==true and type(mark)=='table' and mark.ord==1 and mark.n==1 and mark.epoch==B.TransportStatus().epoch,'RequestRefresh marks the ordinal at that moment')
 check(B.TransportStatus().requests==1 and B.TransportStatus().reqOrd==1,'and the status shows it')
 check(H.orbs.requests==1,'it asked the game once (the existing read-only call)')
end)

-- 11. Segmented messages of the other opcodes: a fragment replaces nothing. The game calls its
-- handler only when every fragment has arrived, so only a COMPLETE message clears a taint; an
-- assembly that includes a rejected fragment taints again; the tracking is bounded.
section('11 segmented messages',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 for _,op in ipairs({16,18,540,542,1000}) do
  local mid=string.format('%04X',op)
  Send(op..'\tFORGED','WHISPER','Other')
  local st=B.TransportStatus()
  local forged=st.bad[op]
  check(forged~=nil,'op '..op..': a forged packet taints')
  local ord=st.ord
  Send(op..'\t@'..mid..'\t001/003\tone','WHISPER',ME)
  Send(op..'\t@'..mid..'\t002/003\ttwo','WHISPER',ME)
  st=B.TransportStatus()
  check(st.ord==ord and (st.good[op] or 0)<forged and st.bad[op]==forged,'op '..op..': fragments of an incomplete message clear nothing and make no record')
  Send(op..'\t@'..mid..'\t002/003\ttwo','WHISPER',ME) -- a duplicate fragment counts once
  check(B.TransportStatus().ord==ord,'op '..op..': a duplicate fragment completes nothing')
  Send(op..'\t@'..mid..'\t003/003\tthree','WHISPER',ME)
  st=B.TransportStatus()
  local last=Last(ord)
  check(st.ord==ord+1 and last.op==op and last.cls=='A' and last.why==nil and last.seg==true,'op '..op..': the complete message is one admitted record')
  check(st.good[op]>st.bad[op],'op '..op..': the complete message replaces what the game cached')
 end
 -- a rejected fragment inside an assembly: the game completes a mixed message
 local ord=B.TransportStatus().ord
 Send('18\t@AAAA\t001/002\tgood','WHISPER',ME)
 Send('18\t@AAAA\t002/002\tforged','WHISPER','Other')
 local st=B.TransportStatus()
 check(st.bad[18]>(st.good[18] or 0) and Last(ord).cls=='R','a rejected fragment taints at once')
 Send('18\t@BBBB\t001/002\tforged','WHISPER','Other')
 local o2=B.TransportStatus().ord
 Send('18\t@BBBB\t002/002\tgood','WHISPER',ME)
 local last=Last(o2)
 check(last and last.cls=='R' and last.why=='mixed' and B.TransportStatus().bad[18]==last.ord,'a message completed with a rejected fragment is rejected and taints')
 -- bounds: more open assemblies than the table holds, and a fragment outside its assembly (a total of zero)
 for i=1,20 do Send('16\t@'..string.format('%04X',0x100+i)..'\t001/002\tx','WHISPER',ME) end
 local before=B.TransportStatus().ord
 Send('16\t@0101\t002/002\ty','WHISPER',ME)  -- its assembly was forgotten: nothing completes
 check(B.TransportStatus().ord==before,'the assembly table is bounded; an evicted assembly never completes')
 local o3=B.TransportStatus().ord
 Send('540\t@CCCC\t001/000\tz','WHISPER',ME)
 local rec=Last(o3)
 check(rec and rec.cls=='A' and rec.why=='range' and B.TransportStatus().bad[540]==rec.ord,'a fragment outside its assembly is an unqualified admitted packet and taints')
 -- opcode 1220 stays unqualified
 local o4=B.TransportStatus().ord
 Send('1220\t@DDDD\t001/001\t49,0,0','WHISPER',ME)
 check(Last(o4).cls=='A' and Last(o4).why=='segmented','a segmented charge reply is never a qualifying reply')
end)

-- 12. The opcode text is canonical; a localized unknown identity does not qualify.
section('12 opcode text and identity',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 local b0=B.TransportStatus().ord
 Send('01220\t49,0,0','WHISPER',ME)
 local r=Last(b0)
 check(r.op==1220 and r.cls=='A' and r.why=='malformed','a leading-zero opcode reaches the game but is never a qualifying reply')
 check(B.TransportStatus().bad[1220]==r.ord,'and it taints')
 local rawName,rawUnknown=UnitName,UNKNOWNOBJECT
 UNKNOWNOBJECT='Unbekannt'
 UnitName=function() return 'Unbekannt' end
 local b1=B.TransportStatus().ord
 Send('1220\t49,0,0','WHISPER','Unbekannt')
 check(Last(b1).cls=='R' and Last(b1).why=='identity','the client\'s own word for an unknown unit is an unknown identity')
 UnitName=rawName;UNKNOWNOBJECT=rawUnknown
end)

-- 13. A failing identity read is an unknown identity, never a silent miss.
section('13 identity read throws',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 local rawName=UnitName
 UnitName=function() error('synthetic identity failure',0) end
 local b0=B.TransportStatus().ord
 Send('1220\t49,0,7','WHISPER','Other')
 UnitName=rawName
 local r=Last(b0)
 check(r and r.cls=='R' and r.why=='identity' and B.TransportStatus().bad[1220]==r.ord,'recorded as rejected for identity, and tainted')
end)

-- 14. A refresh that was not sent has no mark.
section('14 failed request',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs
 local orb=ProjectEbonhold.OrbService
 local raw=orb.RequestCharges
 orb.RequestCharges=function() error('synthetic send failure',0) end
 local ok,why,mark=B.RequestRefresh()
 orb.RequestCharges=raw
 check(ok==false and mark==nil and B.TransportStatus().requests==0 and B.TransportStatus().reqOrd==0,'no request, no mark, no count')
 local ok2,_,mark2=B.RequestRefresh()
 check(ok2==true and mark2~=nil and B.TransportStatus().requests==1,'the next one is marked')
end)

-- 15. A large legitimate message is tracked up to the format limit (three hex digits: 4095
-- fragments); a taint it clears is not permanent. The assembly follows the FIRST fragment's total
-- as the game does (a forged fragment is stored by the game, so it counts here), and an assembly
-- the game would have expired (15 s after its first fragment) never completes.
section('15 large, forged and expired messages',function()
 local H2=S.Fresh();H=H2
 B=Nexus.GameAdapter.Orbs;assert(B.TransportStart())
 local function Frag(op,mid,i,n,sender,text)
  Send(op..'\t@'..mid..'\t'..string.format('%03X',i)..'/'..string.format('%03X',n)..'\t'..(text or 'x'),'WHISPER',sender or ME)
 end
 for _,n in ipairs({65,200,4095}) do
  Send('18\tFORGED','WHISPER','Other')
  local forged=B.TransportStatus().bad[18]
  local ord=B.TransportStatus().ord
  for i=1,n do Frag(18,string.format('%04X',n),i,n) end
  local st=B.TransportStatus()
  check(st.ord==ord+1 and Last(ord).cls=='A' and Last(ord).seg==true and st.good[18]>forged,n..' fragments: one complete admitted record that clears the taint')
 end
 check(B.TransportStatus().bad[18]<B.TransportStatus().good[18],'the opcode is clean afterwards')
 -- a fragment that claims its own smaller total: the game still stores it under the first fragment's total
 Frag(18,'AAAA',1,3)
 Send('18\t@AAAA\t003/002\tFORGED','WHISPER','Other')
 local o1=B.TransportStatus().ord
 Frag(18,'AAAA',2,3)
 local rec=Last(o1)
 check(rec and rec.cls=='R' and rec.why=='mixed','the forged fragment counts toward the assembly: the completed message is mixed')
 -- an assembly older than 15 s is dropped, as the game drops it
 local o2=B.TransportStatus().ord
 Frag(16,'BBBB',1,2)
 H.now=H.now+16
 Frag(16,'BBBB',2,2)
 check(B.TransportStatus().ord==o2,'the late last fragment completes nothing: its assembly expired')
 Frag(16,'BBBB',1,2)
 Frag(16,'BBBB',2,2)
 check(B.TransportStatus().ord==o2+1,'a message sent again within the time completes')
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb transport observer: passive, strict admission, taint and epochs; no competing handler, nothing sent checks='..checks)
