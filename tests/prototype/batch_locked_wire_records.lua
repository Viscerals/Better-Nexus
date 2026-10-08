-- Group 3 supplement (S3-C-05 wire seam; root audit question 3): occupied
-- locked records versus held copies on the existing peer wire, with the
-- existing formats, roles, counts and identity unchanged.
-- Native contract (static data, never executed): one locked record keeps its
-- full stack (perks_service.lua 308-315) and the live capacity is a dynamic
-- positive server value (echo_journal.lua 4533-4535), so 79 ordinary copies
-- plus five locked records holding 1,1,1,3,1 copies (7 locked, 86 total) and
-- 79 ordinary plus seven single locked records are representable loadouts.
-- core/SyncProtocol.lua WithinSemanticEnvelope sums locked COPIES against six
-- (CompactDecode, ValidateNetworkPayload for inline slot-4 rows and for a
-- stated lv=1 set) and NetworkLockedRoles caps a stated set at six rows;
-- core/DpsCapture.lua ReceiveRecord holds a received DPS record to the same
-- copy envelope (CaptureEnvelopeVerdict).
-- EXPECT (fails at 8c):
--   I5/S5 the actual compact encoder -> JSON -> the actual network validator
--         (and the compact decoder) accept 79 ordinary + five locked records
--         holding 7 copies, inline (slot 4) and as a stated set (lv=1/le),
--         with every row, role, copy count and identity field kept;
--   I7/S7 the same for 79 ordinary + seven single locked records (the
--         durable envelopes admit that loadout, batch_locked_units_envelopes);
--   D5    the actual WLD2 receive path stores a verified owner's DPS record of
--         79 ordinary + five locked records holding 7 copies, rows and owner
--         kept, and the actual relay sender serializes it with the same lk
--         rows, stopping at an empty response budget (nothing enqueued).
-- GUARD (holds at 8c): 79 ordinary + six single locked records pass every
-- seam above (DPS stored and serialized the same way); 80 ordinary copies,
-- a row holding 121 copies (the existing 120-copy per-row ceiling), a stated
-- set of 257 rows (the existing 256-row parser ceiling), a DPS locked list of
-- 121 rows (the existing 120-entry DPS list ceiling), a zero count, a slot-4
-- value other than 1, a stated row with a fourth value, a stated set mixed
-- with inline locked rows, rows without lv, disagreeing e/echoes or
-- lk/lockedEchoes aliases, an ownerVerified/isMine claim, an owner key of
-- another player and a mismatched transport sender all stay refused; no DPS
-- record (WLD2) is sent and no game action is made.
-- OLDER PEERS (documented, GUARD on the verbatim released test.9049
-- SyncProtocol fixture with its own 79/6/85 limits): an older peer refuses
-- inline locked copies above six and ignores a stated lv=1 set (it keeps the
-- ordinary targets only). That compatibility limit is not a reason to keep a
-- contradictory local copy cap; accepting the representation is not a claim
-- that the server permits 86 combined copies.
-- SETUP: two isolated runtimes of sync_pair_support (no released peer
-- booted); the protocol instance is built by the actual factory with the
-- limits core/Sync.lua passes. Synthetic identities and packets only.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_wire_records')
local printable=B.printable
local P=dofile('tests/prototype/sync_pair_support.lua')
P.Boot({'Receiver','Idle'},0,nil,{realm='TestRealm'})
local peer=P.A
local N=peer.e.Nexus
C.setup(N.StartupStatus().state=='ready','the receiving peer reached ready')
local Factory=N.SyncInternals and N.SyncInternals.Protocol
C.setup(type(Factory)=='table' and type(Factory.New)=='function','the actual SyncProtocol factory is loaded')

-- The options core/Sync.lua builds its protocol with (MAX_* of core/Sync.lua).
local function Options(extra)
 local o={limits={maxTransferIdBytes=160,maxHashBytes=192,maxVersionBytes=32,maxBuildIdBytes=96,
   maxBuildEchoes=256,maxRequestIdBytes=96,bucketCount=8,maxWireFields=8},
  parseVersion=function(v) return N.Version.Parse(v) end,
  ownerKeyMatchesAuthor=N.Identity.OwnerKeyMatchesAuthor,
  validText=N.Identity.ValidWireText,validPeerName=N.Identity.ValidPlayer,
  canonicalOwnerKey=N.Identity.CanonicalOwnerKey,
  isSafeTree=function(v,d,n) return N.Codec.IsSafeTree(v,d,n) end}
 for k,v in pairs(extra or {}) do o[k]=v end
 return o
end
local Pr=Factory.New(Options())
-- The verbatim released protocol, loaded into its own table (nothing global
-- is replaced), with the released LoadoutEvidence limits (79/6/85).
local function Released()
 local f=assert(loadfile(P.RELEASED..'/core/SyncProtocol.lua'))
 local env=setmetatable({Nexus={SyncInternals={}}},{__index=peer.e})
 setfenv(f,env);f()
 return env.Nexus.SyncInternals.Protocol.New(Options({semanticLimits={ordinary=79,locked=6,total=85}}))
end

local AUTHOR='Other-Ebonhold'
local OWNER=N.Identity.OwnerKey('Other','Ebonhold')
local serial=0
-- A build of `ordinary` single ordinary copies and locked rows holding
-- `stacks`; inline: slot-4 rows in echoes, else a stated lv=1 set.
local function Build(ordinary,stacks,inline)
 serial=serial+1
 local echoes,roles={},{}
 for i=1,ordinary do echoes[#echoes+1]={spellId=200000+i,quality=i%4,stacks=1} end
 for i,s in ipairs(stacks or {}) do
  local row={spellId=200100+i,quality=i%4,stacks=s}
  if inline then row.locked=true;echoes[#echoes+1]=row else roles[#roles+1]=row end
 end
 return {id='wire-records-'..serial,title='Synthetic wire records '..serial,author=AUTHOR,ownerKey=OWNER,
  class='MAGE',lastModified=1700000000+serial,echoes=echoes},(not inline) and roles or nil
end
-- The compact payload as it crosses the wire: the actual encoder, an optional
-- edit of the compact object, then the actual JSON codec.
local function Wire(build,roles,edit)
 local payload=Pr.CompactEncode(build,roles)
 if edit then edit(payload) end
 return N.Codec.JSONDecode(N.Codec.JSONEncode(payload))
end
local function Split(rows)
 local ordinary,locked,stacks=0,0,{}
 for _,r in ipairs(rows or {}) do
  if r.locked then locked=locked+r.stacks;stacks[#stacks+1]=r.stacks else ordinary=ordinary+r.stacks end
 end
 table.sort(stacks)
 return ordinary,locked,table.concat(stacks,',')
end
local function SameIdentity(d,b)
 return d~=nil and d.id==b.id and d.title==b.title and d.author==AUTHOR and d.class=='MAGE'
  and d.ownerKey==N.Identity.CanonicalOwnerKey(OWNER) and d.lastModified==b.lastModified
end
local function Inline(label,ordinary,stacks,want,expectOrGuard)
 local b=Build(ordinary,stacks,true)
 local w=Wire(b)
 local d,raw=Pr.ValidateNetworkPayload(w),Pr.CompactDecode(w)
 local o,l,s=Split(d and d.echoes)
 print('OBSERVED',label,'validated='..printable(d~=nil),'decoded='..printable(raw~=nil),'ordinary='..o,'locked='..l,'stacks='..s)
 expectOrGuard(d~=nil and o==ordinary and s==want and SameIdentity(d,b),
  label..': the network validator keeps every row, role, copy and identity field (inline slot 4)',s)
 expectOrGuard(raw~=nil and select(3,Split(raw.echoes))==want,label..': the compact decoder accepts it too')
end
local function Stated(label,ordinary,stacks,want,expectOrGuard)
 local b,roles=Build(ordinary,stacks,false)
 local w=Wire(b,roles)
 C.setup(w.lv==1 and type(w.le)=='table' and #w.le==#stacks,label..': the actual encoder states the locked set (lv=1)')
 local d=Pr.ValidateNetworkPayload(w)
 local o,l=Split(d and d.echoes)
 local _,rl,rs=Split(d and d.lockedRoles)
 print('OBSERVED',label,'validated='..printable(d~=nil),'ordinary='..o,'inline locked='..l,'stated='..rs)
 expectOrGuard(d~=nil and o==ordinary and l==0 and rs==want and SameIdentity(d,b),
  label..': the stated set keeps every row, copy and identity field',rs)
end
local function Sorted(list)
 local t={};for _,n in ipairs(list) do t[#t+1]=n end;table.sort(t);return table.concat(t,',')
end
local FIVE,SIX={1,1,1,3,1},{1,1,1,1,1,1}
local SEVEN={1,1,1,1,1,1,1}

C.scenario('I5/S5 79 ordinary + five records holding 7',function()
 Inline('I5',79,FIVE,Sorted(FIVE),C.expect)
 Stated('S5',79,FIVE,Sorted(FIVE),C.expect)
end)
C.scenario('I7/S7 79 ordinary + seven single records',function()
 Inline('I7',79,SEVEN,Sorted(SEVEN),C.expect)
 Stated('S7',79,SEVEN,Sorted(SEVEN),C.expect)
end)
C.scenario('G6 positive control: 79 ordinary + six single records',function()
 Inline('I6',79,SIX,Sorted(SIX),C.guard)
 Stated('S6',79,SIX,Sorted(SIX),C.guard)
end)

C.scenario('X refusals on the compact wire',function()
 local function Refused(label,w)
  C.guard(Pr.ValidateNetworkPayload(w)==nil,'X: '..label..' stays refused')
 end
 local b=Build(80,{},true)
 C.guard(Pr.ValidateNetworkPayload(Wire(b))==nil and Pr.CompactDecode(Wire(b))==nil,'X: 80 ordinary copies stay refused')
 Refused('an inline locked row holding 121 copies',Wire(Build(79,{1,1,121,1},true)))
 local sb,sr=Build(79,{1,1,121,1},false)
 Refused('a stated locked row holding 121 copies',Wire(sb,sr))
 local many={};for i=1,257 do many[i]=1 end
 sb,sr=Build(1,many,false)
 Refused('a stated set of 257 rows (parser ceiling)',Wire(sb,sr))
 Refused('a slot-4 value other than 1',Wire(Build(79,FIVE,true),nil,function(p) p.e[80][4]=2 end))
 sb,sr=Build(79,FIVE,false)
 Refused('a stated row with a fourth value',Wire(sb,sr,function(p) p.le[1][4]=1 end))
 Refused('a stated set mixed with an inline locked row',Wire(Build(79,FIVE,true),nil,function(p) p.lv=1;p.le={{200201,1,1}} end))
 sb,sr=Build(79,FIVE,false)
 Refused('stated rows without lv',Wire(sb,sr,function(p) p.lv=nil end))
 Refused('disagreeing e/echoes aliases',Wire(Build(79,FIVE,true),nil,function(p)
  p.echoes={};for i,r in ipairs(p.e) do p.echoes[i]={r[1],r[2],r[3],r[4]} end
  p.echoes[83][3]=2
 end))
 Refused('an ownerVerified claim',Wire(Build(79,FIVE,true),nil,function(p) p.ownerVerified=true end))
 Refused('an isMine claim',Wire(Build(79,FIVE,true),nil,function(p) p.isMine=true end))
 Refused('an owner key of another player',Wire(Build(79,FIVE,true),nil,function(p) p.o=N.Identity.OwnerKey('Someone','Ebonhold') end))
end)

C.scenario('O older peers (verbatim released protocol)',function()
 local ok,Rel=pcall(Released)
 C.setup(ok and type(Rel)=='table' and type(Rel.ValidateNetworkPayload)=='function','O: the released protocol fixture loads',Rel)
 if not ok then return end
 local d=Rel.ValidateNetworkPayload(Wire(Build(79,FIVE,true)))
 print('OBSERVED','O released inline 79+five validated='..printable(d~=nil))
 C.guard(d==nil,'O: an older peer refuses inline locked copies above six (documented compatibility limit)')
 local sb,sr=Build(79,FIVE,false)
 d=Rel.ValidateNetworkPayload(Wire(sb,sr))
 C.guard(d~=nil and #d.echoes==79 and d.lockedRoles==nil,'O: an older peer ignores the stated set and keeps the ordinary targets only')
 d=Rel.ValidateNetworkPayload(Wire(Build(79,SIX,true)))
 C.guard(d~=nil,'O: an older peer accepts 79 ordinary + six single inline locked records')
end)

-- The actual WLD2 receive path (as sync_dps_native_channel_owner.lua): a
-- verified owner "Origin" on the native realm channel.
local function WLD2() local n=0;for _,s in ipairs(peer.H.sent) do if tostring(s.text or ''):gsub('||','|'):find('WLD2|',1,true) then n=n+1 end end;return n end
local sent0,actions0=WLD2(),#peer.H.actions
local stamp=peer.e.time()-2000
local function DpsPayload(category,score,ordinary,counts,edit)
 stamp=stamp+10
 local echoes,locked={},nil
 for i=1,ordinary do echoes[i]={spellId=200000+i,count=1} end
 if counts then locked={};for i,n in ipairs(counts) do locked[i]={spellId=200100+i,count=n} end end
 local p={v=7,p='Origin',o='origin@testrealm',r='TestRealm',k='MAGE',l=80,c=category,d=score,u=180,t=stamp,
  e=echoes,f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),lk=locked}
 if edit then edit(p) end
 return p
end
local function Deliver(p,actual)
 local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(p))
 local chunks={}
 for i=1,#encoded,200 do chunks[#chunks+1]=encoded:sub(i,i+199) end
 for i,chunk in ipairs(chunks) do
  P.Channel(peer,string.format('WLD2|Origin|Origin:%d:%d|%d/%d|%s',p.t,p.d,i,#chunks,chunk),actual or 'Origin')
 end
 for _=1,300 do peer.H.Advance(.05,.05) end
 return N.DpsCapture.GetCharacterBest(p.c,'Origin','origin@testrealm')
end
local function LockedCounts(rows)
 local t={};for _,r in ipairs(rows or {}) do t[#t+1]=tonumber(r.count or r.stacks) or 0 end
 table.sort(t);return table.concat(t,','),#(rows or {})
end
-- The actual relay sender for a stored verified record, observed with an
-- empty response budget: every check runs and nothing is enqueued.
local function Relay(row,category)
 local record=N.DpsCapture.MaterializeRecord(row)
 record.category=category;record._originVerified=true
 local ok,sent,why,prepared=pcall(N.Sync.BroadcastDpsRecord,record,nil,true,
  {requester='Requester-TestRealm',requestId='c1-wire-records-'..category,bucket=N.DpsCapture.SyncBucket(category,'Origin')},{})
 local payload=ok and type(prepared)=='table' and prepared.payload or nil
 print('OBSERVED','relay',category,'ok='..printable(ok),'sent='..printable(sent),'why='..printable(why),
  'lk='..printable(payload and LockedCounts(payload.lk)))
 return ok and sent==false and why=='response wire budget' and payload or nil
end
local function Stored(label,row,score,want,rows,expectOrGuard)
 local record=row and N.DpsCapture.MaterializeRecord(row)
 local counts,n=LockedCounts(record and record.lockedEchoes)
 print('OBSERVED',label,'stored dps='..printable(row and row.dps),'locked='..printable(counts),
  'owner='..printable(row and N.DpsCapture.VerifiedOwnerKey(row)))
 expectOrGuard(row~=nil and row.dps==score and counts==want and n==rows and #record.echoes==79
  and N.DpsCapture.VerifiedOwnerKey(row)=='origin@testrealm',
  label..': the actual receive path stores the verified record with every locked row and copy',counts)
 return row
end

C.scenario('D6 positive control: DPS 79 ordinary + six single records',function()
 local p=DpsPayload('dummy',47000,79,SIX)
 local row=Stored('D6',Deliver(p),47000,Sorted(SIX),6,C.guard)
 local payload=row and Relay(row,'dummy')
 C.guard(payload~=nil and LockedCounts(payload.lk)==Sorted(SIX) and #payload.e==79 and payload.f==p.f,
  'D6: the actual relay sender serializes the same rows and stops at the empty budget')
end)

C.scenario('D5 DPS 79 ordinary + five records holding 7',function()
 local p=DpsPayload('lk',46000,79,FIVE)
 local row=Stored('D5',Deliver(p),46000,Sorted(FIVE),5,C.expect)
 local payload=row and Relay(row,'lk')
 C.expect(payload~=nil and LockedCounts(payload.lk)==Sorted(FIVE) and #payload.e==79 and payload.f==p.f
  and N.Identity.CanonicalOwnerKey(payload.o)=='origin@testrealm',
  'D5: the actual relay sender serializes the same five rows and seven copies, same identity')
end)

C.scenario('DX refusals on the DPS wire',function()
 local function Kept(label,p,actual)
  local row=Deliver(p,actual)
  C.guard(row~=nil and row.dps==47000 and N.DpsCapture.VerifiedOwnerKey(row)=='origin@testrealm',
   'DX: '..label..' is refused; the stored record is unchanged',row and row.dps)
 end
 Kept('80 ordinary copies',DpsPayload('dummy',49100,80,{1}))
 Kept('a locked row holding 121 copies',DpsPayload('dummy',49200,79,{1,1,121}))
 Kept('a zero locked count',DpsPayload('dummy',49300,79,{1,0,1}))
 local many={};for i=1,121 do many[i]=1 end
 Kept('a locked list of 121 rows',DpsPayload('dummy',49400,1,many))
 Kept('disagreeing lk/lockedEchoes aliases',DpsPayload('dummy',49500,79,FIVE,function(p)
  p.lockedEchoes={};for i,r in ipairs(p.lk) do p.lockedEchoes[i]={spellId=r.spellId,count=r.count} end
  p.lockedEchoes[4].count=2
 end))
 Kept('an ownerVerified claim',DpsPayload('dummy',49600,79,FIVE,function(p) p.ownerVerified=true end))
 Kept('an owner key of another player',DpsPayload('dummy',49700,79,FIVE,function(p) p.o='impostor@testrealm' end))
 Kept('a mismatched transport sender',DpsPayload('dummy',49800,79,FIVE),'Impostor-TestRealm')
end)

C.guard(WLD2()==sent0,'no DPS record (WLD2) was sent by the receiving peer',WLD2()-sent0)
C.guard(#peer.H.actions==actions0,'no game action',#peer.H.actions-actions0)
C.finish('(the wire carries occupied records with every copy; formats, refusals and authority unchanged)')
