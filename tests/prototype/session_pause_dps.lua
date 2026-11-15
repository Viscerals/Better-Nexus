-- Issue #171: the whole-addon session pause and DPS recording. A combat that
-- a pause transition crosses (paused at its start, paused or resumed during
-- it, or a Pause and Resume between two samples) records nothing; the next
-- complete combat after Resume records as before. Real TOC, lifecycle combat
-- events and DpsCapture over a fake Details! and a training dummy target.
-- Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
local ordinary={}
for i=1,79 do ordinary[#ordinary+1]={spellId=300000+i,quality=2,stacks=1} end
for _,e in ipairs(ordinary) do H.AddEcho(e.spellId,'Echo '..e.spellId,e.quality,4,e.spellId) end
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local A,D=Nexus.GameAdapter,Nexus.DpsCapture
local realUnitName=UnitName
UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realUnitName(unit) end
UnitExists=function(unit) return unit=='target' end
local combat={total=100000}
function combat:GetActor() return {total=self.total,Tempo=function() return 10 end} end
function combat:GetCombatTime() return 10 end
Details={GetCurrentCombat=function() return combat end}
DETAILS_ATTRIBUTE_DAMAGE=1
local granted={}
for _,e in ipairs(ordinary) do granted[H.names[e.spellId]]={{spellId=e.spellId,quality=e.quality}} end
H.granted=granted;H.locked={}
local echoes={}
for _,e in ipairs(ordinary) do echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=1,locked=false} end
H.perks.serverBuildSlots={[1]={name='Saved',verified=true,echoes=echoes}};H.perks.serverActiveSlot=1
H.Notify();A.Poll();H.Advance(1)

local function Best()
 local best=D.GetCurrentPersonalBest('dummy')
 return best and best.dps or 0
end
-- One combat through the real lifecycle events and update turns. `during`
-- runs after the first half of the samples.
local function Combat(total,during,before)
 combat.total=total
 if before then before() end
 H.Fire('PLAYER_REGEN_DISABLED')
 H.Advance(18,.05)
 if during then during() end
 H.Advance(18,.05)
 H.Fire('PLAYER_REGEN_ENABLED');H.Advance(.5)
end
local function Pause() SlashCmdList.NEXUS('pause') end
local function Resume() SlashCmdList.NEXUS('resume') end

-- D1. Control: a complete qualifying combat records a personal best.
Combat(100000)
local first=Best()
assert(first>0,'control: the complete combat is recorded: '..tostring(Nexus.lastDpsNote))

-- D2. Paused during the combat and still paused at its end.
Combat(200000,Pause)
assert(Best()==first,'a combat paused midway records nothing: '..tostring(Best()))
Resume()

-- D3. Paused and resumed during the combat.
Combat(300000,function() Pause();H.Advance(3,.05);Resume() end)
assert(Best()==first,'a combat that a pause crossed records nothing')

-- D4. A Pause and Resume between two sample turns.
Combat(400000,function() Pause();Resume() end)
assert(Best()==first,'a quick Pause and Resume between samples still ends the capture')

-- D5. Started while paused, resumed midway: it waits for the next combat.
Combat(500000,Resume,Pause)
assert(Best()==first,'a combat that started paused records nothing after Resume')

-- D6. The next complete combat after Resume records under the same rules.
Combat(600000)
assert(Best()>first,'the next complete combat is recorded: '..tostring(Best())..' note='..tostring(Nexus.lastDpsNote))

print('PASS session pause: no DPS record from a combat a pause crossed')
