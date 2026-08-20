-- 1.19.3 cold-start reconciliation sends complete builds so a fresh peer is
-- usable immediately and never depends on the original author remaining online.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/SyncProtocol.lua'); dofile('core/SyncTransport.lua'); dofile('core/SyncCompatibility.lua'); dofile('core/SyncReconciler.lua'); dofile('core/SyncInbound.lua'); dofile('core/SyncDiagnostics.lua'); dofile('core/SyncSession.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Sync=Nexus.Sync
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local who='Author'; UnitName=function() return who end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local echoes={}; for i=1,79 do echoes[i]={spellId=200000+i,stacks=1,quality=3} end
local build={id='cold-build',title='Gnome Army',description='full guide',author='Author',
    ownerKey='author@ebonhold',class='MAGE',echoes=echoes,postedAt=10,lastModified=10,isMine=true}

NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{})
H.sentChatMessages={}
Sync.HandleIncoming('WLRQ|Fresh|0|0|cold-req','Fresh')
Pump(260)
local response={}; local chunks=0
for _,m in ipairs(H.sentChatMessages) do
    if m.text:find('^WLRB') then chunks=chunks+1; response[#response+1]=m end
    assert(#m.text<=255,'wire message exceeds WoW limit')
end
assert(chunks>0,'cold-start reconciliation did not send the complete build')

who='Fresh'; NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
clock=2000; Sync.Init(Nexus.Codec,{})
for _,m in ipairs(response) do Sync.HandleIncoming(m.text,'Author') end
local loaded=NexusDB.communityBuilds['cold-build']
assert(loaded and loaded.echoes and #loaded.echoes==79 and loaded.description=='full guide',
    'fresh client did not receive the complete build')
assert(loaded.ownerVerified==true,'direct author build was not marked owner-verified')

-- Once hashes match, another request produces no duplicate build payload.
H.sentChatMessages={}; clock=clock+100
local request=Sync.RequestSync(); assert(request,'follow-up reconciliation did not start')
Pump(10)
for _,m in ipairs(H.sentChatMessages) do
    assert(not m.text:find('^WLRB'),'matching local state queued a duplicate full build')
end
print('cold-start complete-build reconciliation and owner verification -- OK')
