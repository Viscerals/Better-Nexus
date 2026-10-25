-- Last normal pause-detector attribution, never a report-time probe.
-- Synthetic host only; no native report trigger is inferred here.
-- Policy: only a visible bind-confirmation popup pauses; bag occupancy does not.
Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
local H=dofile('tests/prototype/harness.lua')
H.Boot()
local A=Nexus.GameAdapter
local checks=0
local function check(v,m) checks=checks+1;assert(v,m) end
local bag=false
local counts={clock=0,slots=0,link=0,item=0,popup=0,visible=0}
local nativeTime=GetTime
GetTime=function() counts.clock=counts.clock+1;return nativeTime() end
GetContainerNumSlots=function(i) counts.slots=counts.slots+1;return i==0 and 1 or 0 end
GetContainerItemLink=function(i,j)
    counts.link=counts.link+1
    if bag and i==0 and j==1 then return '|Hitem:990001|h[Tome of Echoes]|h' end
end
GetItemInfo=function() counts.item=counts.item+1;return 'Tome of Echoes' end
local shown,visible=false,false
StaticPopup1={which='LOOT_BIND',text={GetText=function() return 'Using this item will bind it to you' end},
    IsShown=function() counts.popup=counts.popup+1;return shown end,
    IsVisible=function() counts.visible=counts.visible+1;return visible end}
for i=2,4 do _G['StaticPopup'..i]=nil end
local function facts() return A.TomeObservationFacts() end
local function read(want,source,last,remaining,clockReads)
    local clock=counts.clock
    check(A.TomeMutationPaused()==want,'normal guard result '..source)
    check(counts.clock-clock==clockReads,'existing normal clock count '..source)
    local p=facts().pause
    check(p.observed==true and p.source==source,'observed detector attribution '..source)
    check(p.lastPositive==last,'last positive attribution '..source)
    check(p.remainingSeconds==remaining,'rounded remaining value at read '..source)
end
read(false,'clear',nil,0,1)
-- Bag alone must not pause or consult container APIs.
bag=true;shown=false;visible=false
local slotsBefore,linkBefore=counts.slots,counts.link
read(false,'clear',nil,0,1)
check(counts.slots==slotsBefore and counts.link==linkBefore,
    'bag occupancy is not consulted by the pause guard')
bag=false;shown=true;visible=true
read(true,'popup','popup',20,2)
shown=false;visible=false;H.now=H.now+5
read(true,'settling','popup',15,1)
H.now=H.now+16
read(false,'clear','popup',0,1)
shown=true;visible=false
read(false,'clear','popup',0,1)
local old=facts();old.pause.source='mutated';old.pause.lastPositive='mutated'
check(facts().pause.source=='clear' and facts().pause.lastPositive=='popup','pause facts detached')
local revision,retained=facts().revision,facts().retained
for _=1,100 do A.TomeMutationPaused() end
check(facts().revision==revision and facts().retained==retained,'guard observations do not churn the bounded event ring')
local before={}
for k,v in pairs(counts) do before[k]=v end
local lines=table.concat(Nexus.SupportReport.TomeObservationLines(),'\n')
check(lines:find('source=clear',1,true) and lines:find('last_positive=popup',1,true),'report formats copied detector enum')
check(lines:find('remaining_seconds_at_read_rounded_up=0',1,true),'report labels copied rounded remaining value')
check(lines:find('not refreshed',1,true) and lines:find('no current-state or duration proof',1,true),'report states temporal limit')
for k,v in pairs(counts) do check(v==before[k],'report/facts do not re-enter '..k) end
check(not lines:find('990001',1,true) and not lines:find('Tome of Echoes',1,true),'no item link/name in attributed report facts')
A.TomeObservationPause('untrusted item text',math.huge)
local malformed=facts().pause
check(malformed.source=='unknown' and malformed.remainingSeconds==nil,'bounded malformed attribution')
print('PASS copied normal tome pause provenance / passive formatting checks='..checks)
