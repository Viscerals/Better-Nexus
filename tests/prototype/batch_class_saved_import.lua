-- Group 1 (ROOT-S5-CLASS): the current player's class in the actual Saved
-- Build import. core/CommunityController.lua (FinalizeSavedSlot) reads
-- (select(2, UnitClass and UnitClass("player"))); `and` keeps only the
-- localized name, so the current class is never used and the mirror falls
-- back to Echo-only inference: UNKNOWN for shared Echoes, or a foreign class
-- for another class's exclusive Echo.
-- EXPECT (fails at 8c): with UnitClass returning "Mage","MAGE",8 the actual
-- mirror of a Saved Build of shared Echoes, and of one holding a WARRIOR-only
-- Echo, is class MAGE.
-- GUARD (holds at 8c): a MAGE-only Echo gives MAGE; with no current class
-- token the documented last-resort inference stays (WARRIOR-only Echo ->
-- WARRIOR, shared -> UNKNOWN); a verified own published record related to the
-- Saved Build keeps its class precedence (PRIEST) over the current class; the
-- mirror stays the character's own verified build; no game or network action.
-- SETUP: real TOC start-up (format-5 profile), actual adapter projection,
-- normal Build Library reopen per server change (the import is not run by a
-- pure Refresh), actual catalog admission of the related record.
-- Synthetic Echo masks only; no native Lua, live class legality or server claim.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_class_saved_import')
local printable=B.printable
local F=dofile('tests/prototype/format5_support.lua')
local SHARED,WARRIOR_ONLY,MAGE_ONLY=200010,200011,200012
local function E(id) return {spellId=id,quality=(id-200000)%4,stacks=1,locked=false} end
local H=F.Boot(F.Database(),function(h)
 h.db[SHARED].classMask=1535
 h.db[WARRIOR_ONLY].classMask=1
 h.db[MAGE_ONLY].classMask=128
 h.perks.serverBuildSlots={[1]={name='Synthetic class slot',verified=true,echoes={E(SHARED)}}}
 h.perks.serverActiveSlot=1
end)
local A,CB,CAT=Nexus.GameAdapter,Nexus.CommunityBuilds,Nexus.BuildCatalog
C.setup(Nexus.StartupStatus().coreReady==true,'start-up reached core-ready')
local realClass=UnitClass
local _,token=UnitClass('player')
C.setup(token=='MAGE','the synthetic current class token is MAGE')
local projected=(A.Slots() or {}).bySlot
C.setup(projected and projected[1] and projected[1].class==nil,'the actual adapter supplies no per-slot class (the import must use the current class)')

local function Stats()
 local s=CB.VirtualStats()
 return type(s)=='table' and type(s.savedImport)=='table' and s.savedImport or {}
end
local function Mirror()
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==1 then return b end
 end
end
-- The server Saved Build changes, and a normal reopen imports it again.
local function Reimport(label,echoes)
 H.Advance(1.1,.05) -- past the one-second Saved import start spacing
 local before=Stats().completions or 0
 H.perks.serverBuildSlots[1].echoes=echoes
 H.Notify();A.Poll();CB.Hide();CB.Show()
 local done=B.Until(H,function()
  local m=Mirror()
  local record=m and CAT.Get(m.id)
  return (Stats().completions or 0)>before and Stats().pending~=true and record~=nil
   and type(record.echoes)=='table' and record.echoes[1] and record.echoes[1].spellId==echoes[1].spellId
 end,2000)
 C.setup(done~=nil,label..': the actual import completed and serves the Saved Build mirror')
 local m=Mirror() or {}
 print('OBSERVED',label,'mirror class='..printable(m.class),'record='..printable(m.recordBuildId))
 if m.id then
  C.guard(CB.IsOwnBuild(m.id)==true and m.ownerVerified==true and m.ownerKey==F.OWNER,
   label..': the mirror stays the character\'s own verified build',printable(m.ownerKey))
 end
 return m
end

CB.Show()
C.setup(B.Until(H,function() return Mirror()~=nil and Stats().pending~=true end,2000)~=nil,
 'the first actual import serves the mirror')

C.scenario('S shared Echoes, current MAGE',function()
 local m=Reimport('S',{E(SHARED)})
 C.expect(m.class=='MAGE','S: shared-Echo Saved Build mirror uses the current class MAGE',m.class)
end)
C.scenario('W WARRIOR-only Echo, current MAGE',function()
 local m=Reimport('W',{E(WARRIOR_ONLY)})
 C.expect(m.class=='MAGE','W: the current class MAGE is not replaced by a foreign Echo-inferred class',m.class)
end)
C.scenario('M MAGE-only Echo, current MAGE',function()
 local m=Reimport('M',{E(MAGE_ONLY)})
 C.guard(m.class=='MAGE','M: positive control, MAGE-only Echo gives MAGE',m.class)
end)
C.scenario('X no current class token: last-resort inference',function()
 UnitClass=function() return 'Mage' end
 local ok,err=pcall(function()
  local w=Reimport('XW',{E(WARRIOR_ONLY)})
  C.guard(w.class=='WARRIOR','XW: without a current token the documented inference stays (WARRIOR-only -> WARRIOR)',w.class)
  local s=Reimport('XS',{E(SHARED)})
  C.guard(s.class=='UNKNOWN','XS: without a current token shared Echoes stay UNKNOWN, not a guess',s.class)
 end)
 UnitClass=realClass
 if not ok then error(err,0) end
end)
C.scenario('P verified related publication keeps precedence',function()
 local id='synthetic-class-related'
 local row={id=id,title='Synthetic class slot',description='Synthetic related record',
  author=F.NAME,ownerKey=F.OWNER,ownerVerified=true,isMine=true,class='PRIEST',
  postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,
  echoes={{spellId=MAGE_ONLY,quality=(MAGE_ONLY-200000)%4,stacks=1}},lockedEchoes={}}
 local ok,why,ticket=CAT.Put(row,{source='local'})
 if ticket then
  for _=1,4000 do CAT.PumpRootAdmission();H.Advance(.05,.05);if ticket.state~='pending' then break end end
  ok,why=ticket.committed,ticket.reason
 end
 C.setup(ok==true and CAT.Get(id)~=nil,'P: the actual catalog admits the verified own related record',why)
 local m=Reimport('P',{E(MAGE_ONLY)})
 C.setup(m.recordBuildId==id,'P: the import relates the Saved Build to the verified record',m.recordBuildId)
 C.guard(m.class=='PRIEST','P: a verified related publication keeps its class precedence',m.class)
end)

UnitClass=realClass
C.guard(#H.actions==0 and #H.sent==0,'no game or network action',#H.actions..'/'..#H.sent)
C.finish('(current class token reaches the Saved import; fallbacks and precedence unchanged)')
