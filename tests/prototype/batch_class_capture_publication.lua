-- Group 1 (ROOT-S4-CLASS): the current player's class through the actual DPS
-- capture and its publication check. core/DpsCapture.lua (CommitSession)
-- reads the class as select(2, UnitClass and UnitClass("player")); `and`
-- keeps only the first return (the localized name), so the token is lost and
-- every capture stores "UNKNOWN", which the actual Sync egress refuses.
-- EXPECT (fails at 8c): with UnitClass returning "Mage","MAGE",8 the actual
-- capture stores class MAGE, and the record the capture hands to the actual
-- Sync.BroadcastDpsRecord carries MAGE and is not refused as schema.
-- GUARD (holds at 8c): a missing UnitClass, a missing token and an
-- unrecognised token stay conservative: "UNKNOWN" is stored and the egress
-- refuses it as schema. Each capture keeps its actual score, fingerprint,
-- canonical owner and verified flag; no game action; no DPS record (WLD2) is
-- enqueued or sent.
-- SETUP: real TOC start-up, synthetic Details! combat and training-dummy
-- target, four captures of increasing DPS above the score floor (the floor is
-- Group 10 and not touched here).
-- Boundary: Nexus.Sync.BroadcastDpsRecord is observed through a spy that runs
-- the REAL function with an empty response budget: every schema, owner and
-- integrity check runs, and it stops at the budget check before any enqueue.
-- No native Lua, server traffic or gameplay legality claim.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_class_capture_publication')
local printable=B.printable
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
H.playerLevel=10
NexusDB=T.Profile(0,0)
H.AddEcho(300001,'Synthetic ordinary Echo',2,4,300001)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local A,D=Nexus.GameAdapter,Nexus.DpsCapture
H.granted={['Synthetic ordinary Echo']={{spellId=300001,quality=2}}}
H.locked={}
H.perks.serverBuildSlots={[1]={name='Synthetic slot',verified=true,echoes={{spellId=300001,quality=2,stacks=1,locked=false}}}}
H.perks.serverActiveSlot=1
H.Notify();A.Poll()
C.setup(Nexus.StartupStatus().state=='ready','start-up ready')
C.setup(A.LockedOwned().synced==true,'the empty locked map is synchronized')
local _,harnessClass=UnitClass('player')
C.setup(harnessClass=='MAGE','the synthetic UnitClass returns the token MAGE as its second value')

local realName=UnitName
UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realName(unit) end
UnitExists=function(unit) return unit=='target' end
local combat={total=0}
function combat:GetActor() return {total=self.total,Tempo=function() return 30 end} end
function combat:GetCombatTime() return 30 end
Details={GetCurrentCombat=function() return combat end};DETAILS_ATTRIBUTE_DAMAGE=1

-- Pass-through egress observation (see the header). Every call is recorded.
-- The real return values are kept exactly: the egress refuses with
-- `return false, "schema"` (core/Sync.lua BroadcastDpsRecord), and a
-- valid record under the empty budget returns false, "response wire budget".
-- `ok and sent or nil` would turn that refusal `false` into nil.
local egress={}
local realBroadcast=Nexus.Sync.BroadcastDpsRecord
Nexus.Sync.BroadcastDpsRecord=function(record,prepared,responseMode,context)
 local ok,sent,why=pcall(realBroadcast,record,prepared,responseMode,context,{})
 local row={class=type(record)=='table' and record.class or nil,
  dps=type(record)=='table' and tonumber(record.dps) or nil,ok=ok}
 if ok then row.sent,row.why=sent,why else row.why='raised: '..printable(sent) end
 egress[#egress+1]=row
 return false,'test boundary: evaluated, not enqueued'
end

local OWNER='prototypetester@ebonhold'
-- One capture of `total` damage over 30 s. `classFn` replaces UnitClass only
-- for the synchronous combat end that commits the capture (false: unchanged;
-- 'missing': no UnitClass at all). Returns the committed row and the egress
-- record the capture produced for its own score.
local function Capture(label,total,classFn)
 combat.total=total
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 local saved=UnitClass
 if classFn=='missing' then UnitClass=nil elseif classFn then UnitClass=classFn end
 local mark=#egress
 local ok,err=pcall(D.OnCombatEnd)
 UnitClass=saved
 C.setup(ok,label..': the actual combat end ran without raising',err)
 local want=math.floor(total/30)
 local row=D.GetCurrentPersonalBest('dummy')
 C.setup(type(row)=='table' and row.dps==want,label..': the actual capture committed '..want..' DPS',
  row and row.dps or Nexus.lastDpsNote)
 local seen
 for i=mark+1,#egress do if egress[i].dps==want then seen=egress[i] end end
 C.setup(seen~=nil,label..': the capture handed its record to Sync.BroadcastDpsRecord')
 print('OBSERVED',label,'stored class='..printable(row and row.class),
  'egress class='..printable(seen and seen.class),'egress result='..printable(seen and seen.sent)..'/'..printable(seen and seen.why))
 if row then
  C.guard(row.ownerKey==OWNER and row.ownerVerified==true,label..': the capture keeps its canonical verified owner',
   printable(row.ownerKey)..'/'..printable(row.ownerVerified))
  C.guard(type(row.fingerprint)=='string' and row.fingerprint~='',label..': the capture keeps its fingerprint')
 end
 return row or {},seen or {}
end

C.scenario('M current class MAGE',function()
 local row,seen=Capture('M',90000,false)
 C.expect(row.class=='MAGE','M: the actual capture stores the current class token MAGE',row.class)
 C.expect(seen.class=='MAGE','M: the record handed to the actual egress carries MAGE',seen.class)
 C.expect(seen.ok==true and seen.why~='schema',
  'M: the actual egress does not refuse the captured record as schema',seen.why)
end)

C.scenario('N no UnitClass API',function()
 local row,seen=Capture('N',120000,'missing')
 C.guard(row.class=='UNKNOWN','N: without UnitClass the capture stores UNKNOWN, not a guessed class',row.class)
 C.guard(seen.ok==true and seen.sent==false and seen.why=='schema','N: and the actual egress refuses it as schema',seen.why)
end)

C.scenario('T UnitClass returns no token',function()
 local row,seen=Capture('T',150000,function() return 'Mage' end)
 C.guard(row.class=='UNKNOWN','T: without a token the capture stores UNKNOWN',row.class)
 C.guard(seen.ok==true and seen.sent==false and seen.why=='schema','T: and the actual egress refuses it as schema',seen.why)
end)

C.scenario('U unrecognised token',function()
 local row,seen=Capture('U',180000,function() return 'Mage','NOTACLASS',99 end)
 C.guard(row.class=='UNKNOWN','U: an unrecognised token is not stored as a class',row.class)
 C.guard(seen.ok==true and seen.sent==false and seen.why=='schema','U: and the actual egress refuses the record as schema',seen.why)
end)

Nexus.Sync.BroadcastDpsRecord=realBroadcast
local published=0
for _,packet in ipairs(H.sent) do
 if tostring(packet.text or ''):gsub('||','|'):find('WLD2|',1,true) then published=published+1 end
end
C.guard(published==0,'no DPS record (WLD2) was enqueued or sent by any capture',published)
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(class token reaches capture and egress; unknown class stays conservative)')
