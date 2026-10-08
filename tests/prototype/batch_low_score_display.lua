-- Group 10b (S5-C2): sub-1000 DPS display consistency with the local callers.
-- Every other local DPS formatter renders a value below 1000 as an integer:
-- ui/Panel.lua FmtDps (254-260), ui/CommunityRenderer.lua DpsText (341-350),
-- core/CommunityProjection.lua DpsText (102-111), ui/Leaderboard.lua DpsText
-- (146-151). ui/Nameplate.lua FmtDps (28-32) and the capture announcement in
-- core/DpsCapture.lua (CommitSession print, "%dk") floor it to "0k".
-- EXPECT (fails at 8c): the actual unit-tooltip rank line shows 750 and 999
-- as integers, not "0k"; the actual local "New best" announcement for a
-- 666-DPS capture shows 666, not "0k".
-- GUARD (holds at 8c): 2000 shows "2k" and 1,500,000 "1.50M" in the tooltip;
-- a 3000-DPS announcement shows "3k"; the capture keeps its actual score
-- (666) - the receive score floor is not touched; no game action.
-- Not changed here (documented no-change): the arbitrary 1000 score floor
-- (S4-01) and the GUID/localized-name fallback (S4-03).
-- SETUP: part 1 loads the real Nameplate alone with a synthetic leaf record
-- (a sub-1000 peer record is not claimed reachable); part 2 is a real TOC
-- start-up with synthetic Details! combat. The capture's outbound leaf is
-- stubbed so nothing is enqueued.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_low_score_display')
local printable=B.printable

----------------------------------------------------------------------------
-- Part 1: the real unit-tooltip annotation.
----------------------------------------------------------------------------
Nexus={DpsCapture={},Sync={GetPeerInfo=function() return nil end},
 BuildCatalog={IsAuthor=function() return false end}}
UnitIsPlayer=function() return true end
UnitName=function(unit) return unit=='player' and 'SyntheticSelf' or 'SyntheticPeer' end
dofile('ui/Nameplate.lua')
local function Tooltip(score)
 Nexus.DpsCapture.GetPlayerInfo=function(name)
  C.setup(name=='SyntheticPeer','T: the annotation looks up the peer')
  return {rank=1,dps=score,category='dummy'}
 end
 local t={lines={},shown=false}
 function t:GetUnit() return 'SyntheticPeer','target' end
 function t:NumLines() return 0 end
 function t:AddLine(line) self.lines[#self.lines+1]=line end
 function t:Show() self.shown=true end
 Nexus.Nameplate._AugmentUnitTooltip(t)
 C.setup(t.shown and #t.lines==2,'T: the badge and rank lines are rendered for '..score)
 local line=B.Plain(t.lines[2] or '')
 print('OBSERVED','T score='..score,'line='..line)
 return line
end
C.scenario('T tooltip formatter',function()
 for _,score in ipairs({750,999}) do
  local line=Tooltip(score)
  C.expect(line:find(tostring(score),1,true)~=nil and line:find('0k',1,true)==nil,
   'T: '..score..' is shown as an integer, not "0k"',line)
 end
 C.guard(Tooltip(2000):find('2k',1,true)~=nil,'T: 2000 is shown as "2k"')
 C.guard(Tooltip(1500000):find('1.50M',1,true)~=nil,'T: 1,500,000 is shown as "1.50M"')
end)

----------------------------------------------------------------------------
-- Part 2: the real capture announcement.
----------------------------------------------------------------------------
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
H.playerLevel=10
NexusDB=T.Profile(0,0)
H.AddEcho(300001,'Synthetic ordinary Echo',2,4,300001)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function() return Nexus.StartupStatus().state=='ready' end)
local A,D=Nexus.GameAdapter,Nexus.DpsCapture
H.granted={['Synthetic ordinary Echo']={{spellId=300001,quality=2}}}
H.locked={}
H.perks.serverBuildSlots={[1]={name='Synthetic slot',verified=true,echoes={{spellId=300001,quality=2,stacks=1,locked=false}}}}
H.perks.serverActiveSlot=1
H.Notify();A.Poll()
C.setup(A.LockedOwned().synced==true,'A: the empty locked map is synchronized')
local realName=UnitName
UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realName(unit) end
UnitExists=function(unit) return unit=='target' end
local combat={total=0}
function combat:GetActor() return {total=self.total,Tempo=function() return 30 end} end
function combat:GetCombatTime() return 30 end
Details={GetCurrentCombat=function() return combat end};DETAILS_ATTRIBUTE_DAMAGE=1
local realBroadcast=Nexus.Sync.BroadcastDpsRecord
Nexus.Sync.BroadcastDpsRecord=function() return false,'test boundary: outbound leaf stubbed' end
local function Announce(total)
 combat.total=total
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 local lines,ok,err=B.CapturePrint(D.OnCombatEnd)
 C.setup(ok,'A: the actual combat end ran',err)
 local found
 for _,line in ipairs(lines) do if line:find('New best',1,true) then found=B.Plain(line) end end
 C.setup(found~=nil,'A: the actual capture printed its New best line for '..math.floor(total/30))
 print('OBSERVED','A dps='..math.floor(total/30),'line='..printable(found))
 return found or '',D.GetCurrentPersonalBest('dummy') or {}
end
C.scenario('A capture announcement',function()
 local line,row=Announce(20000)
 C.guard(row.dps==666,'A: the capture keeps its actual score 666',row.dps)
 C.expect(line:find('666 DPS',1,true)~=nil and line:find('0k DPS',1,true)==nil,
  'A: the 666-DPS announcement shows 666, not "0k"',line)
 line=Announce(90000)
 C.guard(line:find('3k DPS',1,true)~=nil,'A: the 3000-DPS announcement shows "3k"',line)
end)
Nexus.Sync.BroadcastDpsRecord=realBroadcast
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(sub-1000 DPS shown as integers like every other local formatter)')
