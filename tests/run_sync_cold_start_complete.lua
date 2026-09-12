-- 1.19.3 cold-start reconciliation sends complete builds so a fresh peer is
-- usable immediately and never depends on the original author remaining online.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/SyncProtocol.lua'); dofile('core/SyncTransport.lua'); dofile('core/SyncCompatibility.lua'); dofile('core/SyncReconciler.lua'); dofile('core/SyncInbound.lua'); dofile('core/SyncDiagnostics.lua'); dofile('core/SyncSession.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Sync=Nexus.Sync
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local who='Author'; UnitName=function() return who end
GetNormalizedRealmName=function() return 'Ebonhold' end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local function AwaitCatalog()
    local catalog=Nexus.BuildCatalog
    for _=1,4 do
        if not catalog.RootState().candidate then return true end
        assert(catalog.RootState().state=='ROOT_ADMITTED',
            'cold-start fixture found non-mutation catalog work')
        local ticket=catalog.PumpRootAdmission()
        assert(type(ticket)=='table','cold-start catalog work returned no ticket')
        local previous=tonumber(ticket.pumps) or -1
        for _=1,catalog.Budget().maximumPumps do
            if ticket.state~='pending' then break end
            local observed=catalog.PumpRootAdmission()
            assert(observed==ticket,'cold-start catalog work changed tickets')
            local current=tonumber(ticket.pumps)
            assert(current and current>previous,
                'cold-start catalog work made no progress')
            previous=current
        end
        assert(ticket.state~='pending','cold-start catalog work exhausted its bound')
        assert(ticket.state=='committed' and ticket.committed,
            ticket.reason or 'cold-start catalog work failed')
    end
    error('cold-start fixture produced too many catalog candidates')
end
local echoes={}; for i=1,79 do echoes[i]={spellId=200000+i,stacks=1,quality=3} end
local build={id='cold-build',title='Gnome Army',description='full guide',author='Author',
    ownerKey='author@ebonhold',ownerVerified=true,class='MAGE',echoes=echoes,
    postedAt=10,lastModified=10,isMine=true}

NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
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
H.AdmitCatalogV1(NexusDB)
clock=2000; Sync.Init(Nexus.Codec,{})
for _,m in ipairs(response) do Sync.HandleIncoming(m.text,'Author-Ebonhold') end
AwaitCatalog()
-- Legacy-to-bundle cutover: the fresh client's durable copy is the bundle's
-- payload, not the exact PR #68 location (state machine lines 394, 4849).
local loaded=H.DurableBuilds()['cold-build']
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
