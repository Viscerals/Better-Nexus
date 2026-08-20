-- The compatibility hashes must exactly reflect current build/DPS state and
-- suppress duplicate reconciliation without changing any data.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/SyncProtocol.lua'); dofile('core/SyncTransport.lua'); dofile('core/SyncCompatibility.lua'); dofile('core/SyncReconciler.lua'); dofile('core/SyncInbound.lua'); dofile('core/SyncDiagnostics.lua'); dofile('core/SyncSession.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Sync,DPS=Nexus.Sync,Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
UnitName=function() return 'Valentine' end; UnitClass=function() return 'Mage','MAGE' end
GetNormalizedRealmName=function() return 'Ebonhold' end
local function Pump(seconds) for _=1,math.ceil(seconds/0.2) do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local echoes={{spellId=200101,stacks=1}}
local build={id='compat-build',title='Compat',author='Valentine',ownerKey='valentine@ebonhold',
    realm='ebonhold',ownerVerified=true,class='MAGE',echoes=echoes,
    lastModified=101,postedAt=101,isMine=true}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync)
Pump(100); H.sentChatMessages={}
local b1,d1=Sync.GetCompatibilityHashes()
local b2,d2=Sync.GetCompatibilityHashes()
assert(b1==b2 and d1==d2,'compatibility hashes were nondeterministic')

H.sentChatMessages={}
Sync.HandleIncoming('WLRQ|Current|'..b1..'|'..d1..'|same-state','Current')
Pump(8)
local receipts,payloads=0,0
for _,message in ipairs(H.sentChatMessages) do
    local wire=message.text:gsub('||','|')
    if wire:find('^WLRC|[^|]+|Current|same%-state|') then
        receipts=receipts+1
    elseif wire:find('^WLRB|') or wire:find('^WLD2|') then
        payloads=payloads+1
    end
end
assert(receipts==1 and payloads==0,
    'matching compatibility hashes did not produce one payload-free receipt')

build.lastModified=102
local b3,d3=Sync.GetCompatibilityHashes()
assert(b3~=b1 and d3==d1,'build-only change did not isolate the build hash')

local fp,hash=DPS.GetEchoKey(echoes),DPS.GetEchoHash(echoes)
assert(DPS.ReceiveRecord({v=7,f=fp,h=hash,e=echoes,c='dummy',d=25000000,u=60,t=49000,
    p='Valentine',k='MAGE',o='valentine@ebonhold',r='ebonhold',l=80,b=build.id},'Valentine'))
local b4,d4=Sync.GetCompatibilityHashes()
assert(b4==b3 and d4~=d3,'DPS-only change did not isolate the DPS hash')

Sync.Init(Nexus.Codec,{})
local b5,d5=Sync.GetCompatibilityHashes()
assert(b5==b4 and d5==d4,'reinitialization changed compatibility hashes')
print('deterministic build/DPS compatibility hashes and duplicate suppression -- OK')
